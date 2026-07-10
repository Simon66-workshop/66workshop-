import SwiftUI

enum MacOSKitGlass {
    static let menuRadius: CGFloat = 12
    static let popoverRadius: CGFloat = 20
    static let largeCardRadius: CGFloat = 34
    static let rowHeight: CGFloat = 19
    static let menuHorizontalInset: CGFloat = 12
    static let menuVerticalInset: CGFloat = 5

    static let textPrimary = Color(hex: "#1C1C1E")
    static let textSecondary = Color(hex: "#5E6470")
    static let textTertiary = Color(hex: "#8A9099")
    static let hairline = Color(hex: "#DBE2EA")
    static let coldShadow = Color(red: 32 / 255, green: 42 / 255, blue: 58 / 255)
    static let surfaceBlue = Color(hex: "#D9ECFF")
    static let surfaceSilver = Color(hex: "#F6F8FA")
}

struct MacOSKitGlassBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(hex: "#F8FAFD"),
                Color(hex: "#EAF4FF"),
                Color(hex: "#F7F1EA")
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [
                    Color.white.opacity(0.70),
                    MacOSKitGlass.surfaceBlue.opacity(0.24),
                    Color.clear
                ],
                center: UnitPoint(x: 0.18, y: 0.12),
                startRadius: 8,
                endRadius: 360
            )
            .blendMode(.screen)
        )
        .overlay(
            RadialGradient(
                colors: [
                    Color(hex: "#AEBBD0").opacity(0.18),
                    Color.clear
                ],
                center: UnitPoint(x: 0.86, y: 0.92),
                startRadius: 8,
                endRadius: 420
            )
        )
    }
}

private struct MacOSKitGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let shadow: Bool

    func body(content: Content) -> some View {
        content
            .background(
                MacOSKitGlassSurface(cornerRadius: cornerRadius, shadow: shadow)
            )
    }
}

struct MacOSKitGlassSurface: View {
    let cornerRadius: CGFloat
    var shadow = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            if shadow {
                MacOSKitFloatingShadow()
            }

            shape
                .fill(.ultraThinMaterial)

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.58),
                            MacOSKitGlass.surfaceSilver.opacity(0.34),
                            MacOSKitGlass.surfaceBlue.opacity(0.16),
                            Color.white.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.82),
                            MacOSKitGlass.hairline.opacity(0.68),
                            Color.white.opacity(0.42)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )

            shape
                .inset(by: 1.4)
                .stroke(Color.white.opacity(0.26), lineWidth: 2.4)
                .blur(radius: 0.55)
                .clipShape(shape)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.34),
                    Color.clear,
                    MacOSKitGlass.coldShadow.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(shape)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.30),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.28)
            )
            .clipShape(shape)
            .blendMode(.screen)
        }
    }
}

private struct MacOSKitFloatingShadow: View {
    var body: some View {
        GeometryReader { proxy in
            VStack {
                Spacer(minLength: 0)
                ZStack {
                    Ellipse()
                        .fill(MacOSKitGlass.coldShadow.opacity(0.13))
                        .frame(
                            width: min(max(proxy.size.width * 0.64, 54), 260),
                            height: min(max(proxy.size.height * 0.12, 12), 28)
                        )
                        .blur(radius: 14)
                        .offset(y: 10)

                    Ellipse()
                        .fill(MacOSKitGlass.coldShadow.opacity(0.09))
                        .frame(
                            width: min(max(proxy.size.width * 0.46, 42), 190),
                            height: min(max(proxy.size.height * 0.055, 7), 14)
                        )
                        .blur(radius: 5.5)
                        .offset(y: 4)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MacOSKitGlassChipModifier: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(prominent ? 0.48 : 0.34),
                                        MacOSKitGlass.surfaceBlue.opacity(prominent ? 0.22 : 0.12),
                                        Color.white.opacity(0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(prominent ? 0.62 : 0.42), lineWidth: 0.8)
                    )
                    .shadow(color: MacOSKitGlass.coldShadow.opacity(prominent ? 0.10 : 0.06), radius: 8, x: 0, y: 3)
            )
    }
}

extension View {
    func macOSKitGlassCard(cornerRadius: CGFloat = MacOSKitGlass.popoverRadius, shadow: Bool = true) -> some View {
        modifier(MacOSKitGlassCardModifier(cornerRadius: cornerRadius, shadow: shadow))
    }

    func macOSKitGlassChip(prominent: Bool = false) -> some View {
        modifier(MacOSKitGlassChipModifier(prominent: prominent))
    }
}
