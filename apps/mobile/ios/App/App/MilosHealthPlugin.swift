import Capacitor
import Foundation
import HealthKit

/// ADR-172: Apple Health for the web app (`MilosHealth`, the same interface
/// as the Android Health Connect plugin). Read-only: it asks for read access
/// to the kinds the person chose and reads a time window; the web layer
/// shapes the records and sends them to the API. Nothing is written to
/// HealthKit, nothing is read in the background.
@objc(MilosHealthPlugin)
public class MilosHealthPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "MilosHealthPlugin"
    public let jsName = "MilosHealth"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "availability", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestAuthorization", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "read", returnType: CAPPluginReturnPromise),
    ]

    private static let kinds: Set<String> = ["activities", "sleep", "weight", "resting_hr", "steps"]
    private static let maxSamples = 1000

    private let store = HKHealthStore()

    @objc func availability(_ call: CAPPluginCall) {
        if HKHealthStore.isHealthDataAvailable() {
            call.resolve(["available": true])
        } else {
            call.resolve(["available": false, "reason": "unsupported"])
        }
    }

    /// HealthKit never says whether read access was given (privacy), so
    /// `granted` is null: the person decided in Apple's sheet, and kinds they
    /// refused simply read as empty.
    @objc func requestAuthorization(_ call: CAPPluginCall) {
        let kinds = requestedKinds(call)
        guard HKHealthStore.isHealthDataAvailable() else {
            call.reject("unavailable")
            return
        }
        let types = readTypes(kinds)
        guard !types.isEmpty else {
            call.resolve(["asked": kinds, "granted": NSNull()])
            return
        }
        store.requestAuthorization(toShare: nil, read: types) { _, error in
            if let error = error {
                call.reject("authorization_failed", nil, error)
            } else {
                call.resolve(["asked": kinds, "granted": NSNull()])
            }
        }
    }

    @objc func read(_ call: CAPPluginCall) {
        let kinds = Set(requestedKinds(call))
        guard let from = call.getString("from").flatMap(Self.parse),
              let to = call.getString("to").flatMap(Self.parse),
              from < to
        else {
            call.reject("invalid_window")
            return
        }
        Task {
            do {
                var out: [String: Any] = [:]
                if kinds.contains("activities") { out["workouts"] = try await workouts(from, to) }
                if kinds.contains("sleep") { out["sleep"] = try await sleep(from, to) }
                if kinds.contains("weight") { out["weights"] = try await weights(from, to) }
                if kinds.contains("resting_hr") {
                    out["resting_hr"] = try await daily(.restingHeartRate, .discreteAverage, Self.bpm, from, to)
                        .map { ["date": $0.date, "bpm": $0.value] as [String: Any] }
                }
                if kinds.contains("steps") {
                    // The statistics query merges iPhone and Watch counts without doubling.
                    out["steps"] = try await daily(.stepCount, .cumulativeSum, .count(), from, to)
                        .map { ["date": $0.date, "count": Int($0.value.rounded())] as [String: Any] }
                }
                call.resolve(out)
            } catch {
                call.reject("read_failed", nil, error)
            }
        }
    }

    // MARK: - Types

    private func requestedKinds(_ call: CAPPluginCall) -> [String] {
        (call.getArray("kinds", String.self) ?? []).filter { Self.kinds.contains($0) }
    }

    private func readTypes(_ kinds: [String]) -> Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for kind in kinds {
            switch kind {
            case "activities":
                types.insert(HKObjectType.workoutType())
                if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(heartRate) }
            case "sleep":
                if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
            case "weight":
                if let mass = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(mass) }
            case "resting_hr":
                if let resting = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { types.insert(resting) }
            case "steps":
                if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
            default:
                break
            }
        }
        return types
    }

    // MARK: - Reads

    private func workouts(_ from: Date, _ to: Date) async throws -> [[String: Any]] {
        try await samples(HKObjectType.workoutType(), from, to).compactMap { sample -> [String: Any]? in
            guard let workout = sample as? HKWorkout else { return nil }
            var row: [String: Any] = [
                "id": workout.uuid.uuidString,
                "type": Self.workoutType(workout.workoutActivityType),
                "start": Self.format(workout.startDate),
                "end": Self.format(workout.endDate),
                "offset_minutes": Self.offsetMinutes(workout, at: workout.startDate),
                "source_app": workout.sourceRevision.source.name,
            ]
            if let meters = workout.totalDistance?.doubleValue(for: .meter()), meters > 0 {
                row["distance_m"] = meters
            }
            if #available(iOS 16.0, *),
               let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate),
               let stats = workout.statistics(for: heartRate)
            {
                if let average = stats.averageQuantity() { row["avg_hr"] = average.doubleValue(for: Self.bpm) }
                if let maximum = stats.maximumQuantity() { row["max_hr"] = maximum.doubleValue(for: Self.bpm) }
            }
            return row
        }
    }

    /// Raw segments (in bed, asleep, awake); the web layer joins them into nights.
    private func sleep(_ from: Date, _ to: Date) async throws -> [[String: Any]] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        return try await samples(type, from, to).compactMap { sample -> [String: Any]? in
            guard let segment = sample as? HKCategorySample else { return nil }
            let stage: String
            switch segment.value {
            case HKCategoryValueSleepAnalysis.inBed.rawValue: stage = "in_bed"
            case HKCategoryValueSleepAnalysis.awake.rawValue: stage = "awake"
            default: stage = "asleep"
            }
            return [
                "id": segment.uuid.uuidString,
                "start": Self.format(segment.startDate),
                "end": Self.format(segment.endDate),
                "offset_minutes": Self.offsetMinutes(segment, at: segment.endDate),
                "stage": stage,
            ]
        }
    }

    private func weights(_ from: Date, _ to: Date) async throws -> [[String: Any]] {
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return [] }
        return try await samples(type, from, to).compactMap { sample -> [String: Any]? in
            guard let weight = sample as? HKQuantitySample else { return nil }
            return [
                "id": weight.uuid.uuidString,
                "at": Self.format(weight.startDate),
                "offset_minutes": Self.offsetMinutes(weight, at: weight.startDate),
                "kg": weight.quantity.doubleValue(for: .gramUnit(with: .kilo)),
            ]
        }
    }

    private func samples(_ type: HKSampleType, _ from: Date, _ to: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: from, end: to, options: []),
                limit: Self.maxSamples,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    if Self.isAccessError(error) { continuation.resume(returning: []) } else { continuation.resume(throwing: error) }
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }

    /// One value per local day.
    private func daily(
        _ identifier: HKQuantityTypeIdentifier,
        _ options: HKStatisticsOptions,
        _ unit: HKUnit,
        _ from: Date,
        _ to: Date
    ) async throws -> [(date: String, value: Double)] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }
        let start = Calendar.current.startOfDay(for: from)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: to, options: []),
                options: options,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error = error {
                    if Self.isAccessError(error) { continuation.resume(returning: []) } else { continuation.resume(throwing: error) }
                    return
                }
                var rows: [(date: String, value: Double)] = []
                collection?.enumerateStatistics(from: start, to: to) { statistics, _ in
                    let quantity = options.contains(.cumulativeSum) ? statistics.sumQuantity() : statistics.averageQuantity()
                    if let quantity = quantity {
                        rows.append((date: Self.day(statistics.startDate), value: quantity.doubleValue(for: unit)))
                    }
                }
                continuation.resume(returning: rows)
            }
            store.execute(query)
        }
    }

    // MARK: - Helpers

    private static let bpm = HKUnit.count().unitDivided(by: .minute())

    private static func isAccessError(_ error: Error) -> Bool {
        guard let error = error as? HKError else { return false }
        return error.code == .errorAuthorizationDenied || error.code == .errorAuthorizationNotDetermined
            || error.code == .errorNoData
    }

    /// The wearer's offset then: the sample's own time zone when the
    /// recording app saved one, else this phone's zone at that instant.
    private static func offsetMinutes(_ sample: HKSample, at date: Date) -> Int {
        let zone = (sample.metadata?[HKMetadataKeyTimeZone] as? String).flatMap(TimeZone.init(identifier:)) ?? .current
        return zone.secondsFromGMT(for: date) / 60
    }

    private static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func format(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Named like Garmin's activity types, so the server folds every
    /// provider into the same sports.
    private static func workoutType(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "RUNNING"
        case .cycling: return "CYCLING"
        case .swimming: return "SWIMMING"
        case .walking: return "WALKING"
        case .hiking: return "HIKING"
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: return "STRENGTH_TRAINING"
        case .highIntensityIntervalTraining: return "HIIT"
        case .crossTraining, .mixedCardio: return "INDOOR_CARDIO"
        case .yoga, .mindAndBody: return "YOGA"
        case .pilates: return "PILATES"
        case .rowing: return "ROWING"
        case .elliptical: return "ELLIPTICAL"
        case .stairClimbing, .stairs, .stepTraining: return "STAIR_CLIMBING"
        case .downhillSkiing: return "SKIING"
        case .crossCountrySkiing: return "CROSS_COUNTRY_SKIING"
        default: return "OTHER"
        }
    }
}
