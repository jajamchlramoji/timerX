import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var engine: AlarmEngine

    // The draft schedule, kept between launches.
    @AppStorage("pref.intervalSeconds") private var intervalSeconds: Int = 7200
    @AppStorage("pref.startsNow") private var startsNow: Bool = false
    @AppStorage("pref.startMinutes") private var startMinutes: Int = 8 * 60
    @AppStorage("pref.endMinutes") private var endMinutes: Int = 22 * 60
    @AppStorage("pref.days") private var daysRaw: String = DaySelection.everyDay.rawValue
    /// 0 means "keep going".
    @AppStorage("pref.repeatLimit") private var repeatLimit: Int = 0
    @AppStorage("pref.sound") private var soundOn: Bool = true

    @State private var sheet: SheetKind?
    @State private var undoDeadline: Date?

    private enum SheetKind: String, Identifiable {
        case gap, when
        var id: String { rawValue }
    }

    private var days: DaySelection { DaySelection(rawValue: daysRaw) ?? .everyDay }
    private var windowStart: TimeOfDay { TimeOfDay(minutesFromMidnight: startMinutes) }
    private var windowEnd: TimeOfDay { TimeOfDay(minutesFromMidnight: endMinutes) }
    private var schedule: Schedule? { engine.schedule }
    private var isRunning: Bool { engine.isRunning }
    private var isDone: Bool { engine.justCompleted && !isRunning }

    private var windowFits: Bool {
        startsNow || Schedule.windowFits(
            start: windowStart, end: windowEnd, intervalSeconds: intervalSeconds
        )
    }
    private var canStart: Bool { intervalSeconds > 0 && windowFits }

    var body: some View {
        ZStack {
            AppCanvas()

            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        Spacer(minLength: 10)
                        dial
                        if engine.authorization == .denied { permissionNote }
                        Spacer(minLength: 10)
                        if isDone {
                            doneNote
                        } else if isRunning {
                            runningStatus
                        } else {
                            sentence
                        }
                        Spacer(minLength: 10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }

            if engine.undoableStop != nil {
                VStack {
                    Spacer()
                    Toast(message: "Alarm turned off", actionTitle: "Undo") {
                        Haptics.confirm()
                        engine.undoStop()
                    }
                    .padding(.bottom, 108)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isRunning)
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: engine.undoableStop != nil)
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: startsNow)
        .task { engine.refresh() }
        .sheet(item: $sheet) { which in
            switch which {
            case .gap:
                GapSheet(intervalSeconds: $intervalSeconds)
            case .when:
                WhenSheet(
                    startsNow: $startsNow,
                    startMinutes: $startMinutes,
                    endMinutes: $endMinutes
                )
            }
        }
        .onChange(of: engine.undoableStop != nil) { _, offered in
            undoDeadline = offered ? Date().addingTimeInterval(6) : nil
        }
        .onChange(of: engine.now) { _, now in
            if let deadline = undoDeadline, now >= deadline {
                undoDeadline = nil
                engine.dismissUndo()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Interval.io")
                .font(DS.Typo.display(27))
                .tracking(-0.3)
                .foregroundStyle(DS.ink)
            Spacer()
            Text(isDone ? "Done" : (isRunning ? "Running" : "Ready"))
                .font(DS.Typo.ui(12, .medium))
                .tracking(0.3)
                .foregroundStyle(isRunning ? DS.accentInk : DS.inkMuted)
        }
    }

    // MARK: Dial

    private var secondsToNext: Int {
        guard let schedule, let next = schedule.nextFireDate(after: engine.now) else { return 0 }
        return Int(ceil(next.timeIntervalSince(engine.now)))
    }

    private var dial: some View {
        AlarmDial(
            progress: schedule?.progress(at: engine.now) ?? 0,
            isRunning: isRunning,
            lastRingAt: engine.lastRingAt
        ) {
            if isDone { DialDone() } else { dialReadout }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var dialReadout: some View {
        VStack(spacing: 5) {
            Text(dialLabel)
                .font(DS.Typo.ui(10, .semibold))
                .tracking(1.6)
                .foregroundStyle(DS.inkMuted)
            Text(dialValue)
                .font(DS.Typo.display(isRunning ? 47 : 38))
                .tracking(-1.2)
                .monospacedDigit()
                .foregroundStyle(DS.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText())
            Text(dialCaption)
                .font(DS.Typo.ui(12.5))
                .foregroundStyle(DS.inkMuted)
                .padding(.top, 1)
        }
    }

    /// The next alarm, and whether it is close enough for a countdown to mean
    /// anything. Past the end of the window, the next one is tomorrow — and a
    /// twenty-three hour countdown tells you nothing.
    private var nextFire: Date? { schedule?.nextFireDate(after: engine.now) }

    private var countingDown: Bool {
        guard isRunning, let next = nextFire else { return false }
        return next.timeIntervalSince(engine.now) <= 6 * 3600
    }

    private var dialLabel: String {
        guard isRunning else { return "ALARM EVERY" }
        return countingDown ? "NEXT ALARM IN" : "NEXT ALARM"
    }

    private var dialValue: String {
        guard isRunning else { return TimeFormat.compact(seconds: intervalSeconds) }
        if countingDown { return TimeFormat.clock(seconds: secondsToNext) }
        return nextFire.map(TimeFormat.timeOfDay) ?? "—"
    }

    private var dialCaption: String {
        guard let schedule else {
            return canStart ? "ready when you are" : "that gap doesn't fit"
        }
        guard let next = schedule.nextFireDate(after: engine.now) else { return "nothing left" }
        if countingDown { return "next at \(TimeFormat.timeOfDay(next))" }
        return TimeFormat.dayWord(next)
    }

    // MARK: Running — one line, no card

    private var runningStatus: some View {
        VStack(spacing: 7) {
            Text(statusLine)
                .font(DS.Typo.ui(15))
                .foregroundStyle(DS.ink2)
                .multilineTextAlignment(.center)
            if let days = engine.coverageDays {
                Text("iOS can only hold about \(days) day\(days == 1 ? "" : "s") of this. Open Interval.io now and then, or stretch the gap to keep it running on its own.")
                    .font(DS.Typo.ui(12.5))
                    .foregroundStyle(DS.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statusLine: String {
        guard let schedule else { return "" }
        let gap = TimeFormat.compact(seconds: schedule.intervalSeconds)
        var parts: [String] = []

        if let today = schedule.remainingToday(after: engine.now) {
            parts.append(today == 0 ? "nothing left today" : "\(today) more today")
        } else if let left = schedule.remainingTotal(after: engine.now) {
            parts.append("\(left) still to ring")
        }
        parts.append("every \(gap)")

        if let window = schedule.dailyWindow, window.days != .everyDay {
            parts.append(window.days.label.lowercased())
        }
        let skipped = schedule.skipped.filter { Date(timeIntervalSince1970: TimeInterval($0)) > engine.now }.count
        if skipped > 0 { parts.append("\(skipped) skipped") }
        return parts.joined(separator: " · ")
    }

    // MARK: Done

    private var doneNote: some View {
        VStack(spacing: 6) {
            Text("That's the lot")
                .font(DS.Typo.display(21))
                .foregroundStyle(DS.ink)
            Text("Every alarm in the series has rung. Nothing is waiting.")
                .font(DS.Typo.ui(14))
                .foregroundStyle(DS.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: The sentence

    private var sentence: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 7, lineSpacing: 9) {
                SentenceWord("Ring every")
                Chip(title: TimeFormat.compact(seconds: intervalSeconds), selected: true) {
                    Haptics.tap()
                    sheet = .gap
                }
                if startsNow {
                    SentenceWord("starting")
                    Chip(title: "now") { Haptics.tap(); sheet = .when }
                    repeatChip
                } else {
                    SentenceWord("between")
                    Chip(title: "\(windowStart.display) – \(windowEnd.display)") {
                        Haptics.tap()
                        sheet = .when
                    }
                    daysChip
                }
                soundChip
            }
            .glassGroup(spacing: 12)

            if !windowFits {
                Text("A \(TimeFormat.compact(seconds: intervalSeconds)) gap doesn't fit between \(windowStart.display) and \(windowEnd.display). Try a shorter gap or an earlier start.")
                    .font(DS.Typo.ui(13))
                    .foregroundStyle(DS.warn)
            }
        }
    }

    private var repeatChip: some View {
        Menu {
            Button("Keep going") { repeatLimit = 0 }
            ForEach([3, 5, 8, 10, 20, 50, 100], id: \.self) { n in
                Button("\(n) times") { repeatLimit = n }
            }
        } label: {
            chipLabel(
                text: repeatLimit == 0 ? "keep going" : "\(repeatLimit) times",
                icon: repeatLimit == 0 ? "infinity" : "repeat",
                selected: false
            )
        }
    }

    private var daysChip: some View {
        Menu {
            ForEach(DaySelection.allCases) { option in
                Button(option.label) { daysRaw = option.rawValue }
            }
        } label: {
            chipLabel(text: days.label.lowercased(), icon: "calendar", selected: false)
        }
    }

    private var soundChip: some View {
        Chip(title: "", icon: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", selected: soundOn) {
            Haptics.tap()
            soundOn.toggle()
        }
    }

    private func chipLabel(text: String, icon: String, selected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(DS.Typo.ui(11.5, .semibold))
            Text(text).font(DS.Typo.ui(14, .medium))
        }
        .foregroundStyle(selected ? DS.accentInk : DS.ink2)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .glassSurface(
            RoundedRectangle(cornerRadius: DS.rChip, style: .continuous),
            tint: selected ? DS.accent.opacity(0.55) : nil,
            interactive: true
        )
    }

    // MARK: Permission

    private var permissionNote: some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash")
                    .font(DS.Typo.ui(16, .medium))
                    .foregroundStyle(DS.warn)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications are switched off")
                        .font(DS.Typo.ui(14, .semibold))
                        .foregroundStyle(DS.ink)
                    Text("Nothing can ring until you allow them.")
                        .font(DS.Typo.ui(12.5))
                        .foregroundStyle(DS.ink2)
                }
                Spacer(minLength: 0)
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(DS.Typo.ui(13, .semibold))
                .foregroundStyle(DS.accentInk)
                .buttonStyle(PressStyle())
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if isRunning {
                GhostButton(
                    title: skipLabel,
                    icon: "bell.slash",
                    enabled: schedule?.nextFireDate(after: engine.now) != nil
                ) {
                    Haptics.tap()
                    engine.skipNext()
                }
                SecondaryButton(title: "Turn off", caption: turnOffCaption) {
                    Haptics.confirm()
                    engine.stop()
                }
            } else {
                PrimaryButton(
                    title: isDone ? "Start again" : "Start",
                    caption: startCaption,
                    enabled: canStart
                ) {
                    Haptics.confirm()
                    engine.justCompleted = false
                    Task { await engine.start(draftSchedule()) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .glassGroup(spacing: 18)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) { Rectangle().fill(DS.topSheen).frame(height: 1) }
                .ignoresSafeArea()
        }
    }

    private func draftSchedule() -> Schedule {
        let kind: ScheduleKind = startsNow
            ? .fromNow(startedAt: Date(), totalRepeats: repeatLimit == 0 ? nil : repeatLimit)
            : .daily(start: windowStart, end: windowEnd, days: days)
        return Schedule(intervalSeconds: intervalSeconds, soundEnabled: soundOn, kind: kind)
    }

    private var skipLabel: String {
        guard let schedule, let next = schedule.nextFireDate(after: engine.now) else {
            return "Turn off just the next one"
        }
        return "Turn off just the next one · \(TimeFormat.friendly(next, from: engine.now))"
    }

    private var turnOffCaption: String {
        guard let schedule else { return "ends the schedule" }
        if schedule.isDaily { return "ends the schedule, today and after" }
        if let left = schedule.remainingTotal(after: engine.now) {
            return "ends it — \(left) still to ring"
        }
        return "ends the schedule"
    }

    private var startCaption: String {
        guard canStart else { return "that gap doesn't fit the window" }
        let gap = TimeFormat.compact(seconds: intervalSeconds)
        if startsNow {
            return repeatLimit == 0 ? "every \(gap), until you stop it" : "every \(gap), \(repeatLimit) times"
        }
        return "every \(gap), \(windowStart.display)–\(windowEnd.display), \(days.label.lowercased())"
    }
}

#Preview {
    ContentView().environmentObject(AlarmEngine.shared)
}
