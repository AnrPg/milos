package app.palee.member

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

/**
 * ADR-173: the web app's side of the home-screen widgets (`PaleeWidgets`,
 * the same interface as on iOS). `setSession` keeps the widget token, the
 * app's host, the words and the tap paths, then redraws the widgets;
 * `clear` (sign-out) forgets the token and blanks them.
 */
@CapacitorPlugin(name = "PaleeWidgets")
class PaleeWidgetsPlugin : Plugin() {
    @PluginMethod
    fun setSession(call: PluginCall) {
        val token = call.getString("token")
        val baseUrl = call.getString("baseUrl")
        if (token.isNullOrEmpty() || baseUrl.isNullOrEmpty() || !baseUrl.startsWith("http")) {
            call.reject("token and baseUrl are required")
            return
        }
        PaleeWidgetData.save(context, token, baseUrl, call.getObject("labels", JSObject())!!, call.getObject("paths", JSObject())!!)
        PaleeWidgetProvider.updateAll(context)
        call.resolve()
    }

    @PluginMethod
    fun clear(call: PluginCall) {
        PaleeWidgetData.clear(context)
        PaleeWidgetProvider.updateAll(context)
        call.resolve()
    }
}
