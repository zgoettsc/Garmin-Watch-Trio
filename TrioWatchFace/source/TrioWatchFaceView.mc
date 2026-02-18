using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

class TrioWatchFaceView extends WatchUi.WatchFace {

    // ── BG thresholds (mg/dL) ──
    private const BG_URGENT_LOW  = 55;
    private const BG_LOW         = 70;
    private const BG_HIGH        = 180;
    private const BG_URGENT_HIGH = 250;

    // Loop is considered stale after 15 minutes (900 seconds)
    private const LOOP_STALE_SEC = 900;

    // Offset between Unix epoch (Jan 1, 1970) and Garmin epoch (Dec 31, 1989).
    private const UNIX_EPOCH_OFFSET = 631065600;

    // ── Layout Y-coordinates (280×280 round display) ──
    // DIAGNOSTIC BUILD: time replaced with debug info in the wide center area
    private const Y_DATE         = 28;
    private const Y_DIAG1        = 58;   // was time — now "Rx:1m  keys:7  85%"
    private const Y_DIAG2        = 80;   // raw LDI type + value
    private const Y_DIAG3        = 102;  // extra diag line (now_g / now_u)
    private const Y_SEPARATOR    = 118;
    private const Y_BG           = 150;
    private const Y_DELTA        = 188;
    private const Y_IOB_COB      = 222;
    private const Y_STATUS       = 252;

    // Colors
    private const COLOR_IOB      = 0x00FFFF;  // cyan
    private const COLOR_COB      = 0xFF5500;  // orange

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

        drawDate(dc, cx);
        drawDiagnostics(dc, cx, data);   // replaces drawTime temporarily
        drawSeparator(dc, cx);
        drawBgAndTrend(dc, cx, data);
        drawDelta(dc, cx, data);
        drawIobCob(dc, cx, data);
        drawStatusLine(dc, cx, data);
    }

    // ── Date ──
    private function drawDate(dc, cx) {
        var now = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = Lang.format("$1$ $2$ $3$", [now.day_of_week, now.month, now.day]);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, Y_DATE, Graphics.FONT_XTINY, dateStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ════════════════════════════════════════════
    //  DIAGNOSTIC PANEL — temporarily replaces time
    //  Three lines in the wide center of the round display:
    //    Line 1: "Rx:1m  keys:7  85%"
    //    Line 2: "LDI typ:N val:1771286400"
    //    Line 3: "nowG:1140M nowU:1771M"
    // ════════════════════════════════════════════
    private function drawDiagnostics(dc, cx, data) {
        var app = Application.getApp();

        // ── Line 1: Rx age, key count, battery ──
        var rxStr = "--";
        var rxStale = true;
        if (app.lastReceiveTime > 0) {
            var ageSec = Time.now().value() - app.lastReceiveTime;
            if (ageSec >= 0) {
                var ageMin = ageSec / 60;
                rxStale = (ageMin > 10);
                rxStr = ageMin.toString();
            } else {
                rxStr = "0";
                rxStale = false;
            }
        }

        var keyCount = 0;
        if (data instanceof Lang.Dictionary) {
            keyCount = data.keys().size();
        }

        var battery = System.getSystemStats().battery;
        var line1 = "Rx:" + rxStr + "m  k:" + keyCount + "  " + battery.toNumber().toString() + "%";

        dc.setColor(rxStale ? Graphics.COLOR_RED : Graphics.COLOR_GREEN,
                     Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, Y_DIAG1, Graphics.FONT_XTINY, line1,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Line 2: raw lastLoopDateInterval — type and value ──
        var loopTime = data["lastLoopDateInterval"];
        var line2 = "LDI:null";
        if (loopTime != null) {
            var typeCode = "?";
            if (loopTime instanceof Long)   { typeCode = "Long"; }
            else if (loopTime instanceof Number) { typeCode = "Num"; }
            else if (loopTime instanceof Float)  { typeCode = "Flt"; }
            else if (loopTime instanceof Double) { typeCode = "Dbl"; }
            else if (loopTime instanceof String) { typeCode = "Str"; }
            line2 = "LDI:" + typeCode + " " + loopTime.toString();
        }

        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, Y_DIAG2, Graphics.FONT_XTINY, line2,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Line 3: show Garmin now and Unix now for epoch verification ──
        var nowGarmin = Time.now().value();
        var nowUnix = nowGarmin + UNIX_EPOCH_OFFSET;
        // Show in millions to save space (e.g., "1140M" and "1771M")
        var line3 = "gNow:" + (nowGarmin / 1000000).toString() + "M"
                  + " uNow:" + (nowUnix / 1000000).toString() + "M";

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, Y_DIAG3, Graphics.FONT_XTINY, line3,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ── Separator ──
    private function drawSeparator(dc, cx) {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(cx - 80, Y_SEPARATOR, cx + 80, Y_SEPARATOR);
    }

    // ── BG + Trend Arrow ──
    private function drawBgAndTrend(dc, cx, data) {
        var glucose  = data["glucose"];
        var trendRaw = data["trendRaw"];
        var bgColor  = getBgColor(glucose);
        var bgText   = (glucose != null) ? glucose : "--";

        var bgFont  = Graphics.FONT_NUMBER_MEDIUM;
        var bgWidth = dc.getTextWidthInPixels(bgText, bgFont);
        var arrowSpace = 30;
        var totalWidth = bgWidth + arrowSpace;
        var bgX = cx - (totalWidth / 2) + (bgWidth / 2);

        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(bgX, Y_BG, bgFont, bgText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var arrowX = bgX + (bgWidth / 2) + 18;
        drawTrendArrow(dc, arrowX, Y_BG, trendRaw, bgColor);
    }

    // ── Delta ──
    private function drawDelta(dc, cx, data) {
        var delta   = data["delta"];
        var display = (delta != null) ? delta : "--";

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, Y_DELTA, Graphics.FONT_SMALL, display,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ── IOB / COB ──
    private function drawIobCob(dc, cx, data) {
        var iob = data["iob"];
        var cob = data["cob"];
        var iobText = (iob != null) ? (iob + "u") : "--";
        var cobText = (cob != null) ? (cob + "g") : "--";

        var spacing = 50;

        dc.setColor(COLOR_IOB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - spacing, Y_IOB_COB, Graphics.FONT_SMALL, iobText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_COB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + spacing, Y_IOB_COB, Graphics.FONT_SMALL, cobText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ── Status line: loop dot + time (moved here) ──
    private function drawStatusLine(dc, cx, data) {
        var loopActive = isLoopActive(data);

        // Loop indicator
        var indicatorX = cx - 35;
        if (loopActive) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(indicatorX, Y_STATUS, 5);
        } else {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(indicatorX - 4, Y_STATUS - 4, indicatorX + 4, Y_STATUS + 4);
            dc.drawLine(indicatorX - 4, Y_STATUS + 4, indicatorX + 4, Y_STATUS - 4);
        }

        // Time (moved to bottom status line)
        var clock = System.getClockTime();
        var hours = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            if (hours > 12) { hours = hours - 12; }
            if (hours == 0) { hours = 12; }
        }
        var timeStr = Lang.format("$1$:$2$", [hours, clock.min.format("%02d")]);

        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 20, Y_STATUS, Graphics.FONT_SMALL, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ── BG color from thresholds ──
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

    // ── Loop freshness check ──
    private function isLoopActive(data) {
        var loopTime = data["lastLoopDateInterval"];
        if (loopTime == null) {
            return false;
        }
        var nowUnix = Time.now().value() + UNIX_EPOCH_OFFSET;
        return (nowUnix - loopTime) < LOOP_STALE_SEC;
    }

    // ── Trend arrow drawing ──
    private function drawTrendArrow(dc, cx, cy, trendRaw, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        var s = 12;

        if (trendRaw == null || trendRaw.equals("--")) {
            dc.drawLine(cx - s, cy, cx + s, cy);
            return;
        }

        if (trendRaw.equals("Flat")) {
            dc.drawLine(cx - s, cy, cx + s, cy);
            dc.fillPolygon([[cx + s, cy],
                            [cx + s - 7, cy - 5],
                            [cx + s - 7, cy + 5]]);
        }
        else if (trendRaw.equals("SingleUp")) {
            dc.drawLine(cx, cy + s, cx, cy - s);
            dc.fillPolygon([[cx, cy - s],
                            [cx - 5, cy - s + 7],
                            [cx + 5, cy - s + 7]]);
        }
        else if (trendRaw.equals("SingleDown")) {
            dc.drawLine(cx, cy - s, cx, cy + s);
            dc.fillPolygon([[cx, cy + s],
                            [cx - 5, cy + s - 7],
                            [cx + 5, cy + s - 7]]);
        }
        else if (trendRaw.equals("FortyFiveUp")) {
            dc.drawLine(cx - s, cy + s, cx + s, cy - s);
            dc.fillPolygon([[cx + s, cy - s],
                            [cx + s - 9, cy - s + 1],
                            [cx + s - 1, cy - s + 9]]);
        }
        else if (trendRaw.equals("FortyFiveDown")) {
            dc.drawLine(cx - s, cy - s, cx + s, cy + s);
            dc.fillPolygon([[cx + s, cy + s],
                            [cx + s - 9, cy + s - 1],
                            [cx + s - 1, cy + s - 9]]);
        }
        else if (trendRaw.equals("DoubleUp")) {
            dc.fillPolygon([[cx, cy - s],
                            [cx - 6, cy - s + 9],
                            [cx + 6, cy - s + 9]]);
            dc.fillPolygon([[cx, cy - s + 12],
                            [cx - 6, cy - s + 21],
                            [cx + 6, cy - s + 21]]);
        }
        else if (trendRaw.equals("DoubleDown")) {
            dc.fillPolygon([[cx, cy + s],
                            [cx - 6, cy + s - 9],
                            [cx + 6, cy + s - 9]]);
            dc.fillPolygon([[cx, cy + s - 12],
                            [cx - 6, cy + s - 21],
                            [cx + 6, cy + s - 21]]);
        }
        else {
            dc.drawLine(cx - s, cy, cx + s, cy);
        }
    }
}
