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
        // Trio received our request; data will arrive via phone message
        // in the service delegate's onPhoneAppMessage callback.
    }

    function onError() {
        // Phone not connected or Trio not running — exit the background
        // service so the next temporal event can fire cleanly.
        Background.exit(null);
    }
}
