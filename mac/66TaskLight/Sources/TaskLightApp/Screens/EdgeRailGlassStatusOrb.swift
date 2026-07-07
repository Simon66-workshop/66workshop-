import SwiftUI

struct EdgeRailGlassStatusOrb: View {
    let status: LuckyCatVisualStatus
    let size: CGFloat

    private var semanticAccent: Color {
        switch status {
        case .pending:
            return Color(hex: "#F4C66A")
        case .blocked:
            return LuckyCatTokens.Palette.red
        case .done:
            return Color(hex: "#6FE08A")
        case .observed:
            return LuckyCatTokens.Palette.cyan
        case .idle:
            return Color(hex: "#DDE7F0")
        case .running:
            return LuckyCatTokens.Palette.blue
        }
    }

    private var semanticWashOpacity: Double {
        switch status {
        case .running:
            return 0.20
        case .idle:
            return 0.16
        default:
            return 0.58
        }
    }

    private var semanticRimOpacity: Double {
        switch status {
        case .running:
            return 0.26
        case .idle:
            return 0.20
        default:
            return 0.44
        }
    }

    private var orbBodyColors: [Color] {
        switch status {
        case .pending:
            return [
                Color.white.opacity(0.98),
                Color(hex: "#FFF5D8").opacity(0.96),
                Color(hex: "#FFE0A0").opacity(0.94),
                Color(hex: "#F4C66A").opacity(0.94),
                Color(hex: "#C98524").opacity(0.96),
                Color(hex: "#704813")
            ]
        case .done:
            return [
                Color.white.opacity(0.98),
                Color(hex: "#DDFBE8").opacity(0.96),
                Color(hex: "#8BE8AA").opacity(0.94),
                Color(hex: "#44C779").opacity(0.95),
                Color(hex: "#17894F").opacity(0.98),
                Color(hex: "#0B5635")
            ]
        case .blocked:
            return [
                Color.white.opacity(0.98),
                Color(hex: "#FFE5E7").opacity(0.96),
                Color(hex: "#FF9EAA").opacity(0.93),
                Color(hex: "#F05B6C").opacity(0.95),
                Color(hex: "#B8273B").opacity(0.98),
                Color(hex: "#731222")
            ]
        case .observed:
            return [
                Color.white.opacity(0.98),
                Color(hex: "#D7FAFF").opacity(0.96),
                Color(hex: "#89EFFF").opacity(0.93),
                Color(hex: "#35C5DD").opacity(0.95),
                Color(hex: "#1189A1").opacity(0.98),
                Color(hex: "#07566C")
            ]
        case .idle:
            return [
                Color.white.opacity(0.98),
                Color(hex: "#EDF5FA").opacity(0.96),
                Color(hex: "#C9D8E2").opacity(0.92),
                Color(hex: "#91A8B8").opacity(0.92),
                Color(hex: "#607786").opacity(0.96),
                Color(hex: "#394A55")
            ]
        case .running:
            return [
                Color.white.opacity(0.98),
                Color(red: 205 / 255, green: 240 / 255, blue: 1).opacity(0.96),
                Color(red: 110 / 255, green: 205 / 255, blue: 1).opacity(0.92),
                Color(red: 52 / 255, green: 160 / 255, blue: 235 / 255).opacity(0.95),
                Color(red: 18 / 255, green: 98 / 255, blue: 190 / 255).opacity(0.98),
                Color(red: 10 / 255, green: 58 / 255, blue: 132 / 255)
            ]
        }
    }

    var body: some View {
        ZStack {
            statusOrbShadow
            statusOrbBody
            statusOrbSemanticLens
            statusOrbInnerGlow
            statusOrbCaustic
            statusOrbHighlight
            statusOrbRim
        }
    }

    private var statusOrbShadow: some View {
        Ellipse()
            .fill(Color(red: 40 / 255, green: 50 / 255, blue: 70 / 255).opacity(0.16))
            .frame(width: size * 0.78, height: size * 0.18)
            .offset(y: size * 0.54)
            .blur(radius: 3.0)
    }

    private var statusOrbBody: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: orbBodyColors,
                    center: UnitPoint(x: 0.30, y: 0.20),
                    startRadius: 1,
                    endRadius: size * 0.88
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                semanticAccent.opacity(semanticWashOpacity),
                                semanticAccent.opacity(semanticWashOpacity * 0.58),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.68, y: 0.62),
                            startRadius: 1,
                            endRadius: size * 0.66
                        )
                    )
                    .blendMode(.screen)
            )
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.clear,
                                Color(red: 6 / 255, green: 30 / 255, blue: 78 / 255).opacity(0.22),
                                Color(red: 3 / 255, green: 20 / 255, blue: 60 / 255).opacity(0.34)
                            ],
                            center: UnitPoint(x: 0.58, y: 0.78),
                            startRadius: size * 0.16,
                            endRadius: size * 0.66
                        )
                    )
                    .blendMode(.multiply)
            )
    }

    private var statusOrbSemanticLens: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        semanticAccent.opacity(status == .running ? 0.08 : 0.42),
                        semanticAccent.opacity(status == .running ? 0.05 : 0.26),
                        Color.white.opacity(status == .running ? 0.03 : 0.08),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.68, y: 0.58),
                    startRadius: 1,
                    endRadius: size * 0.62
                )
            )
            .frame(width: size * 0.88, height: size * 0.88)
            .offset(x: size * 0.04, y: size * 0.04)
    }

    private var statusOrbInnerGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.36),
                        Color.white.opacity(0.12),
                        LuckyCatTokens.Palette.glassPrismBlue.opacity(0.08),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.42, y: 0.38),
                    startRadius: 1,
                    endRadius: size * 0.60
                )
            )
            .frame(width: size * 0.84, height: size * 0.84)
            .offset(x: -size * 0.02, y: -size * 0.03)
            .blendMode(.screen)
    }

    private var statusOrbCaustic: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.42),
                            semanticAccent.opacity(status == .running ? 0.10 : 0.18),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: size * 0.36
                    )
                )
                .frame(width: size * 0.44, height: size * 0.24)
                .rotationEffect(.degrees(22))
                .offset(x: size * 0.13, y: size * 0.12)

            Ellipse()
                .fill(Color.white.opacity(0.13))
                .frame(width: size * 0.70, height: size * 0.16)
                .rotationEffect(.degrees(-18))
                .offset(x: -size * 0.02, y: size * 0.28)
        }
        .blur(radius: 0.35)
        .blendMode(.screen)
    }

    private var statusOrbHighlight: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            Color.white.opacity(0.42),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: size * 0.32
                    )
                )
                .frame(width: size * 0.50, height: size * 0.28)
                .rotationEffect(.degrees(-24))
                .offset(x: -size * 0.16, y: -size * 0.24)

            Ellipse()
                .fill(Color.white.opacity(0.66))
                .frame(width: size * 0.16, height: size * 0.08)
                .rotationEffect(.degrees(-18))
                .offset(x: -size * 0.28, y: -size * 0.08)
                .blur(radius: 0.18)
        }
        .blendMode(.screen)
    }

    private var statusOrbRim: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.84),
                            Color.white.opacity(0.34),
                            semanticAccent.opacity(semanticRimOpacity),
                            Color.white.opacity(0.62)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.4
                )
                .frame(width: size + 1.6, height: size + 1.6)

            Circle()
                .trim(from: 0.03, to: 0.38)
                .stroke(
                    Color.white.opacity(0.62),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                )
                .frame(width: size * 0.88, height: size * 0.88)
                .rotationEffect(.degrees(-20))

            Circle()
                .trim(from: 0.08, to: 0.22)
                .stroke(
                    semanticAccent.opacity(status == .running ? 0.24 : 0.46),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
                .frame(width: size * 0.98, height: size * 0.98)
                .rotationEffect(.degrees(18))
                .blur(radius: 0.25)
        }
        .blendMode(.screen)
    }
}
