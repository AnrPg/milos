import Capacitor
import UIKit

/// ADR-172: the app's web view controller (Main.storyboard). It only
/// registers the app's own plugins, which live in this target rather than
/// in an npm package.
class PaleeBridgeViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(PaleeHealthPlugin())
        // ADR-173: home-screen widgets, the arrival reminder and NFC door tags.
        bridge?.registerPluginInstance(PaleeWidgetsPlugin())
        bridge?.registerPluginInstance(PaleeGeofencePlugin())
        bridge?.registerPluginInstance(PaleeNfcPlugin())
        // ADR-249: Tap to Pay through the Viva.com Terminal app.
        bridge?.registerPluginInstance(PaleeVivaTerminalPlugin())
    }
}
