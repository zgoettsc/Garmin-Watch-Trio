using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Background;
using Toybox.Time;
using Toybox.WatchUi;

class TrioWatchFaceApp extends Application.AppBase {

    // Trio data dictionary — populated by background service,
    // persisted to Storage so it survives between updates.
    var trioData = {};

    // Storage key for persisting Trio data
    private const STORAGE_KEY = "trioData";

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        // Restore last-known data from Storage
        var stored = Storage.getValue(STORAGE_KEY);
        if (stored != null) {
            trioData = stored;
        }

        // Schedule the background service to run every 5 minutes
        // (minimum allowed interval for watch faces).
        // Each cycle requests fresh data from Trio via "status" message.
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
            // Persist so the data is available immediately on next app start
            Storage.setValue(STORAGE_KEY, data);
            WatchUi.requestUpdate();
        }
    }
}
