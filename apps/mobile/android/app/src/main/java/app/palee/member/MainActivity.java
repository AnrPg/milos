package app.palee.member;

import android.app.NotificationChannel;
import android.app.NotificationManager;
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
        super.onCreate(savedInstanceState);
        createPushChannel();
    }

    // ADR-256: the channel FCM delivers push messages to (the manifest names it
    // as the default), with a name in the phone's language instead of FCM's
    // "Miscellaneous". Creating an existing channel again only renames it.
    private void createPushChannel() {
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager == null) return;
        NotificationChannel channel = new NotificationChannel(
            getString(R.string.palee_push_channel_id),
            getString(R.string.palee_push_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT
        );
        channel.setDescription(getString(R.string.palee_push_channel_description));
        manager.createNotificationChannel(channel);
    }
}
