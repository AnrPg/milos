package app.milos.member;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        // ADR-172: the app's own Health Connect plugin (MilosHealth).
        registerPlugin(MilosHealthPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
