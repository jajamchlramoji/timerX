import SwiftUI

/// The signature moment.
///
/// The dial is the whole app: it fills as the gap closes, and when an alarm lands
/// the arc completes, a halo breathes out past the rim, the numerals take a breath,
/// and the ring resets for the next one. Wind-up, release, settle — then calm.
struct AlarmDial<Center: View>: View {
    let progress: Double
    let isRunning: Bool
    /// Changes the instant an alarm rings; that change is what fires the moment.
    let lastRingAt: Date?
    @ViewBuilder var center: Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var haloScale: CGFloat = 0.92
    @State private var haloOpacity: Double = 0
    @State private var breath: CGFloat = 1
    @State private var landed: Double = 0

    private let size: CGFloat = 248
    private let lineWidth: CGFloat = 13

    var body: some View {
        ZStack {
            halo
            face
            track
            ticks
            arc
            center
                .scaleEffect(breath)
        }
        .frame(width: size, height: size)
        .onChange(of: lastRingAt) { _, newValue in
            guard newValue != nil else { return }
            land()
        }
    }

    // MARK: Parts

    private var halo: some View {
        Circle()
            .stroke(DS.accent, lineWidth: 2.5)
            .scaleEffect(haloScale)
            .opacity(haloOpacity)
            .blur(radius: 0.5)
    }

    /// The crystal: a disc of glass, so the dial reads as an object you could pick
    /// up rather than a ring drawn on the canvas.
    private var face: some View {
        Color.clear
            .glassSurface(Circle())
            .padding(lineWidth - 1)
    }

    private var track: some View {
        Circle()
            .stroke(DS.softLine, lineWidth: lineWidth)
    }

    /// A minute face. It says "instrument" without drawing attention.
    private var ticks: some View {
        ForEach(0..<60, id: \.self) { i in
            Capsule(style: .continuous)
                .fill(i % 5 == 0 ? DS.inkFaint.opacity(0.55) : DS.inkFaint.opacity(0.2))
                .frame(width: i % 5 == 0 ? 2 : 1.2, height: i % 5 == 0 ? 8 : 4.5)
                .offset(y: -(size / 2) + 28)
                .rotationEffect(.degrees(Double(i) / 60 * 360))
        }
    }

    private var arc: some View {
        Circle()
            .trim(from: 0, to: max(0.0001, min(1, progress)))
            .stroke(DS.arcGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .opacity(isRunning ? 1 : 0)
            .shadow(color: DS.accentGlow, radius: isRunning ? 12 : 0)
            .overlay {
                // The flash at the instant of landing, on top of the arc itself.
                Circle()
                    .stroke(DS.accent, lineWidth: lineWidth)
                    .rotationEffect(.degrees(-90))
                    .opacity(landed * 0.5)
                    .blur(radius: 2)
            }
            .animation(.linear(duration: 0.25), value: progress)
    }

    // MARK: The moment

    private func land() {
        guard !reduceMotion else {
            // Reduced motion keeps the meaning, loses the movement.
            withAnimation(.easeOut(duration: 0.18)) { landed = 1 }
            withAnimation(.easeIn(duration: 0.3).delay(0.2)) { landed = 0 }
            return
        }

        haloScale = 0.92
        haloOpacity = 0.55
        landed = 1
        withAnimation(.timingCurve(0.16, 0.9, 0.3, 1, duration: 0.62)) {
            haloScale = 1.2
            haloOpacity = 0
        }
        withAnimation(.easeOut(duration: 0.38)) { landed = 0 }

        // The numerals take a breath: out on a spring, back on a softer one.
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { breath = 1.055 }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78).delay(0.2)) { breath = 1 }
    }
}

/// The dial's done state: a drawn check and a restrained burst, in place of a modal.
struct DialDone: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: Double = 0

    var body: some View {
        ZStack {
            CelebrationBurst()
            Circle()
                .fill(DS.accentSoft)
                .frame(width: 78, height: 78)
                .overlay { Circle().strokeBorder(DS.accentEdge, lineWidth: 1) }
            DrawnCheck(progress: drawn)
                .stroke(DS.accentInk, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                .frame(width: 42, height: 42)
        }
        .onAppear {
            if reduceMotion {
                drawn = 1
            } else {
                withAnimation(.easeOut(duration: 0.45).delay(0.1)) { drawn = 1 }
            }
        }
    }
}
