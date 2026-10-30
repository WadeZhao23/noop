import XCTest
@testable import WhoopStore

final class AppleHealthWindowTests: XCTestCase {
    func testDeleteReplayAndSourceIsolation() async throws {
        let store = try await WhoopStore.inMemory()
        let point = MetricPoint(day: "2026-10-02", key: "sdnn", value: 50)
        try await store.upsertMetricSeries([point], deviceId: "other")
        let sleep = CachedSleepSession(startTs: 10, endTs: 100, efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: nil)
        for _ in 0..<2 {
            try await store.replaceAppleHealthWindow(from: point.day, to: point.day, start: 0, end: 200,
                inputs: [point.day: Data("one".utf8)], daily: [], apple: [], points: [point], sleep: [sleep], workouts: [])
        }
        let payloads = try await store.appleHealthInputs()
        XCTAssertEqual(payloads, [Data("one".utf8)])
        let sessions = try await store.sleepSessions(deviceId: "apple-health", from: 0, to: 200, limit: 10)
        XCTAssertEqual(sessions.count, 1)
        try await store.replaceAppleHealthWindow(from: point.day, to: point.day, start: 0, end: 200,
            inputs: [:], daily: [], apple: [], points: [], sleep: [], workouts: [])
        let empty = try await store.appleHealthInputs()
        let emptySleep = try await store.sleepSessions(deviceId: "apple-health", from: 0, to: 200, limit: 10)
        XCTAssertTrue(empty.isEmpty); XCTAssertTrue(emptySleep.isEmpty)
        let unaffected = try await store.metricSeries(deviceId: "other", key: "sdnn", from: point.day, to: point.day)
        XCTAssertEqual(unaffected, [point])
    }
    func testTransactionRollbackKeepsLastGoodSnapshot() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.replaceAppleHealthWindow(from: "2026-10-01", to: "2026-10-01", start: 0, end: 1,
            inputs: ["2026-10-01": Data("old".utf8)], daily: [], apple: [], points: [], sleep: [], workouts: [])
        try await store.replaceAppleHealthWindow(from: "2026-10-02", to: "2026-10-02", start: 1, end: 2,
            inputs: ["2026-10-02": Data("also-good".utf8)], daily: [], apple: [], points: [], sleep: [], workouts: [])
        do {
            // Delete the second day's good payload, then fail on a duplicate outside that window.
            try await store.replaceAppleHealthWindow(from: "2026-10-02", to: "2026-10-02", start: 0, end: 1,
                inputs: ["2026-10-01": Data("bad".utf8)], daily: [], apple: [], points: [], sleep: [], workouts: [])
            XCTFail("duplicate primary key must fail")
        } catch { }
        let payloads = try await store.appleHealthInputs()
        XCTAssertEqual(payloads, [Data("old".utf8), Data("also-good".utf8)])
    }
}
