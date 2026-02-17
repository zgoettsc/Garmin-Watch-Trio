using Toybox.Communications;

// Minimal ConnectionListener for the "status" request transmit.
// We don't need to act on success/failure — if the transmit works,
// Trio will respond with a data push that arrives via onPhoneMessage.
class CommListener extends Communications.ConnectionListener {

    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() {
        // Trio received our request; data will arrive via push
    }

    function onError() {
        // Phone not connected or Trio not running — no action needed,
        // data will arrive whenever the connection is re-established
    }
}
