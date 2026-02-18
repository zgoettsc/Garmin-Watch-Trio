using Toybox.Background;
using Toybox.Communications;
using Toybox.System;

// Background service delegate — the only place a watch face
// is allowed to use Toybox.Communications.
//
// Two wake-up paths:
//   A. Push — Trio sends data → registerForPhoneAppMessages wakes us
//      → onPhoneMessage() fires directly with the payload
//   B. Poll — temporal event fires every 5 min → onTemporalEvent()
//      → we send "status" to ask Trio for fresh data
//      → Trio responds → onPhoneMessage() fires with the payload
//
// In both cases onPhoneMessage() passes data to the foreground
// via Background.exit().
(:background)
class TrioServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    // Poll path: fires every 5 min as a fallback.
    // Sends "status" to Trio so it replies with fresh data.
    function onTemporalEvent() {
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
        Communications.transmit("status", null, new BgCommListener());
    }

    // Called for both push (Trio initiated) and poll (our "status" response).
    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        if (msg.data != null) {
            Background.exit(msg.data);
        }
    }
}
