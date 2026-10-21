package app.milos.member;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        // ADR-172: the app's own Health Connect plugin (MilosHealth).
        registerPlugin(MilosHealthPlugin.class);
        // ADR-173: home-screen widgets, the arrival reminder and NFC door tags.
        registerPlugin(MilosWidgetsPlugin.class);
        registerPlugin(MilosGeofencePlugin.class);
        registerPlugin(MilosNfcPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
