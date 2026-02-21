using Toybox.Background;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;

// Background service delegate — fetches Trio data from Nightscout.
//
// Temporal event fires every 5 min → onTemporalEvent()
//   → web request to /entries.json → parse glucose/trend/delta
//   → web request to /devicestatus.json → parse IOB/COB/loop
//   → Background.exit() passes combined data to foreground
//
// This bypasses Garmin Connect Mobile companion messaging entirely,
// using the phone's internet (or watch WiFi) for direct HTTP.
(:background)
class TrioServiceDelegate extends System.ServiceDelegate {

    private const NS_URL = "https://zgoettsc.nightscoutpro.com";

    // Seconds from Unix epoch (1970-01-01) to Garmin epoch (1989-12-31)
    private const EPOCH_OFFSET = 631065600;

    // Intermediate storage while chaining the two requests
    private var _data = {};

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() {
        // Step 1: Fetch latest 2 glucose entries (2 for delta calc)
        Communications.makeWebRequest(
            NS_URL + "/api/v1/entries.json?count=2",
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onEntries)
        );
    }

    // Step 1 callback: parse glucose, trend, delta, reading date
    function onEntries(code as Number, data) as Void {
        if (code == 200 && data instanceof Lang.Array && data.size() > 0) {
            var e = data[0];

            var sgv = e["sgv"];
            if (sgv != null) {
                _data["glucose"] = sgv.toString();
            }

            var dir = e["direction"];
            if (dir != null) {
                _data["trendRaw"] = dir;
            }

            // Reading timestamp → Garmin epoch seconds
            var ds = e["dateString"];
            if (ds != null) {
                var g = isoToGarmin(ds);
                if (g != null) {
                    _data["glucoseDate"] = g;
                }
            }

            // Delta between last two readings
            if (data.size() > 1 && sgv != null) {
                var prev = data[1]["sgv"];
                if (prev != null) {
                    var diff = sgv.toNumber() - prev.toNumber();
                    var sign = "";
                    if (diff >= 0) { sign = "+"; }
                    _data["delta"] = sign + diff.toString();
                }
            }
        }

        // Step 2: Fetch device status for IOB / COB / loop
        Communications.makeWebRequest(
            NS_URL + "/api/v1/devicestatus.json?count=1",
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onDeviceStatus)
        );
    }

    // Step 2 callback: parse IOB, COB, loop date, then exit
    function onDeviceStatus(code as Number, data) as Void {
        if (code == 200 && data instanceof Lang.Array && data.size() > 0) {
            var s = data[0];
            var oa = s["openaps"];
            if (oa != null) {
                // IOB
                var iobObj = oa["iob"];
                if (iobObj != null && iobObj["iob"] != null) {
                    _data["iob"] = iobObj["iob"].format("%.2f");
                }

                // COB: try enacted first, then suggested
                var cob = null;
                var enacted = oa["enacted"];
                if (enacted != null) {
                    cob = enacted["COB"];
                }
                if (cob == null) {
                    var suggested = oa["suggested"];
                    if (suggested != null) {
                        cob = suggested["COB"];
                    }
                }
                if (cob != null) {
                    _data["cob"] = cob.toString();
                }
            }

            // Loop date from devicestatus timestamp
            var ca = s["created_at"];
            if (ca != null) {
                var g = isoToGarmin(ca);
                if (g != null) {
                    _data["loopDate"] = g;
                }
            }
        }

        Background.exit(_data.size() > 0 ? _data : null);
    }

    // Parse ISO 8601 "YYYY-MM-DDTHH:mm:ss..." to Garmin epoch seconds.
    // Uses a Julian Day algorithm — no Gregorian module needed in background.
    private function isoToGarmin(iso as String) as Number or Null {
        if (iso.length() < 19) { return null; }
        var yr = iso.substring(0, 4).toNumber();
        var mo = iso.substring(5, 7).toNumber();
        var dy = iso.substring(8, 10).toNumber();
        var hr = iso.substring(11, 13).toNumber();
        var mn = iso.substring(14, 16).toNumber();
        var sc = iso.substring(17, 19).toNumber();
        if (yr == null || mo == null || dy == null ||
            hr == null || mn == null || sc == null) {
            return null;
        }
        var y = yr;
        var m = mo;
        if (m <= 2) { y = y - 1; m = m + 12; }
        var days = 365 * y + y / 4 - y / 100 + y / 400
                 + (153 * (m - 3) + 2) / 5 + dy - 719469;
        return days * 86400 + hr * 3600 + mn * 60 + sc - EPOCH_OFFSET;
    }
}
