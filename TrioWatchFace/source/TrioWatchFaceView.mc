using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

// ══════════════════════════════════════════════════
//  DEBUG BUILD — raw data dump only, no normal fields
// ══════════════════════════════════════════════════
class TrioWatchFaceView extends WatchUi.WatchFace {

    function initialize() {
        WatchFace.initialize();
    }

    function onUpdate(dc) {
        var width  = dc.getWidth();
        var height = dc.getHeight();
        var cx     = width / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var app  = Application.getApp();
        var data = app.trioData;

        // ── Row 1: Time + Rx age ──
        var clock = System.getClockTime();
        var hours = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            if (hours > 12) { hours = hours - 12; }
            if (hours == 0) { hours = 12; }
        }
        var timeStr = Lang.format("$1$:$2$", [hours, clock.min.format("%02d")]);

        var rxStr = "--";
        if (app.lastReceiveTime > 0) {
            var ageSec = Time.now().value() - app.lastReceiveTime;
            if (ageSec >= 0) {
                rxStr = (ageSec / 60).toString() + "m";
            } else {
                rxStr = "0m";
            }
        }

        var header = timeStr + "  Rx:" + rxStr;
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 18, Graphics.FONT_XTINY, header,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Row 2+: Raw debug log from Storage ──
        // Format: "key1(type)=val|key2(type)=val|..."
        var log = Storage.getValue("debugLog");
        if (log == null || log.length() == 0) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, height / 2, Graphics.FONT_XTINY, "No data yet",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Split on "|" into individual key entries and draw one per line
        var entries = splitString(log, '|');
        var y = 38;
        var lineHeight = 20;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < entries.size(); i++) {
            if (entries[i].length() == 0) {
                continue;  // skip trailing empty from final "|"
            }
            if (y + lineHeight > height) {
                break;  // don't draw off-screen
            }
            dc.drawText(cx, y, Graphics.FONT_XTINY, entries[i],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            y += lineHeight;
        }
    }

    // Simple string split since Monkey C doesn't have String.split()
    private function splitString(str, delim) {
        var result = [];
        var start = 0;
        for (var i = 0; i < str.length(); i++) {
            if (str.substring(i, i + 1).equals(delim.toString())) {
                result.add(str.substring(start, i));
                start = i + 1;
            }
        }
        if (start < str.length()) {
            result.add(str.substring(start, str.length()));
        }
        return result;
    }
}
