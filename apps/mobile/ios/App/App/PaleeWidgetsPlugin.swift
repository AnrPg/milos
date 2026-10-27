import Capacitor
import Foundation
import WidgetKit

/// ADR-173: the web app's side of the home-screen widgets (`PaleeWidgets`,
/// the same interface as on Android). `setSession` keeps the widget token,
/// the app's host, the words and the tap paths in the App Group shared with
/// the widget extension (`PaleeWidgets/`), then reloads the widgets; `clear`
/// (sign-out) forgets the token. The token only opens the widget endpoints.
@objc(PaleeWidgetsPlugin)
public class PaleeWidgetsPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "PaleeWidgetsPlugin"
    public let jsName = "PaleeWidgets"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clear", returnType: CAPPluginReturnPromise),
    ]

    /// Shared with the widget extension; the App Group is an owner action (ADR-173).
    static let appGroup = "group.app.palee.member"

    private var shared: UserDefaults? { UserDefaults(suiteName: Self.appGroup) }

    @objc func setSession(_ call: CAPPluginCall) {
        guard let token = call.getString("token"), !token.isEmpty,
              let baseUrl = call.getString("baseUrl"), baseUrl.hasPrefix("http"),
              let shared = shared
        else {
            call.reject("token and baseUrl are required")
            return
        }
        shared.set(token, forKey: "token")
        shared.set(baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl, forKey: "baseUrl")
        shared.set(call.getObject("labels") ?? [:], forKey: "labels")
        shared.set(call.getObject("paths") ?? [:], forKey: "paths")
        shared.removeObject(forKey: "snapshot")
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve()
    }

    @objc func clear(_ call: CAPPluginCall) {
        // The words stay, so a signed-out widget still says «Άνοιξε το Palee».
        shared?.removeObject(forKey: "token")
        shared?.removeObject(forKey: "snapshot")
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve()
    }
}
