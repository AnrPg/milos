package app.palee.member

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

/**
 * ADR-249: Tap to Pay at the desk through the «Viva.com Terminal» app
 * (`PaleeVivaTerminal`, the same interface as on iOS). `pay` builds the
 * app-to-app Sale request (`vivapayclient://pay/v1?…`, an ACTION_VIEW
 * intent) from the parameters the API signed; the terminal app answers on
 * `palee-terminal://result?…`, which reaches MainActivity (singleTask) and
 * is handed to the web app as a `result` event. The last answer is kept
 * until the web app takes it, in case the web view was not listening.
 *
 * The answer is never trusted here: the web app posts it to the API, which
 * confirms the transaction with Viva before recording any money.
 */
@CapacitorPlugin(name = "PaleeVivaTerminal")
class PaleeVivaTerminalPlugin : Plugin() {
    companion object {
        const val CALLBACK_SCHEME = "palee-terminal"
        const val CALLBACK_HOST = "result"
        val ALLOWED_SCHEMES = listOf("vivapayclient://pay/v1", "palee-sandbox-terminal://pay/v1")
        private const val PREFS = "palee_viva_terminal"
        private const val PENDING = "pending_result"

        /** The Sale request URI: the scheme and every non-empty parameter, encoded. */
        fun buildSaleUri(scheme: String, params: Map<String, String>): Uri? {
            if (scheme !in ALLOWED_SCHEMES) return null
            val builder = Uri.parse(scheme).buildUpon()
            params.filterValues { it.isNotEmpty() }.forEach { (key, value) -> builder.appendQueryParameter(key, value) }
            return builder.build()
        }

        fun isTerminalCallback(uri: Uri?): Boolean = uri != null && uri.scheme == CALLBACK_SCHEME && uri.host == CALLBACK_HOST

        /** The callback's parameters (the web app parses the raw URL the same way). */
        fun parseCallback(uri: Uri): Map<String, String> =
            uri.queryParameterNames.associateWith { name -> uri.getQueryParameter(name).orEmpty() }
    }

    override fun load() {
        // A cold start by the terminal app's answer.
        keep(activity?.intent?.data)
    }

    override fun handleOnNewIntent(intent: Intent) {
        super.handleOnNewIntent(intent)
        keep(intent.data)
    }

    private fun keep(uri: Uri?) {
        if (!isTerminalCallback(uri)) return
        val url = uri.toString()
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(PENDING, url).apply()
        notifyListeners("result", JSObject().put("url", url), true)
    }

    @PluginMethod
    fun isAvailable(call: PluginCall) {
        val probe = Intent(Intent.ACTION_VIEW, Uri.parse(ALLOWED_SCHEMES.first()))
        val available = probe.resolveActivity(context.packageManager) != null
        call.resolve(JSObject().put("available", available))
    }

    @PluginMethod
    fun pay(call: PluginCall) {
        val scheme = call.getString("scheme").orEmpty()
        val params = call.getObject("params") ?: JSObject()
        val values = params.keys().asSequence().associateWith { key -> params.optString(key, "") }
        val uri = buildSaleUri(scheme, values)
        if (uri == null) {
            call.reject("This payment request is not for a terminal app", "terminal_scheme_not_allowed")
            return
        }
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
            addFlags(Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
        }
        if (intent.resolveActivity(context.packageManager) == null) {
            call.resolve(JSObject().put("launched", false))
            return
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(PENDING).apply()
        context.startActivity(intent)
        call.resolve(JSObject().put("launched", true))
    }

    @PluginMethod
    fun takePendingResult(call: PluginCall) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val url = prefs.getString(PENDING, null)
        prefs.edit().remove(PENDING).apply()
        call.resolve(JSObject().put("url", url))
    }
}
