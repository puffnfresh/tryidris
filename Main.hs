{-# LANGUAGE BangPatterns #-}
module Main where

import Control.Applicative ((<$>))
import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, readMVar, takeMVar)
import Control.Monad (mzero, forever, replicateM)
import Control.Monad.Trans (liftIO)
import Data.Aeson as JSON hiding (json)
import Data.Char (isSpace)
import Data.List (isPrefixOf)
import Data.Maybe (fromMaybe)
import Data.Monoid (mempty)
import Language.Sexp.Parser (Sexp(..), parseMaybe)
import Network.HTTP.Types.Status (badRequest400)
import Network.Wai.Middleware.Static
import Numeric (readHex)
import System.Directory
import System.Environment (getArgs)
import System.IO
import System.Process
import Text.Printf (printf)
import Text.Hastache (MuType(MuBool))
import Web.Scotty.Trans
import Web.Scotty.Hastache
import qualified Data.ByteString.Lazy.Char8 as L
import qualified Data.ByteString.UTF8 as UTF8
import qualified Data.Text as S
import qualified Data.Text.Lazy as T
import qualified Data.Text.Lazy.Encoding as E
import qualified Data.Vector as V

import Debug.Trace

{- Talking to Idris ideslave -}
encodeCommand :: String -> String
encodeCommand s = printf "%06x%s" (length s) s

getLength :: Int -> Handle -> IO String
getLength n = replicateM n . hGetChar

readHexLength :: Handle -> IO Int
readHexLength = fmap (fst . head . readHex) . getLength 6

getResponse :: Handle -> IO String
getResponse h = readHexLength h >>= (`getLength` h)

expressionResult :: [Sexp] -> L.ByteString
expressionResult [List (Atom ":return" : List (Atom ":ok" : Atom r : _) : _)] = r

data InterpretData = InterpretData { expression :: String }

instance JSON.FromJSON InterpretData where
    parseJSON (JSON.Object v) = InterpretData <$> v .: "expression"
    parseJSON _ = mzero

instance JSON.ToJSON Sexp where
    toJSON (Atom a) = JSON.String . T.toStrict $ E.decodeUtf8 a
    toJSON (List as) = JSON.Array . V.fromList $ map toJSON as

compile :: String -> IO String
compile code = do
  tempDir <- getTemporaryDirectory

  (idrisTempDir, _) <- openTempFile tempDir "tryidris"
  removeFile idrisTempDir
  createDirectory idrisTempDir

  (tempFile, tempHandle) <- openTempFile idrisTempDir "Main.idr"
  hPutStr tempHandle code
  hClose tempHandle

  let args = ["--codegen", "javascript"
             , "--package", "javascript"
             , "--ibcsubdir", idrisTempDir
             , "--nocolour"
             , "-o", "/dev/stdout"
             , tempFile]

  (_, Just idrisStdout, _, _) <- createProcess $ (proc "idris" args) { std_out = CreatePipe }

  hSetBuffering idrisStdout NoBuffering
  !output <- hGetContents idrisStdout

  removeDirectoryRecursive idrisTempDir
  return output

spawnIdris :: IO (Handle, Handle, ProcessHandle)
spawnIdris = do
  (Just stdin, Just stdout, _, process) <- createProcess $ (proc "idris" ["--ideslave"]) { std_in = CreatePipe, std_out = CreatePipe }

  hSetBuffering stdin NoBuffering
  hSetBuffering stdout NoBuffering

  return (stdin, stdout, process)

main :: IO ()
main = do
  idrisRef <- newEmptyMVar
  spawnIdris >>= putMVar idrisRef

  scottyH' 3000 $ do
    middleware . staticPolicy $ addBase "static"
    setTemplatesDir "templates"
    get "/" $ redirect "/console"
    get "/console" $ do
      setH "in-console" $ MuBool True
      hastache "console.htm"
    get "/compile" $ do
      setH "in-compile" $ MuBool True
      hastache "compile.htm"
    post "/compile" $ do
      code <- body
      output <- liftIO . compile $ L.unpack code
      text $ T.pack output
    post "/interpret" $ do
      interpretData <- jsonData
      let e = dropWhile isSpace $ expression interpretData
      if ":" `isPrefixOf` e
      then do
        status badRequest400
        text "Can't execute REPL commands. Please type an expression."
      else do
        idrisVar <- liftIO newEmptyMVar
        idrisThread <- liftIO . forkIO $ do
          (idrisStdin, idrisStdout, _) <- readMVar idrisRef
          hPutStr idrisStdin . encodeCommand $ "((:interpret " ++ show e ++ ") 1)\n"
          response <- getResponse idrisStdout
          putMVar idrisVar . Just . fromMaybe [List []] . parseMaybe $ L.pack response
        monitorThread <- liftIO . forkIO $ do
          threadDelay 1000000
          (_, _, idrisProcess) <- takeMVar idrisRef
          killThread idrisThread
          terminateProcess idrisProcess
          spawnIdris >>= putMVar idrisRef
          putMVar idrisVar Nothing
        parsed <- liftIO $ takeMVar idrisVar
        liftIO $ killThread monitorThread
        maybe (status badRequest400 >> text "Evaluation did not complete.") json parsed
