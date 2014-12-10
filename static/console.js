jQuery(function() {
    function decorationToClassName(decoration) {
        var className = decoration[1];
        switch(decoration[0]) {
        case ':decor':
            className = className.substr(1);
            break;
        case ':name':
            className = 'name';
            break;
        case ':implicit':
        case ':doc-overview':
        case ':source-loc':
        case ':type':
        default:
            className = '';
            break;
        }

        return className;
    }

    function decoratedCommands(output, decorations) {
        var charIndex = 0,
            commands = [],
            className = '',
            i;

        function handleDecoration(decoration) {
            var start = parseInt(decoration[0]),
                count = parseInt(decoration[1]),
                i;

            if(decoration[2][0][0] != ':decor')
                return;

            for(i = 0; i < decoration[2].length; i++) {
                className += ' ' + decorationToClassName(decoration[2][i]);
            }

            if(start > charIndex) {
                commands.push({msg: output.substring(charIndex, start)});
                charIndex = start;
            }

            commands.push({msg: output.substr(start, count), className: className});
            charIndex = start + count;
        }

        for(i = 0; i < decorations.length; i++) {
            handleDecoration(decorations[i]);
        }

        if(charIndex < output.length) {
            commands.push({msg: output.substring(charIndex, output.length)});
        }

        return commands;
    }

    jQuery(".console").console({
        promptLabel: 'Idris> ',
        autofocus: true,
        commandHandle: function(line, handle) {
            jQuery.ajax({
                url: '/interpret',
                method: 'POST',
                contentType: 'application/json; charset=UTF-8',
                dataType: 'json',
                data: JSON.stringify({expression: line}),
                error: function(response) {
                    handle([{msg: response.responseText, className: 'error'}]);
                },
                success: function(response) {
                    var output = response[0][1][1],
                        decorations = response[0][1][2];

                    if(!decorations) {
                        return handle(output);
                    }

                    handle(decoratedCommands(output, decorations));
                }
            });
        }
    });
});
