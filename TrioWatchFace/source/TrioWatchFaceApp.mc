using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Background;
using Toybox.Lang;
using Toybox.Time;
using Toybox.WatchUi;

(:background)
class TrioWatchFaceApp extends Application.AppBase {

    // Trio data dictionary — populated by background service,
    // persisted to Storage so it survives between updates.
    var trioData = {};

    // Garmin epoch seconds when data was last received from Trio.
    // Used by the view to display data freshness on-screen.
    var lastReceiveTime = 0;

    // Storage keys
    private const STORAGE_KEY = "trioData";
    private const RECEIVE_TIME_KEY = "lastRx";

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        // Restore last-known data from Storage
        var stored = Storage.getValue(STORAGE_KEY);
        if (stored != null) {
            trioData = stored;
        }
        var rxTime = Storage.getValue(RECEIVE_TIME_KEY);
        if (rxTime != null) {
            lastReceiveTime = rxTime;
        }

        // Poll Nightscout every 5 minutes (minimum interval for watch faces).
        // The background service fetches glucose + devicestatus via HTTP.
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
            lastReceiveTime = Time.now().value();

            // Persist so the data is available immediately on next app start
            Storage.setValue(STORAGE_KEY, data);
            Storage.setValue(RECEIVE_TIME_KEY, lastReceiveTime);

            WatchUi.requestUpdate();
        }
    }
}
