import SwiftUI
import UIKit

// Interval.io — token layer.
//
// Personality (see DESIGN.md): a calm instrument in cool slate under smoked glass.
// Accent is a quiet aqua so that red can mean only danger. Components never hold a
// literal colour; they reference these tokens, and every token answers to both
// light and dark.

private func rgb(_ value: UInt32, _ alpha: Double = 1) -> UIColor {
    UIColor(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255,
        alpha: alpha
    )
}

private func dual(_ light: UIColor, _ dark: UIColor) -> Color {
    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
}

enum DS {

    // MARK: Canvas and surfaces — neutrals biased toward the accent's hue

    static let canvasTop   = dual(rgb(0xF7FAFA), rgb(0x101A1D))
    static let canvas      = dual(rgb(0xE6EDED), rgb(0x0A1012))
    static let surface     = dual(rgb(0xFFFFFF), rgb(0x141E21))
    static let surfaceHigh = dual(rgb(0xFFFFFF), rgb(0x1B272B))
    static let line        = dual(rgb(0x0F2021, 0.10), rgb(0xFFFFFF, 0.09))
    static let softLine    = dual(rgb(0x0F2021, 0.06), rgb(0xFFFFFF, 0.05))
    /// The lit top edge that makes a surface read as raised rather than outlined.
    static let topSheen    = dual(rgb(0xFFFFFF, 0.90), rgb(0xFFFFFF, 0.10))
    static let shadow      = dual(rgb(0x0F2021, 0.10), rgb(0x000000, 0.34))

    // MARK: Text — four steps, never pure black or pure white

    static let ink      = dual(rgb(0x0F2021), rgb(0xE9F1F1))
    static let ink2     = dual(rgb(0x415658), rgb(0xA6B5B8))
    static let inkMuted = dual(rgb(0x687B7E), rgb(0x7C8C90))
    static let inkFaint = dual(rgb(0x91A1A3), rgb(0x5A6A6E))

    // MARK: Accent — calm aqua. Fill form stays soft; ink form carries contrast.

    static let accent     = dual(rgb(0x13A89D), rgb(0x5BD0C6))
    static let accentInk  = dual(rgb(0x0A6B63), rgb(0x7FE0D6))
    static let accentSoft = dual(rgb(0x13A89D, 0.10), rgb(0x5BD0C6, 0.12))
    static let accentEdge = dual(rgb(0x13A89D, 0.25), rgb(0x5BD0C6, 0.26))
    static let accentGlow = dual(rgb(0x13A89D, 0.20), rgb(0x5BD0C6, 0.22))
    /// Ink that sits on top of an accent fill.
    static let onAccent   = dual(rgb(0xFFFFFF), rgb(0x04201D))

    /// A second pool of light on the canvas, so the glass has more than one hue to
    /// pick up as it moves.
    static let glow = dual(rgb(0xFFC27A), rgb(0x3F7FA8))

    // MARK: Destructive — reserved for things that end. Never decoration.

    static let warn     = dual(rgb(0xBE3327), rgb(0xF2645A))
    static let warnSoft = dual(rgb(0xBE3327, 0.10), rgb(0xF2645A, 0.14))

    // MARK: Accent fill, with the vertical gradient a primary button wants

    static var accentFill: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.96), accent],
            startPoint: .top, endPoint: .bottom
        )
    }

    static var arcGradient: AngularGradient {
        AngularGradient(
            colors: [accent, accentInk, accent],
            center: .center
        )
    }

    // MARK: Corner language — soft-crisp, continuous

    static let rCard: CGFloat = 20
    static let rControl: CGFloat = 15
    static let rChip: CGFloat = 12

    // MARK: Type — system sans does the work, a serif carries the moments

    enum Typo {
        /// New York. Titles and the countdown only.
        static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }
        static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }
    }
}

/// The app canvas.
///
/// Glass has nothing to refract over a flat colour, so the canvas carries two soft
/// pools of light — one accent, one warm — well out of the way of any text. They
/// are what the glass picks up and bends as things move over them.
struct AppCanvas: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [DS.canvasTop, DS.canvas], startPoint: .top, endPoint: .bottom)

            RadialGradient(
                colors: [DS.accent.opacity(0.17), .clear],
                center: .init(x: 0.12, y: 0.16), startRadius: 0, endRadius: 420
            )
            RadialGradient(
                colors: [DS.glow.opacity(0.15), .clear],
                center: .init(x: 0.94, y: 0.74), startRadius: 0, endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}
