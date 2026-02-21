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

    // Data is stale after 10 minutes (600 seconds)
    private const DATA_STALE_SEC = 600;

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
        var bgColor  = getBgColor(glucose);

        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 145, Graphics.FONT_LARGE, bgText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Draw graphical trend arrow to the right of BG value
        var bgHalf = dc.getTextWidthInPixels(bgText, Graphics.FONT_LARGE) / 2;
        drawTrendArrow(dc, cx + bgHalf + 16, 145, trendRaw, bgColor);

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

        // ── Zone 6: Loop status + Loop age + Battery ──
        drawStatusRow(dc, cx, width, 250, data, app);

        // ── Zone 7: Time since last Nightscout read ──
        var readAgeStr = "--";
        if (app.lastReceiveTime > 0) {
            var readAgeSec = Time.now().value() - app.lastReceiveTime;
            if (readAgeSec < 0) { readAgeSec = 0; }
            readAgeStr = (readAgeSec / 60).toString() + "m ago";
        }
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 272, Graphics.FONT_XTINY, readAgeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ════════════════════════════════════════════
    //  Loop indicator + battery %
    // ════════════════════════════════════════════
    private function drawStatusRow(dc, cx, width, y, data, app) {
        var sp = width / 4;

        // Loop indicator: green if data received within 10 min, red otherwise
        var loopActive = false;
        if (app.lastReceiveTime > 0) {
            var age = Time.now().value() - app.lastReceiveTime;
            if (age >= 0 && age < DATA_STALE_SEC) {
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

        // Battery
        var battery = System.getSystemStats().battery;
        var battStr = battery.toNumber().toString() + "%";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + sp, y, Graphics.FONT_XTINY, battStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ════════════════════════════════════════════
    //  Graphical trend arrows
    // ════════════════════════════════════════════
    private function drawTrendArrow(dc, x, y, trendRaw, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);

        if (trendRaw == null || trendRaw.equals("--")) {
            dc.drawText(x, y, Graphics.FONT_MEDIUM, "-",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        dc.setPenWidth(3);
        var len = 12;
        var hs  = 7;

        if (trendRaw.equals("DoubleUp")) {
            drawArrowUp(dc, x, y - 9, 8, hs);
            drawArrowUp(dc, x, y + 9, 8, hs);
        } else if (trendRaw.equals("SingleUp")) {
            drawArrowUp(dc, x, y, len, hs);
        } else if (trendRaw.equals("FortyFiveUp")) {
            var d = 9;
            dc.drawLine(x - d, y + d, x + d, y - d);
            dc.drawLine(x + d, y - d, x + d - hs, y - d);
            dc.drawLine(x + d, y - d, x + d, y - d + hs);
        } else if (trendRaw.equals("Flat")) {
            dc.drawLine(x - len, y, x + len, y);
            dc.drawLine(x + len, y, x + len - hs, y - hs);
            dc.drawLine(x + len, y, x + len - hs, y + hs);
        } else if (trendRaw.equals("FortyFiveDown")) {
            var d = 9;
            dc.drawLine(x - d, y - d, x + d, y + d);
            dc.drawLine(x + d, y + d, x + d - hs, y + d);
            dc.drawLine(x + d, y + d, x + d, y + d - hs);
        } else if (trendRaw.equals("SingleDown")) {
            drawArrowDown(dc, x, y, len, hs);
        } else if (trendRaw.equals("DoubleDown")) {
            drawArrowDown(dc, x, y - 9, 8, hs);
            drawArrowDown(dc, x, y + 9, 8, hs);
        } else {
            dc.drawText(x, y, Graphics.FONT_MEDIUM, "-",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        dc.setPenWidth(1);
    }

    private function drawArrowUp(dc, x, y, len, hs) {
        dc.drawLine(x, y + len, x, y - len);
        dc.drawLine(x, y - len, x - hs, y - len + hs);
        dc.drawLine(x, y - len, x + hs, y - len + hs);
    }

    private function drawArrowDown(dc, x, y, len, hs) {
        dc.drawLine(x, y - len, x, y + len);
        dc.drawLine(x, y + len, x - hs, y + len - hs);
        dc.drawLine(x, y + len, x + hs, y + len - hs);
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
}
