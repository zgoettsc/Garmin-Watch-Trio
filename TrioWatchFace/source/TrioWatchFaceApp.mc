using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Background;
using Toybox.Time;
using Toybox.WatchUi;

(:background)
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
        // as a fallback poll (minimum allowed interval for watch faces).
        Background.registerForTemporalEvent(new Time.Duration(300));

        // Also wake the background service instantly whenever Trio
        // pushes a message — this is what makes BG updates arrive
        // in real-time instead of only every 5 minutes.
        Background.registerForPhoneAppMessages();
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
