import Foundation

/// Apple-only import envelope. UUIDs and writer identity survive aggregation for reconciliation.
public struct AppleHealthSample: Codable, Equatable, Sendable {
    public var id: String
    public var key: String
    public var start: Double
    public var end: Double
    public var source: String
    public var sourceID: String
    public var isWatch: Bool
    public var value: Double
    public init(id: String, key: String, start: Double, end: Double, source: String,
                sourceID: String, isWatch: Bool, value: Double) {
        self.id = id; self.key = key; self.start = start; self.end = end
        self.source = source; self.sourceID = sourceID; self.isWatch = isWatch; self.value = value
    }
}

public struct AppleSleepSession: Codable, Equatable, Sendable {
    public struct Segment: Codable, Equatable, Sendable {
        public var start: Double, end: Double
        public var stage: String
    }
    public var start: Double, end: Double
    public var source: String, sourceID: String
    public var conflicts: [String]
    public var segments: [Segment]
    public var isMain: Bool = false
    public var asleepMinutes: Double {
        segments.filter { ["light", "deep", "rem", "unspecified"].contains($0.stage) }
            .reduce(0) { $0 + ($1.end - $1.start) / 60 }
    }
    public func minutes(_ stage: String) -> Double {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + ($1.end - $1.start) / 60 }
    }
    public var hasCompleteStages: Bool {
        !segments.isEmpty && segments.allSatisfy { ["light", "deep", "rem", "wake"].contains($0.stage) }
    }
    public var efficiency: Double? { hasCompleteStages && end > start ? asleepMinutes * 60 / (end - start) : nil }
}

/// Normalize one writer at a time. Missing intervals remain unknown, never inferred wake/core.
public enum AppleSleepNormalizer {
    public static func sessions(_ samples: [AppleHealthSample], calendar: Calendar = .current) -> [AppleSleepSession] {
        let unique = Dictionary(samples.filter { $0.key == "sleep" && $0.end > $0.start }
            .map { ($0.id, $0) }, uniquingKeysWith: { _, b in b }).values
        var candidates: [AppleSleepSession] = []
        var watchSources = Set<String>()
        for (sourceID, rows) in Dictionary(grouping: unique, by: \.sourceID) {
            if rows.contains(where: \.isWatch) { watchSources.insert(sourceID) }
            let sorted = rows.sorted { $0.start < $1.start }
            var runs: [[AppleHealthSample]] = []
            for row in sorted {
                if let last = runs.last, row.start <= (last.map(\.end).max() ?? 0) {
                    runs[runs.count - 1].append(row)
                } else { runs.append([row]) }
            }
            let blocks = runs.map { SleepStageTotals.NightBlock(start: Int($0.map(\.start).min()!), end: Int($0.map(\.end).max()!)) }
            let offset = calendar.timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: sorted.first?.end ?? 0))
            for group in SleepStageTotals.bridgedNightGroups(blocks, offsetSec: offset) {
                let rows = group.indices.flatMap { runs[$0] }
                let boundaries = Set(rows.flatMap { [$0.start, $0.end] }).sorted()
                var segments: [AppleSleepSession.Segment] = []
                for (a, b) in zip(boundaries, boundaries.dropFirst()) {
                    let covering = rows.filter { $0.start < b && $0.end > a }
                    // inBed is an envelope, not a sleep stage. Specific stages supersede unspecified.
                    let stages = Set(covering.map { Int($0.value) }.filter { $0 != 0 })
                    let specific = stages.subtracting([1])
                    let stage: String
                    if specific.count == 1, let v = specific.first {
                        stage = [2: "wake", 3: "light", 4: "deep", 5: "rem"][v] ?? "unknown"
                    } else if specific.isEmpty && stages.contains(1) { stage = "unspecified" }
                    else { stage = "unknown" }
                    segments.append(.init(start: a, end: b, stage: stage))
                }
                guard let start = boundaries.first, let end = boundaries.last,
                      segments.contains(where: { ["light", "deep", "rem", "unspecified"].contains($0.stage) }) else { continue }
                candidates.append(.init(start: start, end: end, source: rows[0].source,
                                        sourceID: sourceID, conflicts: [], segments: segments))
            }
        }
        // Select a whole session from one writer; never splice competing writers' stages together.
        candidates.sort {
            let a = watchSources.contains($0.sourceID), b = watchSources.contains($1.sourceID)
            if a != b { return a }
            if $0.hasCompleteStages != $1.hasCompleteStages { return $0.hasCompleteStages }
            if $0.asleepMinutes != $1.asleepMinutes { return $0.asleepMinutes > $1.asleepMinutes }
            return $0.sourceID < $1.sourceID
        }
        var selected: [AppleSleepSession] = []
        for candidate in candidates {
            if let index = selected.firstIndex(where: { $0.start < candidate.end && candidate.start < $0.end }) {
                selected[index].conflicts.append(candidate.source)
            } else { selected.append(candidate) }
        }
        selected.sort { $0.start < $1.start }
        let groups = Dictionary(grouping: selected.indices, by: { AppleHealthDay.dayKey(Date(timeIntervalSince1970: selected[$0].end), calendar: calendar) })
        for indices in groups.values {
            let blocks = indices.map { SleepStageTotals.NightBlock(start: Int(selected[$0].start), end: Int(selected[$0].end)) }
            let offset = calendar.timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: selected[indices[0]].end))
            for index in SleepStageTotals.mainNightGroupIndices(blocks, offsetSec: offset) ?? [] {
                selected[indices[index]].isMain = true
            }
        }
        return selected
    }
}

public struct AppleHealthWorkout: Codable, Equatable, Sendable {
    public var id: String, name: String, source: String
    public var start: Double, end: Double, minutes: Double
    public var energy: Double?, averageHR: Double?, maximumHR: Double?, effort: Double?
    public init(id: String, name: String, source: String, start: Double, end: Double, minutes: Double,
                energy: Double?, averageHR: Double?, maximumHR: Double?, effort: Double?) {
        self.id = id; self.name = name; self.source = source; self.start = start; self.end = end
        self.minutes = minutes; self.energy = energy; self.averageHR = averageHR; self.maximumHR = maximumHR; self.effort = effort
    }
}

/// Persist inputs, not scores: recalibration is applied to the same inputs on every consuming surface.
public struct AppleHealthDay: Codable, Equatable, Sendable {
    public var day: String, timeZone: String
    public var start: Double, end: Double, updated: Double
    public var values: [String: Double]
    public var samples: [AppleHealthSample]
    public var sleep: [AppleSleepSession]
    public var workouts: [AppleHealthWorkout]
    public init(day: String, timeZone: String, start: Double, end: Double, updated: Double,
                values: [String: Double] = [:], samples: [AppleHealthSample] = [],
                sleep: [AppleSleepSession] = [], workouts: [AppleHealthWorkout] = []) {
        self.day = day; self.timeZone = timeZone; self.start = start; self.end = end; self.updated = updated
        self.values = values; self.samples = samples; self.sleep = sleep; self.workouts = workouts
    }
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

public struct AppleMetricResult: Codable, Equatable, Identifiable, Sendable {
    public enum Quality: String, Codable, Sendable { case available, missing, building, simplified, stale }
    public var id: String { "\(day):apple-health:\(key)" }
    public var key: String, title: String, unit: String, day: String
    public var value: Double?
    public var sources: [String]
    public var start: Double, end: Double, updated: Double
    public var quality: Quality
    public var explanation: String
    public var algorithm: String
}

public enum AppleMetricEngine {
    public static func results(for input: AppleHealthDay, history: [AppleHealthDay],
                               hrvEpoch: Double = 0, recoveryEpoch: Double = 0,
                               stale: Bool = false) -> [AppleMetricResult] {
        var results: [AppleMetricResult] = []
        func add(_ key: String, _ title: String, _ unit: String, _ value: Double?,
                 _ explanation: String, quality: AppleMetricResult.Quality = .available,
                 sources: [String]? = nil, start: Double? = nil, end: Double? = nil,
                 algorithm: String = "HealthKit / v1") {
            results.append(.init(key: key, title: title, unit: unit, day: input.day, value: value,
                                 sources: sources ?? Array(Set(input.samples.filter { $0.key == key }.map(\.source))).sorted(),
                                 start: start ?? input.start, end: end ?? input.end, updated: input.updated,
                                 quality: stale ? .stale : (value == nil && quality == .available ? .missing : quality),
                                 explanation: explanation, algorithm: algorithm))
        }
        let sleep = input.sleep
        let sleepSources = Array(Set(sleep.map(\.source))).sorted()
        let conflicts = Array(Set(sleep.flatMap(\.conflicts))).sorted()
        add("sleep", "实际睡眠", "分钟", sleep.isEmpty ? nil : sleep.reduce(0) { $0 + $1.asleepMinutes },
            "按起床日统计，包含主睡眠及单列的午睡；同源重叠只计一次。目标 8 小时。" + (conflicts.isEmpty ? "" : "来源冲突，优先 Apple Watch，未累加：" + conflicts.joined(separator: "、")),
            sources: sleepSources, start: sleep.map(\.start).min(), end: sleep.map(\.end).max(), algorithm: "AppleSleepNormalizer / v1")
        let main = sleep.filter(\.isMain)
        let rest: Double?
        if main.count == 1, let night = main.first, let efficiency = night.efficiency {
            rest = AnalyticsEngine.Rest.composite(tstSeconds: night.asleepMinutes * 60,
                inBedSeconds: night.end - night.start, efficiency: efficiency,
                restorativeSeconds: (night.minutes("deep") + night.minutes("rem")) * 60,
                needHours: 8, consistency: nil, deepSeconds: night.minutes("deep") * 60)
        } else { rest = nil }
        add("rest", "睡眠估算", "分", rest, "沿用仓库 Rest 近似模型；目标 8 小时。仅阶段完整且统计区间确定时计算；缺少一致性输入沿用原模型中性项。", sources: sleepSources, algorithm: "Rest / existing-v1")
        let recovery = WatchRecovery.compute(day: input.day, todaySDNN: input.values["sdnn"],
            todayRHR: input.values["rhr"].map { Int($0.rounded()) },
            history: history.map { .init(day: $0.day, sdnn: $0.values["sdnn"], restingHR: $0.values["rhr"].map { $0.rounded() }) },
            hrvEpoch: hrvEpoch, recoveryEpoch: recoveryEpoch)
        let quality: AppleMetricResult.Quality = recovery.stale ? .stale :
            (input.values["sdnn"] == nil ? .missing : (recovery.recovery == nil ? .building :
                (!recovery.usesRestingHR ? .simplified : (recovery.validDays < 14 ? .building : .available))))
        let baseline = recovery.hrvBaseline.map { String(format: "%.1f", $0) } ?? "—"
        add("recovery", "当日恢复估算", "分", recovery.recovery,
            "日均 SDNN 对比个人基线 \(baseline) ms；已接受 \(recovery.validDays) 个历史日，至少 7 日出分、14 日基线成熟。" +
            (recovery.usesRestingHR ? "使用 SDNN 与静息心率；静息心率按原模型取整，沿用原权重与映射。" : "简化估算：缺少静息心率或其有效基线，仅使用 SDNN。") +
            "这是仓库近似模型，不是 WHOOP 官方分数。", quality: quality,
            sources: Array(Set(input.samples.filter { ["sdnn", "rhr"].contains($0.key) }.map(\.source))).sorted(), algorithm: "WatchRecovery → RecoveryScorer / dated-v1")
        for (key, title, unit) in [("sdnn", "心率变异性 SDNN", "ms"), ("rhr", "静息心率", "次/分"),
                                  ("resp", "呼吸频率", "次/分"), ("spo2", "血氧", "%"),
                                  ("temperature", "睡眠腕温", "°C"), ("energy", "活动能量", "kcal"), ("steps", "步数", "步")] {
            add(key, title, unit, input.values[key], ["energy", "steps"].contains(key)
                ? "HealthKit 当日累计统计；来源明细保留样本标识。" : "HealthKit 当日算术平均。显示保留一位小数，计算保留原始精度；SDNN 不转换为 RMSSD。")
        }
        for (key, title, unit) in [("hr", "心率", "次/分"), ("vo2max", "心肺适能", "ml/kg/min"), ("weight", "体重", "kg")] {
            add(key, title, unit, input.values[key], key == "weight"
                ? "HealthKit 当日最近一次记录。"
                : "HealthKit 当日算术平均；明细保留实际写入来源。")
        }
        add("activity", "运动时长", "分钟", input.workouts.isEmpty ? nil : input.workouts.reduce(0) { $0 + $1.minutes },
            "按运动开始日归属，累计已记录运动的实际时长；不等于健身圆环锻炼分钟，不生成综合负荷分。", sources: Array(Set(input.workouts.map(\.source))).sorted())
        return results
    }
}
