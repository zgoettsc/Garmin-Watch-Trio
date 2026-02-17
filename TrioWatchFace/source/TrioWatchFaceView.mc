using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

class TrioWatchFaceView extends WatchUi.WatchFace {

    // ── BG thresholds (mg/dL) ──
    // V2: make these configurable via Connect IQ app settings
    private const BG_URGENT_LOW  = 55;
    private const BG_LOW         = 70;
    private const BG_HIGH        = 180;
    private const BG_URGENT_HIGH = 250;

    // Loop is considered stale after 15 minutes (900 seconds)
    private const LOOP_STALE_SEC = 900;

    // ── Layout Y-coordinates (280×280 round display) ──
    private const Y_DATE         = 32;
    private const Y_TIME         = 82;
    private const Y_SEPARATOR    = 120;
    private const Y_BG           = 152;
    private const Y_DELTA        = 190;
    private const Y_IOB_COB      = 225;
    private const Y_STATUS       = 255;

    // Colors
    private const COLOR_IOB      = 0x00FFFF;  // cyan
    private const COLOR_COB      = 0xFF5500;  // orange

    function initialize() {
        WatchFace.initialize();
    }

    // Called once per minute by the system, and on-demand via WatchUi.requestUpdate()
    function onUpdate(dc) {
        var width  = dc.getWidth();
        var cx     = width / 2;

        // Black background
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Retrieve the latest Trio payload
        var app  = Application.getApp();
        var data = app.trioData;

        drawDate(dc, cx);
        drawTime(dc, cx);
        drawSeparator(dc, cx);
        drawBgAndTrend(dc, cx, data);
        drawDelta(dc, cx, data);
        drawIobCob(dc, cx, data);
        drawLoopAndBattery(dc, cx, data);
    }

    // ────────────────────────────────────────────
    //  Zone 1 — Date
    // ────────────────────────────────────────────
    private function drawDate(dc, cx) {
        var now = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = Lang.format("$1$ $2$ $3$", [now.day_of_week, now.month, now.day]);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, Y_DATE, Graphics.FONT_XTINY, dateStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ────────────────────────────────────────────
    //  Zone 2 — Time
    // ────────────────────────────────────────────
    private function drawTime(dc, cx) {
        var clock = System.getClockTime();
        var hours = clock.hour;

        if (!System.getDeviceSettings().is24Hour) {
            if (hours > 12) { hours = hours - 12; }
            if (hours == 0) { hours = 12; }
        }

        var timeStr = Lang.format("$1$:$2$", [hours, clock.min.format("%02d")]);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, Y_TIME, Graphics.FONT_NUMBER_HOT, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ────────────────────────────────────────────
    //  Separator line between time and BG
    // ────────────────────────────────────────────
    private function drawSeparator(dc, cx) {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(cx - 80, Y_SEPARATOR, cx + 80, Y_SEPARATOR);
    }

    // ────────────────────────────────────────────
    //  Zone 3 — Blood Glucose + Trend Arrow
    // ────────────────────────────────────────────
    private function drawBgAndTrend(dc, cx, data as Dictionary) {
        var glucose  = data["glucose"] as String?;
        var trendRaw = data["trendRaw"] as String?;
        var bgColor  = getBgColor(glucose);
        var bgText   = (glucose != null) ? glucose : "--";

        // Measure BG text so we can place the arrow to its right
        var bgFont  = Graphics.FONT_NUMBER_MEDIUM;
        var bgWidth = dc.getTextWidthInPixels(bgText, bgFont);
        var arrowSpace = 30;  // space reserved for the trend arrow
        var totalWidth = bgWidth + arrowSpace;
        var bgX = cx - (totalWidth / 2) + (bgWidth / 2);

        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(bgX, Y_BG, bgFont, bgText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Trend arrow drawn to the right of the BG number
        var arrowX = bgX + (bgWidth / 2) + 18;
        drawTrendArrow(dc, arrowX, Y_BG, trendRaw, bgColor);
    }

    // ────────────────────────────────────────────
    //  Zone 4 — Delta
    // ────────────────────────────────────────────
    private function drawDelta(dc, cx, data as Dictionary) {
        var delta   = data["delta"] as String?;
        var display = (delta != null) ? delta : "--";

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, Y_DELTA, Graphics.FONT_SMALL, display,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ────────────────────────────────────────────
    //  Zone 5 — IOB (left) and COB (right)
    // ────────────────────────────────────────────
    private function drawIobCob(dc, cx, data as Dictionary) {
        var iob = data["iob"] as String?;
        var cob = data["cob"] as String?;
        var iobText = (iob != null) ? (iob + "u") : "--";
        var cobText = (cob != null) ? (cob + "g") : "--";

        var spacing = 50;  // half-gap between the two labels

        // IOB — cyan, left of center
        dc.setColor(COLOR_IOB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - spacing, Y_IOB_COB, Graphics.FONT_SMALL, iobText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // COB — orange, right of center
        dc.setColor(COLOR_COB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + spacing, Y_IOB_COB, Graphics.FONT_SMALL, cobText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ────────────────────────────────────────────
    //  Zone 6 — Loop status dot/X and battery %
    // ────────────────────────────────────────────
    private function drawLoopAndBattery(dc, cx, data) {
        var loopActive = isLoopActive(data);

        // ── Loop indicator (left of center) ──
        var indicatorX = cx - 20;

        if (loopActive) {
            // Green filled circle
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(indicatorX, Y_STATUS, 5);
        } else {
            // Red X
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(indicatorX - 4, Y_STATUS - 4, indicatorX + 4, Y_STATUS + 4);
            dc.drawLine(indicatorX - 4, Y_STATUS + 4, indicatorX + 4, Y_STATUS - 4);
        }

        // ── Battery % (right of center) ──
        var battery = System.getSystemStats().battery;
        var battStr = battery.toNumber().toString() + "%";

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 20, Y_STATUS, Graphics.FONT_XTINY, battStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ════════════════════════════════════════════
    //  Helper: determine BG color from thresholds
    // ════════════════════════════════════════════
    private function getBgColor(glucose) {
        if (glucose == null) {
            return Graphics.COLOR_WHITE;
        }

        var bg = glucose.toFloat();
        if (bg == null) {
            return Graphics.COLOR_WHITE;  // non-numeric string
        }

        if (bg < BG_URGENT_LOW || bg > BG_URGENT_HIGH) {
            return Graphics.COLOR_RED;
        }
        if (bg < BG_LOW || bg > BG_HIGH) {
            return Graphics.COLOR_YELLOW;
        }
        return Graphics.COLOR_GREEN;
    }

    // ════════════════════════════════════════════
    //  Helper: is the loop recent (< 15 min)?
    // ════════════════════════════════════════════
    private function isLoopActive(data as Dictionary) {
        var loopTime = data["lastLoopDateInterval"] as Number?;
        if (loopTime == null) {
            return false;
        }
        var now = Time.now().value();
        return (now - loopTime) < LOOP_STALE_SEC;
    }

    // ════════════════════════════════════════════
    //  Helper: draw a trend arrow at (cx, cy)
    //
    //  Each arrow fits in roughly a 24×24 px area.
    //  We draw a shaft + filled arrowhead, or double
    //  chevrons for the rapid-change directions.
    // ════════════════════════════════════════════
    private function drawTrendArrow(dc, cx, cy, trendRaw, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        var s = 12;  // half-size of arrow bounding box

        if (trendRaw == null || trendRaw.equals("--")) {
            // Unknown — horizontal dash
            dc.drawLine(cx - s, cy, cx + s, cy);
            return;
        }

        if (trendRaw.equals("Flat")) {
            // →  horizontal arrow pointing right
            dc.drawLine(cx - s, cy, cx + s, cy);
            dc.fillPolygon([[cx + s, cy],
                            [cx + s - 7, cy - 5],
                            [cx + s - 7, cy + 5]]);
        }
        else if (trendRaw.equals("SingleUp")) {
            // ↑  vertical arrow pointing up
            dc.drawLine(cx, cy + s, cx, cy - s);
            dc.fillPolygon([[cx, cy - s],
                            [cx - 5, cy - s + 7],
                            [cx + 5, cy - s + 7]]);
        }
        else if (trendRaw.equals("SingleDown")) {
            // ↓  vertical arrow pointing down
            dc.drawLine(cx, cy - s, cx, cy + s);
            dc.fillPolygon([[cx, cy + s],
                            [cx - 5, cy + s - 7],
                            [cx + 5, cy + s - 7]]);
        }
        else if (trendRaw.equals("FortyFiveUp")) {
            // ↗  diagonal arrow pointing upper-right
            dc.drawLine(cx - s, cy + s, cx + s, cy - s);
            dc.fillPolygon([[cx + s, cy - s],
                            [cx + s - 9, cy - s + 1],
                            [cx + s - 1, cy - s + 9]]);
        }
        else if (trendRaw.equals("FortyFiveDown")) {
            // ↘  diagonal arrow pointing lower-right
            dc.drawLine(cx - s, cy - s, cx + s, cy + s);
            dc.fillPolygon([[cx + s, cy + s],
                            [cx + s - 9, cy + s - 1],
                            [cx + s - 1, cy + s - 9]]);
        }
        else if (trendRaw.equals("DoubleUp")) {
            // ↑↑  two chevrons pointing up (rapid rise)
            dc.fillPolygon([[cx, cy - s],
                            [cx - 6, cy - s + 9],
                            [cx + 6, cy - s + 9]]);
            dc.fillPolygon([[cx, cy - s + 12],
                            [cx - 6, cy - s + 21],
                            [cx + 6, cy - s + 21]]);
        }
        else if (trendRaw.equals("DoubleDown")) {
            // ↓↓  two chevrons pointing down (rapid fall)
            dc.fillPolygon([[cx, cy + s],
                            [cx - 6, cy + s - 9],
                            [cx + 6, cy + s - 9]]);
            dc.fillPolygon([[cx, cy + s - 12],
                            [cx - 6, cy + s - 21],
                            [cx + 6, cy + s - 21]]);
        }
        else {
            // Unrecognized trend — horizontal dash
            dc.drawLine(cx - s, cy, cx + s, cy);
        }
    }
}
