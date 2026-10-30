import Foundation
import GRDB

extension WhoopStore {
    /// One transaction owns every derived representation. An authoritative empty window deletes
    /// old imports; a failed query must never call this method. User-edited sleep is preserved.
    public func replaceAppleHealthWindow(from: String, to: String, start: Int, end: Int,
                                        inputs: [String: Data], daily: [DailyMetric], apple: [AppleDaily],
                                        points: [MetricPoint], sleep: [CachedSleepSession],
                                        workouts: [WorkoutRow]) async throws {
        let deviceId = "apple-health"
        try syncWrite { db in
            for table in ["dailyMetric", "appleDaily", "metricSeries"] {
                try db.execute(sql: "DELETE FROM \(table) WHERE deviceId = ? AND day >= ? AND day <= ?",
                               arguments: [deviceId, from, to])
            }
            try db.execute(sql: "DELETE FROM sleepSession WHERE deviceId = ? AND endTs >= ? AND endTs < ? AND userEdited = 0",
                           arguments: [deviceId, start, end])
            try db.execute(sql: "DELETE FROM workout WHERE deviceId = ? AND startTs >= ? AND startTs < ?",
                           arguments: [deviceId, start, end])
            try db.execute(sql: "DELETE FROM appleHealthDay WHERE day >= ? AND day <= ?", arguments: [from, to])
            _ = try Self.upsertDailyMetrics(daily, deviceId: deviceId, in: db)
            _ = try Self.upsertAppleDaily(apple, deviceId: deviceId, in: db)
            _ = try Self.upsertMetricSeries(points, deviceId: deviceId, in: db)
            _ = try Self.upsertSleepSessions(sleep, deviceId: deviceId, in: db)
            _ = try Self.upsertWorkouts(workouts, deviceId: deviceId, in: db)
            for (day, data) in inputs {
                try db.execute(sql: "INSERT INTO appleHealthDay (day, payload) VALUES (?, ?)", arguments: [day, data])
            }
        }
    }

    public func appleHealthInputs(from: String = "0000-00-00", to: String = "9999-99-99") async throws -> [Data] {
        try syncRead { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM appleHealthDay WHERE day >= ? AND day <= ? ORDER BY day", arguments: [from, to])
        }
    }
}
