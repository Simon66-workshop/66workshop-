import SwiftUI

extension LuckyCatEdgeRail3DChrome {
    var contentPerspectiveLayer: some View {
        content
            .rotation3DEffect(
                .degrees(EdgeRail3D.contentPitch),
                axis: (x: 0, y: 1, z: 0),
                anchor: .trailing,
                perspective: EdgeRail3D.contentPerspective
            )
            .offset(x: EdgeRail3D.contentOffsetX)
    }

    var floatingShadowLayer: some View {
        Ellipse()
            .fill(EdgeRailGlassOptics.shadowBlueGray.opacity(EdgeRailLiquidGlassParameters.floatShadow))
            .frame(width: 48, height: 16)
            .offset(x: 1, y: LuckyCatLayout.edgeRailHeight / 2 - 7)
            .blur(radius: 12)
            .accessibilityHidden(true)
    }

    var contactShadowLayer: some View {
        Ellipse()
            .fill(EdgeRailGlassOptics.shadowBlueGray.opacity(EdgeRailLiquidGlassParameters.contactShadow))
            .frame(width: 36, height: 7)
            .offset(x: 1, y: LuckyCatLayout.edgeRailHeight / 2 - 2)
            .blur(radius: 5)
            .accessibilityHidden(true)
    }

    var edgeThicknessBand: some View {
        shape
            .inset(by: 3)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.52),
                        LuckyCatTokens.Palette.glassPrismBlue.opacity(0.18),
                        EdgeRailGlassOptics.refractiveBlueGray.opacity(0.055),
                        Color.white.opacity(0.28)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: EdgeRailLiquidGlassParameters.edgeThickness
            )
            .blur(radius: 1.0)
            .blendMode(.screen)
            .mask(straightEdgeMask)
            .accessibilityHidden(true)
    }

    var capLensSurfaceLayer: some View {
        ZStack {
            VStack(spacing: 0) {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                LuckyCatTokens.Palette.glassPrismBlue.opacity(0.050),
                                Color.white.opacity(0.030),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 58, height: 38)
                    .offset(y: -2)
                    .blur(radius: 0.55)
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.040),
                                LuckyCatTokens.Palette.glassPrismBlue.opacity(0.060),
                                EdgeRailGlassOptics.refractiveBlueGray.opacity(0.055)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 58, height: 38)
                    .offset(y: 2)
                    .blur(radius: 0.65)
            }
        }
        .clipShape(shape)
        .blendMode(.screen)
        .accessibilityHidden(true)
    }

    var sdfEdgeCutHighlight: some View {
        shape
            .inset(by: 1.5)
            .stroke(
                AngularGradient(
                    colors: [
                        Color.white.opacity(0.70),
                        LuckyCatTokens.Palette.glassPrismBlue.opacity(0.26),
                        Color.white.opacity(0.58),
                        EdgeRailGlassOptics.refractiveBlueGray.opacity(0.09),
                        LuckyCatTokens.Palette.glassPrismRose.opacity(0.010),
                        Color.white.opacity(0.66)
                    ],
                    center: .center,
                    angle: .degrees(-42)
                ),
                lineWidth: 1.8
            )
            .blendMode(.screen)
            .accessibilityHidden(true)
    }

    var fresnelRimLight: some View {
        shape
            .inset(by: 0.7)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.74),
                        Color.white.opacity(0.52),
                        LuckyCatTokens.Palette.glassPrismBlue.opacity(0.24),
                        Color.white.opacity(0.28)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )
            .overlay(
                shape
                    .inset(by: 3)
                    .stroke(Color.white.opacity(0.16), lineWidth: EdgeRailLiquidGlassV04.Bevel.thickness * 0.42)
                    .blur(radius: 0.8)
                    .mask(straightEdgeMask)
            )
            .blendMode(.screen)
            .accessibilityHidden(true)
    }

    var bottomRefractionEdge: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.30),
                            EdgeRailGlassOptics.refractiveBlueGray.opacity(0.070),
                            LuckyCatTokens.Palette.glassPrismBlue.opacity(0.10)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 42, height: 12)
                .blur(radius: 2.4)
                .offset(y: -4)
        }
        .accessibilityHidden(true)
    }

    var sideThickness: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: EdgeRail3D.sideCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.58),
                            LuckyCatTokens.Palette.glassPrismBlue.opacity(0.24),
                            LuckyCatTokens.Palette.glassPrismRose.opacity(0.004),
                            EdgeRailGlassOptics.refractiveBlueGray.opacity(0.025)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: EdgeRail3D.sideWidth)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.36))
                        .frame(width: 1),
                    alignment: .trailing
                )
        }
        .padding(.vertical, 5)
        .accessibilityHidden(true)
    }

    var contentReadabilityPlate: some View {
        shape
            .inset(by: 2)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.018),
                        LuckyCatTokens.Palette.glassPrismBlue.opacity(0.008),
                        LuckyCatTokens.Palette.glassRoseTint.opacity(0.002),
                        Color.white.opacity(0.012)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .padding(.trailing, EdgeRail3D.sideWidth)
            .accessibilityHidden(true)
    }

    var microNoiseLayer: some View {
        EdgeRailMicroNoise()
            .clipShape(shape)
            .opacity(0.16)
            .blendMode(.screen)
            .accessibilityHidden(true)
    }

    var straightEdgeMask: some View {
        ZStack {
            VStack(spacing: 0) {
                Rectangle()
                    .frame(width: 28, height: 18)
                Spacer(minLength: 0)
                Rectangle()
                    .frame(width: 28, height: 18)
            }

            HStack(spacing: 0) {
                Rectangle()
                    .frame(width: 14, height: 96)
                Spacer(minLength: 0)
                Rectangle()
                    .frame(width: 14, height: 96)
            }
        }
        .blur(radius: 5)
    }

    var straightEdgeHighlightLayer: some View {
        ZStack {
            VStack(spacing: 0) {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                Color.white.opacity(0.060),
                                Color.clear
                            ],
                            center: .top,
                            startRadius: 1,
                            endRadius: 20
                        )
                    )
                    .frame(width: 28, height: 15)
                    .blur(radius: 0.9)
                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 10, height: 82)
                .blur(radius: 0.4)
                Spacer(minLength: 0)
            }
        }
        .blendMode(.screen)
        .accessibilityHidden(true)
    }

    var straightEdgeDimLayer: some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [
                        Color.clear,
                        EdgeRailGlassOptics.refractiveBlueGray.opacity(0.035)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 28, height: 10)
                .blur(radius: 0.4)
            }

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [
                        Color.clear,
                        EdgeRailGlassOptics.refractiveBlueGray.opacity(0.028)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 8, height: 82)
                .blur(radius: 0.4)
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    var innerRefraction: some View {
        shape
            .inset(by: 3)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.white.opacity(0.08),
                        LuckyCatTokens.Palette.glassPrismBlue.opacity(0.035),
                        LuckyCatTokens.Palette.glassPrismRose.opacity(0.002),
                        Color.white.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .accessibilityHidden(true)
    }

    var topSoftGlow: some View {
        VStack(spacing: 0) {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.060),
                            Color.clear
                        ],
                        center: .top,
                        startRadius: 1,
                        endRadius: 24
                    )
                )
                .frame(width: 36, height: 20)
                .blur(radius: 1.2)
                .offset(y: 2)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    var topArcRim: some View {
        VStack(spacing: 0) {
            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.54),
                            Color.white.opacity(0.20),
                            LuckyCatTokens.Palette.glassPrismBlue.opacity(0.14),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.15
                )
                .frame(width: 60, height: 54)
                .blur(radius: 0.25)
                .offset(y: -9)
                .blendMode(.screen)
            Spacer(minLength: 0)
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    var bottomArcRim: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.22),
                            LuckyCatTokens.Palette.glassPrismBlue.opacity(0.16),
                            EdgeRailGlassOptics.refractiveBlueGray.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.15
                )
                .frame(width: 60, height: 54)
                .blur(radius: 0.35)
                .offset(y: 9)
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    var capContourRim: some View {
        ZStack {
            EdgeRailCapArc(top: true)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.78),
                            Color.white.opacity(0.38),
                            LuckyCatTokens.Palette.glassPrismBlue.opacity(0.22),
                            Color.white.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 1.35, lineCap: .round)
                )
                .blendMode(.screen)

            EdgeRailCapArc(top: false)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.30),
                            LuckyCatTokens.Palette.glassPrismBlue.opacity(0.24),
                            EdgeRailGlassOptics.refractiveBlueGray.opacity(0.12),
                            Color.white.opacity(0.64)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 1.35, lineCap: .round)
                )
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    var diagonalLightBand: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(0.20),
                        LuckyCatTokens.Palette.glassPrismBlue.opacity(0.075),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 14, height: LuckyCatLayout.edgeRailHeight - 8)
            .rotationEffect(.degrees(-30))
            .offset(x: -4, y: 10)
            .blendMode(.screen)
            .accessibilityHidden(true)
    }

    var outerEdgeHighlight: some View {
        shape
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.76),
                        LuckyCatTokens.Palette.glassPrismBlue.opacity(0.34),
                        Color.white.opacity(0.54),
                        EdgeRailGlassOptics.refractiveBlueGray.opacity(0.080),
                        Color.white.opacity(0.30)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.7
            )
            .blendMode(.screen)
            .accessibilityHidden(true)
    }

    var leftCutHighlight: some View {
        HStack(spacing: 0) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            LuckyCatTokens.Palette.glassPrismBlue.opacity(0.070),
                            Color.white.opacity(0.050),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 0.9)
                .blur(radius: 0.45)
                .padding(.vertical, LuckyCatLayout.edgeRailCornerRadius + 9)
                .padding(.leading, 3.0)
            Spacer(minLength: 0)
        }
        .blendMode(.screen)
        .accessibilityHidden(true)
    }

    var rightCutHighlight: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.78),
                            LuckyCatTokens.Palette.glassPrismBlue.opacity(0.12),
                            Color.white.opacity(0.36),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2.0)
                .padding(.vertical, 13)
                .padding(.trailing, 2)
        }
        .blendMode(.screen)
        .accessibilityHidden(true)
    }

    var silhouetteOutline: some View {
        shape
            .stroke(Color(red: 210 / 255, green: 230 / 255, blue: 245 / 255).opacity(0.34), lineWidth: 0.55)
            .accessibilityHidden(true)
    }
}
