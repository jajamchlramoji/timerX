import Foundation
import UserNotifications
import UIKit

/// Owns the running schedule: handing it to iOS, taking it back, and the live clock.
///
/// Two scheduling strategies, chosen per schedule:
///
/// * **Counting from now** keeps a chain of elapsed-time notifications, topped up
///   whenever one fires or the app comes forward.
/// * **A daily window** uses repeating *calendar* notifications — one per alarm per
///   weekday — so it is anchored to the clock on the wall (daylight saving included)
///   and keeps running forever without the app ever being opened. When a schedule is
///   too dense for iOS to hold that way, it falls back to a rolling queue and says so.
@MainActor
final class AlarmEngine: ObservableObject {
    static let shared = AlarmEngine()

    // MARK: Published state

    @Published private(set) var schedule: Schedule?
    @Published private(set) var queuedCount: Int = 0
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var now: Date = Date()
    /// Set when a counting schedule has rung for the last time.
    @Published var justCompleted: Bool = false
    /// Changes the instant an alarm rings. The dial watches this to play its moment.
    @Published private(set) var lastRingAt: Date?
    /// Undo over confirm: turning off happens at once and offers the way back.
    @Published private(set) var undoableStop: Schedule?
    /// Set when a daily schedule is too dense to run unattended.
    @Published private(set) var coverageDays: Int?

    var isRunning: Bool { schedule != nil }

    // MARK: Internals

    private let center = UNUserNotificationCenter.current()
    private let storageKey = "Interval.schedule.v3"
    private let prefix = "ia-"
    private let categoryID = "INTERVAL_ALARM"
    private let dismissOneActionID = "DISMISS_ONE"
    private let skipNextActionID = "SKIP_NEXT"
    private let stopAllActionID = "STOP_ALL"
    /// iOS only keeps the 64 soonest pending notifications; stay under that.
    private let maxQueued = 60

    private var ticker: Timer?
    private var expectedNext: Date?
    private var isScheduling = false
    private var needsAnotherPass = false

    private init() {
        schedule = loadSchedule()
        expectedNext = schedule?.nextFireDate(after: Date())
        registerCategory()
        startTicker()

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: Permissions

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    // MARK: Start / stop

    func start(_ newSchedule: Schedule) async {
        guard newSchedule.intervalSeconds > 0 else { return }
        if authorization == .notDetermined {
            await requestAuthorization()
        } else {
            await refreshAuthorization()
        }

        center.removeAllPendingNotificationRequests()
        schedule = newSchedule
        expectedNext = newSchedule.nextFireDate(after: Date())
        justCompleted = false
        undoableStop = nil
        lastRingAt = nil
        save(newSchedule)
        await reschedule()
    }

    /// Turning the alarm off cancels every alarm still waiting.
    /// It happens immediately; `undoableStop` holds the way back for a few seconds.
    func stop(offerUndo: Bool = true) {
        undoableStop = offerUndo ? schedule : nil
        schedule = nil
        expectedNext = nil
        coverageDays = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        queuedCount = 0
        center.setBadgeCount(0, withCompletionHandler: nil)
    }

    /// Puts a turned-off schedule back exactly as it was, still on its original clock.
    func undoStop() {
        guard let restored = undoableStop else { return }
        undoableStop = nil
        guard !restored.isFinished(at: Date()) else { return }
        schedule = restored
        expectedNext = restored.nextFireDate(after: Date())
        justCompleted = false
        save(restored)
        Task { await reschedule() }
    }

    func dismissUndo() {
        undoableStop = nil
    }

    /// Turns off the next alarm only. On a daily schedule that means today's — the
    /// same time tomorrow still rings.
    func skipNext() {
        guard var current = schedule,
              let next = current.nextFireDate(after: Date()) else { return }
        current.skip(next)
        schedule = current
        expectedNext = current.nextFireDate(after: Date())
        save(current)
        Task { await reschedule() }
    }

    /// Clears the alarm showing right now and leaves the schedule running.
    func dismissDelivered(notificationID: String?) {
        if let notificationID {
            center.removeDeliveredNotifications(withIdentifiers: [notificationID])
        } else {
            center.removeAllDeliveredNotifications()
        }
        center.setBadgeCount(0, withCompletionHandler: nil)
    }

    /// Re-reads state, retires a finished schedule and puts the queue back in order.
    func refresh() {
        Task {
            await refreshAuthorization()
            guard var current = schedule else {
                await syncQueuedCount()
                return
            }
            if current.isFinished(at: Date()) {
                justCompleted = true
                stop(offerUndo: false)
                return
            }
            let pruned = current.skipped
            current.pruneSkips(before: Date())
            if current.skipped != pruned {
                schedule = current
                save(current)
            }
            await reschedule()
        }
    }

    // MARK: Handing the schedule to iOS

    private func reschedule() async {
        guard !isScheduling else {
            needsAnotherPass = true
            return
        }
        isScheduling = true
        defer {
            isScheduling = false
            if needsAnotherPass {
                needsAnotherPass = false
                Task { await reschedule() }
            }
        }

        guard let current = schedule else { return }
        let desired = requests(for: current)
        let wanted = Set(desired.map(\.identifier))

        // Reconcile rather than wipe and rebuild, so the queue is never briefly empty.
        let queued = Set(
            await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
        )
        let obsolete = queued.subtracting(wanted)
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(obsolete))
        }
        for request in desired where !queued.contains(request.identifier) {
            try? await center.add(request)
        }

        await syncQueuedCount()
    }

    private func requests(for current: Schedule) -> [UNNotificationRequest] {
        switch current.kind {
        case .fromNow:
            coverageDays = nil
            return countingRequests(for: current)
        case let .daily(start, end, days):
            let needed = current.repeatingRequestCount ?? .max
            if needed <= maxQueued && !current.hasFutureSkips {
                coverageDays = nil
                return repeatingDailyRequests(for: current, start: start, end: end, days: days)
            }
            // Too dense for iOS to hold forever — queue what fits and say so.
            let slots = max(1, current.slotsPerDay ?? 1)
            coverageDays = current.hasFutureSkips ? nil : max(1, maxQueued / slots)
            return rollingRequests(for: current)
        }
    }

    private func countingRequests(for current: Schedule) -> [UNNotificationRequest] {
        guard case let .fromNow(startedAt, _) = current.kind else { return [] }
        let now = Date()
        return current.upcomingFireDates(after: now, limit: maxQueued).compactMap { fire in
            let delay = fire.timeIntervalSince(now)
            guard delay > 0.1 else { return nil }
            let index = Int((fire.timeIntervalSince(startedAt) / Double(current.intervalSeconds)).rounded())
            return UNNotificationRequest(
                identifier: "\(prefix)timer-\(index)",
                content: content(for: current, index: index),
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            )
        }
    }

    private func repeatingDailyRequests(
        for current: Schedule, start: TimeOfDay, end: TimeOfDay, days: DaySelection
    ) -> [UNNotificationRequest] {
        var result: [UNNotificationRequest] = []
        let slots = current.dailySlotSeconds
        // An every-day schedule needs no weekday, so it costs one request per alarm.
        let weekdays: [Int?] = days == .everyDay ? [nil] : days.weekdays.map { Optional($0) }

        for weekday in weekdays {
            for slot in slots {
                var components = DateComponents()
                components.hour = slot / 3600
                components.minute = (slot % 3600) / 60
                components.second = slot % 60
                if let weekday { components.weekday = weekday }
                result.append(
                    UNNotificationRequest(
                        identifier: "\(prefix)rep-\(weekday.map(String.init) ?? "all")-\(slot)",
                        content: content(for: current, index: nil),
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    )
                )
            }
        }
        return result
    }

    private func rollingRequests(for current: Schedule) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        return current.upcomingFireDates(after: Date(), limit: maxQueued).map { fire in
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: fire
            )
            return UNNotificationRequest(
                identifier: "\(prefix)once-\(Int(fire.timeIntervalSince1970.rounded()))",
                content: content(for: current, index: nil),
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
        }
    }

    private func content(for current: Schedule, index: Int?) -> UNNotificationContent {
        let body = UNMutableNotificationContent()
        body.title = "Alarm"
        let gap = TimeFormat.compact(seconds: current.intervalSeconds)
        if let window = current.dailyWindow {
            body.body = "Every \(gap) · \(window.start.display) to \(window.end.display)"
        } else if let total = current.totalRepeats, let index {
            body.body = "Every \(gap) — \(index) of \(total)"
        } else {
            body.body = "Every \(gap)"
        }
        body.sound = current.soundEnabled
            ? UNNotificationSound(named: UNNotificationSoundName("AlarmTone.wav"))
            : nil
        body.categoryIdentifier = categoryID
        body.interruptionLevel = .timeSensitive
        return body
    }

    private func syncQueuedCount() async {
        let pending = await center.pendingNotificationRequests()
        queuedCount = pending.filter { $0.identifier.hasPrefix(prefix) }.count
    }

    // MARK: Live clock

    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        now = Date()
        guard let current = schedule else { return }

        if let due = expectedNext, now >= due {
            expectedNext = current.nextFireDate(after: now)
            lastRingAt = now
            Haptics.alarm()
            Task { await reschedule() }
        } else if expectedNext == nil {
            expectedNext = current.nextFireDate(after: now)
        }

        if current.isFinished(at: now) {
            justCompleted = true
            stop(offerUndo: false)
        }
    }

    // MARK: Notification buttons

    private func registerCategory() {
        let dismissOne = UNNotificationAction(
            identifier: dismissOneActionID, title: "Turn Off This One", options: []
        )
        let skipNextAction = UNNotificationAction(
            identifier: skipNextActionID, title: "Skip the Next One", options: []
        )
        let stopAll = UNNotificationAction(
            identifier: stopAllActionID, title: "Turn Off All", options: [.destructive]
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: categoryID,
                actions: [dismissOne, skipNextAction, stopAll],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    func handleAction(identifier: String, notificationID: String?) {
        switch identifier {
        case stopAllActionID:
            stop()
        case skipNextActionID:
            dismissDelivered(notificationID: notificationID)
            skipNext()
        case dismissOneActionID:
            dismissDelivered(notificationID: notificationID)
        default:
            break
        }
    }

    // MARK: Persistence

    private func save(_ current: Schedule) {
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadSchedule() -> Schedule? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Schedule.self, from: data)
        else { return nil }
        return decoded.isFinished(at: Date()) ? nil : decoded
    }
}

enum Haptics {
    static func alarm() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func tap() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func confirm() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
}
