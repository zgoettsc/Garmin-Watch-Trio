using Toybox.Application;
using Toybox.Communications;
using Toybox.WatchUi;

class TrioDataFieldApp extends Application.AppBase {

    // Trio data dictionary — populated by phone messages
    var trioData = {};

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
        Communications.transmit("status", null, new CommListener());
    }

    function onStop(state) {
    }

    function getInitialView() {
        return [ new TrioDataFieldView() ];
    }

    function onPhoneMessage(msg) {
        if (msg.data != null) {
            trioData = msg.data;
            WatchUi.requestUpdate();
        }
    }
}
