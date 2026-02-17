using Toybox.Background;
using Toybox.Communications;
using Toybox.System;

// Background service delegate — the only place a watch face
// is allowed to use Toybox.Communications.
(:background)
class TrioServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() {
        // Register to receive data pushed from the Trio phone app
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
    }

    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        if (msg.data != null) {
            // Hand the payload back to the foreground via onBackgroundData()
            Background.exit(msg.data);
        }
    }
}
