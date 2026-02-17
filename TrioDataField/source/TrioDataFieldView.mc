using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

class TrioDataFieldView extends WatchUi.DataField {

    // ── BG thresholds (mg/dL) — same as watch face ──
    private const BG_URGENT_LOW  = 55;
    private const BG_LOW         = 70;
    private const BG_HIGH        = 180;
    private const BG_URGENT_HIGH = 250;

    function initialize() {
        DataField.initialize();
    }

    // compute() is called on each activity recording tick.
    // We don't use activity info — our data comes from Trio.
    function compute(info) {
    }

    function onUpdate(dc) {
        var width  = dc.getWidth();
        var height = dc.getHeight();
        var cx     = width / 2;
        var cy     = height / 2;

        // Use the field's background color
        var bgColor = getBackgroundColor();
        dc.setColor(bgColor, bgColor);
        dc.clear();

        // Default text color: inverse of background
        var textColor = (bgColor == Graphics.COLOR_BLACK)
            ? Graphics.COLOR_WHITE
            : Graphics.COLOR_BLACK;

        var app  = Application.getApp();
        var data = app.trioData;

        if (height >= 100) {
            drawTallLayout(dc, width, height, cx, cy, data, textColor);
        } else if (height >= 50) {
            drawMediumLayout(dc, width, height, cx, cy, data, textColor);
        } else {
            drawCompactLayout(dc, width, height, cx, cy, data, textColor);
        }
    }

    // ────────────────────────────────────────────
    //  Tall layout (single-field or large area)
    //
    //  Row 1:   120  →   +5
    //  Row 2:   2.5u     25g
    // ────────────────────────────────────────────
    private function drawTallLayout(dc, w, h, cx, cy, data, textColor) {
        var glucose  = data["glucose"];
        var trendRaw = data["trendRaw"];
        var delta    = data["delta"];
        var iob      = data["iob"];
        var cob      = data["cob"];

        var bgColorVal = getBgColor(glucose);
        var bgText  = (glucose != null) ? glucose : "--";
        var tArrow  = getTrendText(trendRaw);
        var dText   = (delta != null) ? delta : "--";
        var iobText = (iob != null) ? (iob + "u") : "--";
        var cobText = (cob != null) ? (cob + "g") : "--";

        // Row 1: BG  arrow  delta
        var row1Y = cy - h / 6;
        var row1Str = bgText + " " + tArrow + "  " + dText;

        dc.setColor(bgColorVal, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, row1Y, Graphics.FONT_MEDIUM, row1Str,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Row 2: IOB   COB
        var row2Y = cy + h / 5;
        var spacing = w / 5;

        dc.setColor(0x00FFFF, Graphics.COLOR_TRANSPARENT);  // cyan
        dc.drawText(cx - spacing, row2Y, Graphics.FONT_SMALL, iobText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(0xFF5500, Graphics.COLOR_TRANSPARENT);  // orange
        dc.drawText(cx + spacing, row2Y, Graphics.FONT_SMALL, cobText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ────────────────────────────────────────────
    //  Medium layout (half-screen field)
    //
    //  120 →  +5   2.5u   25g
    // ────────────────────────────────────────────
    private function drawMediumLayout(dc, w, h, cx, cy, data, textColor) {
        var glucose  = data["glucose"];
        var trendRaw = data["trendRaw"];
        var delta    = data["delta"];
        var iob      = data["iob"];

        var bgColorVal = getBgColor(glucose);
        var bgText  = (glucose != null) ? glucose : "--";
        var tArrow  = getTrendText(trendRaw);
        var dText   = (delta != null) ? delta : "--";
        var iobText = (iob != null) ? (iob + "u") : "--";

        // BG + trend + delta on left, IOB on right
        var leftStr = bgText + " " + tArrow + " " + dText;

        dc.setColor(bgColorVal, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - w / 6, cy, Graphics.FONT_SMALL, leftStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(0x00FFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + w / 3, cy, Graphics.FONT_SMALL, iobText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ────────────────────────────────────────────
    //  Compact layout (quarter-screen / tiny field)
    //
    //  120 →
    //  +5  2.5u
    // ────────────────────────────────────────────
    private function drawCompactLayout(dc, w, h, cx, cy, data, textColor) {
        var glucose  = data["glucose"];
        var trendRaw = data["trendRaw"];
        var delta    = data["delta"];
        var iob      = data["iob"];

        var bgColorVal = getBgColor(glucose);
        var bgText  = (glucose != null) ? glucose : "--";
        var tArrow  = getTrendText(trendRaw);
        var dText   = (delta != null) ? delta : "--";
        var iobText = (iob != null) ? (iob + "u") : "--";

        // Row 1: BG + trend
        dc.setColor(bgColorVal, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - h / 5, Graphics.FONT_TINY, bgText + " " + tArrow,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Row 2: delta + IOB
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + h / 5, Graphics.FONT_XTINY, dText + "  " + iobText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ════════════════════════════════════════════
    //  Helpers
    // ════════════════════════════════════════════

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

    // Text-based trend arrow for the compact data field layouts.
    // (The watch face uses graphical arrows; the data field uses text
    //  characters so they inline naturally with the BG string.)
    private function getTrendText(trendRaw) {
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
