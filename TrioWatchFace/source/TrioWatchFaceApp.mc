using Toybox.Application;
using Toybox.Background;
using Toybox.WatchUi;

class TrioWatchFaceApp extends Application.AppBase {

    // Trio data dictionary — populated by background service
    var trioData = {};

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        // Schedule the background service to run every 5 minutes
        // (minimum interval for watch faces)
        Background.registerForTemporalEvent(new Time.Duration(300));
    }

    function onStop(state) {
        Background.deleteTemporalEvent();
    }

    function getInitialView() {
        return [ new TrioWatchFaceView() ];
    }

    // Return the background service delegate
    function getServiceDelegate() {
        return [ new TrioServiceDelegate() ];
    }

    // Called when the background service hands back data via Background.exit()
    function onBackgroundData(data) {
        if (data != null) {
            trioData = data;
            WatchUi.requestUpdate();
        }
    }
}
