import Capacitor
import UIKit

/// ADR-172: the app's web view controller (Main.storyboard). It only
/// registers the app's own plugins, which live in this target rather than
/// in an npm package.
class MilosBridgeViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(MilosHealthPlugin())
        // ADR-173: home-screen widgets, the arrival reminder and NFC door tags.
        bridge?.registerPluginInstance(MilosWidgetsPlugin())
        bridge?.registerPluginInstance(MilosGeofencePlugin())
        bridge?.registerPluginInstance(MilosNfcPlugin())
    }
}
