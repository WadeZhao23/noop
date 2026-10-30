import Foundation
import StrandAnalytics

/// Single resolver for phone navigation, trends, widgets and the watch transport.
@MainActor
enum Nine23Metrics {
    struct Day: Identifiable {
        var id: String { input.day }
        var input: AppleHealthDay
        var metrics: [AppleMetricResult]
        subscript(_ key: String) -> AppleMetricResult? { metrics.first { $0.key == key } }
    }
    static func load(repo: Repository, now: Date = Date()) async throws -> [Day] {
        guard let store = await repo.storeHandle() else { return [] }
        let inputs = try await store.appleHealthInputs().map { try JSONDecoder().decode(AppleHealthDay.self, from: $0) }
        let failed = UserDefaults.standard.string(forKey: "nine23.health.lastError") != nil
        return inputs.map { input in
            let stale = failed || (input.day == AppleHealthDay.dayKey(now) && now.timeIntervalSince1970 - input.updated > 6 * 3600)
            return Day(input: input, metrics: AppleMetricEngine.results(for: input, history: inputs,
                hrvEpoch: Baselines.hrvBaselineEpoch(), recoveryEpoch: Baselines.recoveryBaselineEpoch(), stale: stale))
        }
    }
    static func today(repo: Repository) async -> Day? {
        try? await load(repo: repo).first { $0.id == AppleHealthDay.dayKey(Date()) }
    }
    static func quality(_ quality: AppleMetricResult.Quality) -> String {
        switch quality {
        case .available: return "数据可用"
        case .missing: return "暂无数据"
        case .building: return "建立基线中"
        case .simplified: return "简化估算"
        case .stale: return "待更新"
        }
    }
    static func value(_ metric: AppleMetricResult?) -> String {
        guard let metric, let value = metric.value else { return "—" }
        if metric.key == "sleep" { let minutes = Int(value.rounded()); return "\(minutes / 60) 小时 \(minutes % 60) 分" }
        return String(format: metric.unit == "分" || metric.unit == "步" ? "%.0f" : "%.1f", value)
    }
}
