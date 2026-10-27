package app.palee.member

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import org.json.JSONArray
import org.json.JSONObject

/**
 * ADR-173: the arrival reminder on Android. The web app hands over regions
 * (`PaleeGeofence.setRegions`), each with its check-in windows and the words
 * of its reminder; Play Services watches them. On entering one while a
 * window is open, the phone shows one reminder per window; tapping it opens
 * the region's link in the app (`/c/<location>/g/<token>`). The location
 * never leaves the phone. Regions survive a reboot or an app update
 * (`PaleeGeofenceBootReceiver`).
 */
object PaleeGeofenceStore {
    private const val PREFS = "palee_geofence"
    private const val CHANNEL = "palee_arrival"
    private const val DAY_MS = 86_400_000L

    fun save(context: Context, regions: JSONArray) {
        prefs(context).edit().putString("regions", regions.toString()).apply()
    }

    fun regions(context: Context): JSONArray =
        runCatching { JSONArray(prefs(context).getString("regions", "[]")) }.getOrDefault(JSONArray())

    fun clear(context: Context) {
        prefs(context).edit().clear().apply()
        LocationServices.getGeofencingClient(context).removeGeofences(pendingIntent(context))
    }

    fun hasLocation(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** Replaces the watched regions with the stored ones; returns how many. */
    @SuppressLint("MissingPermission")
    fun register(context: Context): Int {
        val client = LocationServices.getGeofencingClient(context)
        client.removeGeofences(pendingIntent(context))
        val regions = regions(context)
        if (regions.length() == 0 || !hasLocation(context)) return 0
        val fences = (0 until regions.length()).map { index ->
            val region = regions.getJSONObject(index)
            Geofence.Builder()
                .setRequestId(region.getString("id"))
                .setCircularRegion(region.getDouble("latitude"), region.getDouble("longitude"), region.getDouble("radius").toFloat())
                .setExpirationDuration(Geofence.NEVER_EXPIRE)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
                .build()
        }
        val request = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofences(fences)
            .build()
        client.addGeofences(request, pendingIntent(context))
        return fences.size
    }

    /** Called on entering regions: one reminder per open window, never twice. */
    fun entered(context: Context, ids: List<String>, now: Long = System.currentTimeMillis()) {
        val regions = regions(context)
        val shown = prefs(context).getStringSet("shown", emptySet())!!.toMutableSet()
        for (index in 0 until regions.length()) {
            val region = regions.getJSONObject(index)
            if (region.getString("id") !in ids) continue
            val window = openWindow(region.optJSONArray("windows") ?: JSONArray(), now) ?: continue
            val key = region.getString("id") + "@" + window.getLong("from")
            if (!shown.add(key)) continue
            notify(context, region.getString("url"), window.optString("title"), window.optString("body"), key.hashCode())
        }
        // Forget reminders of windows that opened more than a day ago.
        val recent = shown.filter { key -> key.substringAfterLast('@').toLongOrNull()?.let { now - it < DAY_MS } ?: false }
        prefs(context).edit().putStringSet("shown", recent.toSet()).apply()
    }

    fun openWindow(windows: JSONArray, now: Long): JSONObject? =
        (0 until windows.length()).map { windows.getJSONObject(it) }.firstOrNull { now >= it.getLong("from") && now <= it.getLong("to") }

    @SuppressLint("MissingPermission") // checked above (POST_NOTIFICATIONS on Android 13+)
    private fun notify(context: Context, url: String, title: String, body: String, id: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, title.ifEmpty { "Check-in" }, NotificationManager.IMPORTANCE_DEFAULT))
        }
        // Opens like an App Link, so the web app routes it (`appUrlOpen`).
        val open = Intent(Intent.ACTION_VIEW, Uri.parse(url), context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(PendingIntent.getActivity(context, id, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            .build()
        NotificationManagerCompat.from(context).notify(id, notification)
    }

    private fun pendingIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, PaleeGeofenceReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

/** Play Services' region events. */
class PaleeGeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError() || event.geofenceTransition != Geofence.GEOFENCE_TRANSITION_ENTER) return
        PaleeGeofenceStore.entered(context, event.triggeringGeofences.orEmpty().map { it.requestId })
    }
}

/** Geofences are dropped on reboot and app update; this puts them back. */
class PaleeGeofenceBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            PaleeGeofenceStore.register(context)
        }
    }
}
