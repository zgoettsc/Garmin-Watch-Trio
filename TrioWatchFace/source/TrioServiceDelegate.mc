using Toybox.Background;
using Toybox.Communications;
using Toybox.System;

// Background service delegate — the only place a watch face
// is allowed to use Toybox.Communications.
//
// Flow:
//   1. Temporal event fires every 5 min → onTemporalEvent()
//   2. We register for phone messages AND request fresh data ("status")
//   3. Trio responds with a data dictionary
//   4. onPhoneMessage() receives it and passes to foreground via Background.exit()
//   5. Foreground onBackgroundData() stores and displays the data
(:background)
class TrioServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() {
        // Listen for data pushed from Trio
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));

        // Request fresh data so we don't wait for Trio's next push cycle
        Communications.transmit("status", null, new BgCommListener());
    }

    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        if (msg.data != null) {
            // Hand the payload back to the foreground via onBackgroundData()
            Background.exit(msg.data);
        }
    }
}
