#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

struct Nine23CalendarView: View {
    @Binding var date: Date
    let days: [Nine23Metrics.Day]
    @Environment(\.dismiss) private var dismiss
    @State private var month = Date()
    private var start: Date { Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: month))! }
    private var offset: Int { (Calendar.current.component(.weekday, from: start) + 5) % 7 }
    private var count: Int { Calendar.current.range(of: .day, in: .month, for: month)!.count }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Nine23Style.section) {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("上个月")
                    Spacer(); Text(month.formatted(.dateTime.year().month(.wide))).font(Nine23Style.title); Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)).accessibilityLabel("下个月")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: Nine23Style.small) {
                    ForEach(Array(["一", "二", "三", "四", "五", "六", "日"].enumerated()), id: \.offset) { _, label in Text(label).font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary) }
                    ForEach(0..<(offset + count), id: \.self) { i in
                        if i < offset { Color.clear.frame(height: 44) }
                        else {
                            let item = Calendar.current.date(byAdding: .day, value: i - offset, to: start)!
                            let key = AppleHealthDay.dayKey(item)
                            let score = days.first { $0.id == key }?["recovery"]?.value
                            Button { date = item; dismiss() } label: {
                                Text("\(i - offset + 1)").font(Nine23Style.heading).frame(maxWidth: .infinity, minHeight: 44)
                                    .background(score.map { Nine23Style.accent("recovery", value: $0).opacity(0.25) } ?? Nine23Style.surface, in: Circle())
                                    .overlay { Circle().stroke(Calendar.current.isDate(item, inSameDayAs: date) ? Nine23Style.text : .clear, lineWidth: 2) }
                            }.buttonStyle(.plain).disabled(item > Calendar.current.startOfDay(for: Date()))
                                .accessibilityLabel("\(key)，恢复\(score.map { String(Int($0.rounded())) } ?? "无数据")")
                        }
                    }
                }
                Nine23Card {
                    Text("恢复估算日历").font(Nine23Style.heading)
                    HStack { legend("0–33", Nine23Style.red); Spacer(); legend("34–66", Nine23Style.yellow); Spacer(); legend("67–100", Nine23Style.recovery) }
                    Text("空白圆圈表示没有恢复分数。点选日期后，在首页下拉可刷新该日记录。").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary)
                }
                Button("回到今天") { date = Date(); dismiss() }.frame(maxWidth: .infinity).buttonStyle(.bordered)
            }.padding(Nine23Style.page)
        }.navigationTitle("日历").nine23Screen().onAppear { month = date }
    }
    private func move(_ n: Int) { month = Calendar.current.date(byAdding: .month, value: n, to: start)! }
    private func legend(_ title: String, _ color: Color) -> some View { HStack { Circle().fill(color).frame(width: 8, height: 8); Text(title).font(Nine23Style.caption) } }
}

struct Nine23JournalView: View {
    @EnvironmentObject private var repo: Repository
    let days: [Nine23Metrics.Day]
    @State private var date: Date
    @State private var answers: [String: Bool] = [:]
    @State private var effects: [BehaviorEffect] = []
    @State private var note = ""
    @State private var error: String?
    @State private var saving = false
    @State private var showInsights = false
    @State private var saved = false
    private let questions: [(key: String, title: String, icon: String)] = [
        ("Alcohol", "饮酒", "wineglass"), ("Caffeine", "摄入咖啡因", "cup.and.saucer"),
        ("Late meal", "睡前进食", "fork.knife"), ("Meditation", "冥想或呼吸练习", "brain.head.profile"),
        ("Screen before bed", "睡前看屏幕", "iphone"), ("Stretching", "拉伸放松", "figure.flexibility")]
    private var dayKey: String { AppleHealthDay.dayKey(date) }
    init(initialDay: String, days: [Nine23Metrics.Day]) { self.days = days; _date = State(initialValue: Nine23Presentation.date(initialDay)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Nine23Style.section) {
                DatePicker("记录日期", selection: $date, in: ...Date(), displayedComponents: .date).font(Nine23Style.heading).disabled(saving)
                Picker("日记内容", selection: $showInsights) { Text("记录").tag(false); Text("行为洞察").tag(true) }.pickerStyle(.segmented)
                if showInsights { insights }
                else {
                    Nine23Section(title: "这一天，你做了什么？", caption: "未回答与“没有”分别保存。每次选择后自动保存。")
                    if let error { Text(error).foregroundStyle(Nine23Style.red).font(Nine23Style.body) }
                    ForEach(questions, id: \.key) { q in
                        Nine23Card {
                            Label(q.title, systemImage: q.icon).font(Nine23Style.heading)
                            HStack(spacing: Nine23Style.gap) {
                                answerButton("没有", key: q.key, answer: false)
                                answerButton("有", key: q.key, answer: true)
                            }
                        }
                    }
                    Nine23Card {
                        Text("今天的感受").font(Nine23Style.heading)
                        TextEditor(text: $note).frame(minHeight: 100).scrollContentBackground(.hidden).font(Nine23Style.body).disabled(saving)
                        Button(saving ? "保存中…" : saved ? "已保存" : "保存感受") { Task { await saveNote() } }.buttonStyle(.bordered).disabled(saving)
                    }
                    Text("记录仅保存在本机。行为洞察使用已记录的“有／没有”与次日恢复，不把未填写日期当成“没有”。").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary)
                }
            }.padding(Nine23Style.page)
        }.navigationTitle("我的日记").nine23Screen().task(id: dayKey) { await load() }
            .onChange(of: note) { _, _ in saved = false }
    }
    private func answerButton(_ title: String, key: String, answer: Bool) -> some View {
        Button { Task { await save(key, answer) } } label: {
            Text(title).font(Nine23Style.heading).frame(maxWidth: .infinity, minHeight: 44)
                .background(answers[key] == answer ? Nine23Style.activity.opacity(0.3) : Nine23Style.raised, in: RoundedRectangle(cornerRadius: Nine23Style.radius))
                .overlay { RoundedRectangle(cornerRadius: Nine23Style.radius).stroke(answers[key] == answer ? Nine23Style.activity : .clear) }
        }.buttonStyle(.plain).disabled(saving).accessibilityLabel("\(questions.first { $0.key == key }?.title ?? key)，\(title)")
    }
    private var insights: some View {
        Group {
            Nine23Section(title: "习惯与次日恢复", caption: "NOOP BehaviorInsights · 个人观察，不代表因果")
            if effects.isEmpty {
                Nine23Card { Text("继续积累你的日记").font(Nine23Style.heading); Text("同一行为需要足够的“有”和“没有”记录，并且下一天有恢复分数，才能比较两组结果。").font(Nine23Style.body).foregroundStyle(Nine23Style.secondary) }
            }
            ForEach(effects, id: \.behavior) { effect in
                Nine23Card {
                    Text(questions.first { $0.key == effect.behavior }?.title ?? effect.behavior).font(Nine23Style.heading)
                    Nine23ValueRow(title: "记录“有”后的恢复均值", value: String(format: "%.1f", effect.meanWith), unit: "分")
                    Nine23ValueRow(title: "记录“没有”后的恢复均值", value: String(format: "%.1f", effect.meanWithout), unit: "分")
                    Text("\(effect.nWith) / \(effect.nWithout) 个有效样本 · \(effect.significant ? "达到原模型统计门槛" : "统计证据不足")").font(Nine23Style.caption).foregroundStyle(Nine23Style.secondary)
                    Text(String(format: "差值 %+.1f 分 · Cohen’s d %.2f", effect.delta, effect.cohensD)).font(Nine23Style.body)
                }
            }
        }
    }
    private func load(preserveDraft: Bool = false) async {
        let requested = dayKey
        let all = await repo.journalEntries()
        let native = await repo.nativeJournalAnswers(day: requested)
        guard requested == dayKey else { return }
        answers = native
        if !preserveDraft { note = all.first { $0.day == requested && $0.question == "nine23.daily-note" }?.notes ?? "" }
        var behaviors: [String: Set<String>] = [:], controls: [String: Set<String>] = [:]
        for entry in all where questions.contains(where: { $0.key == entry.question }) {
            if entry.answeredYes { behaviors[entry.question, default: []].insert(entry.day) }
            else { controls[entry.question, default: []].insert(entry.day) }
        }
        var nextDayRecovery: [String: Double] = [:]
        for day in days { if let score = day["recovery"]?.value { let previous = Calendar.current.date(byAdding: .day, value: -1, to: Nine23Presentation.date(day.id))!; nextDayRecovery[AppleHealthDay.dayKey(previous)] = score } }
        effects = BehaviorInsights.rank(behaviors: behaviors, controls: controls, outcomeByDay: nextDayRecovery, outcome: "Next-day recovery")
    }
    private func save(_ question: String, _ answer: Bool) async {
        saving = true; defer { saving = false }; error = nil
        guard let store = await repo.storeHandle() else { error = "本机数据库未就绪，请稍后重试。"; return }
        do { _ = try await store.upsertJournal([JournalEntry(day: dayKey, question: question, answeredYes: answer, notes: nil)], deviceId: Repository.journalDeviceId); await load(preserveDraft: true) }
        catch { self.error = "保存失败：\(error.localizedDescription)" }
    }
    private func saveNote() async {
        saving = true; defer { saving = false }; error = nil
        guard let store = await repo.storeHandle() else { error = "本机数据库未就绪，请稍后重试。"; return }
        do { _ = try await store.upsertJournal([JournalEntry(day: dayKey, question: "nine23.daily-note", answeredYes: true, notes: note)], deviceId: Repository.journalDeviceId); saved = true }
        catch { self.error = "保存失败：\(error.localizedDescription)" }
    }
}

struct Nine23PlanView: View {
    @AppStorage("nine23.plan.wake-minute") private var wakeMinute = 7 * 60
    private var wake: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: wakeMinute / 60, minute: wakeMinute % 60, second: 0, of: Date())! }, set: { wakeMinute = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) })
    }
    private var bedtime: String { let minute = (wakeMinute - 480 + 1440) % 1440; return String(format: "%02d:%02d", minute / 60, minute % 60) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Nine23Style.section) {
                Nine23Section(title: "今晚的睡眠", caption: "用固定目标安排作息")
                Nine23Card {
                    Label("计划入睡", systemImage: "moon.zzz").font(Nine23Style.heading)
                    Text(bedtime).font(Nine23Style.score)
                    Divider().overlay(Nine23Style.line)
                    DatePicker("计划起床", selection: wake, displayedComponents: .hourAndMinute).font(Nine23Style.heading)
                    Nine23ValueRow(title: "睡眠目标", value: "8:00", unit: "时:分")
                }
                Nine23Card {
                    Text("计划如何计算").font(Nine23Style.heading)
                    Text("按你选择的起床时间向前推 8 小时，与当前睡眠模型的固定目标一致。此处保存作息计划，尚未设置系统闹钟或手表震动提醒。").font(Nine23Style.body).foregroundStyle(Nine23Style.secondary)
                }
            }.padding(Nine23Style.page)
        }.navigationTitle("睡眠计划").nine23Screen()
    }
}

struct Nine23CapabilitiesView: View {
    private let capabilities: [(String, String, String)] = [
        ("压力监测", "waveform.path", "Apple Watch 的间歇心率与 SDNN 尚未接入可验证的连续压力模型。当前可查看真实心率样本与恢复趋势。"),
        ("健康年龄", "heart.circle", "暂无已接入 Apple 数据的健康年龄和衰老速度结果。可先查看心肺适能、步数、体重与长期趋势。"),
        ("心电与血压", "waveform.path.ecg", "当前版本未导入心电图或血压记录，也不会根据心率推算血压。"),
        ("生理周期洞察", "circle.lefthalf.filled", "当前版本尚未请求或导入周期记录。"),
        ("综合运动负荷", "figure.run", "保留 NOOP 算法边界，Apple 模式暂不生成综合负荷分。运动时长、关联心率、能量和 Apple 努力程度可在活动详情查看。")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Nine23Style.section) {
                Nine23Section(title: "功能支持情况", caption: "WHOOP 界面参考与 Apple Watch 数据能力")
                ForEach(capabilities, id: \.0) { item in
                    Nine23Card { Label(item.0, systemImage: item.1).font(Nine23Style.heading); Text("尚未接入").font(Nine23Style.caption).foregroundStyle(Nine23Style.yellow); Text(item.2).font(Nine23Style.body).foregroundStyle(Nine23Style.secondary) }
                }
            }.padding(Nine23Style.page)
        }.navigationTitle("更多健康功能").nine23Screen()
    }
}
#endif
