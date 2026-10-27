package app.palee.member

import android.Manifest
import android.os.Build
import com.getcapacitor.JSObject
import com.getcapacitor.PermissionState
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.annotation.Permission
import com.getcapacitor.annotation.PermissionCallback
import org.json.JSONArray

/**
 * ADR-173: the web app's side of the arrival reminder (`PaleeGeofence`, the
 * same interface as on iOS). Asks for location (then background location,
 * then notifications), and replaces or clears the watched regions.
 */
@CapacitorPlugin(
    name = "PaleeGeofence",
    permissions = [
        Permission(strings = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION], alias = "location"),
        Permission(strings = [Manifest.permission.ACCESS_BACKGROUND_LOCATION], alias = "background"),
        Permission(strings = [Manifest.permission.POST_NOTIFICATIONS], alias = "notifications"),
    ],
)
class PaleeGeofencePlugin : Plugin() {
    @PluginMethod
    override fun checkPermissions(call: PluginCall) {
        call.resolve(status())
    }

    @PluginMethod
    override fun requestPermissions(call: PluginCall) {
        if (getPermissionState("location") != PermissionState.GRANTED) {
            requestPermissionForAlias("location", call, "afterLocation")
        } else {
            afterLocation(call)
        }
    }

    @PermissionCallback
    private fun afterLocation(call: PluginCall) {
        val needsBackground = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        if (getPermissionState("location") == PermissionState.GRANTED && needsBackground &&
            getPermissionState("background") != PermissionState.GRANTED
        ) {
            requestPermissionForAlias("background", call, "afterBackground")
        } else {
            afterBackground(call)
        }
    }

    @PermissionCallback
    private fun afterBackground(call: PluginCall) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && getPermissionState("notifications") != PermissionState.GRANTED) {
            requestPermissionForAlias("notifications", call, "afterNotifications")
        } else {
            afterNotifications(call)
        }
    }

    @PermissionCallback
    private fun afterNotifications(call: PluginCall) {
        PaleeGeofenceStore.register(context)
        call.resolve(status())
    }

    @PluginMethod
    fun setRegions(call: PluginCall) {
        val regions = call.getArray("regions") ?: JSONArray()
        PaleeGeofenceStore.save(context, JSONArray(regions.toString()))
        call.resolve(JSObject().put("monitored", PaleeGeofenceStore.register(context)))
    }

    @PluginMethod
    fun clear(call: PluginCall) {
        PaleeGeofenceStore.clear(context)
        call.resolve()
    }

    private fun status(): JSObject {
        val location = getPermissionState("location")
        val background = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || getPermissionState("background") == PermissionState.GRANTED
        val notifications = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || getPermissionState("notifications") == PermissionState.GRANTED
        return JSObject()
            .put(
                "location",
                when {
                    location == PermissionState.GRANTED && background -> "granted"
                    location == PermissionState.GRANTED -> "when_in_use"
                    location == PermissionState.DENIED -> "denied"
                    else -> "prompt"
                },
            )
            .put("notifications", if (notifications) "granted" else if (getPermissionState("notifications") == PermissionState.DENIED) "denied" else "prompt")
    }
}
