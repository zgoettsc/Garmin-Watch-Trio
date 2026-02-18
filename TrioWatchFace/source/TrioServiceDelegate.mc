using Toybox.Background;
using Toybox.Communications;
using Toybox.System;

// Background service delegate — the only place a watch face
// is allowed to use Toybox.Communications.
//
// Two wake-up paths:
//   A. Push — Trio sends data → registerForPhoneAppMessageEvent wakes us
//      → onPhoneAppMessage() fires directly with the payload
//   B. Poll — temporal event fires every 5 min → onTemporalEvent()
//      → we register for messages and send "status" to ask Trio
//      → Trio responds → onPhoneAppMessage() fires with the payload
//
// In both cases onPhoneAppMessage() passes data to the foreground
// via Background.exit().
(:background)
class TrioServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    // Poll path: fires every 5 min as a fallback.
    // Registers for phone messages and sends "status" to Trio
    // so it replies with fresh data.
    function onTemporalEvent() {
        Communications.registerForPhoneAppMessages(method(:onPhoneAppMessage));
        Communications.transmit("status", null, new BgCommListener());
    }

    // Called for both push (Trio initiated) and poll (our "status" response).
    // This is an override of ServiceDelegate.onPhoneAppMessage(), which the
    // system invokes when registerForPhoneAppMessageEvent() triggers a wake.
    function onPhoneAppMessage(msg as Communications.PhoneAppMessage) as Void {
        if (msg.data != null) {
            Background.exit(msg.data);
        }
    }
}
