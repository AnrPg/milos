package app.palee.member;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        // ADR-172: the app's own Health Connect plugin (PaleeHealth).
        registerPlugin(PaleeHealthPlugin.class);
        // ADR-173: home-screen widgets, the arrival reminder and NFC door tags.
        registerPlugin(PaleeWidgetsPlugin.class);
        registerPlugin(PaleeGeofencePlugin.class);
        registerPlugin(PaleeNfcPlugin.class);
        // ADR-249: Tap to Pay through the Viva.com Terminal app.
        registerPlugin(PaleeVivaTerminalPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
