jQuery(function() {
    var textarea = document.getElementById('code'),
        editor = textarea && CodeMirror.fromTextArea(textarea);

    function updateOutput(code) {
        jQuery('#output').text(code);
    }

    function execute(code) {
        jQuery('<script></script>').text(code).appendTo(document.body);
    }

    function compile(callback) {
        jQuery.ajax({
            url: '/compile',
            method: 'POST',
            contentType: 'text/plain; charset=UTF-8',
            dataType: 'text',
            data: editor.getValue(),
            success: callback
        });  
    }

    jQuery('#execute-button').click(function() {
        compile(function(code) {
            updateOutput(code);
            execute(code);
        });
    });

    jQuery('#compile-button').click(function() {
        compile(updateOutput);
    });

    textarea && compile(updateOutput);
});
