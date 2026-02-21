using Toybox.Background;
using Toybox.Communications;
using Toybox.System;

// Background service delegate — the only place a watch face
// is allowed to use Toybox.Communications.
//
// Poll-only: temporal event fires every 5 min → onTemporalEvent()
//   → we register for messages and send "status" to ask Trio
//   → Trio reads its persistent store and responds with the latest payload
//   → onPhoneAppMessage() fires → Background.exit() passes data to foreground
//
// Trio keeps its store fresh on every Live Activity update (~1 min),
// so the 5-min poll always gets recent data.
(:background)
class TrioServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    // Fires every 5 min. Registers for phone messages so we can
    // receive Trio's response, then sends "status" to request data.
    function onTemporalEvent() {
        Communications.registerForPhoneAppMessages(method(:onPhoneAppMessage));
        Communications.transmit("status", null, new BgCommListener());
    }

    // Called when Trio responds to our "status" request with the data payload.
    function onPhoneAppMessage(msg as Communications.PhoneAppMessage) as Void {
        // Always call Background.exit() so the service terminates and
        // the next temporal event can fire.  Pass null when there's no
        // payload — onBackgroundData() already guards against null.
        Background.exit(msg.data);
    }
}
