#if os(iOS)
import Foundation
import HealthKit
import StrandAnalytics
import WhoopStore

/// Read-only Apple lane. No derived/imported sample is ever written back to HealthKit.
@MainActor
enum AppleHealthAdapter {
    static let modeEnabled = true
    private struct Quantity {
        var id: HKQuantityTypeIdentifier, key: String, unit: HKUnit
        var cumulative = false
        var mostRecent = false
        var scale = 1.0
    }
    private static let quantities: [Quantity] = [
        .init(id: .heartRateVariabilitySDNN, key: "sdnn", unit: .secondUnit(with: .milli)),
        .init(id: .restingHeartRate, key: "rhr", unit: .count().unitDivided(by: .minute())),
        .init(id: .heartRate, key: "hr", unit: .count().unitDivided(by: .minute())),
        .init(id: .respiratoryRate, key: "resp", unit: .count().unitDivided(by: .minute())),
        .init(id: .oxygenSaturation, key: "spo2", unit: .percent(), scale: 100),
        .init(id: .appleSleepingWristTemperature, key: "temperature", unit: .degreeCelsius()),
        .init(id: .activeEnergyBurned, key: "energy", unit: .kilocalorie(), cumulative: true),
        .init(id: .basalEnergyBurned, key: "basal", unit: .kilocalorie(), cumulative: true),
        .init(id: .stepCount, key: "steps", unit: .count(), cumulative: true),
        .init(id: .vo2Max, key: "vo2max", unit: HKUnit(from: "ml/kg*min")),
        .init(id: .bodyMass, key: "weight", unit: .gramUnit(with: .kilo), mostRecent: true),
        .init(id: .bodyFatPercentage, key: "body_fat", unit: .percent(), scale: 100),
        .init(id: .leanBodyMass, key: "lean_mass", unit: .gramUnit(with: .kilo), mostRecent: true),
        .init(id: .bodyMassIndex, key: "bmi", unit: .count(), mostRecent: true)
    ]
    static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>(quantities.compactMap { HKQuantityType.quantityType(forIdentifier: $0.id) })
        types.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        types.insert(HKObjectType.workoutType())
        if #available(iOS 18, *) {
            types.insert(HKQuantityType(.workoutEffortScore))
            types.insert(HKQuantityType(.estimatedWorkoutEffortScore))
        }
        return types
    }

    static func read(store: HKHealthStore, start: Date, end: Date, calendar: Calendar = .current) async throws -> [AppleHealthDay] {
        var days: [String: AppleHealthDay] = [:]
        var cursor = calendar.startOfDay(for: start)
        while cursor < end {
            let next = calendar.date(byAdding: .day, value: 1, to: cursor)!
            let key = AppleHealthDay.dayKey(cursor, calendar: calendar)
            days[key] = .init(day: key, timeZone: calendar.timeZone.identifier,
                             start: cursor.timeIntervalSince1970, end: min(next, end).timeIntervalSince1970,
                             updated: Date().timeIntervalSince1970)
            cursor = next
        }
        for quantity in quantities {
            guard let type = HKQuantityType.quantityType(forIdentifier: quantity.id) else { continue }
            let rows = try await samples(store: store, type: type, start: start, end: end)
            for sample in rows.compactMap({ $0 as? HKQuantitySample }) {
                let key = AppleHealthDay.dayKey(sample.startDate, calendar: calendar)
                let value = sample.quantity.doubleValue(for: quantity.unit) * quantity.scale
                guard value.isFinite else { continue }
                days[key]?.samples.append(record(sample, key: quantity.key, value: value))
            }
            // HealthKit owns cumulative source reconciliation (e.g. overlapping phone/watch steps).
            let aggregate = try await statistics(store: store, type: type, quantity: quantity, start: start, end: end, calendar: calendar)
            for (key, value) in aggregate { days[key]?.values[quantity.key] = value }
        }
        let sleepStart = calendar.date(byAdding: .day, value: -2, to: start)!
        let rawSleep = try await samples(store: store, type: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
                                         start: sleepStart, end: end, strict: false)
            .compactMap { sample -> AppleHealthSample? in
                guard let sample = sample as? HKCategorySample else { return nil }
                return record(sample, key: "sleep", value: Double(sample.value))
            }
        for session in AppleSleepNormalizer.sessions(rawSleep, calendar: calendar) {
            let key = AppleHealthDay.dayKey(Date(timeIntervalSince1970: session.end), calendar: calendar)
            guard days[key] != nil else { continue }
            days[key]?.sleep.append(session)
            days[key]?.samples.append(contentsOf: rawSleep.filter { $0.start < session.end && $0.end > session.start })
        }
        let workouts = try await samples(store: store, type: .workoutType(), start: start, end: end).compactMap { $0 as? HKWorkout }
        let efforts = try await workoutEfforts(store: store, start: start, end: end)
        for workout in workouts {
            let key = AppleHealthDay.dayKey(workout.startDate, calendar: calendar)
            let heartStats = workout.statistics(for: HKQuantityType(.heartRate))
            let heartUnit = HKUnit.count().unitDivided(by: .minute())
            var effortValue: Double?
            if #available(iOS 18, *), let effort = efforts[workout.uuid] {
                effortValue = effort.quantity.doubleValue(for: .appleEffortScore())
                days[key]?.samples.append(record(effort, key: "effort", value: effortValue!))
            }
            let activity = AppleHealthWorkout(id: workout.uuid.uuidString, name: name(workout.workoutActivityType),
                source: workout.sourceRevision.source.name, start: workout.startDate.timeIntervalSince1970,
                end: workout.endDate.timeIntervalSince1970, minutes: workout.duration / 60,
                energy: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                averageHR: heartStats?.averageQuantity()?.doubleValue(for: heartUnit), maximumHR: heartStats?.maximumQuantity()?.doubleValue(for: heartUnit), effort: effortValue)
            days[key]?.workouts.append(activity)
            days[key]?.samples.append(record(workout, key: "activity", value: workout.duration / 60))
        }
        for key in days.keys {
            let samples = days[key]?.samples ?? []
            let unique = Dictionary(samples.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            days[key]?.samples = unique.values.sorted { $0.start < $1.start }
        }
        return days.values.sorted { $0.day < $1.day }
    }

    private static func predicate(start: Date, end: Date, strict: Bool = true) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end, options: strict ? .strictStartDate : []),
            NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))
        ])
    }
    private static func samples(store: HKHealthStore, type: HKSampleType, start: Date, end: Date, strict: Bool = true) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            store.execute(HKSampleQuery(sampleType: type, predicate: predicate(start: start, end: end, strict: strict), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, rows, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: rows ?? []) }
            })
        }
    }
    private static func statistics(store: HKHealthStore, type: HKQuantityType, quantity: Quantity, start: Date, end: Date, calendar: Calendar) async throws -> [String: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate(start: start, end: end),
                options: quantity.cumulative ? .cumulativeSum : (quantity.mostRecent ? .discreteMostRecent : .discreteAverage),
                anchorDate: calendar.startOfDay(for: start), intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                var values: [String: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let q = quantity.cumulative ? stats.sumQuantity() : (quantity.mostRecent ? stats.mostRecentQuantity() : stats.averageQuantity()) {
                        values[AppleHealthDay.dayKey(stats.startDate, calendar: calendar)] = q.doubleValue(for: quantity.unit) * quantity.scale
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }
    private static func record(_ sample: HKSample, key: String, value: Double) -> AppleHealthSample {
        let product = sample.sourceRevision.productType ?? ""
        return .init(id: sample.uuid.uuidString, key: key, start: sample.startDate.timeIntervalSince1970,
            end: sample.endDate.timeIntervalSince1970, source: sample.sourceRevision.source.name,
            sourceID: sample.sourceRevision.source.bundleIdentifier + ":" + (sample.device?.localIdentifier ?? product),
            isWatch: product.hasPrefix("Watch") || sample.device?.model?.localizedCaseInsensitiveContains("watch") == true, value: value)
    }
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
    }
    private static func workoutEfforts(store: HKHealthStore, start: Date, end: Date) async throws -> [UUID: HKQuantitySample] {
        guard #available(iOS 18, *) else { return [:] }
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            let query = HKWorkoutEffortRelationshipQuery(predicate: predicate(start: start, end: end), anchor: nil, options: .mostRelevant) { query, relationships, _, error in
                guard once.claim() else { return }
                store.stop(query)
                if let error { continuation.resume(throwing: error); return }
                var values: [UUID: HKQuantitySample] = [:]
                for relationship in relationships ?? [] where relationship.activity == nil {
                    if let sample = relationship.samples?.compactMap({ $0 as? HKQuantitySample }).first {
                        values[relationship.workout.uuid] = sample
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }
    private static func name(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "跑步"
        case .walking: return "步行"
        case .cycling: return "骑行"
        case .swimming: return "游泳"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "力量训练"
        case .yoga: return "瑜伽"
        case .hiking: return "徒步"
        default: return "运动（\(type.rawValue)）"
        }
    }

    static func persist(_ days: [AppleHealthDay], in store: WhoopStore) async throws {
        guard let first = days.first, let last = days.last else { return }
        var daily: [DailyMetric] = [], apple: [AppleDaily] = [], points: [MetricPoint] = []
        var sleep: [CachedSleepSession] = [], workouts: [WorkoutRow] = [], inputs: [String: Data] = [:]
        let encoder = JSONEncoder()
        for day in days {
            inputs[day.day] = try encoder.encode(day)
            let values = day.values
            let asleep = day.sleep.isEmpty ? nil : day.sleep.reduce(0) { $0 + $1.asleepMinutes }
            let complete = !day.sleep.isEmpty && day.sleep.allSatisfy(\.hasCompleteStages)
            func minutes(_ stage: String) -> Double? { complete ? day.sleep.reduce(0) { $0 + $1.minutes(stage) } : nil }
            daily.append(.init(day: day.day, totalSleepMin: asleep, efficiency: day.sleep.first(where: \.isMain)?.efficiency,
                deepMin: minutes("deep"), remMin: minutes("rem"), lightMin: minutes("light"), disturbances: nil,
                restingHr: values["rhr"].map { Int($0.rounded()) }, avgHrv: values["sdnn"], recovery: nil, strain: nil,
                exerciseCount: day.workouts.count, spo2Pct: values["spo2"], skinTempDevC: nil, respRateBpm: values["resp"],
                steps: values["steps"].map { Int($0.rounded()) }, activeKcalEst: values["energy"], avgSdnn: values["sdnn"], skinTempC: values["temperature"]))
            apple.append(.init(day: day.day, steps: values["steps"].map { Int($0.rounded()) }, activeKcal: values["energy"], basalKcal: values["basal"], vo2max: values["vo2max"],
                avgHr: values["hr"].map { Int($0.rounded()) }, maxHr: day.samples.filter { $0.key == "hr" }.map(\.value).max().map { Int($0.rounded()) }, walkingHr: nil, weightKg: values["weight"]))
            let keys = ["sdnn": "hrv", "rhr": "resting_hr", "resp": "resp_rate", "spo2": "spo2", "temperature": "skin_temp", "energy": "active_kcal", "steps": "steps", "basal": "basal_kcal", "vo2max": "vo2max", "hr": "avg_hr", "weight": "weight", "body_fat": "body_fat", "lean_mass": "lean_mass", "bmi": "bmi"]
            for (key, value) in values { if let metric = keys[key] { points.append(.init(day: day.day, key: metric, value: value)) } }
            if let asleep { points.append(.init(day: day.day, key: "asleep_min", value: asleep)) }
            for (stage, key) in [("deep", "deep_min"), ("rem", "rem_min"), ("light", "core_min")] {
                if let value = minutes(stage) { points.append(.init(day: day.day, key: key, value: value)) }
            }
            for session in day.sleep {
                sleep.append(.init(startTs: Int(session.start), endTs: Int(session.end), efficiency: session.efficiency,
                    restingHr: nil, avgHrv: nil, stagesJSON: String(data: try encoder.encode(session.segments), encoding: .utf8)))
            }
            for workout in day.workouts {
                workouts.append(.init(startTs: Int(workout.start), endTs: Int(workout.end), sport: workout.name, source: "apple-health",
                    durationS: workout.minutes * 60, energyKcal: workout.energy, avgHr: workout.averageHR.map { Int($0.rounded()) },
                    maxHr: workout.maximumHR.map { Int($0.rounded()) }, strain: nil, distanceM: nil, zonesJSON: nil, notes: nil, steps: nil))
            }
        }
        try await store.replaceAppleHealthWindow(from: first.day, to: last.day, start: Int(first.start), end: Int(last.end),
            inputs: inputs, daily: daily, apple: apple, points: points, sleep: sleep, workouts: workouts)
    }
}
#endif
