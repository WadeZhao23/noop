#if os(iOS) && DEBUG
import Foundation
import StrandAnalytics

/// Explicit launch-only fixture for simulator UI review. Never used by a production sync.
@MainActor
enum Nine23Demo {
    static func seed(repo: Repository) async throws {
        guard CommandLine.arguments.contains("--nine23-demo"), let store = await repo.storeHandle() else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var days: [AppleHealthDay] = []
        for offset in (-29)...0 {
            let start = cal.date(byAdding: .day, value: offset, to: today)!
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let day = AppleHealthDay.dayKey(start)
            let base = start.timeIntervalSince1970
            let stages: [(Double, Double, Double)] = [(-3600, 7200, 3), (7200, 12600, 4), (12600, 18000, 3), (18000, 23400, 5)]
            var samples = stages.enumerated().map { index, stage in
                AppleHealthSample(id: "synthetic-\(day)-sleep-\(index)", key: "sleep", start: base + stage.0,
                    end: base + stage.1, source: "Apple Watch · 演示", sourceID: "synthetic-watch", isWatch: true, value: stage.2)
            }
            let sdnn = 53 + Double((offset + 30) % 7)
            let values = ["sdnn": sdnn, "rhr": 53.0, "hr": 67.0, "steps": 4280.0,
                          "energy": 326.0, "spo2": 98.0, "resp": 14.5, "temperature": 35.8]
            for (key, value) in values {
                samples.append(.init(id: "synthetic-\(day)-\(key)", key: key, start: base + 25000, end: base + 25001,
                    source: "Apple Watch · 演示", sourceID: "synthetic-watch", isWatch: true, value: value))
            }
            days.append(.init(day: day, timeZone: cal.timeZone.identifier, start: base,
                end: min(Date(), end).timeIntervalSince1970, updated: Date().timeIntervalSince1970, values: values,
                samples: samples, sleep: AppleSleepNormalizer.sessions(samples),
                workouts: [.init(id: "synthetic-workout-\(day)", name: "户外步行", source: "Apple Watch · 演示",
                    start: base + 27000, end: base + 29100, minutes: 35, energy: 146, averageHR: 112, maximumHR: 134, effort: 4)]))
        }
        try await AppleHealthAdapter.persist(days, in: store)
    }
}
#endif
