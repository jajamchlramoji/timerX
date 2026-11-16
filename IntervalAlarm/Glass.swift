import SwiftUI

// Liquid Glass.
//
// On iOS 26 and later this hands the work to the system: real refraction, real
// specular highlights, real edge lighting, and the morphing behaviour between
// nearby glass shapes. Older systems get a hand-built stand-in — blur, a lit top
// edge, a soft glint and a long shadow — which is the same recipe by hand.
//
// Glass only reads as glass when there is something behind it, which is why the
// canvas carries soft colour (see `AppCanvas`).

struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive: Bool = false
    var fallbackFill: Material = .ultraThinMaterial

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(systemGlass, in: shape)
        } else {
            content.background { legacyGlass }
        }
    }

    @available(iOS 26.0, *)
    private var systemGlass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    private var legacyGlass: some View {
        shape
            .fill(fallbackFill)
            .overlay {
                if let tint { shape.fill(tint.opacity(0.22)) }
            }
            .overlay {
                // The lit edge: bright along the top, darker underneath.
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0.06), .black.opacity(0.10)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .overlay {
                // A specular glint near the top-left.
                shape.fill(
                    RadialGradient(
                        colors: [.white.opacity(0.28), .clear],
                        center: .init(x: 0.22, y: 0.1), startRadius: 0, endRadius: 120
                    )
                )
                .blendMode(.plusLighter)
            }
            .compositingGroup()
            .shadow(color: DS.shadow, radius: 16, y: 8)
    }
}

extension View {
    /// Glass for chrome and controls.
    func glassSurface<S: Shape>(
        _ shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }

    /// Groups nearby glass so the system can let it flow and merge as it moves.
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 14) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}
