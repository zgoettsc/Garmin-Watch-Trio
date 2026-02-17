using Toybox.Application;
using Toybox.Communications;
using Toybox.WatchUi;

class TrioWatchFaceApp extends Application.AppBase {

    // Trio data dictionary — populated by phone messages
    var trioData = {};

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        // Listen for data pushed from Trio on the phone
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));

        // Request initial data so we don't wait for the next push cycle
        Communications.transmit("status", null, new CommListener());
    }

    function onStop(state) {
    }

    function getInitialView() {
        return [ new TrioWatchFaceView() ];
    }

    // Called when Trio sends a data dictionary to the watch
    function onPhoneMessage(msg) {
        if (msg.data != null) {
            trioData = msg.data;
            WatchUi.requestUpdate();
        }
    }
}
