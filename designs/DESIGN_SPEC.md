# Trio Garmin Watch Apps — Design Specification

## Target Device
- **Garmin Enduro 2** (Connect IQ device ID: `fenix7x`)
- 280x280 pixel round MIP (memory-in-pixel) display
- 64-color palette
- Always-on display

## Apps to Build

### 1. Watch Face (TrioWatchFace)
### 2. Data Field (TrioDataField)

Each gets its own unique UUID from the Connect IQ developer portal.

---

## Watch Face Design

### Layout (top to bottom)

| Zone | Content | Font Size | Color | Y Range (approx) |
|------|---------|-----------|-------|-------------------|
| 1 | Date: `Tue Feb 17` | Small (~16px) | Light gray | 30–50 |
| 2 | Time: `10:42` | Largest (~50px) | White | 55–110 |
| 3 | BG + Trend: `120 →` | Large (~42px) | Dynamic (see below) | 120–170 |
| 4 | Delta: `+5` | Medium (~22px) | White | 170–195 |
| 5 | IOB / COB: `2.5u  25g` | Small-med (~20px) | Cyan / Orange | 210–235 |
| 6 | Loop status + Battery | Tiny (~12px) | Green/Red + White | 240–260 |

### BG Color Thresholds (mg/dL)

| Range | Color | Meaning |
|-------|-------|---------|
| 70–180 | Green | In range |
| 55–70 | Yellow | Low caution |
| 180–250 | Yellow | High caution |
| < 55 | Red | Urgent low |
| > 250 | Red | Urgent high |

*V2: Make these configurable via Connect IQ app settings.*

### BG Color Application
- BG value text: colored
- Trend arrow: same color as BG (reinforces urgency)
- Delta: always white (neutral)

### Trend Arrow Mapping

| trendRaw | Display | Description |
|----------|---------|-------------|
| `"DoubleUp"` | ↑↑ | Rapid rise |
| `"SingleUp"` | ↑ | Rising |
| `"FortyFiveUp"` | ↗ | Slowly rising |
| `"Flat"` | → | Stable |
| `"FortyFiveDown"` | ↘ | Slowly falling |
| `"SingleDown"` | ↓ | Falling |
| `"DoubleDown"` | ↓↓ | Rapid fall |
| `"--"` or null | — | Unknown |

### Loop Status Indicator
- **Green filled circle** (●): Last loop within 15 minutes
- **Red X**: Last loop older than 15 minutes OR no data
- Calculated from: `currentTime - lastLoopDateInterval > 900 seconds`

### Battery Indicator
- Battery percentage from watch system
- Displayed small, near loop indicator at bottom
- Format: `85%`
- White text

### IOB / COB Labels
- IOB: value + `u` suffix (e.g., `2.5u`) — Cyan/light blue
- COB: value + `g` suffix (e.g., `25g`) — Orange/amber
- No "IOB"/"COB" text labels

### No Data State
- All Trio fields show `--` as placeholder
- Loop indicator shows red X
- Time, date, battery always functional (from watch)

### Units
- mg/dL (Trio pre-formats, watch displays as-is)

---

## Data Field Design

### Priority Data (always shown)
1. BG value + Trend arrow
2. Delta
3. IOB

### Secondary Data (shown when space allows)
4. COB

### Omitted from Data Field
- Loop status indicator (not critical during activity)
- Date/time (provided by activity screen)
- Battery (provided by activity screen)

### Layout Variants

**Wide single field (full width):**
```
  120 →  +5     2.5u   25g
```
Single row: BG, trend, delta, IOB, COB

**Tall single field:**
```
       120  →   +5
       2.5u     25g
```
Two rows: BG+trend+delta on row 1, IOB+COB on row 2

**Small field (quarter screen):**
```
       120 →
     +5   2.5u
```
Two rows: BG+trend, delta+IOB (COB dropped)

### Color Behavior
- Same BG color thresholds as watch face
- Other text adapts to activity screen background (white on dark, black on light)

---

## Communication Protocol

### Receiving Data from Trio
- Register `Communications.registerForPhoneAppMessages()` on app start
- Parse incoming dictionary:
  - `glucose` → String? → BG display
  - `trendRaw` → String? → arrow mapping
  - `delta` → String? → delta display
  - `iob` → String? → IOB + "u"
  - `cob` → String? → COB + "g"
  - `lastLoopDateInterval` → Number? → loop staleness calc
  - `eventualBGRaw` → String? → stored but not displayed (V2)
  - `isf` → String? → stored but not displayed (V2)

### Requesting Data
- On app start: transmit `"status"` to request immediate data from Trio
- Handles case where watch app starts after Trio (no push waiting)

### Null Handling
- Any field can be null → display `"--"`
- Loop staleness: null → treat as inactive (red X)

---

## Trio-Side Changes (User Responsibility)

The user will modify Trio's `GarminManager.swift` to register the new app UUIDs.

**File:** `Trio/Sources/Services/WatchManager/GarminManager.swift` (lines 621–627)

**Change from:**
```swift
private enum Config {
    static let watchfaceUUID = UUID(uuidString: "EC3420F6-027D-49B3-B45F-D81D6D3ED90A")
    static let watchdataUUID = UUID(uuidString: "71CF0982-CA41-42A5-8441-EA81D36056C3")
}
```

**Change to (Option A — replace existing):**
```swift
private enum Config {
    static let watchfaceUUID = UUID(uuidString: "<NEW-WATCHFACE-UUID>")
    static let watchdataUUID = UUID(uuidString: "<NEW-DATAFIELD-UUID>")
}
```

The actual UUIDs will be assigned by the Connect IQ developer portal when the apps are created. We will provide these to the user once known.

---

## Project Structure (Connect IQ / Monkey C)

```
TrioWatchFace/
├── manifest.xml              # App metadata, UUID, supported devices
├── resources/
│   ├── strings.xml           # String resources
│   ├── drawables.xml         # Drawable resources (bitmaps)
│   ├── layouts/
│   │   └── layout.xml        # Watchface layout definition
│   └── fonts/                # Custom fonts if needed
├── source/
│   ├── TrioWatchFaceApp.mc   # App entry point
│   ├── TrioWatchFaceView.mc  # Main view (onUpdate draws the face)
│   ├── TrioData.mc           # Data model (stores parsed Trio state)
│   └── TrioComms.mc          # Communications handler
└── monkey.jungle             # Build configuration

TrioDataField/
├── manifest.xml
├── resources/
│   ├── strings.xml
│   └── drawables.xml
├── source/
│   ├── TrioDataFieldApp.mc   # App entry point
│   ├── TrioDataFieldView.mc  # Field rendering (compute + onUpdate)
│   └── TrioData.mc           # Shared data model
└── monkey.jungle
```

---

## V2 Features (Future)
- User-configurable BG thresholds via Connect IQ app settings
- Eventual BG display option
- ISF display option
- Mini BG trend graph (last 30–60 min of readings stored on watch)
- Vibration/alert on urgent high/low
- Multiple device support beyond Enduro 2
