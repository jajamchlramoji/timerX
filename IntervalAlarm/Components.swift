import SwiftUI

// MARK: - Surfaces

/// A pane of glass. Content inside stays solid so it keeps its contrast.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .glassSurface(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
    }
}

/// Small, tracked-out caps with a hairline running to the edge.
struct SectionLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(text.uppercased())
                .font(DS.Typo.ui(10.5, .semibold))
                .tracking(1.6)
                .foregroundStyle(DS.inkMuted)
            Rectangle()
                .fill(DS.softLine)
                .frame(height: 1)
        }
    }
}

// MARK: - Buttons
//
// One primary per view. Secondary is neutral glass. Ghost is for "not now".
// Destructive stays quiet — it never arrives as a wall of red.

struct PrimaryButton: View {
    let title: String
    var caption: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(DS.Typo.ui(17, .semibold))
                if let caption {
                    Text(caption).font(DS.Typo.ui(12)).opacity(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(DS.onAccent)
            .glassSurface(
                RoundedRectangle(cornerRadius: DS.rControl, style: .continuous),
                tint: DS.accent.opacity(0.78),
                interactive: enabled
            )
            .shadow(color: DS.accentGlow, radius: 18, y: 7)
            .opacity(enabled ? 1 : 0.38)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
    }
}

struct SecondaryButton: View {
    let title: String
    var caption: String? = nil
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(spacing: 7) {
                    if let icon {
                        Image(systemName: icon).font(DS.Typo.ui(13, .semibold))
                    }
                    Text(title).font(DS.Typo.ui(16, .semibold))
                }
                if let caption {
                    Text(caption).font(DS.Typo.ui(12)).foregroundStyle(DS.inkMuted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(DS.ink)
            .glassSurface(
                RoundedRectangle(cornerRadius: DS.rControl, style: .continuous),
                interactive: true
            )
        }
        .buttonStyle(PressStyle())
    }
}

struct GhostButton: View {
    let title: String
    var icon: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon).font(DS.Typo.ui(12.5, .semibold))
                }
                Text(title).font(DS.Typo.ui(14.5, .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(DS.ink2)
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
    }
}

/// A press should feel like a press. Interactive glass does its own squash on
/// iOS 26, so this only dims there.
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                configuration.label.opacity(configuration.isPressed ? 0.94 : 1)
            } else {
                configuration.label
                    .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.975 : 1))
                    .opacity(configuration.isPressed ? 0.9 : 1)
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Chips

struct Chip: View {
    let title: String
    var icon: String? = nil
    var selected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(DS.Typo.ui(11.5, .semibold))
                }
                if !title.isEmpty {
                    Text(title).font(DS.Typo.ui(14, .medium))
                }
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
        .buttonStyle(PressStyle())
    }
}

// MARK: - Toast

struct Toast: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(message)
                .font(DS.Typo.ui(14, .medium))
                .foregroundStyle(DS.ink)
            Button(action: action) {
                Text(actionTitle)
                    .font(DS.Typo.ui(14, .semibold))
                    .foregroundStyle(DS.accentInk)
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassSurface(Capsule(style: .continuous))
    }
}

// MARK: - Celebration

struct CelebrationBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fly = false

    private let seeds: [(angle: Double, distance: CGFloat, length: CGFloat, wide: Bool)] = (0..<14).map { i in
        let a = Double(i) / 14 * 360 + Double((i * 37) % 11)
        return (a, CGFloat(74 + (i * 13) % 34), CGFloat(9 + (i * 7) % 11), i % 3 == 0)
    }

    var body: some View {
        ZStack {
            ForEach(Array(seeds.enumerated()), id: \.offset) { index, seed in
                Capsule(style: .continuous)
                    .fill(index % 3 == 0 ? DS.accentInk : DS.accent)
                    .frame(width: seed.wide ? 4 : 2.5, height: seed.length)
                    .offset(y: fly ? -seed.distance : -24)
                    .rotationEffect(.degrees(seed.angle))
                    .opacity(fly ? 0 : 0.95)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.timingCurve(0.16, 0.9, 0.3, 1, duration: 0.9)) { fly = true }
        }
    }
}

/// The check that confirms, drawn rather than stamped.
struct DrawnCheck: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.18, y: h * 0.52))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.76))
        path.addLine(to: CGPoint(x: w * 0.83, y: h * 0.26))
        return path.trimmedPath(from: 0, to: progress)
    }
}

// MARK: - Sentence layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 7
    var lineSpacing: CGFloat = 9

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// A plain word in the sentence. Padded to a chip's height so the line sits straight.
struct SentenceWord: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(DS.Typo.ui(15))
            .foregroundStyle(DS.inkMuted)
            .padding(.vertical, 9)
    }
}
