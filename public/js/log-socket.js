// newlines to <br/>
function nl2br (str, is_xhtml) {
    var breakTag = (is_xhtml || typeof is_xhtml === 'undefined') ? '<br />' : '<br>';
    return (str + '').replace(/([^>\r\n]?)(\r\n|\n\r|\r|\n)/g, '$1' + breakTag + '$2');
}

// highlights the "Go to bottom" button if the log output isn't scrolled to the
// bottom of the page, else the button is opaque.
function checkGoBottomButton() {
    var currentPosition = $(document).scrollTop();
    var bottomPosition = $(document).height() - $(window).height();

    if(currentPosition < bottomPosition) {

        /* this a trick to handle bad float management from javascript */
        if(Math.floor($('#to-bottom').css('opacity')*10) == 1) {
            $('#to-bottom').fadeTo(400, 1);
        }
    }
    else if (currentPosition == bottomPosition) {

        if($('#to-bottom').css('opacity') == 1) {
            $('#to-bottom').fadeTo(400, 0.1);
        }
    }
}

// checks, if given element is in viewport (visible in the browser)
function isScrolledIntoView(elem) {
    var docViewTop = $(window).scrollTop();
    var docViewBottom = docViewTop + $(window).height();

    var elemTop = $(elem).offset().top;
    var elemBottom = elemTop + $(elem).height();

    return ((elemBottom >= docViewTop) && (elemTop <= docViewBottom)
      && (elemBottom <= docViewBottom) &&  (elemTop >= docViewTop) );
}

// checks if new log lines are in viewport and makes them fadeIn
function checkIfElementIsViewed() {
    $('.tab-pane.active li.new').each(function() {
        if(isScrolledIntoView($(this))) {
            $(this).fadeTo(2000, 1, function() {
                $(this).removeClass('new');
            });
        }
    });
    // fadeOut separator, if it is viewed
    $('.separator').each(function() {
        if($(this).css('opacity') == 1 && isScrolledIntoView($(this))) {
            $(this).fadeTo(5000, 0.2);
        }
    });
}

$(document).ready(function() {

    checkGoBottomButton();
    
    var socket_url = $('[data-socket_url]').data('socket_url');
    if (socket_url.length == 0) {return;}
    var socket = io.connect(socket_url);
    var container = $('#container .tab-content');
    var monitors = [];

    $(document).scroll(function(event) {

        var slug = $('.tab-content .active').attr('id');
        var currentPosition = $(document).scrollTop();
        monitors[slug].scrollPos = currentPosition;

        checkGoBottomButton();
        checkIfElementIsViewed();
    });


    $('#go-to-bottom').click(function(event) {
        checkGoBottomButton();
    });


    socket.on('new-data', function(data) {

        if ($('#' + data.fileSlug).length == 0) {

            var newMonitor = $('<div class="tab-pane" id="' + data.fileSlug + '"></div>');
            newMonitor.append($('<ul></ul>'));
            var newMonitorTitle = $('<li id="title-' + data.fileSlug + '"></li>');

            var newMonitorTitleLink = $('<a data-toggle="tab"></a>');
            newMonitorTitleLink.attr('href', '#' + data.fileSlug);
            newMonitorTitleLink.html(data.fileName + ' ');
            newMonitorTitleLink.append($('<span class="badge badge-important"></span>'));
            newMonitorTitleLink.appendTo(newMonitorTitle);

            newMonitorTitleLink.on('shown', function(event) {
                var id = $(event.target).attr('href');
                var slug = id.substr(1, id.length);
                $(document).scrollTop(monitors[slug].scrollPos);
                checkGoBottomButton();
                checkIfElementIsViewed();
            });

            newMonitor.appendTo(container);
            newMonitorTitle.appendTo($('#menu ul'));

            monitors[data.fileSlug] = {
                'scrollPos': 0
            };

            newMonitorTitle.click(function() {
                counter = $('#title-' + data.fileSlug + ' span').html('');
                checkGoBottomButton();
            });
        }

        var newItem = $('<li>' + nl2br(data.value) + '</li>');
        var maxScrollPosition = $(document).height() - $(window).height();
        var mustAutoScroll = maxScrollPosition == monitors[data.fileSlug].scrollPos;


        if(!$('#' + data.fileSlug).hasClass('active') && $('#' + data.fileSlug + ' li.new').length == 0 && $('#' + data.fileSlug + ' li').length > 0) {
            $('#' + data.fileSlug + ' ul').append($('<li class="separator">#############################################################################</li>'));
        }

        if(!$('#' + data.fileSlug).hasClass('active') || !isScrolledIntoView(newItem)) {
           if($('#' + data.fileSlug + ' li').length == 0) {
                newItem.addClass('old');
            }
            else {
                newItem.addClass('new');
            }
        }

        $('#' + data.fileSlug + ' ul').append(newItem);


        if(!$('#' + data.fileSlug).hasClass('active') && $('#' + data.fileSlug + ' li').length > 1) {

            var counter = $('#title-' + data.fileSlug + ' span');
            if(counter.html() == '') {
                counter.html('0');
            }
            counter.html(parseInt(counter.html()) + 1);
        }
        else {

            if(mustAutoScroll) {
                $(document).scrollTop($(document).height());
                monitors[data.fileSlug].scrollPos = $(document).scrollTop();
            }
        }
    });
});