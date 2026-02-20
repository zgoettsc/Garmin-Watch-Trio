using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

class TrioWatchFaceView extends WatchUi.WatchFace {

    // BG color thresholds (mg/dL)
    private const BG_URGENT_LOW  = 55;
    private const BG_LOW         = 70;
    private const BG_HIGH        = 180;
    private const BG_URGENT_HIGH = 250;

    // Loop is stale after 15 minutes (900 seconds)
    private const LOOP_STALE_SEC = 900;

    function initialize() {
        WatchFace.initialize();
    }

    function onUpdate(dc) {
        var width  = dc.getWidth();
        var cx     = width / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var app  = Application.getApp();
        var data = app.trioData;

        // ── Zone 1: Date ──
        var now  = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_MEDIUM);
        var dateStr = info.day_of_week + " " + info.month + " " + info.day;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 40, Graphics.FONT_XTINY, dateStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Zone 2: Time ──
        var clock = System.getClockTime();
        var hours = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            if (hours > 12) { hours = hours - 12; }
            if (hours == 0) { hours = 12; }
        }
        var timeStr = hours.toString() + ":" + clock.min.format("%02d");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 82, Graphics.FONT_NUMBER_HOT, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Zone 3: BG + Trend arrow ──
        var glucose  = safeGet(data, "glucose");
        var trendRaw = safeGet(data, "trendRaw");
        var bgText   = (glucose != null) ? glucose : "--";
        var tArrow   = getTrendArrow(trendRaw);
        var bgColor  = getBgColor(glucose);

        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 145, Graphics.FONT_LARGE, bgText + " " + tArrow,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Zone 4: Delta ──
        var delta = safeGet(data, "delta");
        var dText = (delta != null) ? delta : "--";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 185, Graphics.FONT_SMALL, dText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Zone 5: IOB / COB ──
        var iob = safeGet(data, "iob");
        var cob = safeGet(data, "cob");
        var iobText = (iob != null) ? (iob + "u") : "--";
        var cobText = (cob != null) ? (cob + "g") : "--";
        var spacing = width / 5;

        dc.setColor(0x00FFFF, Graphics.COLOR_TRANSPARENT);  // cyan
        dc.drawText(cx - spacing, 222, Graphics.FONT_TINY, iobText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(0xFF5500, Graphics.COLOR_TRANSPARENT);  // orange
        dc.drawText(cx + spacing, 222, Graphics.FONT_TINY, cobText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Zone 6: Loop status + Glucose age + Battery ──
        drawStatusRow(dc, cx, width, 250, data, app);
    }

    // ════════════════════════════════════════════
    //  Loop indicator + glucose age + battery %
    // ════════════════════════════════════════════
    private function drawStatusRow(dc, cx, width, y, data, app) {
        var sp = width / 4;

        // Loop indicator: green dot or red X
        var loopActive = false;
        var loopDate = safeGet(data, "lastLoopDateInterval");
        if (loopDate != null) {
            var nowSec = Time.now().value();
            var loopSec = (loopDate instanceof Long) ? loopDate.toNumber() : loopDate;
            var age = nowSec - loopSec;
            if (age >= 0 && age < LOOP_STALE_SEC) {
                loopActive = true;
            }
        }

        if (loopActive) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - sp, y, 5);
        } else {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx - sp, y, Graphics.FONT_XTINY, "X",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Glucose age: minutes since Trio sent the payload (sentAt = "HH:mm:ss")
        var ageStr = "--";
        var sentAt = safeGet(data, "sentAt");
        if (sentAt != null && sentAt.length() >= 8) {
            var sentH = sentAt.substring(0, 2).toNumber();
            var sentM = sentAt.substring(3, 5).toNumber();
            var sentS = sentAt.substring(6, 8).toNumber();
            if (sentH != null && sentM != null && sentS != null) {
                var sentTotal = sentH * 3600 + sentM * 60 + sentS;
                var clock = System.getClockTime();
                var nowTotal = clock.hour * 3600 + clock.min * 60 + clock.sec;
                var diffSec = nowTotal - sentTotal;
                if (diffSec < 0) {
                    diffSec = diffSec + 86400;  // midnight crossover
                }
                ageStr = (diffSec / 60).toString() + "m";
            }
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, ageStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Battery
        var battery = System.getSystemStats().battery;
        var battStr = battery.toNumber().toString() + "%";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + sp, y, Graphics.FONT_XTINY, battStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ════════════════════════════════════════════
    //  Helpers
    // ════════════════════════════════════════════

    // Safe dictionary access — returns null if key missing or data isn't a dict
    private function safeGet(dict, key) {
        if (dict instanceof Lang.Dictionary && dict.hasKey(key)) {
            return dict[key];
        }
        return null;
    }

    // BG color based on clinical thresholds
    private function getBgColor(glucose) {
        if (glucose == null) {
            return Graphics.COLOR_WHITE;
        }
        var bg = glucose.toFloat();
        if (bg == null) {
            return Graphics.COLOR_WHITE;
        }
        if (bg < BG_URGENT_LOW || bg > BG_URGENT_HIGH) {
            return Graphics.COLOR_RED;
        }
        if (bg < BG_LOW || bg > BG_HIGH) {
            return Graphics.COLOR_YELLOW;
        }
        return Graphics.COLOR_GREEN;
    }

    // Trend arrow mapping — ASCII arrows for MIP display compatibility
    private function getTrendArrow(trendRaw) {
        if (trendRaw == null || trendRaw.equals("--")) { return "-"; }
        if (trendRaw.equals("DoubleUp"))      { return "^^"; }
        if (trendRaw.equals("SingleUp"))      { return "^";  }
        if (trendRaw.equals("FortyFiveUp"))   { return "/";  }
        if (trendRaw.equals("Flat"))          { return ">";  }
        if (trendRaw.equals("FortyFiveDown")) { return "\\"; }
        if (trendRaw.equals("SingleDown"))    { return "v";  }
        if (trendRaw.equals("DoubleDown"))    { return "vv"; }
        return "-";
    }
}
