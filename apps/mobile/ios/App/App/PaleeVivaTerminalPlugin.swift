import Capacitor
import Foundation
import UIKit

/// ADR-249: Tap to Pay at the desk through the «Viva.com Terminal» app
/// (`PaleeVivaTerminal`, the same interface as on Android). `pay` builds the
/// app-to-app Sale request (`vivapayclient://pay/v1?…`) from the parameters
/// the API signed and opens it; the terminal app answers on
/// `palee-terminal://result?…`, which Capacitor posts as an open-URL
/// notification. When the PIN pad shows, iOS resets this app to its idle
/// screen, so the answer is also kept until the web app takes it.
///
/// The answer is never trusted here: the web app posts it to the API, which
/// confirms the transaction with Viva before recording any money.
@objc(PaleeVivaTerminalPlugin)
public class PaleeVivaTerminalPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "PaleeVivaTerminalPlugin"
    public let jsName = "PaleeVivaTerminal"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pay", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "takePendingResult", returnType: CAPPluginReturnPromise),
    ]

    static let callbackScheme = "palee-terminal"
    static let callbackHost = "result"
    static let allowedSchemes = ["vivapayclient://pay/v1", "palee-sandbox-terminal://pay/v1"]
    private static let pendingKey = "palee.vivaTerminal.pendingResult"

    /// The Sale request URL: the scheme and every non-empty parameter,
    /// percent-encoded (`+` too, which URLComponents leaves alone).
    static func buildSaleURL(scheme: String, params: [String: String]) -> URL? {
        guard allowedSchemes.contains(scheme), var components = URLComponents(string: scheme) else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?/:")
        components.percentEncodedQuery = params
            .filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .compactMap { key, value in
                guard let k = key.addingPercentEncoding(withAllowedCharacters: allowed),
                      let v = value.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
        return components.url
    }

    static func isTerminalCallback(_ url: URL) -> Bool {
        url.scheme == callbackScheme && url.host == callbackHost
    }

    /// The callback's parameters (the web app parses the raw URL the same way).
    static func parseCallback(_ url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        var result: [String: String] = [:]
        for item in items where result[item.name] == nil {
            result[item.name] = item.value ?? ""
        }
        return result
    }

    override public func load() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenURL(_:)),
            name: Notification.Name.capacitorOpenURL,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleOpenURL(_ notification: Notification) {
        guard let object = notification.object as? [String: Any],
              let url = object["url"] as? URL,
              Self.isTerminalCallback(url) else { return }
        UserDefaults.standard.set(url.absoluteString, forKey: Self.pendingKey)
        notifyListeners("result", data: ["url": url.absoluteString], retainUntilConsumed: true)
    }

    @objc func isAvailable(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let probe = URL(string: Self.allowedSchemes[0])!
            call.resolve(["available": UIApplication.shared.canOpenURL(probe)])
        }
    }

    @objc func pay(_ call: CAPPluginCall) {
        let scheme = call.getString("scheme") ?? ""
        let raw = call.getObject("params") ?? [:]
        var params: [String: String] = [:]
        for (key, value) in raw {
            if let text = value as? String { params[key] = text }
        }
        guard let url = Self.buildSaleURL(scheme: scheme, params: params) else {
            call.reject("This payment request is not for a terminal app", "terminal_scheme_not_allowed")
            return
        }
        DispatchQueue.main.async {
            guard UIApplication.shared.canOpenURL(url) else {
                call.resolve(["launched": false])
                return
            }
            UserDefaults.standard.removeObject(forKey: Self.pendingKey)
            UIApplication.shared.open(url, options: [:]) { opened in
                call.resolve(["launched": opened])
            }
        }
    }

    @objc func takePendingResult(_ call: CAPPluginCall) {
        let url = UserDefaults.standard.string(forKey: Self.pendingKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        if let url = url {
            call.resolve(["url": url])
        } else {
            call.resolve(["url": NSNull()])
        }
    }
}
