import Foundation

/// A time of day, to the minute. Windows never cross midnight, so a schedule is
/// always "this much of one day".
struct TimeOfDay: Codable, Equatable, Comparable, Hashable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(minutesFromMidnight: Int) {
        let clamped = max(0, min(23 * 60 + 59, minutesFromMidnight))
        hour = clamped / 60
        minute = clamped % 60
    }

    var minutesFromMidnight: Int { hour * 60 + minute }
    var secondsFromMidnight: Int { minutesFromMidnight * 60 }

    static func < (a: TimeOfDay, b: TimeOfDay) -> Bool {
        a.minutesFromMidnight < b.minutesFromMidnight
    }

    func date(on day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    var display: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

enum DaySelection: String, Codable, CaseIterable, Identifiable {
    case everyDay, weekdays, weekends

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyDay: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekends: return "Weekends"
        }
    }

    /// Calendar weekday numbers: 1 = Sunday … 7 = Saturday.
    var weekdays: [Int] {
        switch self {
        case .everyDay: return [1, 2, 3, 4, 5, 6, 7]
        case .weekdays: return [2, 3, 4, 5, 6]
        case .weekends: return [1, 7]
        }
    }

    func includes(_ weekday: Int) -> Bool { weekdays.contains(weekday) }
}

/// Where the alarms come from. Everything else about a schedule is shared.
enum ScheduleKind: Codable, Equatable {
    /// Counts from the moment you pressed Start. Ends after `totalRepeats`, or never.
    case fromNow(startedAt: Date, totalRepeats: Int?)
    /// Repeats inside a daily window, anchored to the clock on the wall.
    case daily(start: TimeOfDay, end: TimeOfDay, days: DaySelection)
}

struct Schedule: Codable, Equatable {
    var intervalSeconds: Int
    var soundEnabled: Bool
    var kind: ScheduleKind
    /// Individual alarms turned off one at a time, as whole seconds since 1970.
    var skipped: Set<Int> = []

    // MARK: Shape

    var isDaily: Bool {
        if case .daily = kind { return true }
        return false
    }

    var dailyWindow: (start: TimeOfDay, end: TimeOfDay, days: DaySelection)? {
        if case let .daily(start, end, days) = kind { return (start, end, days) }
        return nil
    }

    var totalRepeats: Int? {
        if case let .fromNow(_, total) = kind { return total }
        return nil
    }

    // MARK: Fire times

    private static func key(_ date: Date) -> Int { Int(date.timeIntervalSince1970.rounded()) }

    func isSkipped(_ date: Date) -> Bool { skipped.contains(Schedule.key(date)) }

    mutating func skip(_ date: Date) { skipped.insert(Schedule.key(date)) }

    /// Drops skips that are already in the past, so a daily schedule can return to
    /// its cheap repeating form once the skipped alarm has gone by.
    mutating func pruneSkips(before date: Date) {
        let cutoff = Schedule.key(date)
        skipped = skipped.filter { $0 >= cutoff }
    }

    var hasFutureSkips: Bool {
        let now = Schedule.key(Date())
        return skipped.contains { $0 >= now }
    }

    /// The next fire times from `date` onward, soonest first, skipped ones removed.
    func upcomingFireDates(after date: Date, limit: Int, calendar: Calendar = .current) -> [Date] {
        guard intervalSeconds > 0, limit > 0 else { return [] }
        let step = Double(intervalSeconds)

        switch kind {
        case let .fromNow(startedAt, totalRepeats):
            var result: [Date] = []
            let elapsed = date.timeIntervalSince(startedAt)
            var k = max(1, Int(floor(max(0, elapsed) / step)) + 1)
            var examined = 0
            while result.count < limit, examined < 10_000 {
                if let total = totalRepeats, k > total { break }
                let fire = startedAt.addingTimeInterval(Double(k) * step)
                if fire > date, !isSkipped(fire) { result.append(fire) }
                k += 1
                examined += 1
            }
            return result

        case let .daily(start, end, days):
            var result: [Date] = []
            var day = calendar.startOfDay(for: date)
            var scanned = 0
            while result.count < limit, scanned < 120 {
                if days.includes(calendar.component(.weekday, from: day)),
                   let windowStart = start.date(on: day, calendar: calendar),
                   let windowEnd = end.date(on: day, calendar: calendar) {
                    // Jump straight past anything already gone rather than walking to it.
                    var fire = windowStart
                    if date > windowStart {
                        let steps = floor(date.timeIntervalSince(windowStart) / step) + 1
                        fire = windowStart.addingTimeInterval(steps * step)
                    }
                    while fire <= windowEnd, result.count < limit {
                        if fire > date, !isSkipped(fire) { result.append(fire) }
                        fire = fire.addingTimeInterval(step)
                    }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                scanned += 1
            }
            return result
        }
    }

    func nextFireDate(after date: Date, calendar: Calendar = .current) -> Date? {
        upcomingFireDates(after: date, limit: 1, calendar: calendar).first
    }

    /// Alarms left to ring today. Daily schedules only.
    func remainingToday(after date: Date, calendar: Calendar = .current) -> Int? {
        guard case let .daily(start, end, days) = kind, intervalSeconds > 0 else { return nil }
        let day = calendar.startOfDay(for: date)
        guard days.includes(calendar.component(.weekday, from: day)),
              let windowStart = start.date(on: day, calendar: calendar),
              let windowEnd = end.date(on: day, calendar: calendar)
        else { return 0 }

        // Counted rather than walked — this is read on every frame of the countdown.
        let step = Double(intervalSeconds)
        var first = windowStart
        if date > windowStart {
            let steps = floor(date.timeIntervalSince(windowStart) / step) + 1
            first = windowStart.addingTimeInterval(steps * step)
        }
        guard first <= windowEnd else { return 0 }
        let span = windowEnd.timeIntervalSince(first)
        let total = Int(floor(span / step)) + 1
        let skippedAhead = skipped.filter { key in
            let date = Date(timeIntervalSince1970: TimeInterval(key))
            return date >= first && date <= windowEnd
        }.count
        return max(0, total - skippedAhead)
    }

    /// Alarms that have already rung. Counting schedules only.
    func firedCount(at date: Date) -> Int? {
        guard case let .fromNow(startedAt, totalRepeats) = kind, let total = totalRepeats else { return nil }
        let elapsed = date.timeIntervalSince(startedAt)
        guard elapsed > 0 else { return 0 }
        let slots = min(total, Int(floor(elapsed / Double(intervalSeconds))))
        let skippedSoFar = skipped.filter { key in
            let fired = Date(timeIntervalSince1970: TimeInterval(key))
            return fired <= date && fired > startedAt
        }.count
        return max(0, slots - skippedSoFar)
    }

    func remainingTotal(after date: Date) -> Int? {
        guard case let .fromNow(startedAt, totalRepeats) = kind, let total = totalRepeats else { return nil }
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        let slots = min(total, Int(floor(elapsed / Double(intervalSeconds))))
        let futureSkips = skipped.filter { Date(timeIntervalSince1970: TimeInterval($0)) > date }.count
        return max(0, total - slots - futureSkips)
    }

    /// A counting schedule is finished once nothing is left to ring.
    func isFinished(at date: Date) -> Bool {
        guard case let .fromNow(_, totalRepeats) = kind, totalRepeats != nil else { return false }
        return nextFireDate(after: date) == nil
    }

    /// 0 → just rang, 1 → about to ring. The ring fills over the last interval,
    /// so an overnight gap doesn't leave it frozen for hours.
    func progress(at date: Date) -> Double {
        guard let next = nextFireDate(after: date), intervalSeconds > 0 else { return 0 }
        let remaining = next.timeIntervalSince(date)
        return min(1, max(0, 1 - remaining / Double(intervalSeconds)))
    }

    // MARK: Daily density
    //
    // iOS holds 64 pending notifications. A repeating schedule costs one per alarm
    // per weekday it runs on, so these numbers decide whether a daily schedule can
    // run forever untouched or has to be topped up.

    var slotsPerDay: Int? {
        guard case let .daily(start, end, _) = kind, intervalSeconds > 0 else { return nil }
        let span = end.secondsFromMidnight - start.secondsFromMidnight
        guard span >= 0 else { return 0 }
        return span / intervalSeconds + 1
    }

    var repeatingRequestCount: Int? {
        guard case let .daily(_, _, days) = kind, let slots = slotsPerDay else { return nil }
        // An every-day schedule carries no weekday, so one repeating notification
        // per alarm covers all seven days. Picking days costs one per day instead.
        return days == .everyDay ? slots : slots * days.weekdays.count
    }

    /// Every fire time of one day, as seconds from midnight.
    var dailySlotSeconds: [Int] {
        guard case let .daily(start, end, _) = kind, intervalSeconds > 0 else { return [] }
        var result: [Int] = []
        var t = start.secondsFromMidnight
        while t <= end.secondsFromMidnight, result.count < 200 {
            result.append(t)
            t += intervalSeconds
        }
        return result
    }

    /// An interval schedule needs at least two alarms in the window, otherwise it
    /// isn't an interval.
    static func windowFits(start: TimeOfDay, end: TimeOfDay, intervalSeconds: Int) -> Bool {
        start.secondsFromMidnight + intervalSeconds <= end.secondsFromMidnight
    }
}

enum TimeFormat {
    /// "2h 30m", "45s", "1h 5m 10s"
    static func compact(seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        if s > 0 || parts.isEmpty { parts.append("\(s)s") }
        return parts.joined(separator: " ")
    }

    /// "01:23" or "1:02:03" — for the big countdown.
    static func clock(seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }

    static func timeOfDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    /// "2:24 AM", "tomorrow 2:24 AM", "Tue 2:24 AM" — a date stamp on a dial is
    /// never what you want to read.
    static func friendly(_ date: Date, from now: Date = Date()) -> String {
        let calendar = Calendar.current
        let clock = timeOfDay(date)
        if calendar.isDateInToday(date) { return clock }
        if calendar.isDateInTomorrow(date) { return "tomorrow \(clock)" }
        let weekday = DateFormatter()
        weekday.dateFormat = "EEE"
        return "\(weekday.string(from: date)) \(clock)"
    }

    /// How far off "later" is, in words.
    static func dayWord(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInTomorrow(date) { return "tomorrow" }
        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        return weekday.string(from: date).lowercased()
    }
}
