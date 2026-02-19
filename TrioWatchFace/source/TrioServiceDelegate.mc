using Toybox.Background;
using Toybox.Communications;
using Toybox.System;

// Background service delegate — the only place a watch face
// is allowed to use Toybox.Communications.
//
// Two wake-up paths:
//   A. Push — Trio sends data → registerForPhoneAppMessageEvent wakes us
//      → onPhoneAppMessage() fires directly with the payload
//      → Background.exit(data) → app re-registers push in onBackgroundData
//   B. Poll — temporal event fires every 5 min → onTemporalEvent()
//      → sends "status" to Trio → exits immediately (fire-and-forget)
//      → Trio responds → push event wakes us → same as path A
//
// Push events are one-shot (Garmin SDK requirement): after the event fires,
// the app must call registerForPhoneAppMessageEvent() again.  This is done
// in onBackgroundData() after every background exit.
(:background)
class TrioServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    // Poll path: fires every 5 min as a fallback.
    // Sends "status" to Trio so it replies with fresh data.
    // The service exits immediately in onComplete/onError (BgCommListener);
    // Trio's response arrives via the push channel (registerForPhoneAppMessageEvent).
    function onTemporalEvent() {
        Communications.transmit("status", null, new BgCommListener());
    }

    // Called for both push (Trio initiated) and poll (our "status" response).
    // This is an override of ServiceDelegate.onPhoneAppMessage(), which the
    // system invokes when registerForPhoneAppMessageEvent() triggers a wake.
    function onPhoneAppMessage(msg as Communications.PhoneAppMessage) as Void {
        // Always call Background.exit() so the service terminates and
        // the next temporal event can fire.  Pass null when there's no
        // payload — onBackgroundData() already guards against null.
        Background.exit(msg.data);
    }
}
