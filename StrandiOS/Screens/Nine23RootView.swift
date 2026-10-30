#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics

/// Reference shell with Apple-only routes that retain the selected metric and calendar day.
struct Nine23RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var watch: WatchSessionBridge
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var health: HealthKitBridge
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var date = Date()
    @State private var days: [Nine23Metrics.Day] = []
    @State private var error: String?
    @State private var tab = 0
    @State private var path: [Nine23Route] = []
    @State private var sheet: Sheet?
    @State private var recalibrate = false
    @State private var range = 30
    @State private var trendKey = "recovery"
    @AppStorage("nine23.dashboard.metrics") private var dashboardRaw = "sdnn,rhr,steps,energy,resp,spo2"
    private enum Sheet: String, Identifiable { case calendar, dashboard, settings, device; var id: String { rawValue } }
    private var dayKey: String { AppleHealthDay.dayKey(date) }
    private var selected: Nine23Metrics.Day? { days.first { $0.id == dayKey } }
    private var dashboardKeys: [String] { dashboardRaw.split(separator: ",").map(String.init).filter { Nine23Presentation.dashboardKeys.contains($0) } }
    private var isDemo: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--nine23-demo")
        #else
        false
        #endif
    }
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Nine23Style.section) {
                    header
                    if let message = error ?? health.lastError { Text(message).font(Nine23Style.caption).foregroundStyle(Nine23Style.red) }
                    if isDemo { Text("演示数据 · 不代表真实健康记录").font(Nine23Style.caption).foregroundStyle(Nine23Style.yellow) }
                    if tab == 0 { home } else if tab == 1 { healthPage } else if tab == 2 { community } else { more }
                }.padding(.horizontal, Nine23Style.page).padding(.top, Nine23Style.small).padding(.bottom, Nine23Style.section)
            }
            .id(tab)
            .refreshable { await refresh() }
            .nine23Screen().toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Nine23Route.self) { route in destination(route).toolbar(.visible, for: .navigationBar).navigationBarTitleDisplayMode(.inline) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { if path.isEmpty { tabBar } }
        .tint(Nine23Style.text)
        .task {
            #if DEBUG
            try? await Nine23Demo.seed(repo: repo)
            #endif
            await load()
        }
        .onChange(of: repo.refreshSeq) { _, _ in Task { await load() } }
        .onChange(of: health.lastError) { _, _ in Task { await load(); await publish() } }
        .onChange(of: health.lastSync) { _, _ in Task { await load(); await publish() } }
        .sheet(item: $sheet) { item in
            NavigationStack {
                Group {
                    switch item {
                    case .calendar: Nine23CalendarView(date: $date, days: days)
                    case .dashboard: dashboardEditor
                    case .settings: SettingsView()
                    case .device: devicePage
                    }
                }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } } }
            }.tint(Nine23Style.text)
        }
        .confirmationDialog("重新校准后将从今天积累基线，原始健康记录会保留。", isPresented: $recalibrate, titleVisibility: .visible) {
            Button("重新建立基线") { Baselines.recalibrateRecoveryBaselines(); Task { await load(); await publish() } }
        }
    }
    private var header: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: Nine23Style.small) {
                    HStack { profileButton; Spacer(); deviceButton }
                    dateControl.frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: Nine23Style.small) { profileButton; Spacer(minLength: 0); dateControl; Spacer(minLength: 0); deviceButton }
            }
        }
    }
    private var profileButton: some View {
        Button { tab = 3 } label: { Image(systemName: "person.crop.circle").font(Nine23Style.title).frame(width: 44, height: 44) }.accessibilityLabel("个人资料")
    }
    private var deviceButton: some View {
        Button { sheet = .device } label: { Image(systemName: health.syncing ? "arrow.triangle.2.circlepath" : "applewatch").font(Nine23Style.title).frame(width: 44, height: 44) }.accessibilityLabel("Apple Watch 与同步")
    }
    private var dateControl: some View {
        HStack(spacing: 0) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("前一天")
                Button { sheet = .calendar } label: { Text(Calendar.current.isDateInToday(date) ? "今天" : date.formatted(.dateTime.month().day())).font(Nine23Style.heading).lineLimit(1).minimumScaleFactor(0.7) }.accessibilityLabel("选择日期，\(dayKey)")
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(Calendar.current.isDateInToday(date)).accessibilityLabel("后一天")
        }.background(Nine23Style.surface, in: Capsule())
    }
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<4) { index in
                Button { tab = index } label: {
                    VStack(spacing: 5) {
                        Image(systemName: ["house", "heart.text.square", "person.2", "line.3.horizontal"][index]).font(Nine23Style.heading)
                        Text(["首页", "健康", "社区", "更多"][index]).font(Nine23Style.label)
                    }.frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, Nine23Style.small)
                        .foregroundStyle(tab == index ? Nine23Style.text : Nine23Style.secondary)
                        .background(tab == index ? Nine23Style.raised.opacity(0.5) : .clear)
                }.buttonStyle(.plain).accessibilityAddTraits(tab == index ? .isSelected : [])
            }
        }.background(Nine23Style.surface).overlay(alignment: .top) { Rectangle().fill(Nine23Style.line).frame(height: 0.5) }
    }
    private var home: some View {
        Group {
            Text("9:23").font(Nine23Style.heading).italic().tracking(4).frame(maxWidth: .infinity)
            if health.auth != .authorized && !isDemo { authorization }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Nine23Style.gap)) : AnyLayout(HStackLayout(spacing: Nine23Style.gap))
            layout {
                ForEach(["sleep", "recovery", "activity"], id: \.self) { key in
                    NavigationLink(value: Nine23Route.metric(key, dayKey)) {
                        Nine23Gauge(key: key, value: key == "sleep" ? selected?[key]?.value.map { $0 / 480 * 100 } : selected?[key]?.value, compact: true)
                    }.buttonStyle(.plain)
                }
            }
            NavigationLink(value: Nine23Route.coach) {
                Nine23Card {
                    HStack { Text(outlookTitle).font(Nine23Style.heading); Spacer(); Image(systemName: "sparkles") }
                    Text(outlook).font(Nine23Style.body).foregroundStyle(Nine23Style.secondary).multilineTextAlignment(.leading)
                    HStack { Text("查看今日解读").font(Nine23Style.caption); Spacer(); Image(systemName: "chevron.right") }
                }
            }.buttonStyle(.plain)
            HStack(alignment: .top, spacing: Nine23Style.small) {
                NavigationLink(value: Nine23Route.monitor(dayKey)) {
                    Nine23Card { Text("健康监测  ›").font(Nine23Style.label); Label("\(vitalCount) / 5 项", systemImage: "waveform.path.ecg").font(Nine23Style.heading); Text("查看身体指标").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) }
                }.buttonStyle(.plain)
                NavigationLink(value: Nine23Route.metric("hr", dayKey)) {
                    Nine23Card { Text("心率趋势  ›").font(Nine23Style.label); Text(selected?.input.values["hr"].map { "\(Int($0.rounded())) 次/分" } ?? "— 次/分").font(Nine23Style.heading); Text("当日均值 · 非实时").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) }
                }.buttonStyle(.plain)
            }
            Nine23Section(title: "我的一天", caption: date.formatted(.dateTime.weekday(.wide).month().day()))
            activities
            NavigationLink(value: Nine23Route.journal(dayKey)) { linkCard("我的日记", subtitle: "记录习惯，观察它们与身体状态的关系", icon: "book.closed") }.buttonStyle(.plain)
            Nine23Section(title: "我的计划")
            NavigationLink(value: Nine23Route.plan) { linkCard("今晚的睡眠", subtitle: "安排作息 · 8 小时睡眠目标", icon: "moon.zzz") }.buttonStyle(.plain)
            Nine23Card {
                Text("最近一周活动").font(Nine23Style.heading)
                HStack {
                    ForEach(weekDays, id: \.self) { key in
                        let count = days.first { $0.id == key }?.input.workouts.count ?? 0
                        VStack(spacing: Nine23Style.small) { Text(Nine23Presentation.date(key).formatted(.dateTime.weekday(.narrow))).font(Nine23Style.caption); Image(systemName: count > 0 ? "checkmark.circle.fill" : "circle").foregroundStyle(count > 0 ? Nine23Style.activity : Nine23Style.line) }.frame(maxWidth: .infinity)
                    }
                }
                NavigationLink("查看运动与周趋势", value: Nine23Route.metric("activity", dayKey)).font(Nine23Style.caption)
            }
            HStack { Nine23Section(title: "我的指标面板"); Button { sheet = .dashboard } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("自定义指标面板") }
            dashboard
            syncFooter
        }
    }
    private var healthPage: some View {
        Group {
            Nine23Section(title: "健康", caption: "更完整地了解你的身体")
            NavigationLink(value: Nine23Route.metric("hr", dayKey)) {
                Nine23Card {
                    HStack { Label("心率", systemImage: "heart.fill").foregroundStyle(Nine23Style.red); Spacer(); Text("当日均值").font(Nine23Style.caption) }
                    Text(selected?.input.values["hr"].map { "\(Int($0.rounded())) 次/分" } ?? "— 次/分").font(Nine23Style.score)
                    Nine23HeartChart(samples: selected?.input.samples.filter { $0.key == "hr" } ?? [], zone: selected?.input.timeZone, compact: true)
                }
            }.buttonStyle(.plain)
            NavigationLink(value: Nine23Route.monitor(dayKey)) { linkCard("健康监测", subtitle: "\(vitalCount) / 5 项有记录 · 查看个人变化", icon: "waveform.path.ecg") }.buttonStyle(.plain)
            ForEach(["sdnn", "rhr", "resp", "spo2", "temperature"], id: \.self) { key in metricTile(key) }
            Nine23Section(title: "长期健康")
            ForEach(["vo2max", "weight", "steps"], id: \.self) { key in metricTile(key) }
            NavigationLink(value: Nine23Route.capabilities) { linkCard("更多健康功能", subtitle: "压力、健康年龄、心电与血压的支持情况", icon: "square.grid.2x2") }.buttonStyle(.plain)
        }
    }
    private var community: some View {
        Group {
            Nine23Section(title: "社区", caption: "个人参考版 · 本地档案")
            Nine23Card {
                HStack { Image(systemName: "person.crop.circle.fill").font(Nine23Style.score); VStack(alignment: .leading) { Text("我的健康旅程").font(Nine23Style.heading); Text("Apple Watch · 9点23").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) } }
                Nine23ValueRow(title: "已同步日期", value: "\(days.count)", unit: "天")
                Nine23ValueRow(title: "记录的运动", value: "\(days.reduce(0) { $0 + $1.input.workouts.count })", unit: "次")
            }
            Nine23Section(title: "我的进展")
            NavigationLink(value: Nine23Route.trends) { linkCard("回看最近 30 天", subtitle: "睡眠、恢复与活动的变化", icon: "chart.bar.xaxis") }.buttonStyle(.plain)
            NavigationLink(value: Nine23Route.journal(dayKey)) { linkCard("建立日记习惯", subtitle: "从一条真实记录开始", icon: "checkmark.circle") }.buttonStyle(.plain)
            Nine23Card {
                Label("团队与排行榜", systemImage: "person.3").font(Nine23Style.heading)
                Text("当前版本只有你的本地记录，尚未接入社区账号、好友或团队服务。").font(Nine23Style.body).foregroundStyle(Nine23Style.secondary)
                Link("浏览 WHOOP 社区参考", destination: URL(string: "https://www.community.whoop.com/")!).font(Nine23Style.caption)
            }
        }
    }
    private var more: some View {
        Group {
            Nine23Section(title: "更多", caption: "9点23 · Apple Watch 参考版")
            NavigationLink(value: Nine23Route.trends) { linkCard("趋势与报告", subtitle: "7 天 / 30 天 / 90 天", icon: "chart.xyaxis.line") }.buttonStyle(.plain)
            NavigationLink(value: Nine23Route.journal(dayKey)) { linkCard("日记与行为洞察", subtitle: "查看记录和下一天的恢复变化", icon: "book") }.buttonStyle(.plain)
            NavigationLink(value: Nine23Route.coach) { linkCard("教练与今日解读", subtitle: "从已有数据理解今天", icon: "sparkles") }.buttonStyle(.plain)
            NavigationLink(value: Nine23Route.plan) { linkCard("睡眠计划", subtitle: "设置你的起床时间", icon: "bed.double") }.buttonStyle(.plain)
            Button { sheet = .device } label: { linkCard("设备与数据同步", subtitle: "Apple Watch → 苹果健康 → 9点23", icon: "applewatch") }.buttonStyle(.plain)
            Button { sheet = .settings } label: { linkCard("设置与高级功能", subtitle: "外观、备份、导出及原项目工具", icon: "gearshape") }.buttonStyle(.plain)
            Nine23Card {
                Text("关于 9点23").font(Nine23Style.heading)
                Text("界面参考 WHOOP 的公开页面，数据来自苹果健康，恢复与睡眠计算基于 NOOP 现有近似模型。").font(Nine23Style.body).foregroundStyle(Nine23Style.secondary)
                Link("开源项目与许可", destination: URL(string: "https://github.com/ryanbr/noop")!)
                NavigationLink("查看功能支持情况", value: Nine23Route.capabilities)
            }
        }
    }
    @ViewBuilder private func destination(_ route: Nine23Route) -> some View {
        switch route {
        case let .metric(key, day): Nine23DetailView(key: key, dayKey: day, days: days)
        case let .workout(id, day): Nine23WorkoutView(workout: days.first { $0.id == day }?.input.workouts.first { $0.id == id }, day: days.first { $0.id == day })
        case let .monitor(day): Nine23MonitorView(dayKey: day, days: days)
        case .trends: trends
        case let .journal(day): Nine23JournalView(initialDay: day, days: days)
        case .plan: Nine23PlanView()
        case .coach: coach
        case .capabilities: Nine23CapabilitiesView()
        }
    }
    private var trends: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Nine23Style.section) {
                Picker("指标", selection: $trendKey) { ForEach(["recovery", "sleep", "activity", "sdnn", "rhr"], id: \.self) { Text(Nine23Presentation.title($0)).tag($0) } }.pickerStyle(.menu)
                Picker("时间范围", selection: $range) { Text("7 天").tag(7); Text("30 天").tag(30); Text("90 天").tag(90) }.pickerStyle(.segmented)
                Nine23Card { Nine23TrendChart(days: days, key: trendKey, count: range, endDay: dayKey) { path.append(.metric(trendKey, $0)) } }
                ForEach(days.filter { $0.id <= dayKey && Nine23Presentation.date($0.id) >= Calendar.current.date(byAdding: .day, value: -(range - 1), to: Calendar.current.startOfDay(for: date))! }.reversed()) { day in
                    NavigationLink(value: Nine23Route.metric(trendKey, day.id)) { Nine23Card { Nine23ValueRow(title: day.id, value: Nine23Metrics.value(Nine23Presentation.metric(trendKey, in: day)), unit: trendKey == "sleep" ? "" : (day[trendKey]?.unit ?? "")) } }.buttonStyle(.plain)
                }
            }.padding(Nine23Style.page)
        }.navigationTitle("趋势与报告").nine23Screen()
    }
    private var coach: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Nine23Style.section) {
                Nine23Section(title: outlookTitle, caption: dayKey)
                Nine23Card { Text(outlook).font(Nine23Style.body); Text("依据当前选择日期的记录生成。").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) }
                ForEach(["sleep", "recovery", "activity"], id: \.self) { key in
                    NavigationLink(value: Nine23Route.metric(key, dayKey)) { linkCard(Nine23Presentation.title(key), subtitle: selected?[key]?.explanation ?? "这一天尚无可读取记录。", icon: "chevron.right") }.buttonStyle(.plain)
                }
                NavigationLink { CoachView() } label: { linkCard("打开 AI 教练", subtitle: "使用原项目的可选 AI 配置与对话能力", icon: "bubble.left.and.bubble.right") }.buttonStyle(.plain)
            }.padding(Nine23Style.page)
        }.navigationTitle("今日解读").nine23Screen()
    }
    private var activities: some View {
        Nine23Card {
            HStack { Text("当天记录").font(Nine23Style.label); Spacer(); NavigationLink(value: Nine23Route.journal(dayKey)) { Image(systemName: "plus.circle.fill").font(Nine23Style.title) }.accessibilityLabel("添加日记") }
            if let day = selected {
                ForEach(Array(day.input.sleep.enumerated()), id: \.offset) { _, sleep in
                    NavigationLink(value: Nine23Route.metric("sleep", dayKey)) {
                        HStack(spacing: Nine23Style.gap) { Image(systemName: "moon.zzz.fill").foregroundStyle(Nine23Style.sleep); VStack(alignment: .leading) { Text(sleep.isMain ? "睡眠" : "午睡").font(Nine23Style.heading); Text("\(Nine23Presentation.time(sleep.start, zone: day.input.timeZone)) – \(Nine23Presentation.time(sleep.end, zone: day.input.timeZone))").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) }; Spacer(); Text(Nine23Presentation.duration(sleep.asleepMinutes)).font(Nine23Style.value); Image(systemName: "chevron.right").font(Nine23Style.caption) }
                    }.buttonStyle(.plain)
                    Divider().overlay(Nine23Style.line)
                }
                ForEach(day.input.workouts, id: \.id) { workout in
                    NavigationLink(value: Nine23Route.workout(workout.id, dayKey)) {
                        HStack(spacing: Nine23Style.gap) { Image(systemName: "figure.run").foregroundStyle(Nine23Style.activity); VStack(alignment: .leading) { Text(workout.name).font(Nine23Style.heading); Text(Nine23Presentation.time(workout.start, zone: day.input.timeZone)).font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) }; Spacer(); Text("\(Int(workout.minutes.rounded())) 分钟").font(Nine23Style.heading); Image(systemName: "chevron.right").font(Nine23Style.caption) }
                    }.buttonStyle(.plain)
                }
                if day.input.sleep.isEmpty && day.input.workouts.isEmpty { emptyRecords }
            } else { emptyRecords }
        }
    }
    private var emptyRecords: some View { Text("同步后，睡眠与运动会按时间排列在这里。").font(Nine23Style.body).foregroundStyle(Nine23Style.secondary) }
    private var dashboard: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Nine23Style.small), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: Nine23Style.small) { ForEach(dashboardKeys, id: \.self) { key in metricTile(key) } }
    }
    private func metricTile(_ key: String) -> some View {
        let metric = Nine23Presentation.metric(key, in: selected)
        return NavigationLink(value: Nine23Route.metric(key, dayKey)) {
            Nine23Card {
                HStack { Text(Nine23Presentation.title(key)).font(Nine23Style.label); Spacer(); Image(systemName: "chevron.right").font(Nine23Style.label) }
                Text(Nine23Metrics.value(metric)).font(Nine23Style.value).lineLimit(1).minimumScaleFactor(0.65)
                Text(metric?.unit ?? "暂无数据").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary)
                Nine23TrendChart(days: days, key: key, endDay: dayKey, compact: true).allowsHitTesting(false)
            }
        }.buttonStyle(.plain)
    }
    private var authorization: some View {
        Nine23Card { Text("连接苹果健康").font(Nine23Style.heading); Text("读取 Apple Watch 的睡眠、心率和运动记录。").font(Nine23Style.body); Button("允许读取健康数据") { Task { await health.requestAuthorization(); await refresh() } }.buttonStyle(.bordered) }
    }
    private var syncFooter: some View {
        VStack(spacing: Nine23Style.small) {
            if let updated = selected?.input.updated { Text("更新于 \(Date(timeIntervalSince1970: updated).formatted(date: .abbreviated, time: .shortened))").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) }
            Button(health.syncing ? "正在同步…" : "刷新所选日期") { Task { await refresh() } }.disabled(health.syncing).font(Nine23Style.body)
        }.frame(maxWidth: .infinity)
    }
    private var devicePage: some View {
        List {
            Section("数据链路") { Label("Apple Watch → 苹果健康 → 9点23", systemImage: "applewatch"); Text("只读健康数据。手表与组件接收手机计算的同一份结果。").font(Nine23Style.body) }
            Section("同步") { LabeledContent("状态", value: health.syncing ? "同步中" : health.lastError == nil ? "等待刷新 / 已完成" : "上次同步失败"); if let error = health.lastError { Text(error) }; Button("允许读取健康数据") { Task { await health.requestAuthorization() } }; Button("同步最近 30 天") { date = Date(); Task { await refresh() } }.disabled(health.syncing) }
            Section("恢复基线") { Text("至少 7 个有效历史日开始出分，14 日成熟。重新校准不会删除原始记录。"); Button("重新建立个人基线") { sheet = nil; recalibrate = true } }
        }.navigationTitle("设备与同步")
    }
    private var dashboardEditor: some View {
        List {
            Section("选择首页指标") {
                ForEach(Nine23Presentation.dashboardKeys, id: \.self) { key in
                    Toggle(Nine23Presentation.title(key), isOn: Binding(get: { dashboardKeys.contains(key) }, set: { enabled in var keys = dashboardKeys; if enabled { keys.append(key) } else { keys.removeAll { $0 == key } }; dashboardRaw = keys.joined(separator: ",") }))
                }
            }
            Section("排列顺序") { ForEach(dashboardKeys, id: \.self) { Text(Nine23Presentation.title($0)) }.onMove { indices, offset in var keys = dashboardKeys; keys.move(fromOffsets: indices, toOffset: offset); dashboardRaw = keys.joined(separator: ",") } }
        }.environment(\.editMode, .constant(.active)).navigationTitle("自定义指标面板")
    }
    private func linkCard(_ title: String, subtitle: String, icon: String) -> some View {
        Nine23Card { HStack(spacing: Nine23Style.gap) { Image(systemName: icon).font(Nine23Style.title); VStack(alignment: .leading, spacing: Nine23Style.small) { Text(title).font(Nine23Style.heading); Text(subtitle).font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary).multilineTextAlignment(.leading) }; Spacer(minLength: 0); Image(systemName: "chevron.right").font(Nine23Style.caption) } }
    }
    private var vitalCount: Int { ["sdnn", "rhr", "resp", "spo2", "temperature"].filter { selected?[$0]?.value != nil }.count }
    private var weekDays: [String] { (0..<7).reversed().map { AppleHealthDay.dayKey(Calendar.current.date(byAdding: .day, value: -$0, to: date)!) } }
    private var outlookTitle: String { selected?["recovery"]?.value == nil ? "从今天开始，了解你的身体" : "你的今日状态" }
    private var outlook: String {
        guard let selected else { return "这一天尚未同步。下拉刷新，或选择已有记录的日期，查看睡眠、恢复和活动。" }
        let sleep = selected["sleep"]?.value == nil ? "暂无睡眠记录。" : "实际睡眠 \(Nine23Metrics.value(selected["sleep"]))。"
        let recovery = selected["recovery"]?.value.map { "恢复估算 \(Int($0.rounded())) 分。" } ?? "恢复估算需要当日 SDNN 和至少 7 个有效历史日。"
        return sleep + recovery + "已记录 \(selected.input.workouts.count) 次运动。"
    }
    private func shift(_ offset: Int) { date = min(Date(), Calendar.current.date(byAdding: .day, value: offset, to: date)!) }
    private func load() async { do { days = try await Nine23Metrics.load(repo: repo); error = nil } catch { self.error = "读取缓存失败：\(error.localizedDescription)" } }
    private func refresh() async { _ = await health.syncApple(days: 30, through: date); await load(); await publish() }
    private func publish() async { await WidgetSnapshot.publish(from: model); watch.send(await WatchSessionBridge.buildSnapshot(from: model)) }
}
#endif
