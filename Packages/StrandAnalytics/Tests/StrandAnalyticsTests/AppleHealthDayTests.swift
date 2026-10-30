import XCTest
@testable import StrandAnalytics

final class AppleHealthDayTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    func timestamp(_ value: String) -> Double { ISO8601DateFormatter().date(from: value)!.timeIntervalSince1970 }
    func sample(_ id: String, _ start: String, _ end: String, _ stage: Double,
                source: String = "watch", watch: Bool = true) -> AppleHealthSample {
        .init(id: id, key: "sleep", start: timestamp(start), end: timestamp(end), source: source, sourceID: source, isWatch: watch, value: stage)
    }
    func testMidnightOverlapAndWriterPriority() {
        let rows = [sample("a", "2026-10-01T22:00:00Z", "2026-10-02T06:00:00Z", 3),
                    sample("b", "2026-10-01T23:00:00Z", "2026-10-02T05:00:00Z", 3),
                    sample("c", "2026-10-01T21:00:00Z", "2026-10-02T07:00:00Z", 1, source: "third-party", watch: false)]
        let result = AppleSleepNormalizer.sessions(rows, calendar: calendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].asleepMinutes, 480)
        XCTAssertEqual(result[0].sourceID, "watch")
        XCTAssertEqual(result[0].conflicts, ["third-party"])
        XCTAssertEqual(AppleHealthDay.dayKey(Date(timeIntervalSince1970: result[0].end), calendar: calendar), "2026-10-02")
    }
    func testNapAndUnknownRemainSeparate() {
        let rows = [sample("a", "2026-10-01T22:00:00Z", "2026-10-02T06:00:00Z", 3),
                    sample("b", "2026-10-02T14:00:00Z", "2026-10-02T14:30:00Z", 1)]
        let result = AppleSleepNormalizer.sessions(rows, calendar: calendar)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].isMain)
        XCTAssertFalse(result[1].isMain)
        XCTAssertEqual(result[1].minutes("unspecified"), 30)
        XCTAssertEqual(result[1].minutes("light"), 0)
        XCTAssertNil(result[1].efficiency)
    }
    func testGapIsNotWakeAndRestIsUnavailable() {
        let rows = [sample("a", "2026-10-01T22:00:00Z", "2026-10-02T02:00:00Z", 3),
                    sample("b", "2026-10-02T02:10:00Z", "2026-10-02T06:00:00Z", 5)]
        let sleep = AppleSleepNormalizer.sessions(rows, calendar: calendar)
        XCTAssertEqual(sleep.count, 1)
        XCTAssertEqual(sleep[0].minutes("unknown"), 10)
        XCTAssertEqual(sleep[0].minutes("wake"), 0)
        let day = AppleHealthDay(day: "2026-10-02", timeZone: "UTC", start: 0, end: 1, updated: 1, sleep: sleep)
        XCTAssertNil(AppleMetricEngine.results(for: day, history: []).first { $0.key == "rest" }?.value)
    }
    func history() -> [WatchRecovery.Day] {
        (1...14).map { .init(day: String(format: "2026-09-%02d", $0), sdnn: 50 + Double($0 % 3), restingHR: 60) }
    }
    func testContinuousDatesPreserveOriginalFormula() {
        let rows = history()
        let old = WatchRecovery.compute(todaySDNN: 53, todayRHR: 59, sdnnHistory: rows.compactMap(\.sdnn), rhrHistory: rows.compactMap(\.restingHR))
        let dated = WatchRecovery.compute(day: "2026-09-15", todaySDNN: 53, todayRHR: 59, history: rows)
        XCTAssertEqual(old.recovery, dated.recovery)
        XCTAssertEqual(dated.confidence, .solid)
        XCTAssertEqual(dated.validDays, 14)
    }
    func testFutureLeakageRecalibrationAndThirtyDayGap() {
        let rows = history()
        let expected = WatchRecovery.compute(day: "2026-09-15", todaySDNN: 53, todayRHR: 59, history: rows)
        let future = rows + [.init(day: "2026-09-15", sdnn: 500, restingHR: 180), .init(day: "2026-12-01", sdnn: 500, restingHR: 180)]
        XCTAssertEqual(expected, WatchRecovery.compute(day: "2026-09-15", todaySDNN: 53, todayRHR: 59, history: future))
        let recalibrated = WatchRecovery.compute(day: "2026-09-15", todaySDNN: 53, todayRHR: 59, history: rows,
            hrvEpoch: timestamp("2026-09-12T00:00:00Z"), recoveryEpoch: timestamp("2026-09-12T00:00:00Z"))
        XCTAssertNil(recalibrated.recovery)
        XCTAssertEqual(recalibrated.validDays, 3)
        let gap = WatchRecovery.compute(day: "2026-10-15", todaySDNN: 53, todayRHR: 59, history: rows)
        XCTAssertNil(gap.recovery)
        XCTAssertTrue(gap.stale)
    }
    func testMissingInputsAndSelectedDayIsolation() {
        let history = history().map { AppleHealthDay(day: $0.day, timeZone: "UTC", start: 0, end: 1, updated: 1, values: ["sdnn": $0.sdnn!, "rhr": 60]) }
        let input = AppleHealthDay(day: "2026-09-15", timeZone: "UTC", start: 0, end: 1, updated: 1, values: ["sdnn": 53])
        let results = AppleMetricEngine.results(for: input, history: history)
        XCTAssertEqual(results.first { $0.key == "recovery" }?.quality, .simplified)
        XCTAssertNotNil(results.first { $0.key == "recovery" }?.value)
        XCTAssertNil(results.first { $0.key == "activity" }?.value)
        XCTAssertEqual(Set(results.map(\.day)), ["2026-09-15"])
        var missing = input; missing.values = [:]
        XCTAssertNil(AppleMetricEngine.results(for: missing, history: history).first { $0.key == "recovery" }?.value)
    }
    func testAdditionalHealthMetricsRetainDaySourceAndStaleState() {
        let samples = [AppleHealthSample(id: "scale-reading", key: "weight", start: 10, end: 11,
            source: "Personal scale", sourceID: "scale", isWatch: false, value: 70.25)]
        let input = AppleHealthDay(day: "2026-10-02", timeZone: "UTC", start: 0, end: 100, updated: 99,
            values: ["weight": 70.25, "hr": 62.5], samples: samples)
        let results = AppleMetricEngine.results(for: input, history: [])
        let weight = results.first { $0.key == "weight" }!
        XCTAssertEqual(weight.value, 70.25)
        XCTAssertEqual(weight.sources, ["Personal scale"])
        XCTAssertEqual(weight.day, input.day)
        XCTAssertEqual(weight.end, 100)
        XCTAssertTrue(weight.explanation.contains("最近一次"))
        XCTAssertEqual(results.first { $0.key == "hr" }?.value, 62.5)
        XCTAssertEqual(results.first { $0.key == "vo2max" }?.quality, .missing)
        XCTAssertEqual(AppleMetricEngine.results(for: input, history: [], stale: true).first { $0.key == "weight" }?.quality, .stale)
    }
}
