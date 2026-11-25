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

    // Result of the most recent poll: 0 = ok, otherwise the HTTP status
    // or Connect IQ error code.  Shown next to the data age when non-zero.
    var lastError = 0;

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
        armPoll();
    }

    // (Re-)arm the 5-minute Nightscout poll.  Safe to call repeatedly:
    // registering again with the same interval replaces the existing
    // registration.  Never let an exception here take the face down.
    function armPoll() {
        try {
            Background.registerForTemporalEvent(new Time.Duration(300));
        } catch (e) {
        }
    }

    function onStop(state) {
        // Do NOT delete the temporal event here.
        //
        // This class is annotated (:background), so the system runs
        // onStart()/onStop() for the background service process as well
        // as for the watch face itself.  Every 5-minute poll therefore
        // ended with onStop() -> deleteTemporalEvent(), cancelling the
        // next poll.  Polling only resumed if onBackgroundData() happened
        // to re-register afterwards, or when the face was restarted
        // (re-selecting the face), which is why the data went stale for
        // hours and then "caught up".
        //
        // The registration is tied to this app: the system drops it when
        // another watch face is selected, so no clean-up is needed.
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
        // Re-register the temporal event every time, regardless of whether
        // this request succeeded.  Garmin devices can silently revoke the
        // registration (slow response, transient error, firmware quirk).
        // Re-arming here guarantees the next poll fires in 5 minutes.
        armPoll();

        if (data instanceof Lang.Dictionary && data.hasKey("err")) {
            // Failed poll: keep showing the last good reading (its age is
            // on screen) and remember why the poll failed.
            lastError = data["err"];
            WatchUi.requestUpdate();
        } else if (data != null) {
            lastError = 0;
            trioData = data;
            lastReceiveTime = Time.now().value();

            // Persist so the data is available immediately on next app start
            Storage.setValue(STORAGE_KEY, data);
            Storage.setValue(RECEIVE_TIME_KEY, lastReceiveTime);

            WatchUi.requestUpdate();
        }
    }
}
