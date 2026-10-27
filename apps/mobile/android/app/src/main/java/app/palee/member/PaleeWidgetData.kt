package app.palee.member

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.TimeZone

/**
 * ADR-173: what the home-screen widgets share. The web app hands over the
 * widget token, the app's host, the words to show and the paths a tap opens
 * (`PaleeWidgets.setSession`); the widgets read `GET /api/widget/snapshot`
 * and post «+1 νερό» with that token. Kept in the app's private preferences.
 */
object PaleeWidgetData {
    private const val PREFS = "palee_widgets"
    private const val TIMEOUT_MS = 8_000

    data class Session(val token: String, val baseUrl: String, val labels: JSONObject, val paths: JSONObject)

    fun save(context: Context, token: String, baseUrl: String, labels: JSONObject, paths: JSONObject) {
        prefs(context).edit()
            .putString("token", token)
            .putString("baseUrl", baseUrl.trimEnd('/'))
            .putString("labels", labels.toString())
            .putString("paths", paths.toString())
            .remove("snapshot")
            .apply()
    }

    /** Sign-out: no token and nothing personal; the words stay for «Άνοιξε το Palee». */
    fun clear(context: Context) {
        prefs(context).edit().remove("token").remove("snapshot").apply()
    }

    fun session(context: Context): Session? {
        val prefs = prefs(context)
        val token = prefs.getString("token", null) ?: return null
        val baseUrl = prefs.getString("baseUrl", null) ?: return null
        return Session(
            token,
            baseUrl,
            JSONObject(prefs.getString("labels", "{}") ?: "{}"),
            JSONObject(prefs.getString("paths", "{}") ?: "{}"),
        )
    }

    /** The last snapshot that arrived, shown while offline. */
    fun cachedSnapshot(context: Context): JSONObject? =
        prefs(context).getString("snapshot", null)?.let { runCatching { JSONObject(it) }.getOrNull() }

    /** Fetches a fresh snapshot (call off the main thread); null when offline or signed out. */
    fun fetchSnapshot(context: Context): JSONObject? {
        val session = session(context) ?: return null
        val zone = Uri.encode(TimeZone.getDefault().id)
        return request(context, session, "GET", "/api/widget/snapshot?timezone=$zone", null)
    }

    /** «+1 νερό»: one glass of the member's size; returns the new snapshot. */
    fun addWater(context: Context): JSONObject? {
        val session = session(context) ?: return null
        val body = JSONObject().put("timezone", TimeZone.getDefault().id)
        return request(context, session, "POST", "/api/widget/water", body)
    }

    private fun request(context: Context, session: Session, method: String, path: String, body: JSONObject?): JSONObject? {
        val connection = (URL(session.baseUrl + path).openConnection() as HttpURLConnection)
        return try {
            connection.requestMethod = method
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.setRequestProperty("Authorization", "Bearer ${session.token}")
            connection.setRequestProperty("Accept", "application/json")
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write(body.toString().toByteArray()) }
            }
            when (connection.responseCode) {
                in 200..299 -> {
                    val text = connection.inputStream.bufferedReader().use { it.readText() }
                    prefs(context).edit().putString("snapshot", text).apply()
                    JSONObject(text)
                }
                // Revoked or expired: the widget asks to open the app, which renews it.
                401 -> {
                    prefs(context).edit().remove("snapshot").remove("token").apply()
                    null
                }
                else -> null
            }
        } catch (_: Exception) {
            null
        } finally {
            connection.disconnect()
        }
    }

    /** Opens the app at a path on its own host (handled like an App Link). */
    fun openPathIntent(context: Context, pathKey: String, requestCode: Int): PendingIntent {
        val session = session(context)
        val path = session?.paths?.optString(pathKey, "/") ?: "/"
        val intent = if (session != null) {
            Intent(Intent.ACTION_VIEW, Uri.parse(session.baseUrl + path), context, MainActivity::class.java)
        } else {
            Intent(context, MainActivity::class.java)
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(context, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun label(context: Context, key: String, fallback: String): String {
        val labels = runCatching { JSONObject(prefs(context).getString("labels", "{}") ?: "{}") }.getOrNull()
        return labels?.optString(key)?.takeIf { it.isNotEmpty() } ?: fallback
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
