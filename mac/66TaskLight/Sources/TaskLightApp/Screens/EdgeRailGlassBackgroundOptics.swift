import SwiftUI

extension LuckyCatEdgeRail3DChrome {
    var environmentBackgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#FBFDFF").opacity(0.14),
                    Color(hex: "#EDF4F9").opacity(0.080),
                    Color(hex: "#F8FBFF").opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 120 / 255, green: 210 / 255, blue: 1).opacity(0.095),
                    Color.clear
                ],
                center: UnitPoint(x: 0.34, y: 0.18),
                startRadius: 1,
                endRadius: 36
            )

            RadialGradient(
                colors: [
                    Color(red: 180 / 255, green: 120 / 255, blue: 1).opacity(0.006),
                    Color.clear
                ],
                center: UnitPoint(x: 0.76, y: 0.76),
                startRadius: 1,
                endRadius: 42
            )
        }
        .clipShape(shape)
        .opacity(0.18)
        .accessibilityHidden(true)
    }

    var blurredBackgroundTexture: some View {
        EdgeRailEnvironmentGrid()
            .clipShape(shape)
            .blur(radius: 0.35)
            .opacity(0.11)
            .brightness(0.10)
            .saturation(0.92)
            .accessibilityHidden(true)
    }

    var backgroundLiftPlate: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.016),
                        Color(hex: "#F6FBFF").opacity(0.012),
                        LuckyCatTokens.Palette.glassPrismBlue.opacity(0.004)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .brightness(0.14)
            .saturation(0.88)
            .accessibilityHidden(true)
    }

    var glassCardBase: some View {
        shape
            .fill(Color.clear)
            .modifier(EdgeRailSystemGlass(shape: shape))
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.070),
                            Color.white.opacity(EdgeRailLiquidGlassParameters.glassAlpha),
                            Color.white.opacity(0.045),
                            LuckyCatTokens.Palette.glassPrismBlue.opacity(0.024),
                            Color.white.opacity(0.026)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.050),
                            Color.white.opacity(0.016),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .blendMode(.screen)
            )
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            EdgeRailGlassOptics.refractiveBlueGray.opacity(0.012),
                            LuckyCatTokens.Palette.glassPrismBlue.opacity(0.026)
                        ],
                        startPoint: .center,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .rotation3DEffect(
                .degrees(EdgeRail3D.pitch),
                axis: (x: 0, y: 1, z: 0),
                anchor: .trailing,
                perspective: EdgeRail3D.perspective
            )
            .accessibilityHidden(true)
    }

    var centerLuminosityField: some View {
        shape
            .inset(by: 7)
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.060),
                        LuckyCatTokens.Palette.glassPrismBlue.opacity(0.020),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 2,
                    endRadius: 58
                )
            )
            .blur(radius: EdgeRailLiquidGlassParameters.blur / 6)
            .blendMode(.screen)
            .accessibilityHidden(true)
    }

    var subsurfaceDiffusionLayer: some View {
        ZStack {
            shape
                .inset(by: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.038),
                            LuckyCatTokens.Palette.glassPrismBlue.opacity(0.020),
                            EdgeRailGlassOptics.refractiveBlueGray.opacity(0.016),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blur(radius: 2.4)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.070),
                                LuckyCatTokens.Palette.glassPrismBlue.opacity(0.024),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 24)
                    .blur(radius: 5.5)
                    .padding(.horizontal, 11)
                    .padding(.bottom, 24)
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.040),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 11, height: LuckyCatLayout.edgeRailHeight + 20)
                .rotationEffect(.degrees(-23))
                .offset(x: -5, y: 7)
                .blur(radius: 1.1)
        }
        .clipShape(shape)
        .blendMode(.screen)
        .accessibilityHidden(true)
    }

    var fullBodyRefractionVeil: some View {
        ZStack {
            VStack(spacing: 14) {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.055),
                                LuckyCatTokens.Palette.glassPrismBlue.opacity(0.024),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 38, height: 14)
                    .blur(radius: 3.0)
                    .offset(x: 4)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.068),
                                LuckyCatTokens.Palette.glassPrismBlue.opacity(0.026)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 22)
                    .blur(radius: 3.6)
                    .offset(x: -2)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.086),
                                LuckyCatTokens.Palette.glassPrismBlue.opacity(0.030),
                                EdgeRailGlassOptics.refractiveBlueGray.opacity(0.020)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 46, height: 18)
                    .blur(radius: 3.2)
                    .offset(x: 1)
            }
            .padding(.top, 24)
            .padding(.bottom, 18)
        }
        .clipShape(shape)
        .blendMode(.screen)
        .accessibilityHidden(true)
    }

    var refractedEdgeField: some View {
        ZStack {
            edgeRefractionStrip(edge: .top)
            edgeRefractionStrip(edge: .bottom)
            edgeRefractionStrip(edge: .leading)
            edgeRefractionStrip(edge: .trailing)
        }
        .accessibilityHidden(true)
    }

    var normalRefractionLayer: some View {
        shape
            .inset(by: 4)
            .stroke(
                AngularGradient(
                    colors: [
                        Color.white.opacity(0.34),
                        LuckyCatTokens.Palette.glassPrismBlue.opacity(0.20),
                        Color.clear,
                        EdgeRailGlassOptics.refractiveBlueGray.opacity(0.10),
                        LuckyCatTokens.Palette.glassPrismRose.opacity(0.004),
                        Color.white.opacity(0.30)
                    ],
                    center: .center,
                    angle: .degrees(-38)
                ),
                lineWidth: EdgeRailLiquidGlassV04.Refraction.edgeStrength
            )
            .blur(radius: 1.2)
            .blendMode(.screen)
            .opacity(0.46)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func edgeRefractionStrip(edge: EdgeRailRefractionEdge) -> some View {
        switch edge {
        case .top:
            VStack(spacing: 0) {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.24),
                                Color.white.opacity(0.075),
                                Color.clear
                            ],
                            center: .top,
                            startRadius: 1,
                            endRadius: 28
                        )
                    )
                    .frame(width: 44, height: 26)
                    .blur(radius: 0.8)
                    .offset(y: 2)
                Spacer(minLength: 0)
            }
        case .bottom:
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.070),
                                EdgeRailGlassOptics.refractiveBlueGray.opacity(0.12)
                            ],
                            center: .bottom,
                            startRadius: 3,
                            endRadius: 30
                        )
                    )
                    .frame(width: 44, height: 26)
                    .blur(radius: 1.0)
                    .offset(y: -2)
            }
        case .leading:
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.14),
                        Color.white.opacity(0.045),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: EdgeRailGlassOptics.refractionWidth)
                .offset(x: 1.0)
                .padding(.vertical, LuckyCatLayout.edgeRailCornerRadius + 7)
                Spacer(minLength: 0)
            }
        case .trailing:
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(0.10),
                        EdgeRailGlassOptics.refractiveBlueGray.opacity(0.12)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: EdgeRailGlassOptics.refractionWidth + 2)
                .offset(x: -1.5)
                .padding(.vertical, LuckyCatLayout.edgeRailCornerRadius + 3)
            }
        }
    }
}

private enum EdgeRailRefractionEdge {
    case top
    case bottom
    case leading
    case trailing
}
