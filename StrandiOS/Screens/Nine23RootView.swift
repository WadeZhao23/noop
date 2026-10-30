#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics

/// Apple Watch first navigation. Routes carry a dated metric result, never a generic catalog key.
struct Nine23RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var watch: WatchSessionBridge
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var health: HealthKitBridge
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var date = Date()
    @State private var days: [Nine23Metrics.Day] = []
    @State private var error: String?
    @State private var trendKey = "sleep"
    @State private var showAdvanced = false
    @State private var recalibrate = false
    private var dayKey: String { AppleHealthDay.dayKey(date) }
    private var selected: Nine23Metrics.Day? { days.first { $0.id == dayKey } }

    var body: some View {
        TabView {
            NavigationStack { today.navigationTitle("9点23") }
                .tabItem { Label("今日", systemImage: "circle.grid.2x2.fill") }
            NavigationStack { trends.navigationTitle("趋势") }
                .tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }
            NavigationStack { profile.navigationTitle("我的") }
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tint(NoopVisualStyle.mint)
        .task {
            #if DEBUG
            try? await Nine23Demo.seed(repo: repo)
            #endif
            await load()
        }
        .onChange(of: repo.refreshSeq) { _, _ in Task { await load() } }
        .onChange(of: health.lastError) { _, _ in Task { await load(); await publish() } }
        .onChange(of: health.lastSync) { _, _ in Task { await load(); await publish() } }
        .sheet(isPresented: $showAdvanced) { NavigationStack { SettingsView().toolbar { Button("完成") { showAdvanced = false } } } }
    }

    private var today: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopVisualStyle.sectionGap) {
                #if DEBUG
                if CommandLine.arguments.contains("--nine23-demo") { Text("演示数据 · 不代表真实健康记录").font(StrandFont.caption) }
                #endif
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: NoopVisualStyle.itemGap) {
                        Text("跟随身体的节奏").font(StrandFont.title2)
                        DatePicker("日期", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden()
                    }
                } else {
                    HStack {
                        Text("跟随身体的节奏").font(StrandFont.title2)
                        Spacer()
                        DatePicker("日期", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden()
                    }
                }
                if let error = error ?? health.lastError { Text(error).font(StrandFont.caption).foregroundStyle(StrandPalette.statusCritical) }
                if health.auth != .authorized && !isDemo { authorization }
                ForEach(["sleep", "recovery", "activity"], id: \.self) { key in
                    if let metric = selected?[key] {
                        NavigationLink { Nine23MetricDetail(metric: metric, input: selected!.input) } label: { domain(metric) }
                            .buttonStyle(.plain)
                    } else { emptyDomain(key) }
                }
                Text(summary).font(StrandFont.body).foregroundStyle(NoopVisualStyle.secondaryText)
                VStack(alignment: .leading, spacing: NoopVisualStyle.itemGap) {
                    Text("当天记录").font(StrandFont.headline)
                    if let input = selected?.input {
                        ForEach(Array(input.sleep.enumerated()), id: \.offset) { _, sleep in
                            Label("\(sleep.isMain ? "主睡眠" : "午睡") · \(Int(sleep.asleepMinutes.rounded())) 分钟", systemImage: "bed.double")
                                .font(StrandFont.body)
                        }
                        ForEach(input.workouts, id: \.id) { workout in
                            VStack(alignment: .leading) {
                                Text("\(workout.name) · \(Int(workout.minutes.rounded())) 分钟").font(StrandFont.body)
                                Text(workout.effort.map { "Apple 努力程度 \(String(format: "%.1f", $0)) / 10" } ?? "未提供 Apple 努力程度")
                                    .font(StrandFont.caption).foregroundStyle(NoopVisualStyle.secondaryText)
                            }
                        }
                        if input.sleep.isEmpty && input.workouts.isEmpty { Text("当天还没有睡眠或运动记录").font(StrandFont.body) }
                    } else { Text("同步后查看当天记录").font(StrandFont.body) }
                }
                if let updated = selected?.input.updated {
                    Text("更新于 \(Date(timeIntervalSince1970: updated).formatted(date: .abbreviated, time: .shortened)) · 苹果健康")
                        .font(StrandFont.caption).foregroundStyle(NoopVisualStyle.tertiaryText)
                }
                Button(health.syncing ? "正在同步…" : "刷新这一天") { Task { await refresh() } }
                    .disabled(health.syncing).buttonStyle(.bordered)
            }.padding(NoopVisualStyle.pagePadding)
        }
        .background(NoopVisualStyle.canvas)
        .refreshable { await refresh() }
    }

    private var isDemo: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("--nine23-demo")
        #else
        return false
        #endif
    }
    private var authorization: some View {
        VStack(alignment: .leading, spacing: NoopVisualStyle.itemGap) {
            Text("连接苹果健康").font(StrandFont.headline)
            Text("使用 iPhone 与 Apple Watch 的睡眠、心率和运动记录。数据只保存在本机。").font(StrandFont.body)
            Button("允许读取健康数据") { Task { await health.requestAuthorization(); await refresh() } }
                .buttonStyle(.borderedProminent).foregroundStyle(NoopVisualStyle.canvas)
        }.padding(NoopVisualStyle.cardPadding).background(NoopVisualStyle.surface, in: RoundedRectangle(cornerRadius: NoopVisualStyle.cardRadius))
    }

    private func domain(_ metric: AppleMetricResult) -> some View {
        VStack(alignment: .leading, spacing: NoopVisualStyle.itemGap) {
            HStack {
                Label(metric.key == "recovery" ? "恢复" : metric.title, systemImage: metric.key == "sleep" ? "moon.zzz.fill" : metric.key == "recovery" ? "heart.fill" : "figure.walk")
                    .font(StrandFont.headline)
                Spacer()
                Image(systemName: "chevron.right").font(StrandFont.caption)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Nine23Metrics.value(metric)).font(StrandFont.title1).monospacedDigit()
                if metric.key != "sleep" { Text(metric.unit).font(StrandFont.body) }
            }.foregroundStyle(NoopVisualStyle.mint)
            if metric.key == "sleep", let minutes = metric.value {
                ProgressView(value: min(1, minutes / 480)).tint(NoopVisualStyle.mint)
                Text("目标 8 小时 · 完成 \(Int((minutes / 480 * 100).rounded()))%").font(StrandFont.caption)
            }
            Text(Nine23Metrics.quality(metric.quality)).font(StrandFont.caption).foregroundStyle(NoopVisualStyle.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NoopVisualStyle.cardPadding)
        .background(NoopVisualStyle.surface, in: RoundedRectangle(cornerRadius: NoopVisualStyle.cardRadius))
    }
    private func emptyDomain(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: NoopVisualStyle.itemGap) {
            Text(key == "sleep" ? "实际睡眠" : key == "recovery" ? "恢复" : "运动时长").font(StrandFont.headline)
            Text("—").font(StrandFont.title1)
            Text("该日期尚未同步，或没有可读取的数据").font(StrandFont.caption)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(NoopVisualStyle.cardPadding)
            .background(NoopVisualStyle.surface, in: RoundedRectangle(cornerRadius: NoopVisualStyle.cardRadius))
    }
    private var summary: String {
        guard let day = selected else { return "戴上 Apple Watch 后，先同步苹果健康。恢复估算需要至少 7 个有效历史日。" }
        let sleep = day["sleep"]?.value.map { "睡眠 \(Int($0.rounded())) 分钟" } ?? "睡眠暂无数据"
        return "\(sleep)，记录了 \(day.input.workouts.count) 次运动。" + (day["recovery"]?.value == nil ? "恢复估算仍需有效的当日 SDNN 与个人基线。" : "恢复估算可点开查看输入和依据。")
    }

    private var trends: some View {
        List {
            Picker("指标", selection: $trendKey) {
                Text("睡眠").tag("sleep"); Text("恢复").tag("recovery"); Text("活动").tag("activity")
            }.pickerStyle(.segmented)
            Chart {
                ForEach(days.suffix(30)) { day in
                    if let value = day[trendKey]?.value { BarMark(x: .value("日期", day.id), y: .value("数值", value)).foregroundStyle(NoopVisualStyle.mint) }
                }
            }.frame(minHeight: 200).accessibilityLabel("最近 30 个已同步日期，缺失数据不补零")
            Text("缺失数据保留为空；点开日期查看来源与统计窗口。").font(StrandFont.caption)
            ForEach(days.reversed()) { day in
                if let metric = day[trendKey] {
                    NavigationLink { Nine23MetricDetail(metric: metric, input: day.input) } label: {
                        LabeledContent(day.id, value: "\(Nine23Metrics.value(metric)) \(metric.key == "sleep" ? "" : metric.unit)")
                    }
                }
            }
        }
    }
    private var profile: some View {
        List {
            Section("Apple Watch 模式") {
                Label("9点23 · 本机计算", systemImage: "applewatch")
                Text("健康数据只读，不回写导入结果。手机、手表和组件使用同一份指标计算结果。").font(StrandFont.body)
                Button("同步最近 30 天") { date = Date(); Task { await refresh() } }.disabled(health.syncing)
                Button("重新建立个人基线") { recalibrate = true }
            }
            Section("基础指标") {
                if let day = selected {
                    ForEach(day.metrics.filter { !["sleep", "activity", "recovery"].contains($0.key) }) { metric in
                        NavigationLink { Nine23MetricDetail(metric: metric, input: day.input) } label: {
                            LabeledContent(metric.title, value: Nine23Metrics.value(metric))
                        }
                    }
                }
                Text("日期：\(dayKey)").font(StrandFont.caption)
            }
            Section("更多") {
                NavigationLink("睡眠分析") { SleepView() }
                NavigationLink("教练") { CoachView() }
                Button("高级功能与设置") { showAdvanced = true }
                Text("9点23 基于 ryanbr/noop 开源项目修改。恢复与睡眠为仓库近似模型，仅用于个人趋势观察。").font(StrandFont.body)
                Link("上游项目与许可", destination: URL(string: "https://github.com/ryanbr/noop")!)
            }
        }
        .confirmationDialog("重新校准后将从今天开始积累基线，原始健康数据会保留。", isPresented: $recalibrate, titleVisibility: .visible) {
            Button("重新建立基线") {
                Baselines.recalibrateRecoveryBaselines()
                Task { await load(); await publish() }
            }
        }
    }
    private func load() async {
        do { days = try await Nine23Metrics.load(repo: repo); error = nil }
        catch { self.error = "读取本机缓存失败：\(error.localizedDescription)" }
    }
    private func refresh() async {
        _ = await health.syncApple(days: 30, through: date)
        await load()
        await publish()
    }
    private func publish() async {
        await WidgetSnapshot.publish(from: model)
        watch.send(await WatchSessionBridge.buildSnapshot(from: model))
    }
}

private struct Nine23MetricDetail: View {
    let metric: AppleMetricResult
    let input: AppleHealthDay
    var body: some View {
        List {
            Section {
                Text("\(Nine23Metrics.value(metric)) \(metric.key == "sleep" ? "" : metric.unit)").font(StrandFont.title1).foregroundStyle(NoopVisualStyle.mint)
                Text(Nine23Metrics.quality(metric.quality)).font(StrandFont.body)
            }
            Section("数据口径") {
                LabeledContent("日期", value: metric.day)
                LabeledContent("来源", value: metric.sources.isEmpty ? "未读取到样本" : metric.sources.joined(separator: "、"))
                LabeledContent("时区", value: input.timeZone)
                LabeledContent("统计开始", value: timestamp(metric.start))
                LabeledContent("统计截止", value: timestamp(metric.end))
                LabeledContent("更新时间", value: timestamp(metric.updated))
                Text(metric.explanation).font(StrandFont.body)
                Text(metric.algorithm).font(StrandFont.caption)
            }
            if metric.key == "sleep" || metric.key == "rest" {
                Section("睡眠会话") {
                    ForEach(Array(input.sleep.enumerated()), id: \.offset) { _, session in
                        VStack(alignment: .leading, spacing: NoopVisualStyle.itemGap) {
                            Text("\(session.isMain ? "主睡眠" : "午睡") · \(Int(session.asleepMinutes.rounded())) 分钟").font(StrandFont.headline)
                            Text("\(timestamp(session.start)) – \(timestamp(session.end))").font(StrandFont.caption)
                            Text("深睡 \(stageMinutes(session, "deep")) · REM \(stageMinutes(session, "rem")) · 核心 \(stageMinutes(session, "light")) · 未分期睡眠 \(Int(session.minutes("unspecified"))) 分钟").font(StrandFont.body)
                            if !session.hasCompleteStages { Text("阶段或区间不完整，不计算睡眠估算。").font(StrandFont.caption) }
                        }
                    }
                }
            }
            if metric.key == "activity" {
                Section("运动明细") {
                    ForEach(input.workouts, id: \.id) { workout in
                        VStack(alignment: .leading) {
                            Text(workout.name).font(StrandFont.headline)
                            Text("\(timestamp(workout.start)) · \(String(format: "%.1f", workout.minutes)) 分钟")
                            Text("能量 \(workout.energy.map { String(format: "%.1f", $0) } ?? "—") kcal · 平均心率 \(workout.averageHR.map { String(format: "%.1f", $0) } ?? "—") 次/分")
                            Text(workout.effort.map { "Apple 努力程度 \(String(format: "%.1f", $0)) / 10" } ?? "缺少 Apple 努力程度")
                            Text(workout.source).font(StrandFont.caption)
                        }.font(StrandFont.body)
                    }
                }
            }
            Section("HealthKit 样本") {
                let samples = input.samples.filter { $0.key == metric.key || (metric.key == "recovery" && ["sdnn", "rhr"].contains($0.key)) }
                Text("共 \(samples.count) 条。保留样本 UUID，可与苹果健康的显示所有数据核对。显示舍入不影响计算。").font(StrandFont.caption)
                ForEach(Array(samples.prefix(200).enumerated()), id: \.offset) { _, sample in
                    VStack(alignment: .leading) {
                        Text("\(sample.source) · \(String(format: "%.2f", sample.value))").font(StrandFont.body)
                        Text(timestamp(sample.start)).font(StrandFont.caption)
                        Text(sample.id).font(StrandFont.caption).textSelection(.enabled)
                    }
                }
                if samples.count > 200 { Text("仅展示前 200 条，完整样本保留在本机缓存中。").font(StrandFont.caption) }
            }
        }.navigationTitle(metric.title)
    }
    private func stageMinutes(_ session: AppleSleepSession, _ stage: String) -> String {
        let minutes = session.minutes(stage)
        return session.hasCompleteStages || minutes > 0 ? String(Int(minutes.rounded())) : "—"
    }
    private func timestamp(_ value: Double) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.timeZone = TimeZone(identifier: input.timeZone)
        f.dateFormat = "MM-dd HH:mm:ss"; return f.string(from: Date(timeIntervalSince1970: value))
    }
}
#endif
