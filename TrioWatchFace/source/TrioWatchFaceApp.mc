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
    private const DEBUG_LOG_KEY = "debugLog";

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

        // Schedule the background service to run every 5 minutes
        // as a fallback poll (minimum allowed interval for watch faces).
        Background.registerForTemporalEvent(new Time.Duration(300));

        // Wake the background service instantly whenever Trio pushes
        // a message — this enables real-time updates instead of only
        // receiving data every 5 minutes via the temporal poll.
        Background.registerForPhoneAppMessageEvent();
    }

    function onStop(state) {
        Background.deleteTemporalEvent();
        Background.deletePhoneAppMessageEvent();
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

            // Debug: log every key with its type and value so we can see
            // exactly what Trio sent (viewable if we read Storage later).
            // Type codes: S=String, N=Number(32b), L=Long(64b), F=Float, D=Double
            if (data instanceof Lang.Dictionary) {
                var keys = data.keys();
                var log = "";
                for (var i = 0; i < keys.size(); i++) {
                    var k = keys[i];
                    var v = data[k];
                    var t = "?";
                    if (v == null)              { t = "null"; }
                    else if (v instanceof Long)   { t = "L"; }
                    else if (v instanceof Number) { t = "N"; }
                    else if (v instanceof Float)  { t = "F"; }
                    else if (v instanceof Double) { t = "D"; }
                    else if (v instanceof String) { t = "S"; }
                    var vs = (v != null) ? v.toString() : "null";
                    log = log + k.toString() + "(" + t + ")=" + vs + "|";
                }
                Storage.setValue(DEBUG_LOG_KEY, log);
            }

            WatchUi.requestUpdate();
        }
    }
}
