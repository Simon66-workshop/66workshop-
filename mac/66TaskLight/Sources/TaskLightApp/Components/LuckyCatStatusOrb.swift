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

    @State private var animated = false

    var body: some View {
        ZStack {
            if showsGlow {
                Circle()
                    .fill(status.glow)
                    .frame(width: size + 24, height: size + 24)
                    .blur(radius: 14)
                    .scaleEffect(pulsing && animated ? 1.12 : 0.98)
                    .opacity(pulsing ? 0.95 : 0.78)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            style == .embedded ? status.tint.opacity(0.98) : Color.white.opacity(0.92),
                            status.tint.opacity(style == .embedded ? 0.88 : 0.95),
                            status.tint.opacity(style == .embedded ? 0.30 : 0.42)
                        ],
                        center: style == .embedded ? .center : .topLeading,
                        startRadius: 1,
                        endRadius: size * (style == .embedded ? 0.62 : 0.72)
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.42), lineWidth: 1)
                )
                .frame(width: size, height: size)

            if style == .embedded {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.72),
                                Color.white.opacity(0.18),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 1,
                            endRadius: size * 0.44
                        )
                    )
                    .frame(width: size * 0.72, height: size * 0.72)
                    .offset(x: -size * 0.11, y: -size * 0.12)
                    .blendMode(.screen)
            }

            Circle()
                .fill(Color.white.opacity(style == .embedded ? 0.38 : 0.44))
                .frame(width: size * (style == .embedded ? 0.18 : 0.22), height: size * (style == .embedded ? 0.18 : 0.22))
                .offset(x: -size * 0.14, y: -size * 0.14)
        }
        .animation(pulsing ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : nil, value: animated)
        .onAppear {
            guard pulsing else { return }
            animated = true
        }
    }
}
