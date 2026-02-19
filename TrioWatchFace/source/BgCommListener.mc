using Toybox.Background;
using Toybox.Communications;

// ConnectionListener used by the background service when transmitting
// a "status" request to Trio.  On success, data arrives via
// onPhoneAppMessage in the service delegate.  On error, we must call
// Background.exit() so the service terminates and the next temporal
// event can fire.
(:background)
class BgCommListener extends Communications.ConnectionListener {

    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() {
        // Request sent successfully.  Exit immediately — the response from
        // Trio will arrive via the push channel (registerForPhoneAppMessageEvent).
        // Without this, the service hangs waiting for a phone message that may
        // never arrive (e.g. GCM bridge hiccup), causing the system to throttle
        // future temporal events.
        Background.exit(null);
    }

    function onError() {
        // Phone not connected or Trio not running — exit the background
        // service so the next temporal event can fire cleanly.
        Background.exit(null);
    }
}
