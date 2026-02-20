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

            WatchUi.requestUpdate();
        }

        // CRITICAL: Phone app message events are one-shot in the Garmin SDK.
        // After the event fires, it is unregistered and no more push data
        // will arrive until we re-register.  Do this after every background
        // exit (even null/error) so push stays alive.
        Background.registerForPhoneAppMessageEvent();
    }
}
