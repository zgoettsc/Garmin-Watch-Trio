# Trio Communication and Data Issues

Investigation document for the persistent data delivery delay between the Trio iOS app and the Garmin watch face.

---

## Current Watch-Side Architecture

### Two Data Paths

The watch face receives data through two independent paths:

**Path A: Push (Trio-initiated)**
```
Trio iOS App → ConnectIQ SDK → Garmin Connect Mobile (GCM) → BLE → Watch
```
- Trio proactively sends `GarminWatchState` when glucose/IOB/COB/loop data changes
- Throttled at 300 seconds (5 minutes) via Combine `.throttle()` on `GarminManager.swift:321`
- Watch wakes via `registerForPhoneAppMessageEvent()` (one-shot, re-registered after each delivery)

**Path B: Poll (watch-initiated)**
```
Watch → BLE → GCM → Trio → (builds fresh state) → GCM → BLE → Watch
```
- Watch sends `"status"` string via `Communications.transmit()` every 5 minutes (temporal event)
- Trio's `receivedMessage(_:from:)` (line 520) responds immediately by calling `broadcastStateToWatchApps()` directly, **bypassing the throttle**
- This is a fallback to ensure data arrives even if push delivery fails

### Watch-Side Source Files

| File | Role |
|------|------|
| `TrioWatchFace/source/TrioWatchFaceApp.mc` | App lifecycle, registers both temporal (poll) and phone message (push) events, processes incoming data in `onBackgroundData()`, persists to Storage |
| `TrioWatchFace/source/TrioServiceDelegate.mc` | Background service — handles both push and poll wake-ups, exits via `Background.exit(msg.data)` |
| `TrioWatchFace/source/BgCommListener.mc` | Connection listener for poll transmit — on error calls `Background.exit(null)` so the service terminates cleanly |
| `TrioWatchFace/source/TrioWatchFaceView.mc` | Debug display — shows raw key/value dump with Rx age |

### One-Shot Message Model (Critical Constraint)

Garmin's ConnectIQ SDK uses a **one-shot** model for watch face phone app message events:

1. `Background.registerForPhoneAppMessageEvent()` registers the watch to receive ONE message
2. When a message arrives, the background service wakes, processes it, and calls `Background.exit(data)`
3. `onBackgroundData()` in the foreground app handles the data, then **must re-register** for the next message
4. Until re-registration completes, no further messages can be delivered — they queue in the ConnectIQ/GCM layer

This means the watch can only process messages **serially**, with system overhead per cycle (estimated 10-30 seconds per message including wake, process, exit, re-register, next delivery).

### Temporal Event (Poll) Details

Registered in `onStart()` at `TrioWatchFaceApp.mc:41`:
```monkeyc
Background.registerForTemporalEvent(new Time.Duration(300));  // 5 min minimum for watch faces
```

When it fires (`TrioServiceDelegate.mc:31-33`):
```monkeyc
function onTemporalEvent() {
    Communications.registerForPhoneAppMessages(method(:onPhoneAppMessage));
    Communications.transmit("status", null, new BgCommListener());
}
```

The temporal event sends `"status"` to Trio, which triggers an **immediate** response (bypasses the push throttle). If the transmit fails (phone disconnected, GCM not running), `BgCommListener.onError()` calls `Background.exit(null)` so the background service terminates and the next temporal event can fire.

### Data Field App (Simpler Model)

The data field (`TrioDataField/`) uses a simpler model — it's NOT a watch face, so it can use foreground `Communications` directly:
- Registers `Communications.registerForPhoneAppMessages()` in `onStart()`
- Sends `"status"` on startup to request initial data
- Receives messages in `onPhoneMessage()` callback (foreground, not one-shot)

This app type is **not subject to the same one-shot constraint** and should not exhibit the same delivery delay.

---

## Trio (Phone) Side — What We Know

### Message Assembly

Trio builds `GarminWatchState` with these fields (all strings except `lastLoopDateInterval` which is UInt64):

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
| `sentAt` | String | Timestamp when the payload was built (HH:mm:ss) |
| `glucoseDate` | String | Timestamp of the glucose reading itself (HH:mm:ss) |

### Push Triggers

The push pipeline fires when any of these Combine publishers emit:
- `glucoseStorage.updatePublisher` — new CGM reading
- `iobService.iobPublisher` — IOB recalculated
- CoreData save notification for `OrefDetermination` — new loop result
- CoreData change notification for `GlucoseStored` — glucose entry deleted
- `SettingsObserver` callback — user changes glucose unit preference

### Throttle (Recently Changed)

**Previous:** 10-second throttle (`GarminManager.swift:321`)
**Current:** 300-second throttle (changed to match CGM reading interval)

The change was made because the 10-second throttle produced ~6 messages/minute while the watch's one-shot model was estimated to consume only ~2-3/minute, potentially causing unbounded queue growth.

### Poll Response Path

`receivedMessage(_:from:)` at `GarminManager.swift:520` handles incoming `"status"` messages from the watch. It calls `broadcastStateToWatchApps()` **directly**, bypassing `watchStateSubject` and its throttle. This means poll responses should be immediate — no throttle delay.

### Message Dispatch

For each registered `IQApp` in `watchApps`:
1. Check if installed via `connectIQ.getAppStatus()`
2. Send via `connectIQ.sendMessage(dict, to: app, progress:, completion:)`
3. ConnectIQ SDK handles handoff to Garmin Connect Mobile

---

## Observed Data Delay — Field Evidence

### Observation 1: ~31 minute delay
```
Watch time:   7:21 PM
sentAt:       18:50:04 (6:50 PM)
glucoseDate:  18:49:59
Rx:           0m
```
- **Transit time (sentAt → watch):** ~31 minutes
- **Rx: 0m** — watch just received it, processed instantly
- The message sat in the ConnectIQ/GCM pipeline for 31 minutes before the watch got it

### Observation 2: ~18 minute delay (improvement during active testing)
```
Watch time:   7:52 PM
sentAt:       19:34:25 (7:34 PM)
glucoseDate:  19:34:18
Rx:           0m
```
- **Transit time:** ~18 minutes
- User had Garmin Connect Mobile in the foreground for 12 minutes before this reading
- Delay improved but did NOT become fresh — still 18 minutes behind

### Observation 3: ~28 minute delay (after 300s throttle change)
```
Watch time:   9:57 PM
sentAt:       21:29:24 (9:29 PM)
glucoseDate:  21:29:19
Rx:           3m
```
- **Transit time (sentAt → received):** ~25 minutes (received at ~9:54, sent at 9:29)
- **Rx: 3m** — watch received it 3 minutes ago (displayed on next face update)
- The 300-second throttle change did NOT resolve the delay
- Delay got worse again compared to observation 2

### Key Patterns

1. **`sentAt` and `glucoseDate` are always within seconds of each other** — Trio is building payloads with fresh data at send time. The phone side is NOT the source of staleness.

2. **Rx is always small (0-3 minutes)** — the watch processes messages immediately upon receipt. The watch side is NOT the source of staleness.

3. **The entire delay is in transit:** Trio → ConnectIQ SDK → GCM → BLE → Watch. This is a black box we do not control.

4. **The delay fluctuates (31 → 18 → 28)** — this is inconsistent with a simple FIFO queue model, which would show monotonically decreasing delay as the queue drains. The fluctuation suggests external factors: iOS app suspension, GCM sync windows, or BLE connection scheduling.

5. **Foregrounding GCM helped partially but did not fix it** — 12 minutes with GCM open reduced delay from 31 to 18 minutes, but never to fresh data. This suggests GCM foreground state is a factor but not the only one.

6. **Switching watch faces sometimes helps** — this re-runs `onStart()`, re-registers both temporal and phone message events, and may trigger BLE activity that prompts GCM to flush queued messages.

---

## Potential Causes Under Investigation

### 1. Residual Message Queue from Old 10s Throttle
**Theory:** Before the throttle was changed to 300s, the 10-second throttle may have accumulated hundreds of messages in the ConnectIQ queue. These must drain FIFO before new (300s-throttle) messages reach the watch. At ~20-30 seconds per one-shot cycle, draining 500 messages takes 3-6 hours.

**Evidence for:** The delay hasn't improved yet after the throttle change, and only ~2 hours had passed.
**Evidence against:** The fluctuation (31 → 18 → 28) doesn't match a steady queue drain.
**Test:** Kill Trio, kill GCM, switch away from watch face and back, reopen GCM, reopen Trio. This should clear any residual queue. If the delay persists after a clean restart, this theory is eliminated.

### 2. GCM Message Delivery is Inherently Batched/Delayed
**Theory:** Garmin Connect Mobile may not relay ConnectIQ messages to the watch in real time. It may batch deliveries on its own schedule (e.g., during periodic sync windows every 15-30 minutes), regardless of when `sendMessage()` was called.

**Evidence for:** The ~30 minute delay is suspiciously close to typical GCM sync intervals. Foregrounding GCM improved but didn't eliminate delay — GCM may have internal scheduling independent of iOS app state.
**Evidence against:** If this were purely a sync interval issue, foregrounding GCM should have overridden the schedule and delivered immediately.
**Test:** Check if other ConnectIQ apps (e.g., a simple test app) also experience delivery delays when receiving messages from a companion app.

### 3. iOS Background Execution Limits on GCM and/or Trio
**Theory:** iOS suspends background apps aggressively. When Trio calls `connectIQ.sendMessage()`, the ConnectIQ SDK hands the message to GCM via IPC. If GCM is suspended by iOS, this handoff may fail silently or queue. Similarly, when the watch sends `"status"` and it reaches GCM, if Trio is suspended, GCM cannot forward the request.

**Evidence for:** The fluctuating delay correlates with periods of phone activity vs. inactivity. The delay was shortest (18 min) during active testing when the user was interacting with the phone.
**Evidence against:** Foregrounding GCM for 12 minutes didn't produce fresh data. If iOS suspension were the sole cause, foregrounding should have fixed it immediately.
**Test:** Keep BOTH Trio AND GCM in foreground (split screen or rapid switching) and observe if delay drops to near-zero. If it does, iOS suspension is confirmed as a major factor.

### 4. ConnectIQ SDK Internal Queue/Rate Limiting
**Theory:** The ConnectIQ Mobile SDK may have internal rate limiting or queuing that introduces delay independent of GCM's state. Even with GCM foregrounded, the SDK may batch messages for delivery at intervals.

**Evidence for:** Delay persisted even with GCM in foreground.
**Evidence against:** This would be a Garmin SDK design limitation documented somewhere.
**Test:** Review ConnectIQ SDK documentation for any mention of message delivery timing, batching, or rate limits. Also test with the ConnectIQ simulator where BLE isn't a factor.

### 5. BLE Connection Interval
**Theory:** The Bluetooth Low Energy connection between the phone and watch has a connection interval that determines how often data can be exchanged. If GCM negotiates a long connection interval (for battery), message delivery is delayed until the next BLE window.

**Evidence for:** BLE connection intervals can range from 7.5ms to 4 seconds, and in practice Garmin watches use longer intervals for battery life.
**Evidence against:** BLE intervals are measured in seconds, not the 25-30 minutes we're observing. This alone cannot explain the delay but could compound other issues.

### 6. Background Service Contention on the Watch
**Theory:** The watch's background service is a shared resource. Only one background task can run at a time. If the temporal event (poll) fires while a push message is being delivered (or vice versa), one may be blocked or dropped.

**Evidence for:** The temporal event fires every 5 minutes and the push can arrive at any time. The poll's `Communications.transmit("status")` occupies the background service until the response arrives or `BgCommListener.onError()` fires.
**Evidence against:** The watch code handles both paths through the same `onPhoneAppMessage()` handler, and `Background.exit()` always terminates the service. Contention would cause occasional dropped messages, not consistent 30-minute delays.

---

## What We Have Adapted (Changes Made So Far)

1. **Throttle increase (Trio side):** Changed `GarminManager.swift:321` from `.throttle(for: .seconds(10))` to `.throttle(for: .seconds(300))` to prevent flooding the one-shot message queue. Poll response path remains unthrottled.

2. **Debug watch face (watch side):** Current watch face view (`TrioWatchFaceView.mc`) is a raw data dump showing all received fields with type annotations and an Rx age counter. This enables field diagnosis of delivery timing.

3. **Documented one-shot re-registration (watch side):** Added explicit comments and ensured `registerForPhoneAppMessageEvent()` is called after every `onBackgroundData()` exit, including null/error cases (`TrioWatchFaceApp.mc:98-102`).

---

## Recommended Next Steps

### Immediate: Clean Restart Test
Kill Trio, kill GCM, switch to a different watch face, wait 30 seconds, switch back to the Trio watch face, reopen GCM, reopen Trio. This eliminates any residual message queue and tests the 300s throttle from a clean state. **If the delay persists after this, the queue theory is eliminated and the issue is in the ConnectIQ/GCM delivery infrastructure.**

### Add sentAt-vs-now Staleness Display on Watch
Modify the watch face to calculate and display the age of `sentAt` relative to the current watch time. This makes the transit delay immediately visible without manual subtraction.

### Test Poll-Only Mode
Temporarily disable push on the Trio side (comment out the throttled pipeline that writes to `watchStateSubject`). Only the poll path remains: the watch requests data every 5 minutes via `"status"`, Trio responds immediately. If the poll response arrives within seconds, the push delivery pipeline (or its queue) is the issue. If the poll response is also delayed by 25+ minutes, the problem is in the GCM/BLE layer itself and affects ALL ConnectIQ communication.

### Instrument the Trio Side
Add logging in `connectIQ.sendMessage()` completion handler to record whether messages are being accepted or rejected by the ConnectIQ SDK. If `sendMessage` reports errors, GCM may not be relaying.

### Investigate ConnectIQ SDK Documentation
Search for any documented behavior around message delivery timing, SDK-level queuing, or delivery guarantees. The ConnectIQ Mobile SDK may have known limitations or configuration options for delivery behavior.

### Test with ConnectIQ Simulator
Use the Garmin ConnectIQ simulator to send messages from the companion app to the watch. The simulator bypasses BLE entirely. If messages arrive instantly in the simulator, the delay is confirmed to be in the BLE/GCM layer, not in the app code.

---

## Summary

The watch-side code is functioning correctly. Messages are processed immediately upon receipt (Rx: 0-3m). The phone-side code is building fresh payloads at send time (sentAt matches glucoseDate within seconds). **The entire 25-31 minute delay occurs in the ConnectIQ SDK / Garmin Connect Mobile / BLE transport layer** — a black box neither the watch code nor the Trio code directly controls.

The throttle change from 10s to 300s was a necessary fix to prevent queue flooding but may not be sufficient if the underlying transport has inherent delivery latency. The clean restart test is the critical next step to isolate whether we're still draining a residual queue or facing a fundamental ConnectIQ delivery limitation.
