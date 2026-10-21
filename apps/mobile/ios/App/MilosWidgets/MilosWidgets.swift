import AppIntents
import SwiftUI
import WidgetKit

// ADR-173: the iOS home-screen widgets («+1 νερό», Σήμερα, Check-in), a
// WidgetKit extension sharing the App Group `group.app.milos.member` with the
// app. The app's `MilosWidgets` plugin writes the widget token, the host, the
// words and the tap paths there; the widgets read GET /api/widget/snapshot and
// post «+1 νερό» (iOS 17 interactive button) with that token.
//
// The extension target is added once in Xcode (ADR-173 «Owner actions»):
// File › New › Target › Widget Extension named `MilosWidgets`, replace its
// generated files with this folder, deployment target iOS 17, App Groups
// capability with `group.app.milos.member` on both targets.

enum MilosShared {
    static let group = UserDefaults(suiteName: "group.app.milos.member")

    static var token: String? { group?.string(forKey: "token") }
    static var baseUrl: String? { group?.string(forKey: "baseUrl") }

    static func label(_ key: String, _ fallback: String) -> String {
        (group?.dictionary(forKey: "labels")?[key] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    }

    static func url(_ pathKey: String) -> URL? {
        guard let base = baseUrl else { return nil }
        let path = group?.dictionary(forKey: "paths")?[pathKey] as? String ?? "/"
        return URL(string: base + path)
    }

    static var cached: Snapshot? {
        group?.data(forKey: "snapshot").flatMap { try? JSONDecoder.milos.decode(Snapshot.self, from: $0) }
    }

    /// GET or POST with the widget token; keeps the last good snapshot for offline.
    static func request(_ method: String, _ path: String, body: [String: String]? = nil) async -> Snapshot? {
        guard let token = token, let base = baseUrl, let url = URL(string: base + path) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return nil }
        if status == 401 {
            // Revoked or expired: the widget asks to open the app, which renews it.
            group?.removeObject(forKey: "token")
            group?.removeObject(forKey: "snapshot")
            return nil
        }
        guard (200..<300).contains(status), let snapshot = try? JSONDecoder.milos.decode(Snapshot.self, from: data) else { return nil }
        group?.set(data, forKey: "snapshot")
        return snapshot
    }

    static var zone: String { TimeZone.current.identifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "UTC" }
}

struct Snapshot: Decodable {
    struct Water: Decodable { let ml: Int; let goal_ml: Int; let can_add: Bool }
    struct Item: Decodable { let kind: String; let title: String?; let at: Date?; let box_name: String? }
    let water: Water?
    let today: [Item]
    let next_class: Item?
}

extension JSONDecoder {
    static let milos: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "date")
        }
        return decoder
    }()
}

struct MilosEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    let signedIn: Bool
}

struct MilosProvider: TimelineProvider {
    func placeholder(in context: Context) -> MilosEntry { MilosEntry(date: Date(), snapshot: nil, signedIn: true) }

    func getSnapshot(in context: Context, completion: @escaping (MilosEntry) -> Void) {
        completion(MilosEntry(date: Date(), snapshot: MilosShared.cached, signedIn: MilosShared.token != nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MilosEntry>) -> Void) {
        Task {
            let fresh = await MilosShared.request("GET", "/api/widget/snapshot?timezone=\(MilosShared.zone)")
            let entry = MilosEntry(date: Date(), snapshot: fresh ?? MilosShared.cached, signedIn: MilosShared.token != nil)
            // Every 30 minutes; the app reloads the widgets whenever it opens.
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }
}

/// «+1 νερό» without opening the app.
struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "+1"

    func perform() async throws -> some IntentResult {
        _ = await MilosShared.request("POST", "/api/widget/water", body: ["timezone": TimeZone.current.identifier])
        return .result()
    }
}

private func line(_ item: Snapshot.Item) -> String {
    let kind = MilosShared.label(item.kind, item.kind)
    let title = (item.title?.isEmpty == false ? item.title : nil) ?? kind
    guard let at = item.at else { return title }
    return "\(at.formatted(date: .omitted, time: .shortened)) · \(title)"
}

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
    }
}

struct WaterView: View {
    let entry: MilosEntry
    var body: some View {
        Card(title: MilosShared.label("water", "Water")) {
            if let water = entry.snapshot?.water, entry.signedIn {
                Text("\(water.ml) / \(water.goal_ml) ml").font(.headline)
                if water.can_add {
                    Button(intent: AddWaterIntent()) { Text(MilosShared.label("addGlass", "+1")).frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Link(MilosShared.label("addGlass", "+1"), destination: MilosShared.url("water") ?? URL(string: "about:blank")!)
                }
            } else {
                Text(MilosShared.label("openApp", "Open Milos")).font(.subheadline)
            }
        }
        .widgetURL(MilosShared.url("water"))
    }
}

struct TodayView: View {
    let entry: MilosEntry
    var body: some View {
        Card(title: MilosShared.label("today", "Today")) {
            if !entry.signedIn || entry.snapshot == nil {
                Text(MilosShared.label("openApp", "Open Milos")).font(.subheadline)
            } else if let items = entry.snapshot?.today, !items.isEmpty {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(line(item)).font(.subheadline).lineLimit(1)
                }
            } else {
                Text(MilosShared.label("nothingToday", "Nothing for today")).font(.subheadline)
            }
        }
        .widgetURL(MilosShared.url("today"))
    }
}

struct CheckInView: View {
    let entry: MilosEntry
    var body: some View {
        Card(title: MilosShared.label("checkIn", "Check-in")) {
            if !entry.signedIn || entry.snapshot == nil {
                Text(MilosShared.label("openApp", "Open Milos")).font(.subheadline)
            } else if let next = entry.snapshot?.next_class {
                Text(line(next)).font(.headline).lineLimit(2)
                if let box = next.box_name { Text(box).font(.caption).foregroundStyle(.secondary) }
            } else {
                Text(MilosShared.label("noClass", "No booking today")).font(.subheadline)
            }
        }
        .widgetURL(MilosShared.url("checkIn"))
    }
}

struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MilosWater", provider: MilosProvider()) { WaterView(entry: $0) }
            .configurationDisplayName("Water").supportedFamilies([.systemSmall])
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MilosToday", provider: MilosProvider()) { TodayView(entry: $0) }
            .configurationDisplayName("Today").supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CheckInWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MilosCheckIn", provider: MilosProvider()) { CheckInView(entry: $0) }
            .configurationDisplayName("Check-in").supportedFamilies([.systemSmall])
    }
}

@main
struct MilosWidgetBundle: WidgetBundle {
    var body: some Widget {
        WaterWidget()
        TodayWidget()
        CheckInWidget()
    }
}
