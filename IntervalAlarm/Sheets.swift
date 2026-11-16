import SwiftUI

/// A small sheet that holds one decision and gets out of the way.
private struct SheetFrame<Content: View>: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            AppCanvas()
            VStack(spacing: 16) {
                HStack {
                    Text(title)
                        .font(DS.Typo.display(20))
                        .foregroundStyle(DS.ink)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(DS.Typo.ui(16, .semibold))
                        .foregroundStyle(DS.accentInk)
                        .buttonStyle(PressStyle())
                }
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }
}

/// How long the gap is: a row of presets, with the wheels behind "Custom".
struct GapSheet: View {
    @Binding var intervalSeconds: Int
    @State private var customOpen = false
    @State private var hours = 0
    @State private var minutes = 0
    @State private var seconds = 0

    private let presets: [(String, Int)] = [
        ("30s", 30), ("1m", 60), ("5m", 300), ("10m", 600), ("15m", 900),
        ("20m", 1200), ("30m", 1800), ("1h", 3600), ("2h", 7200),
        ("3h", 10800), ("4h", 14400), ("6h", 21600)
    ]

    var body: some View {
        SheetFrame(title: "Ring every") {
            VStack(alignment: .leading, spacing: 14) {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(presets, id: \.0) { preset in
                        Chip(title: preset.0, selected: !customOpen && intervalSeconds == preset.1) {
                            Haptics.tap()
                            customOpen = false
                            intervalSeconds = preset.1
                        }
                    }
                    Chip(title: "Custom", icon: "slider.horizontal.3", selected: customOpen) {
                        Haptics.tap()
                        customOpen.toggle()
                    }
                }

                if customOpen {
                    HStack(spacing: 0) {
                        wheel(value: $hours, upperBound: 24, unit: "hr")
                        wheel(value: $minutes, upperBound: 60, unit: "min")
                        wheel(value: $seconds, upperBound: 60, unit: "sec")
                    }
                    .frame(height: 170)
                }
            }
        }
        .onAppear {
            hours = intervalSeconds / 3600
            minutes = (intervalSeconds % 3600) / 60
            seconds = intervalSeconds % 60
            customOpen = !presets.contains { $0.1 == intervalSeconds }
        }
        .onChange(of: hours) { _, _ in commitCustom() }
        .onChange(of: minutes) { _, _ in commitCustom() }
        .onChange(of: seconds) { _, _ in commitCustom() }
    }

    private func commitCustom() {
        guard customOpen else { return }
        let total = hours * 3600 + minutes * 60 + seconds
        if total > 0 { intervalSeconds = total }
    }

    private func wheel(value: Binding<Int>, upperBound: Int, unit: String) -> some View {
        Picker("", selection: value) {
            ForEach(0..<upperBound, id: \.self) { i in
                Text("\(i) \(unit)").font(DS.Typo.ui(17)).tag(i)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
    }
}

/// When it runs: from right now, or inside a window that repeats every day.
struct WhenSheet: View {
    @Binding var startsNow: Bool
    @Binding var startMinutes: Int
    @Binding var endMinutes: Int

    var body: some View {
        SheetFrame(title: "When") {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Chip(title: "From now", icon: "bolt.fill", selected: startsNow) {
                        Haptics.tap()
                        startsNow = true
                    }
                    Chip(title: "Daily window", icon: "clock", selected: !startsNow) {
                        Haptics.tap()
                        startsNow = false
                    }
                    Spacer(minLength: 0)
                }

                if startsNow {
                    Text("Counts from the moment you press Start, and keeps going until you turn it off.")
                        .font(DS.Typo.ui(13.5))
                        .foregroundStyle(DS.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 10) {
                        timeRow("First alarm", minutes: $startMinutes)
                        Rectangle().fill(DS.softLine).frame(height: 1)
                        timeRow("Stop by", minutes: $endMinutes)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: DS.rCard, style: .continuous)
                            .fill(DS.surface)
                            .overlay {
                                RoundedRectangle(cornerRadius: DS.rCard, style: .continuous)
                                    .strokeBorder(DS.line, lineWidth: 1)
                            }
                    }

                    Text("Alarms never cross midnight — the day ends here and starts again tomorrow.")
                        .font(DS.Typo.ui(12.5))
                        .foregroundStyle(DS.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func timeRow(_ label: String, minutes: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(DS.Typo.ui(15))
                .foregroundStyle(DS.ink2)
            Spacer()
            CompactTimePicker(minutes: minutes)
        }
    }
}

/// A clock field bound to minutes from midnight.
struct CompactTimePicker: View {
    @Binding var minutes: Int
    @State private var date = Date()

    var body: some View {
        DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
            .datePickerStyle(.compact)
            .labelsHidden()
            .onAppear {
                var components = DateComponents()
                components.hour = minutes / 60
                components.minute = minutes % 60
                date = Calendar.current.date(from: components) ?? Date()
            }
            .onChange(of: date) { _, newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
    }
}
