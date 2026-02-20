# Trio Communication and Data Issues

Investigation and resolution of the persistent data delivery delay between the Trio iOS app and the Garmin watch face.

**Status: RESOLVED** — Transit delay reduced from 25-31 minutes to ~1 minute.

---

## Problem Summary

The Garmin watch face was displaying glucose data that was 25-31 minutes old. The watch processed messages instantly upon receipt (Rx: 0-3m), and Trio built payloads with fresh data at send time (sentAt ≈ glucoseDate), so the entire delay was in transit between the phone and the watch.

---

## Root Causes Found

The delay was **not** a Garmin middleware problem. It was caused by multiple issues on the Trio phone side in `GarminManager.swift`:

### 1. Stale Data at Build Time (Primary Cause)

The original `setupGarminWatchState()` method fetched glucose data from CoreData, but new CGM readings arrive via `NSBatchInsertRequest` which **bypasses** NSManagedObjectContext change propagation. The fetch context held stale data from its last query, so the "fresh" payload was actually built from old readings.

**Fix:** Replaced direct CoreData fetches with `LiveActivityManager.snapshotPublisher`, which receives pre-merged snapshots that are always current. The `buildWatchState(from:)` method now takes a `LiveActivitySnapshot` parameter instead of querying CoreData directly.

### 2. Four Racing Combine Triggers

The original push pipeline had four independent Combine publishers that could fire simultaneously when a new CGM reading arrived:
- `glucoseStorage.updatePublisher`
- `iobService.iobPublisher`
- CoreData save notification for `OrefDetermination`
- CoreData change notification for `GlucoseStored`

Each trigger independently called `setupGarminWatchState()`, which fetched from CoreData. Multiple concurrent fetches raced against the context merge, and whichever fired first often grabbed stale data.

**Fix:** Replaced all four triggers with a single subscription to `LiveActivityManager.snapshotPublisher`. This fires once per data update cycle with a consistent, already-merged snapshot. No race conditions.

### 3. Throttle Too Aggressive (10 seconds)

The original `.throttle(for: .seconds(10))` produced ~6 messages/minute, but the watch's one-shot `registerForPhoneAppMessageEvent()` model can only consume ~2-3 messages/minute. The excess messages queued in the ConnectIQ/GCM pipeline, creating an ever-growing backlog.

**Fix:** Changed throttle to `.throttle(for: .seconds(300))` (5 minutes), matching the CGM reading interval. At most one push per cycle keeps the queue shallow.

### 4. No In-Flight Send Gating

The original code could call `connectIQ.sendMessage()` for the same app while a previous send was still in-flight. The ConnectIQ SDK would queue these, compounding the backlog.

**Fix:** Added `appsWithInFlightSend: Set<UUID>` tracking. If a send to an app hasn't completed, the new send is skipped. The next cycle sends fresh data instead of queuing stale data.

### 5. Poll Responses Were Throttled

When the watch sent a `"status"` poll, the original `receivedMessage(_:from:)` handler rebuilt state and sent it through the same throttled `watchStateSubject` pipeline. This meant poll responses could be delayed up to 5 minutes by the throttle.

**Fix:** `receivedMessage` now calls `broadcastStateToWatchApps()` directly, bypassing the throttle entirely. It uses cached `lastWatchStateData` for instant response — no CoreData fetch needed.

### 6. No Safety Net for Dropped Updates

If the Combine pipeline stalled (publisher error, backpressure, etc.), no data would flow until the next external trigger.

**Fix:** Added a `Timer.publish(every: 5 * 60)` safety net that unconditionally re-sends `lastWatchStateData` through the pipeline. Redundant sends are naturally deduplicated by the throttle.

---

## Resolution Timeline

| Time | Transit Delay | What Changed |
|------|--------------|--------------|
| Initial | ~31 min | Baseline — 10s throttle, 4 racing triggers, stale CoreData fetches |
| +2h | ~18 min | User foregrounded Garmin Connect Mobile |
| +3h | ~28 min | Throttle changed to 300s (helped prevent new queue growth, but residual queue still draining) |
| +4h | ~22 min | Queue continuing to drain |
| +5h | ~10 min | Full Trio-side rewrite deployed (snapshot publisher, single pipeline, in-flight gating) |
| +6h | ~6 min | System stabilizing |
| +7h | ~1 min | Steady state — effectively real-time for CGM data |

---

## Current Architecture

### Trio Side (GarminManager.swift)

```
CGM Reading
    ↓
CoreData (NSBatchInsertRequest)
    ↓
LiveActivityManager context auto-merges
    ↓
LiveActivityData @Published properties update
    ↓
snapshotPublisher.send(LiveActivitySnapshot)
    ↓
GarminManager.subscribeToUpdateTriggers()
    ↓
buildWatchState(from: snapshot) → JSON encode → cache in lastWatchStateData
    ↓
watchStateSubject.send(dict)
    ↓
.throttle(300s, latest: true)
    ↓
broadcastStateToWatchApps() → sendMessage (with in-flight gating)
    ↓
ConnectIQ SDK → Garmin Connect Mobile → BLE → Watch
```

**Additional paths:**
- **Poll response:** Watch sends `"status"` → `receivedMessage` → `broadcastStateToWatchApps` (bypasses throttle, uses cached data)
- **Safety net timer:** Every 5 min → re-sends `lastWatchStateData` through throttled pipeline

### Watch Side

**Watch Face (`TrioWatchFace/`)** — background service model:
- Push path: `registerForPhoneAppMessageEvent()` (one-shot, re-registered after each delivery)
- Poll path: Temporal event every 5 min sends `"status"` to Trio
- Both paths converge through `onPhoneAppMessage()` → `Background.exit(data)` → `onBackgroundData()`

**Data Field (`TrioDataField/`)** — foreground model:
- Uses `Communications.registerForPhoneAppMessages()` directly (not one-shot)
- Sends `"status"` on startup
- Not subject to the background service constraints

### Watch-Side Source Files

| File | Role |
|------|------|
| `TrioWatchFace/source/TrioWatchFaceApp.mc` | App lifecycle, registers temporal (poll) and phone message (push) events, processes data in `onBackgroundData()`, persists to Storage |
| `TrioWatchFace/source/TrioWatchFaceView.mc` | 6-zone display: date, time, BG+trend, delta, IOB/COB, loop status+battery |
| `TrioWatchFace/source/TrioServiceDelegate.mc` | Background service — handles push and poll wake-ups via `Background.exit(msg.data)` |
| `TrioWatchFace/source/BgCommListener.mc` | Connection listener for poll transmit — on error calls `Background.exit(null)` |

### Message Format

| Field | Type | Description |
|-------|------|-------------|
| `glucose` | String | Current glucose, pre-formatted in user's units |
| `trendRaw` | String | CGM trend direction (`"Flat"`, `"FortyFiveUp"`, etc.) |
| `delta` | String | Change from previous reading with +/- prefix |
| `iob` | String | Insulin on board, 1 decimal |
| `cob` | String | Carbs on board, integer |
| `lastLoopDateInterval` | UInt64 | Unix epoch seconds of last successful loop |
| `eventualBGRaw` | String | Predicted eventual BG |
| `isf` | String | Current insulin sensitivity factor |
| `sentAt` | String | Timestamp when payload was built (HH:mm:ss) |
| `glucoseDate` | String | Timestamp of the glucose reading (HH:mm:ss) |
| `source` | String | `"push"` or `"poll"` — diagnostic field |

---

## Key Constraints

### One-Shot Message Model (Watch Face)

Garmin's ConnectIQ SDK uses a one-shot model for watch face phone app message events:
1. `Background.registerForPhoneAppMessageEvent()` registers to receive ONE message
2. Message arrives → background service wakes → `Background.exit(data)`
3. `onBackgroundData()` processes data, then **must re-register** for the next message
4. Until re-registration completes, messages queue in ConnectIQ/GCM

The watch processes messages serially with ~10-30s overhead per cycle. This is why the Trio-side throttle (300s) and in-flight gating are critical — they prevent the queue from growing faster than the watch can drain it.

### Temporal Event Minimum Interval

Watch faces can only register temporal events at a minimum of 300 seconds (5 minutes). This is a ConnectIQ SDK limitation for battery life.

---

## Lessons Learned

1. **The transport layer was a red herring.** Initial investigation focused on ConnectIQ/GCM/BLE delivery delays, but the real problem was stale data being sent from the phone. Fresh data transits the pipeline in ~1 minute.

2. **`NSBatchInsertRequest` bypasses change propagation.** CoreData batch inserts don't trigger `NSManagedObjectContextDidSave` on the inserting context. Any downstream consumer must use a context that auto-merges from the persistent store, or subscribe to a publisher that guarantees merged data.

3. **Multiple Combine triggers for the same logical event create race conditions.** When glucose, IOB, and loop determination all update within milliseconds, four independent publishers fire concurrently. The first to execute its sink may read partially-updated state. A single consolidated publisher eliminates the race.

4. **The one-shot constraint makes queue management critical.** Even a small mismatch between send rate and consume rate compounds over time. The 10s throttle produced 6x the messages the watch could process, building a 30+ minute backlog within hours.

5. **Poll responses should bypass push throttling.** The watch's background service may go back to sleep if the poll response is delayed. Direct broadcast with cached data provides instant response.

---

## Debugging Tools Used

- **Debug watch face:** Temporarily replaced the production watch face with a raw data dump showing all received fields with type annotations (`key(S)=value`) and an Rx age counter. This made it possible to see exactly what Trio sent and when it arrived.

- **`sentAt` field:** Diagnostic timestamp added to the payload showing when Trio built it. Comparing `sentAt` to watch display time reveals the transit delay.

- **`source` field:** Distinguishes push vs poll deliveries for path diagnosis.

- **`Rx:Nm` display:** Shows minutes since the watch received the last message, confirming the watch processes data instantly upon receipt.

---

## Trio-Side Files Modified

All changes on branch `claude/fix-garmin-stale-data-M7QCh` of the Trio repo:

| File | Changes |
|------|---------|
| `GarminManager.swift` | Replaced 4 racing triggers with single `snapshotPublisher` subscription; replaced CoreData fetch with snapshot-based `buildWatchState(from:)`; added in-flight send gating; added periodic refresh timer; poll response bypasses throttle and uses cached data |
| `GarminWatchState.swift` | Added `source` field; `Equatable`/`Hashable` exclude diagnostic fields (`sentAt`, `glucoseDate`, `source`) |
