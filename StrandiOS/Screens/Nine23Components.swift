#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics

enum Nine23Route: Hashable {
    case metric(String, String), workout(String, String), monitor(String), trends, journal(String), plan, coach, capabilities
}

enum Nine23Presentation {
    static let dashboardKeys = ["sdnn", "rhr", "steps", "energy", "resp", "spo2", "temperature", "vo2max", "weight", "hr"]
    static func date(_ key: String) -> Date {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key) ?? Date()
    }
    static func title(_ key: String) -> String {
        ["sleep": "睡眠", "rest": "睡眠表现", "recovery": "恢复", "activity": "活动", "sdnn": "心率变异性", "rhr": "静息心率", "hr": "心率", "resp": "呼吸频率", "spo2": "血氧", "temperature": "睡眠腕温", "energy": "活动能量", "steps": "步数", "vo2max": "心肺适能", "weight": "体重"][key] ?? key
    }
    static func time(_ seconds: Double, zone: String? = nil) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; if let zone { f.timeZone = TimeZone(identifier: zone) }
        return f.string(from: Date(timeIntervalSince1970: seconds))
    }
    static func duration(_ minutes: Double?) -> String {
        guard let minutes else { return "—" }; let n = Int(minutes.rounded())
        return "\(n / 60):\(String(format: "%02d", n % 60))"
    }
    static func metric(_ key: String, in day: Nine23Metrics.Day?) -> AppleMetricResult? {
        day?[key]
    }
    static func recovery(_ day: Nine23Metrics.Day, history: [Nine23Metrics.Day]) -> WatchRecovery.Result {
        WatchRecovery.compute(day: day.id, todaySDNN: day.input.values["sdnn"],
            todayRHR: day.input.values["rhr"].map { Int($0.rounded()) },
            history: history.map { .init(day: $0.id, sdnn: $0.input.values["sdnn"], restingHR: $0.input.values["rhr"].map { $0.rounded() }) },
            hrvEpoch: Baselines.hrvBaselineEpoch(), recoveryEpoch: Baselines.recoveryBaselineEpoch())
    }
}

struct Nine23Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: Nine23Style.gap, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(Nine23Style.gap)
            .background(Nine23Style.surface, in: RoundedRectangle(cornerRadius: Nine23Style.radius))
    }
}

struct Nine23Section: View {
    let title: String
    var caption: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: Nine23Style.small) {
            Text(title).font(Nine23Style.title)
            if let caption { Text(caption).font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Nine23Gauge: View {
    let key: String
    let value: Double?
    var compact = false
    private var progress: Double? {
        guard key != "activity", let value else { return nil }
        return min(1, max(0, value / 100))
    }
    var body: some View {
        VStack(spacing: Nine23Style.small) {
            ZStack {
                Circle().stroke(Nine23Style.line, lineWidth: compact ? 6 : 10)
                if let progress {
                    Circle().trim(from: 0, to: progress).stroke(Nine23Style.accent(key, value: value), style: StrokeStyle(lineWidth: compact ? 6 : 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 2) {
                    Text(value.map { String(format: "%.0f", $0) } ?? "—").font(compact ? Nine23Style.value : Nine23Style.score)
                        .minimumScaleFactor(0.65).lineLimit(1)
                    Text(key == "activity" ? "分钟" : key == "sleep" ? "% 目标" : "分 · 估算")
                        .font(Nine23Style.label).foregroundStyle(Nine23Style.secondary)
                }.padding(Nine23Style.small)
            }.aspectRatio(1, contentMode: .fit).padding(compact ? 4 : Nine23Style.gap)
            if compact { Text(Nine23Presentation.title(key)).font(Nine23Style.label).tracking(1) }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Nine23Presentation.title(key))，\(value.map { String(format: "%.0f", $0) } ?? "暂无数据")，\(key == "activity" ? "分钟" : key == "sleep" ? "目标完成百分比" : "估算分")")
    }
}

struct Nine23ValueRow: View {
    let title: String
    let value: String
    var unit: String = ""
    var color: Color = Nine23Style.text
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Nine23Style.small) {
            Text(title).font(Nine23Style.body).foregroundStyle(Nine23Style.secondary)
            Spacer(minLength: Nine23Style.small)
            Text(value).font(Nine23Style.heading).foregroundStyle(color).monospacedDigit()
            if !unit.isEmpty { Text(unit).font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) }
        }
    }
}

struct Nine23TrendChart: View {
    let days: [Nine23Metrics.Day]
    let key: String
    var count = 7
    var endDay = AppleHealthDay.dayKey(Date())
    var compact = false
    var onSelect: ((String) -> Void)? = nil
    @State private var selection: Date?
    private var start: Date { Calendar.current.date(byAdding: .day, value: -(count - 1), to: Nine23Presentation.date(endDay))! }
    private var points: [(day: String, date: Date, value: Double)] {
        days.filter { $0.id <= endDay && Nine23Presentation.date($0.id) >= start }.compactMap { day in
            Nine23Presentation.metric(key, in: day)?.value.map { (day.id, Nine23Presentation.date(day.id), $0) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Nine23Style.small) {
            if !compact, let selection {
                let selectedDay = AppleHealthDay.dayKey(selection)
                let point = points.first { $0.day == selectedDay }
                HStack {
                    Text(selectedDay).font(Nine23Style.caption)
                    Spacer()
                    Text(point.map { String(format: "%.1f", $0.value) } ?? "暂无数据").font(Nine23Style.heading)
                    if point != nil, let onSelect { Button("详情") { onSelect(selectedDay) }.font(Nine23Style.caption) }
                }
            }
            Chart {
                ForEach(points, id: \.day) { point in
                    BarMark(x: .value("日期", point.date, unit: .day), y: .value("数值", point.value))
                        .foregroundStyle(Nine23Style.accent(key, value: point.value))
                        .opacity(selection == nil || Calendar.current.isDate(selection!, inSameDayAs: point.date) ? 1 : 0.35)
                        .cornerRadius(2)
                        .accessibilityLabel("\(point.day)，\(Nine23Presentation.title(key)) \(String(format: "%.1f", point.value))")
                }
                if !compact, let selection { RuleMark(x: .value("选择日期", selection)).foregroundStyle(Nine23Style.secondary).lineStyle(StrokeStyle(dash: [3, 3])) }
            }
            .chartXScale(domain: start...Calendar.current.date(byAdding: .day, value: 1, to: Nine23Presentation.date(endDay))!)
            .chartXAxis {
                if !compact { AxisMarks(values: .stride(by: .day, count: count > 7 ? 7 : 1)) { _ in AxisValueLabel(format: .dateTime.day()); AxisTick() } }
            }
            .chartYAxis { if !compact { AxisMarks(position: .leading) } }
            .nine23ChartSelection($selection)
            .frame(height: compact ? 45 : Nine23Style.chartHeight)
            .overlay { if points.isEmpty && !compact { Text("这段时间暂无记录").font(Nine23Style.body).foregroundStyle(Nine23Style.secondary) } }
            if !compact { Text("点选或拖动图表查看日期；缺失记录保留为空。").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) }
        }
        .onChange(of: endDay) { _, _ in selection = nil }
        .onChange(of: key) { _, _ in selection = nil }
        .onChange(of: count) { _, _ in selection = nil }
    }
}

extension View {
    /// Keep the last point after touch-up so the dated detail action stays reachable.
    func nine23ChartSelection(_ selection: Binding<Date?>) -> some View {
        chartXSelection(value: Binding(get: { selection.wrappedValue }, set: { value in
            if let value { selection.wrappedValue = value }
        }))
    }

    func nine23Screen() -> some View {
        self.background(Nine23Style.canvas).foregroundStyle(Nine23Style.text)
            .toolbarBackground(Nine23Style.canvas, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
    }
}
#endif
