#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics

struct Nine23DetailView: View {
    let key: String
    let days: [Nine23Metrics.Day]
    @State private var date: Date
    @State private var range = 1
    @State private var showSources = false
    private var dayKey: String { AppleHealthDay.dayKey(date) }
    private var day: Nine23Metrics.Day? { days.first { $0.id == dayKey } }
    private var metric: AppleMetricResult? { Nine23Presentation.metric(key, in: day) }
    init(key: String, dayKey: String, days: [Nine23Metrics.Day]) { self.key = key; self.days = days; _date = State(initialValue: Nine23Presentation.date(dayKey)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Nine23Style.section) {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("详情前一天")
                    Spacer(); Text(dayKey).font(Nine23Style.heading); Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(Calendar.current.isDateInToday(date)).accessibilityLabel("详情后一天")
                }
                Picker("统计周期", selection: $range) { Text("日").tag(1); Text("周").tag(7); Text("月").tag(30); Text("90 天").tag(90) }.pickerStyle(.segmented)
                if range == 1 {
                    hero
                    if let day {
                        if key == "sleep" || key == "rest" { sleep(day) }
                        else if key == "recovery" { recovery(day) }
                        else if key == "activity" { activity(day) }
                        else { rawMetric(day) }
                    } else {
                        Nine23Card { Text("这一天尚未同步，或没有可读取的数据。").font(Nine23Style.body); Text("返回首页，选择这一天并下拉刷新。").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) }
                    }
                } else {
                    Nine23Section(title: "\(range) 天变化", caption: "截至 \(dayKey)")
                    Nine23Card { Nine23TrendChart(days: days, key: key, count: range, endDay: dayKey) { date = Nine23Presentation.date($0); range = 1 } }
                    comparison
                }
                if range == 1 {
                    Nine23Section(title: "最近 7 天")
                    Nine23Card { Nine23TrendChart(days: days, key: key, endDay: dayKey) { date = Nine23Presentation.date($0) } }
                }
                if let metric, let day {
                    Nine23Card {
                        Text("计算依据").font(Nine23Style.heading)
                        Text(metric.explanation).font(Nine23Style.body).foregroundStyle(Nine23Style.secondary)
                        Text(Nine23Metrics.quality(metric.quality)).font(Nine23Style.caption).foregroundStyle(Nine23Style.accent(key, value: metric.value))
                        Button("来源、时间窗口与原始记录") { showSources = true }.font(Nine23Style.caption)
                        Text("更新于 \(Date(timeIntervalSince1970: day.input.updated).formatted(date: .abbreviated, time: .shortened))").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary)
                    }
                }
            }.padding(Nine23Style.page)
        }.navigationTitle(Nine23Presentation.title(key)).nine23Screen()
            .sheet(isPresented: $showSources) { if let metric, let day { NavigationStack { Nine23SourceView(metric: metric, input: day.input).toolbar { Button("完成") { showSources = false } } } } }
    }
    private var hero: some View {
        VStack(spacing: Nine23Style.small) {
            if ["sleep", "rest", "recovery", "activity"].contains(key) {
                Nine23Gauge(key: key, value: key == "sleep" ? metric?.value.map { $0 / 480 * 100 } : metric?.value).frame(maxWidth: 218)
            } else {
                Text(Nine23Metrics.value(metric)).font(Nine23Style.score)
                Text(metric?.unit ?? "").font(Nine23Style.body).foregroundStyle(Nine23Style.secondary)
            }
            Text(key == "sleep" ? "睡眠目标完成度" : key == "activity" ? "已记录运动时长" : metric?.title ?? Nine23Presentation.title(key)).font(Nine23Style.heading)
            if key == "sleep" { Text("实际睡眠 \(Nine23Presentation.duration(metric?.value)) · 目标 8:00").font(Nine23Style.body).foregroundStyle(Nine23Style.secondary) }
            Text(metric.map { Nine23Metrics.quality($0.quality) } ?? "暂无数据").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary)
        }.frame(maxWidth: .infinity)
    }
    @ViewBuilder private func sleep(_ day: Nine23Metrics.Day) -> some View {
        Nine23Card {
            Nine23ValueRow(title: "实际睡眠", value: Nine23Presentation.duration(day["sleep"]?.value), unit: "时:分")
            Nine23ValueRow(title: "睡眠表现 · NOOP Rest", value: Nine23Metrics.value(day["rest"]), unit: "分", color: Nine23Style.sleep)
            if let main = day.input.sleep.first(where: \.isMain) {
                Nine23ValueRow(title: "睡眠效率", value: main.efficiency.map { String(format: "%.0f", $0 * 100) } ?? "—", unit: "%")
                Nine23ValueRow(title: "恢复性睡眠（深睡 + REM）", value: main.hasCompleteStages ? Nine23Presentation.duration(main.minutes("deep") + main.minutes("rem")) : "—")
            }
        }
        Nine23Section(title: "睡眠阶段", caption: "按起床日归属 · 午睡单列")
        ForEach(Array(day.input.sleep.enumerated()), id: \.offset) { _, session in
            Nine23Card {
                HStack { Text(session.isMain ? "主睡眠" : "午睡").font(Nine23Style.heading); Spacer(); Text(Nine23Presentation.duration(session.asleepMinutes)).font(Nine23Style.value) }
                Text("\(Nine23Presentation.time(session.start, zone: day.input.timeZone)) – \(Nine23Presentation.time(session.end, zone: day.input.timeZone))").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary)
                Nine23SleepChart(session: session, timeZone: day.input.timeZone)
                ForEach(["wake", "rem", "light", "deep", "unspecified", "unknown"], id: \.self) { stage in
                    if session.hasCompleteStages || session.minutes(stage) > 0 {
                        HStack(spacing: Nine23Style.small) {
                            Circle().fill(Nine23SleepChart.color(stage)).frame(width: 8, height: 8)
                            Text(Nine23SleepChart.label(stage)).font(Nine23Style.body)
                            Spacer(); Text(Nine23Presentation.duration(session.minutes(stage))).font(Nine23Style.heading)
                        }
                    }
                }
                if !session.hasCompleteStages { Text("存在未分期或未知区间，未补成清醒或浅睡；睡眠表现可能不可计算。").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) }
            }
        }
        if day.input.sleep.isEmpty { Nine23Card { Text("暂无睡眠会话。请确认 Apple Watch 睡眠记录和健康读取权限。").font(Nine23Style.body) } }
        NavigationLink(value: Nine23Route.plan) { Nine23Card { Label("安排今晚的睡眠", systemImage: "bed.double").font(Nine23Style.heading) } }.buttonStyle(.plain)
    }
    @ViewBuilder private func recovery(_ day: Nine23Metrics.Day) -> some View {
        let result = Nine23Presentation.recovery(day, history: days)
        Nine23Section(title: "恢复影响因素", caption: "当日值与个人基线 · 沿用 NOOP 原模型")
        Nine23Card {
            factor("SDNN", value: day.input.values["sdnn"], baseline: result.hrvBaseline, unit: "ms")
            Divider().overlay(Nine23Style.line)
            factor("静息心率", value: day.input.values["rhr"], baseline: result.restingHRBaseline, unit: "次/分")
        }
        Nine23Card {
            Text("你的个人基线").font(Nine23Style.heading)
            ProgressView(value: Double(min(14, result.validDays)), total: 14).tint(Nine23Style.recovery)
            Text("\(result.validDays) 个有效历史日 · 7 日开始出分 · 14 日成熟").font(Nine23Style.body)
            Text(result.recovery == nil ? "当前输入或历史基线不足，暂不生成恢复估算。" : result.usesRestingHR ? "本次估算使用 SDNN 与静息心率。" : "简化估算：静息心率或其基线不足，本次只使用 SDNN。").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary)
        }
        Nine23Section(title: "同时观察")
        ForEach(["sleep", "resp", "spo2", "temperature"], id: \.self) { item in
            NavigationLink(value: Nine23Route.metric(item, dayKey)) { Nine23Card { Nine23ValueRow(title: Nine23Presentation.title(item), value: Nine23Metrics.value(day[item]), unit: item == "sleep" ? "" : day[item]?.unit ?? "") } }.buttonStyle(.plain)
        }
    }
    private func factor(_ title: String, value: Double?, baseline: Double?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: Nine23Style.small) {
            Nine23ValueRow(title: title, value: value.map { String(format: "%.1f", $0) } ?? "—", unit: unit)
            HStack {
                Text("个人基线 \(baseline.map { String(format: "%.1f", $0) } ?? "—") \(unit)")
                Spacer()
                if let value, let baseline, baseline != 0 { Text(String(format: "%+.1f%%", (value / baseline - 1) * 100)).monospacedDigit() }
            }.font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary)
        }
    }
    @ViewBuilder private func activity(_ day: Nine23Metrics.Day) -> some View {
        Nine23Card {
            Nine23ValueRow(title: "已记录运动", value: "\(day.input.workouts.count)", unit: "次")
            Nine23ValueRow(title: "活动能量", value: Nine23Metrics.value(day["energy"]), unit: "kcal")
            Nine23ValueRow(title: "步数", value: Nine23Metrics.value(day["steps"]), unit: "步")
            Text("活动页展示真实运动时长，尚不生成 WHOOP 0–21 综合负荷分。").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary)
        }
        Nine23Section(title: "当天运动")
        ForEach(day.input.workouts, id: \.id) { workout in
            NavigationLink(value: Nine23Route.workout(workout.id, dayKey)) {
                Nine23Card {
                    HStack { Label(workout.name, systemImage: "figure.run").font(Nine23Style.heading); Spacer(); Image(systemName: "chevron.right") }
                    Nine23ValueRow(title: Nine23Presentation.time(workout.start, zone: day.input.timeZone), value: "\(Int(workout.minutes.rounded()))", unit: "分钟")
                    Text(workout.effort.map { String(format: "Apple 努力程度 %.1f / 10", $0) } ?? "未提供 Apple 努力程度").font(Nine23Style.caption).foregroundStyle(Nine23Style.activity)
                }
            }.buttonStyle(.plain)
        }
        if day.input.workouts.isEmpty { Nine23Card { Text("这一天还没有运动记录。使用 Apple Watch 的体能训练记录运动后同步。").font(Nine23Style.body) } }
    }
    @ViewBuilder private func rawMetric(_ day: Nine23Metrics.Day) -> some View {
        let samples = day.input.samples.filter { $0.key == key }
        Nine23Section(title: "当日记录", caption: "\(samples.count) 条样本 · 按实际来源分组")
        Nine23Card {
            Nine23HeartChart(samples: samples, zone: day.input.timeZone, compact: false)
            if let min = samples.map(\.value).min(), let max = samples.map(\.value).max() {
                Nine23ValueRow(title: "样本范围", value: String(format: "%.1f – %.1f", min, max), unit: metric?.unit ?? "")
            }
            Text("图中为原始样本；日汇总使用 HealthKit 统计口径。能量与步数的单条样本不等于当日累计。").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary)
        }
    }
    private var comparison: some View {
        let start = Calendar.current.date(byAdding: .day, value: -(range - 1), to: date)!
        let values = days.filter { $0.id <= dayKey && Nine23Presentation.date($0.id) >= start }.compactMap { Nine23Presentation.metric(key, in: $0)?.value }
        return Nine23Card {
            Nine23ValueRow(title: "有值的日期", value: "\(values.count)", unit: "天")
            Nine23ValueRow(title: "平均", value: values.isEmpty ? "—" : String(format: "%.1f", values.reduce(0, +) / Double(values.count)), unit: metric?.unit ?? "")
            Nine23ValueRow(title: "最高", value: values.max().map { String(format: "%.1f", $0) } ?? "—")
            Nine23ValueRow(title: "最低", value: values.min().map { String(format: "%.1f", $0) } ?? "—")
        }
    }
    private func shift(_ offset: Int) { date = min(Calendar.current.startOfDay(for: Date()), Calendar.current.date(byAdding: .day, value: offset, to: date)!) }
}

struct Nine23SleepChart: View {
    let session: AppleSleepSession
    let timeZone: String
    @State private var selected: Date?
    static func label(_ stage: String) -> String { ["wake": "清醒", "rem": "REM", "light": "核心", "deep": "深睡", "unspecified": "未分期", "unknown": "未知"][stage] ?? stage }
    static func color(_ stage: String) -> Color { switch stage { case "wake": return Nine23Style.secondary; case "rem": return Nine23Style.rem; case "light": return Nine23Style.sleep; case "deep": return Nine23Style.deep; default: return Nine23Style.line } }
    var body: some View {
        VStack(alignment: .leading, spacing: Nine23Style.small) {
            if let selected, let stage = session.segments.first(where: { $0.start <= selected.timeIntervalSince1970 && $0.end > selected.timeIntervalSince1970 }) {
                Text("\(Nine23Presentation.time(selected.timeIntervalSince1970, zone: timeZone)) · \(Self.label(stage.stage))").font(Nine23Style.caption)
            }
            Chart {
                ForEach(Array(session.segments.enumerated()), id: \.offset) { _, segment in
                    RectangleMark(xStart: .value("开始", Date(timeIntervalSince1970: segment.start)), xEnd: .value("结束", Date(timeIntervalSince1970: segment.end)), y: .value("阶段", Self.label(segment.stage)), height: .ratio(0.7))
                        .foregroundStyle(Self.color(segment.stage)).cornerRadius(2)
                }
                if let selected { RuleMark(x: .value("时间", selected)).foregroundStyle(Nine23Style.text) }
            }.chartYScale(domain: ["清醒", "REM", "核心", "深睡", "未分期", "未知"].filter { label in session.segments.contains { Self.label($0.stage) == label } })
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { value in AxisValueLabel { if let date = value.as(Date.self) { Text(Nine23Presentation.time(date.timeIntervalSince1970, zone: timeZone)) } } } }
                .chartXSelection(value: $selected).frame(height: Nine23Style.chartHeight)
            Text("拖动查看分期与时间").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary)
        }
    }
}

struct Nine23HeartChart: View {
    let samples: [AppleHealthSample]
    var zone: String?
    var compact = false
    @State private var selected: Date?
    private var ordered: [AppleHealthSample] { samples.sorted { $0.start < $1.start } }
    var body: some View {
        VStack(alignment: .leading, spacing: Nine23Style.small) {
            if let selected, let sample = ordered.min(by: { abs($0.start - selected.timeIntervalSince1970) < abs($1.start - selected.timeIntervalSince1970) }) {
                Text("\(Nine23Presentation.time(sample.start, zone: zone)) · \(String(format: "%.1f", sample.value)) · \(sample.source)").font(Nine23Style.caption)
            }
            Chart {
                ForEach(ordered, id: \.id) { sample in
                    PointMark(x: .value("时间", Date(timeIntervalSince1970: sample.start)), y: .value("数值", sample.value))
                        .foregroundStyle(by: .value("来源", sample.source)).symbolSize(compact ? 7 : 12)
                }
                if let selected { RuleMark(x: .value("选择", selected)).foregroundStyle(Nine23Style.secondary) }
            }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { value in AxisValueLabel { if let date = value.as(Date.self) { Text(Nine23Presentation.time(date.timeIntervalSince1970, zone: zone)) } } } }
                .chartLegend(compact ? .hidden : .visible).chartYScale(domain: .automatic(includesZero: false))
                .chartXSelection(value: $selected).frame(height: compact ? 85 : Nine23Style.chartHeight)
                .overlay { if ordered.isEmpty { Text("暂无样本").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) } }
            if !compact { Text("保留采样间隔，未把缺失时段连接成连续测量。").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) }
        }
    }
}

struct Nine23WorkoutView: View {
    let workout: AppleHealthWorkout?
    let day: Nine23Metrics.Day?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Nine23Style.section) {
                if let workout {
                    Nine23Section(title: workout.name, caption: "\(day?.id ?? "") · \(Nine23Presentation.time(workout.start, zone: day?.input.timeZone)) – \(Nine23Presentation.time(workout.end, zone: day?.input.timeZone))")
                    Text(Nine23Presentation.duration(workout.minutes)).font(Nine23Style.score).frame(maxWidth: .infinity)
                    Text("运动时长 · 时:分").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary).frame(maxWidth: .infinity)
                    Nine23Card {
                        Nine23ValueRow(title: "Apple 努力程度", value: workout.effort.map { String(format: "%.1f", $0) } ?? "—", unit: "/ 10", color: Nine23Style.activity)
                        Nine23ValueRow(title: "活动能量", value: workout.energy.map { String(format: "%.0f", $0) } ?? "—", unit: "kcal")
                        Nine23ValueRow(title: "平均心率", value: workout.averageHR.map { String(format: "%.0f", $0) } ?? "—", unit: "次/分")
                        Nine23ValueRow(title: "最高心率", value: workout.maximumHR.map { String(format: "%.0f", $0) } ?? "—", unit: "次/分")
                    }
                    Nine23Section(title: "运动期间的心率", caption: "同来源、同时间窗的样本")
                    Nine23Card {
                        Nine23HeartChart(samples: day?.input.samples.filter { $0.key == "hr" && $0.source == workout.source && $0.start >= workout.start && $0.start <= workout.end } ?? [], zone: day?.input.timeZone)
                    }
                    Nine23Card { Text("实际来源：\(workout.source)").font(Nine23Style.body); Text("平均与最高心率取自 HealthKit 运动关联统计；缺少努力程度时不填默认值。").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary); Text(workout.id).font(Nine23Style.caption).textSelection(.enabled) }
                } else { Text("这条运动记录已删除，或尚未同步。").font(Nine23Style.body) }
            }.padding(Nine23Style.page)
        }.navigationTitle("运动详情").nine23Screen()
    }
}

struct Nine23MonitorView: View {
    let dayKey: String
    let days: [Nine23Metrics.Day]
    private var day: Nine23Metrics.Day? { days.first { $0.id == dayKey } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Nine23Style.section) {
                Nine23Section(title: "健康监测", caption: dayKey)
                Text("与你自己的历史记录比较。下方是历史观测范围，并非医学正常范围。").font(Nine23Style.body).foregroundStyle(Nine23Style.secondary)
                ForEach(["resp", "spo2", "rhr", "sdnn", "temperature"], id: \.self) { key in
                    let values = days.filter { $0.id < dayKey }.suffix(14).compactMap { $0[key]?.value }
                    NavigationLink(value: Nine23Route.metric(key, dayKey)) {
                        Nine23Card {
                            Nine23ValueRow(title: Nine23Presentation.title(key), value: Nine23Metrics.value(day?[key]), unit: day?[key]?.unit ?? "")
                            if let low = values.min(), let high = values.max() {
                                let current = day?[key]?.value
                                let start = min(low, current ?? low), end = max(high, current ?? high)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Nine23Style.line)
                                        Capsule().fill(Nine23Style.activity.opacity(0.45)).frame(width: max(4, geo.size.width * (high - low) / max(1, end - start))).offset(x: geo.size.width * (low - start) / max(1, end - start))
                                        if let current { Circle().fill(Nine23Style.text).frame(width: 12, height: 12).offset(x: max(0, min(geo.size.width - 12, geo.size.width * (current - start) / max(1, end - start)))) }
                                    }
                                }.frame(height: 8)
                                Text(String(format: "此前最多 14 个记录日：%.1f – %.1f", low, high)).font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary)
                            } else { Text("积累记录后显示个人变化范围").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) }
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(Nine23Style.page)
        }.navigationTitle("健康监测").nine23Screen()
    }
}

struct Nine23SourceView: View {
    let metric: AppleMetricResult
    let input: AppleHealthDay
    private var samples: [AppleHealthSample] { input.samples.filter { $0.key == metric.key || (["rest", "sleep"].contains(metric.key) && $0.key == "sleep") || (metric.key == "recovery" && ["sdnn", "rhr"].contains($0.key)) } }
    var body: some View {
        List {
            Section("统计口径") {
                LabeledContent("日期", value: metric.day); LabeledContent("时区", value: input.timeZone)
                LabeledContent("来源", value: metric.sources.joined(separator: "、"))
                LabeledContent("开始", value: timestamp(metric.start)); LabeledContent("截止", value: timestamp(metric.end)); LabeledContent("更新", value: timestamp(metric.updated))
                Text(metric.algorithm); Text(metric.explanation)
            }
            Section("原始记录 · 共 \(samples.count) 条") {
                ForEach(Array(samples.prefix(200).enumerated()), id: \.offset) { _, sample in
                    VStack(alignment: .leading, spacing: Nine23Style.small) {
                        Text("\(sample.source) · \(String(format: "%.2f", sample.value))")
                        Text(timestamp(sample.start)).font(Nine23Style.caption)
                        Text(sample.id).font(Nine23Style.caption).textSelection(.enabled)
                    }
                }
                if samples.count > 200 { Text("此页显示前 200 条，完整样本仍保留在本机。") }
            }
        }.navigationTitle("数据来源")
    }
    private func timestamp(_ time: Double) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.timeZone = TimeZone(identifier: input.timeZone)
        return f.string(from: Date(timeIntervalSince1970: time))
    }
}
#endif
