import SwiftUI

struct LuckyCatStatusOrb: View {
    enum Style {
        case standard
        case embedded
    }

    let status: LuckyCatVisualStatus
    var size: CGFloat = LuckyCatLayout.orbSize
    var pulsing: Bool = false
    var showsGlow: Bool = true
    var style: Style = .standard

    var body: some View {
        ZStack {
            if showsGlow {
                Circle()
                    .fill(status.glow)
                    .frame(width: size + 24, height: size + 24)
                    .blur(radius: 14)
                    .scaleEffect(pulsing ? 1.04 : 0.98)
                    .opacity(pulsing ? 0.86 : 0.78)
            }

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            status.tint.opacity(0.46),
                            LuckyCatTokens.Palette.glassPrismBlue.opacity(0.74),
                            Color.white.opacity(0.58),
                            status.tint.opacity(0.20)
                        ],
                        center: .center,
                        angle: .degrees(0)
                    ),
                    lineWidth: style == .embedded ? 2.6 : 3.2
                )
                .frame(width: size + (style == .embedded ? 5 : 8), height: size + (style == .embedded ? 5 : 8))
                .blur(radius: style == .embedded ? 0.25 : 0.6)
                .opacity(style == .embedded ? 0.72 : 0.58)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            style == .embedded ? status.tint : Color.white.opacity(0.92),
                            status.tint,
                            status.tint.opacity(style == .embedded ? 0.92 : 0.42)
                        ],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: size * (style == .embedded ? 0.62 : 0.72)
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(style == .embedded ? 0.58 : 0.42), lineWidth: 1)
                )
                .frame(width: size, height: size)

            if style == .embedded {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.58),
                                Color.white.opacity(0.14),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                    .frame(width: size * 0.96, height: size * 0.96)
                    .blendMode(.screen)

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.72),
                                status.tint.opacity(0.18),
                                status.tint.opacity(0.26)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.4
                    )
                    .frame(width: size * 0.92, height: size * 0.92)
                    .blendMode(.screen)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.76),
                                Color.white.opacity(0.18),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 1,
                            endRadius: size * 0.48
                        )
                    )
                    .frame(width: size * 0.78, height: size * 0.78)
                    .offset(x: -size * 0.12, y: -size * 0.13)
                    .blendMode(.screen)

                Ellipse()
                    .fill(Color.white.opacity(0.50))
                    .frame(width: size * 0.38, height: size * 0.14)
                    .rotationEffect(.degrees(-24))
                    .offset(x: -size * 0.10, y: -size * 0.26)
                    .blur(radius: 0.4)

                Circle()
                    .trim(from: 0.08, to: 0.27)
                    .stroke(
                        Color.white.opacity(pulsing ? 0.34 : 0.16),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                    )
                    .frame(width: size * 0.72, height: size * 0.72)
                    .rotationEffect(.degrees(-24))
                    .offset(x: size * 0.03, y: size * 0.02)
                    .blur(radius: 0.25)
                    .blendMode(.screen)
            }

            Circle()
                .fill(Color.white.opacity(style == .embedded ? 0.58 : 0.44))
                .frame(width: size * (style == .embedded ? 0.16 : 0.22), height: size * (style == .embedded ? 0.16 : 0.22))
                .offset(x: -size * 0.14, y: -size * 0.14)
        }
    }
}
