using Toybox.Background;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;

// Background service delegate — fetches Trio data from Nightscout.
//
// Uses the /pebble endpoint which returns a single JSON object (not
// an array) containing glucose, trend, delta, IOB, and COB in one
// request.  This is critical because Connect IQ's makeWebRequest
// rejects top-level JSON arrays with error -400.
(:background)
class TrioServiceDelegate extends System.ServiceDelegate {

    private const NS_URL = "https://zgoettsc.nightscoutpro.com";

    // Seconds from Unix epoch (1970-01-01) to Garmin epoch (1989-12-31)
    private const EPOCH_OFFSET = 631065600;

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() {
        try {
            Communications.makeWebRequest(
                NS_URL + "/pebble",
                null,
                {
                    :method => Communications.HTTP_REQUEST_METHOD_GET,
                    :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
                },
                method(:onReceive)
            );
        } catch (e) {
            // Ensure we always exit so the system does not revoke our
            // temporal-event registration for an unresponsive service.
            Background.exit(null);
        }
    }

    function onReceive(code as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (code != 200 || data == null || !(data instanceof Lang.Dictionary)) {
            Background.exit(null);
            return;
        }

        var result = {};

        // bgs is an array inside the top-level dict
        var bgs = data["bgs"];
        if (bgs instanceof Lang.Array && bgs.size() > 0) {
            var bg = bgs[0];

            var sgv = bg["sgv"];
            if (sgv != null) {
                result["glucose"] = sgv.toString();
            }

            var dir = bg["direction"];
            if (dir != null) {
                result["trendRaw"] = dir;
            }

            var delta = bg["bgdelta"];
            if (delta != null) {
                var d = delta.toNumber();
                var sign = "";
                if (d >= 0) { sign = "+"; }
                result["delta"] = sign + d.toString();
            }

            var iob = bg["iob"];
            if (iob != null) {
                result["iob"] = iob.toString();
            }

            var cob = bg["cob"];
            if (cob != null) {
                result["cob"] = cob.toString();
            }

            // Reading timestamp → Garmin epoch seconds
            // datetime is Unix milliseconds; toLong() handles all numeric types
            var dt = bg["datetime"];
            if (dt != null && !(dt instanceof Lang.String)) {
                var unixSec = (dt.toLong() / 1000l).toNumber();
                result["glucoseDate"] = unixSec - EPOCH_OFFSET;
            }
        }

        // Use status[0].now as loop timestamp (millis since epoch)
        var status = data["status"];
        if (status instanceof Lang.Array && status.size() > 0) {
            var s0 = status[0];
            var nowTs = s0["now"];
            if (nowTs != null && !(nowTs instanceof Lang.String)) {
                var unixSec = (nowTs.toLong() / 1000l).toNumber();
                result["loopDate"] = unixSec - EPOCH_OFFSET;
            }
        }

        Background.exit(result.size() > 0 ? result : null);
    }
}
