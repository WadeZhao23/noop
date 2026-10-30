#if os(iOS) && DEBUG
import Foundation
import StrandAnalytics

/// Explicit launch-only fixture for simulator UI review. Never used by a production sync.
@MainActor
enum Nine23Demo {
    static func seed(repo: Repository) async throws {
        guard CommandLine.arguments.contains("--nine23-demo"), let store = await repo.storeHandle() else { return }
        // Fixtures are allowed only in a simulator, even when a physical Debug build is launched.
        #if targetEnvironment(simulator)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var days: [AppleHealthDay] = []
        for offset in (-29)...0 {
            let start = cal.date(byAdding: .day, value: offset, to: today)!
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let day = AppleHealthDay.dayKey(start)
            let base = start.timeIntervalSince1970
            let duration = 420 + ((offset + 30) % 5) * 12
            let pattern: [(Int, Double)] = [(35, 3), (25, 4), (30, 3), (18, 5), (4, 2), (30, 3), (28, 4), (35, 3), (25, 5), (3, 2), (40, 3), (24, 4), (35, 3), (30, 5), (38, 3)]
            var cursor = -Double(duration - 390) * 60
            var stages: [(Double, Double, Double)] = []
            for (minutes, stage) in pattern {
                let next = min(23400, cursor + Double(minutes) * 60)
                if next > cursor { stages.append((cursor, next, stage)) }
                cursor = next
            }
            if cursor < 23400 { stages.append((cursor, 23400, 5)) }
            var samples = stages.enumerated().map { index, stage in
                AppleHealthSample(id: "synthetic-\(day)-sleep-\(index)", key: "sleep", start: base + stage.0,
                    end: base + stage.1, source: "Apple Watch · 演示", sourceID: "synthetic-watch", isWatch: true, value: stage.2)
            }
            let index = Double(offset + 30)
            let sdnn = 53 + sin(index * 0.72) * 13
            let minutes = Double(25 + (offset + 30) % 6 * 8)
            let workoutStart = base + 27000, workoutEnd = workoutStart + minutes * 60
            var values = ["sdnn": sdnn, "rhr": 54 - sin(index * 0.72) * 4, "steps": 4200 + Double((offset + 30) % 7) * 780,
                          "energy": 280 + minutes * 3, "spo2": 97 + Double((offset + 30) % 3) * 0.5, "resp": 14 + sin(index) * 0.8,
                          "temperature": 35.8 + sin(index) * 0.2, "vo2max": 43.2 + index * 0.04, "weight": 69.2 - index * 0.015]
            for (key, value) in values {
                samples.append(.init(id: "synthetic-\(day)-\(key)", key: key, start: base + 25000, end: base + 25001,
                    source: "Apple Watch · 演示", sourceID: "synthetic-watch", isWatch: true, value: value))
            }
            // Sparse daytime samples remain disconnected; workout points are denser.
            var heart: [Double] = []
            for n in 0..<60 {
                let second = Double(n) * 1200
                let value = 66 + sin(Double(n) * 0.9) * 9 + cos(index) * 3
                heart.append(value)
                samples.append(.init(id: "synthetic-\(day)-hr-\(n)", key: "hr", start: base + second, end: base + second + 1, source: "Apple Watch · 演示", sourceID: "synthetic-watch", isWatch: true, value: value))
            }
            var workoutHeart: [Double] = []
            for n in 0..<Int(minutes) {
                let value = 104 + min(22, Double(n) * 2) + sin(Double(n) * 0.45) * 8
                heart.append(value); workoutHeart.append(value)
                samples.append(.init(id: "synthetic-\(day)-workout-hr-\(n)", key: "hr", start: workoutStart + Double(n) * 60, end: workoutStart + Double(n) * 60 + 1, source: "Apple Watch · 演示", sourceID: "synthetic-watch", isWatch: true, value: value))
            }
            values["hr"] = heart.reduce(0, +) / Double(heart.count)
            var input = AppleHealthDay(day: day, timeZone: cal.timeZone.identifier, start: base,
                end: min(Date(), end).timeIntervalSince1970, updated: Date().timeIntervalSince1970, values: values,
                samples: samples, sleep: AppleSleepNormalizer.sessions(samples),
                workouts: [.init(id: "synthetic-workout-\(day)", name: "户外步行", source: "Apple Watch · 演示",
                    start: workoutStart, end: workoutEnd, minutes: minutes, energy: minutes * 4.2,
                    averageHR: workoutHeart.reduce(0, +) / Double(workoutHeart.count), maximumHR: workoutHeart.max(), effort: 4)])
            input.samples.removeAll { $0.end > input.end }
            input.workouts.removeAll { $0.end > input.end }
            for key in Array(input.values.keys) where !input.samples.contains(where: { $0.key == key }) {
                input.values.removeValue(forKey: key)
            }
            let observedHeart = input.samples.filter { $0.key == "hr" }.map(\.value)
            input.values["hr"] = observedHeart.isEmpty ? nil : observedHeart.reduce(0, +) / Double(observedHeart.count)
            if CommandLine.arguments.contains("--nine23-demo-edge-cases") { applyEdgeCase(offset, to: &input) }
            input.sleep = AppleSleepNormalizer.sessions(input.samples)
            if offset == 0 && CommandLine.arguments.contains("--nine23-demo-stale") { input.updated -= 8 * 3600 }
            days.append(input)
        }
        try await AppleHealthAdapter.persist(days, in: store)
        #endif
    }

    /// Relative dates keep each failure mode reachable through the normal calendar UI.
    private static func applyEdgeCase(_ offset: Int, to input: inout AppleHealthDay) {
        switch offset {
        case -1, -2:
            let key = offset == -1 ? "rhr" : "sdnn"
            input.values.removeValue(forKey: key)
            input.samples.removeAll { $0.key == key }
        case -3:
            input.samples.removeAll { $0.id.hasSuffix("sleep-2") }
            if let index = input.samples.firstIndex(where: { $0.key == "sleep" }) { input.samples[index].value = 1 }
        case -4:
            input.values = [:]; input.samples = []; input.workouts = []
        case -5:
            input.samples.append(.init(id: "synthetic-competing-sleep-\(input.day)", key: "sleep", start: input.start - 3600, end: input.start + 7 * 3600, source: "第三方睡眠 · 演示", sourceID: "synthetic-third-party", isWatch: false, value: 1))
        case -6:
            if var duplicate = input.samples.first(where: { $0.key == "sleep" }) {
                duplicate.id += "-overlap"; input.samples.append(duplicate)
            }
            input.samples.append(.init(id: "synthetic-nap-\(input.day)", key: "sleep", start: input.start + 14 * 3600, end: input.start + 14.5 * 3600, source: "Apple Watch · 演示", sourceID: "synthetic-watch", isWatch: true, value: 1))
        case -7:
            if !input.workouts.isEmpty { input.workouts[0].effort = nil }
        default: break
        }
    }
}
#endif
