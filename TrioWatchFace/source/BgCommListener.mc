using Toybox.Communications;

// Minimal ConnectionListener used by the background service when
// transmitting a "status" request to Trio. We don't need to act on
// success/failure — if the transmit works, Trio will respond with
// a data push that arrives via onPhoneMessage in the service delegate.
(:background)
class BgCommListener extends Communications.ConnectionListener {

    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() {
        // Trio received our request; data will arrive via phone message
    }

    function onError() {
        // Phone not connected or Trio not running — no action needed,
        // data will arrive on the next temporal event cycle
    }
}
