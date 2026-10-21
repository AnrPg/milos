import Capacitor
import CoreLocation
import Foundation
import UserNotifications

/// ADR-173: the arrival reminder on iOS. The web app hands over regions
/// (`PaleeGeofence.setRegions`), each with its check-in windows and the
/// words of its reminder; Core Location watches them, also while the app is
/// closed (iOS relaunches it in the background, so the monitor starts in
/// `AppDelegate`). On entering one while a window is open the phone shows
/// one reminder per window; tapping it opens the region's link in the app
/// (`/c/<location>/g/<token>`). The location never leaves the phone.
final class PaleeGeofenceMonitor: NSObject, CLLocationManagerDelegate {
    static let shared = PaleeGeofenceMonitor()
    static let urlKey = "paleeGeofenceUrl"

    private let manager = CLLocationManager()
    private let defaults = UserDefaults.standard
    private var permissionWaiters: [() -> Void] = []
    private static let regionsKey = "palee.geofence.regions"
    private static let shownKey = "palee.geofence.shown"
    private static let prefix = "palee-"

    private override init() {
        super.init()
        manager.delegate = self
    }

    /// Called at launch (creating the manager and its delegate) so region
    /// events reach us when iOS wakes the app in the background.
    func start() {}

    var locationStatus: String {
        switch manager.authorizationStatus {
        case .authorizedAlways: return "granted"
        case .authorizedWhenInUse: return "when_in_use"
        case .denied, .restricted: return "denied"
        default: return "prompt"
        }
    }

    /// When In Use first, then Always (iOS shows the second prompt later or in Settings).
    func requestPermission(_ done: @escaping () -> Void) {
        switch manager.authorizationStatus {
        case .notDetermined:
            permissionWaiters.append(done)
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            permissionWaiters.append(done)
            manager.requestAlwaysAuthorization()
            // iOS may answer later (or never, if it defers the prompt).
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.finishPermission() }
        default:
            done()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse, !permissionWaiters.isEmpty {
            manager.requestAlwaysAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.finishPermission() }
            return
        }
        finishPermission()
        _ = register()
    }

    private func finishPermission() {
        let waiters = permissionWaiters
        permissionWaiters = []
        waiters.forEach { $0() }
    }

    func save(_ regions: [[String: Any]]) {
        if let data = try? JSONSerialization.data(withJSONObject: regions) {
            defaults.set(data, forKey: Self.regionsKey)
        }
    }

    func clear() {
        defaults.removeObject(forKey: Self.regionsKey)
        defaults.removeObject(forKey: Self.shownKey)
        stopMonitoring()
    }

    private var regions: [[String: Any]] {
        guard let data = defaults.data(forKey: Self.regionsKey),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return list
    }

    private func stopMonitoring() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.prefix) {
            manager.stopMonitoring(for: region)
        }
    }

    /// Replaces the watched regions with the stored ones; returns how many.
    @discardableResult
    func register() -> Int {
        stopMonitoring()
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
              [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus)
        else { return 0 }
        var count = 0
        for region in regions.prefix(20) {
            guard let id = region["id"] as? String, id.hasPrefix(Self.prefix),
                  let latitude = region["latitude"] as? Double,
                  let longitude = region["longitude"] as? Double,
                  let radius = region["radius"] as? Double
            else { continue }
            let circle = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                radius: min(radius, manager.maximumRegionMonitoringDistance),
                identifier: id
            )
            circle.notifyOnEntry = true
            circle.notifyOnExit = false
            manager.startMonitoring(for: circle)
            // Already inside when the window opens: the state check covers it.
            manager.requestState(for: circle)
            count += 1
        }
        return count
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        entered(region.identifier)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        if state == .inside { entered(region.identifier) }
    }

    /// One reminder per open window, never twice.
    private func entered(_ id: String, now: Date = Date()) {
        guard let region = regions.first(where: { $0["id"] as? String == id }),
              let url = region["url"] as? String,
              let windows = region["windows"] as? [[String: Any]]
        else { return }
        let millis = now.timeIntervalSince1970 * 1000
        guard let window = windows.first(where: {
            guard let from = $0["from"] as? Double, let to = $0["to"] as? Double else { return false }
            return millis >= from && millis <= to
        }), let from = window["from"] as? Double else { return }

        let key = "\(id)@\(Int64(from))"
        var shown = (defaults.dictionary(forKey: Self.shownKey) as? [String: Double]) ?? [:]
        if shown[key] != nil { return }
        shown = shown.filter { millis - $0.value < 86_400_000 }
        shown[key] = from
        defaults.set(shown, forKey: Self.shownKey)

        let content = UNMutableNotificationContent()
        content.title = window["title"] as? String ?? ""
        content.body = window["body"] as? String ?? ""
        content.sound = .default
        content.userInfo = [Self.urlKey: url]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
    }
}

/// The web app's side (`PaleeGeofence`, the same interface as on Android).
@objc(PaleeGeofencePlugin)
public class PaleeGeofencePlugin: CAPPlugin, CAPBridgedPlugin, NotificationHandlerProtocol {
    public let identifier = "PaleeGeofencePlugin"
    public let jsName = "PaleeGeofence"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setRegions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clear", returnType: CAPPluginReturnPromise),
    ]

    private let monitor = PaleeGeofenceMonitor.shared

    public override func load() {
        // Taps on our local reminders come here (pushes keep their own handler).
        bridge?.notificationRouter.localNotificationHandler = self
    }

    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        status { call.resolve($0) }
    }

    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.monitor.requestPermission {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                    self.status { call.resolve($0) }
                }
            }
        }
    }

    @objc func setRegions(_ call: CAPPluginCall) {
        let regions = (call.getArray("regions") as? [[String: Any]]) ?? []
        DispatchQueue.main.async {
            self.monitor.save(regions)
            call.resolve(["monitored": self.monitor.register()])
        }
    }

    @objc func clear(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.monitor.clear()
            call.resolve()
        }
    }

    private func status(_ done: @escaping ([String: Any]) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let notifications: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: notifications = "granted"
            case .denied: notifications = "denied"
            default: notifications = "prompt"
            }
            DispatchQueue.main.async {
                done(["location": self.monitor.locationStatus, "notifications": notifications])
            }
        }
    }

    // MARK: NotificationHandlerProtocol

    public func willPresent(notification: UNNotification) -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Opens the reminder's link like a universal link (`appUrlOpen` in the web app).
    public func didReceive(response: UNNotificationResponse) {
        guard let link = response.notification.request.content.userInfo[PaleeGeofenceMonitor.urlKey] as? String,
              let url = URL(string: link)
        else { return }
        NotificationCenter.default.post(name: .capacitorOpenURL, object: ["url": url, "options": [:]])
    }
}
