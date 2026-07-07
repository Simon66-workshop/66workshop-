import SwiftUI
import TaskLightCore

struct LuckyCatEdgeRailView: View {
    @ObservedObject var viewModel: TaskLightViewModel

    private var status: LuckyCatVisualStatus {
        viewModel.luckyCatPresentationStatus()
    }

    var body: some View {
        LuckyCatEdgeRail3DChrome {
            readableContent
        }
        .frame(width: LuckyCatLayout.edgeRailPanelWidth, height: LuckyCatLayout.edgeRailPanelHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.compactStatusTitle()), \(viewModel.edgeRailThreadSummary()), \(viewModel.quotaCompactText())")
        .help("拖动移动，点击恢复小猫")
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var readableContent: some View {
        VStack(spacing: 5) {
            EdgeRailGlassStatusOrb(
                status: status,
                size: EdgeRailLiquidGlassParameters.orbSize
            )
            .frame(width: 54, height: 52)
            .accessibilityHidden(true)

            statusTitle

            railDivider

            countStack

            edgeQuota
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 8)
        .frame(width: LuckyCatLayout.edgeRailWidth, height: LuckyCatLayout.edgeRailHeight)
        .clipShape(Capsule(style: .continuous))
    }

    private var statusTitle: some View {
        Text(viewModel.compactStatusTitle())
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .kerning(-0.45)
            .foregroundStyle(statusTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .frame(width: 66, height: 20)
            .background(statusTitleGlass)
            .overlay(statusTitleRim)
            .background(
                Text(viewModel.compactStatusTitle())
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .kerning(-0.45)
                    .foregroundStyle(statusTextColor.opacity(0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(width: 66)
                    .blur(radius: 0.55)
            )
    }

    private var statusTitleGlass: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.34),
                        statusTextColor.opacity(0.095),
                        Color.white.opacity(0.16),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                    .blendMode(.screen)
            )
    }

    private var statusTitleRim: some View {
        Capsule(style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.42),
                        statusTextColor.opacity(0.22),
                        Color.white.opacity(0.20)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )
    }

    private var countStack: some View {
        VStack(spacing: 4) {
            countRow(label: "运", value: viewModel.runningDisplayCount())
            countRow(label: "验", value: viewModel.pendingDisplayCount())
            countRow(label: "观", value: viewModel.observedDisplayCount())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(width: 60)
        .background(countGlassWell)
        .overlay(countGlassRim)
        .overlay(countGlassAirLayer)
    }

    private var countGlassWell: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(EdgeRailLiquidGlassParameters.infoPanelAlpha),
                        Color(hex: "#EBF7FF").opacity(0.086),
                        Color.white.opacity(0.050)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                    .blendMode(.screen)
            )
            .overlay(
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Capsule(style: .continuous)
                        .fill(EdgeRailGlassOptics.refractiveBlueGray.opacity(0.024))
                        .frame(height: 2.5)
                        .blur(radius: 1.2)
                        .padding(.horizontal, 7)
                        .padding(.bottom, 1)
                }
            )
    }

    private var countGlassRim: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.60),
                        Color.white.opacity(0.18),
                        EdgeRailGlassOptics.refractiveBlueGray.opacity(0.042)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )
    }

    private var countGlassAirLayer: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .inset(by: 1.2)
            .stroke(Color.white.opacity(0.20), lineWidth: 1)
            .blur(radius: 0.8)
    }

    private func countRow(label: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 11.0, weight: .black, design: .rounded))
                .foregroundStyle(EdgeRailGlassText.countLabel)
                .frame(width: 15, alignment: .leading)
            Text("\(value)")
                .font(.system(size: 12.4, weight: .black, design: .rounded))
                .foregroundStyle(EdgeRailGlassText.countValue)
                .monospacedDigit()
                .frame(width: 20, alignment: .trailing)
        }
        .frame(width: 42, alignment: .center)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var edgeQuota: some View {
        VStack(spacing: 3) {
            Text("⚡")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(LuckyCatTokens.Palette.quotaBolt)

            Text(String(viewModel.quotaCompactText().dropFirst()))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(viewModel.quotaIsCritical() ? LuckyCatTokens.Palette.red : EdgeRailGlassText.quotaNumber)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .monospacedDigit()
                .frame(width: 46)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(width: 58)
        .background(quotaGlassGroove)
        .overlay(quotaGrooveRim)
    }

    @ViewBuilder
    private var quotaGlassGroove: some View {
        if #available(macOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.26))
                .glassEffect(.clear.interactive(false), in: Capsule(style: .continuous))
                .overlay(quotaGrooveDepth)
        } else {
            Capsule(style: .continuous)
                .fill(Color.clear)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                Color.white.opacity(0.22),
                                Color(hex: "#FFF7EA").opacity(0.095),
                                Color.white.opacity(0.055)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        )
                )
                .overlay(quotaGrooveDepth)
        }
    }

    private var quotaGrooveDepth: some View {
        Capsule(style: .continuous)
            .inset(by: 1)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.30),
                        Color(hex: "#E7DCCF").opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var quotaGrooveRim: some View {
        Capsule(style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.44),
                        LuckyCatTokens.Palette.quotaDivider.opacity(0.92),
                        Color.white.opacity(0.24)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var railDivider: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.30))
            .frame(width: 34, height: 1)
    }

    private var statusTextColor: Color {
        switch status {
        case .blocked:
            return LuckyCatTokens.Palette.red
        case .running:
            return Color(hex: "#4BB6FF")
        case .pending:
            return Color(hex: "#B87916")
        case .done:
            return Color(hex: "#72DB93")
        case .observed:
            return Color(hex: "#33C0D8")
        case .idle:
            return Color(hex: "#4D5B66")
        }
    }
}

private struct LuckyCatEdgeRail3DChrome<Content: View>: View {
    @ViewBuilder var content: Content

    private var shape: Capsule {
        Capsule(style: .continuous)
    }

    var body: some View {
        ZStack {
            floatingShadowLayer
            contactShadowLayer

            ZStack(alignment: .trailing) {
                environmentBackgroundLayer
                blurredBackgroundTexture
                backgroundLiftPlate
                glassCardBase
                centerLuminosityField
                fullBodyRefractionVeil
                subsurfaceDiffusionLayer
                refractedEdgeField
                normalRefractionLayer
                edgeThicknessBand
                sdfEdgeCutHighlight
                fresnelRimLight
                bottomRefractionEdge
                sideThickness
                contentReadabilityPlate
                straightEdgeHighlightLayer
                straightEdgeDimLayer
                microNoiseLayer
                contentPerspectiveLayer
            }
            .clipShape(shape)
            .overlay(innerRefraction)
            .overlay(topSoftGlow)
            .overlay(capLensSurfaceLayer)
            .overlay(topArcRim)
            .overlay(bottomArcRim)
            .overlay(capContourRim)
            .overlay(diagonalLightBand)
            .overlay(outerEdgeHighlight)
            .overlay(leftCutHighlight)
            .overlay(rightCutHighlight)
            .overlay(silhouetteOutline)
        }
        .frame(width: LuckyCatLayout.edgeRailWidth, height: LuckyCatLayout.edgeRailHeight)
        .frame(width: LuckyCatLayout.edgeRailPanelWidth, height: LuckyCatLayout.edgeRailPanelHeight)
    }

    private var environmentBackgroundLayer: some View {
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

    private var blurredBackgroundTexture: some View {
        EdgeRailEnvironmentGrid()
            .clipShape(shape)
            .blur(radius: 0.35)
            .opacity(0.11)
            .brightness(0.10)
            .saturation(0.92)
            .accessibilityHidden(true)
    }

    private var backgroundLiftPlate: some View {
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

    private var glassCardBase: some View {
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

    private var centerLuminosityField: some View {
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

    private var subsurfaceDiffusionLayer: some View {
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

    private var fullBodyRefractionVeil: some View {
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

    private var refractedEdgeField: some View {
        ZStack {
            edgeRefractionStrip(edge: .top)
            edgeRefractionStrip(edge: .bottom)
            edgeRefractionStrip(edge: .leading)
            edgeRefractionStrip(edge: .trailing)
        }
        .accessibilityHidden(true)
    }

    private var normalRefractionLayer: some View {
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

    private enum RefractionEdge {
        case top
        case bottom
        case leading
        case trailing
    }

    @ViewBuilder
    private func edgeRefractionStrip(edge: RefractionEdge) -> some View {
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

    private var contentPerspectiveLayer: some View {
        content
            .rotation3DEffect(
                .degrees(EdgeRail3D.contentPitch),
                axis: (x: 0, y: 1, z: 0),
                anchor: .trailing,
                perspective: EdgeRail3D.contentPerspective
            )
            .offset(x: EdgeRail3D.contentOffsetX)
    }

    private var floatingShadowLayer: some View {
        Ellipse()
            .fill(EdgeRailGlassOptics.shadowBlueGray.opacity(EdgeRailLiquidGlassParameters.floatShadow))
            .frame(width: 48, height: 16)
            .offset(x: 1, y: LuckyCatLayout.edgeRailHeight / 2 - 7)
            .blur(radius: 12)
            .accessibilityHidden(true)
    }

    private var contactShadowLayer: some View {
        Ellipse()
            .fill(EdgeRailGlassOptics.shadowBlueGray.opacity(EdgeRailLiquidGlassParameters.contactShadow))
            .frame(width: 36, height: 7)
            .offset(x: 1, y: LuckyCatLayout.edgeRailHeight / 2 - 2)
            .blur(radius: 5)
            .accessibilityHidden(true)
    }

    private var edgeThicknessBand: some View {
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

    private var capLensSurfaceLayer: some View {
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

    private var sdfEdgeCutHighlight: some View {
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

    private var fresnelRimLight: some View {
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

    private var bottomRefractionEdge: some View {
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

    private var sideThickness: some View {
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

    private var contentReadabilityPlate: some View {
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

    private var microNoiseLayer: some View {
        EdgeRailMicroNoise()
            .clipShape(shape)
            .opacity(0.16)
            .blendMode(.screen)
            .accessibilityHidden(true)
    }

    private var straightEdgeMask: some View {
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

    private var straightEdgeHighlightLayer: some View {
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

    private var straightEdgeDimLayer: some View {
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

    private var innerRefraction: some View {
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

    private var topSoftGlow: some View {
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

    private var topArcRim: some View {
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

    private var bottomArcRim: some View {
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

    private var capContourRim: some View {
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

    private var diagonalLightBand: some View {
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

    private var outerEdgeHighlight: some View {
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

    private var leftCutHighlight: some View {
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

    private var rightCutHighlight: some View {
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

    private var silhouetteOutline: some View {
        shape
            .stroke(Color(red: 210 / 255, green: 230 / 255, blue: 245 / 255).opacity(0.34), lineWidth: 0.55)
            .accessibilityHidden(true)
    }
}

private enum EdgeRail3D {
    static let pitch: Double = -11.5
    static let perspective: Double = 0.62
    static let contentPitch: Double = -6
    static let contentPerspective: Double = 0.56
    static let contentOffsetX: CGFloat = -1.2
    static let sideWidth: CGFloat = 6
    static let sideCornerRadius: CGFloat = 4
}

private enum EdgeRailLiquidGlassParameters {
    static let glassAlpha: Double = 0.10
    static let blur: CGFloat = 24
    static let saturate: Double = 1.12
    static let brightness: Double = 1.18
    static let edgeThickness: CGFloat = 6.2
    static let rimIntensity: Double = 0.96
    static let refractionStrength: CGFloat = 7.2
    static let bottomShadow: Double = 0.075
    static let floatShadow: Double = 0.11
    static let contactShadow: Double = 0.075
    static let orbSize: CGFloat = 45
    static let orbRimOpacity: Double = 0.78
    static let infoPanelAlpha: Double = 0.22
}

private enum EdgeRailLiquidGlassV04 {
    enum Card {
        static let width: CGFloat = LuckyCatLayout.edgeRailWidth
        static let height: CGFloat = LuckyCatLayout.edgeRailHeight
        static let radius: CGFloat = LuckyCatLayout.edgeRailCornerRadius
    }

    enum Glass {
        static let centerAlpha: Double = 0.45
        static let edgeAlpha: Double = 0.94
        static let blur: CGFloat = 26
        static let brightness: Double = 1.18
        static let saturation: Double = 1.12
        static let tint = Color(red: 0.94, green: 0.985, blue: 1.0)
    }

    enum Refraction {
        static let centerStrength: CGFloat = 0.9
        static let edgeStrength: CGFloat = 7.2
        static let cornerStrength: CGFloat = 8.0
    }

    enum Bevel {
        static let thickness: CGFloat = 8.0
        static let outerHighlight: Double = 0.96
        static let innerHighlight: Double = 0.36
        static let bottomShadow: Double = 0.075
        static let rightShadow: Double = 0.045
    }

    enum Light {
        static let directionX: Double = -0.65
        static let directionY: Double = -0.76
        static let topGlow: Double = 0.16
        static let sweepOpacity: Double = 0.34
    }

    enum Shadow {
        static let floatY: CGFloat = 20
        static let floatBlur: CGFloat = 42
        static let floatOpacity: Double = 0.13
        static let contactY: CGFloat = 4
        static let contactBlur: CGFloat = 10
        static let contactOpacity: Double = 0.10
    }
}

private enum EdgeRailGlassOptics {
    static let thicknessWidth: CGFloat = 4.6
    static let refractionWidth: CGFloat = 8
    static let refractiveBlueGray = Color(red: 80 / 255, green: 100 / 255, blue: 120 / 255)
    static let shadowBlueGray = Color(red: 40 / 255, green: 50 / 255, blue: 70 / 255)
}

private enum EdgeRailGlassText {
    static let countLabel = Color(red: 22 / 255, green: 32 / 255, blue: 46 / 255).opacity(0.76)
    static let countValue = Color(red: 10 / 255, green: 20 / 255, blue: 32 / 255).opacity(0.98)
    static let quotaNumber = Color(red: 24 / 255, green: 34 / 255, blue: 48 / 255).opacity(0.74)
}

private struct EdgeRailCapArc: Shape {
    let top: Bool

    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 3.0
        let radius = (rect.width - inset * 2) / 2
        let left = CGPoint(x: rect.minX + inset, y: top ? rect.minY + inset + radius : rect.maxY - inset - radius)
        let center = CGPoint(x: rect.midX, y: top ? rect.minY + inset : rect.maxY - inset)
        let right = CGPoint(x: rect.maxX - inset, y: top ? rect.minY + inset + radius : rect.maxY - inset - radius)
        var path = Path()
        path.move(to: left)
        path.addQuadCurve(to: center, control: CGPoint(x: left.x, y: center.y))
        path.addQuadCurve(to: right, control: CGPoint(x: right.x, y: center.y))
        return path
    }
}

private struct EdgeRailMicroNoise: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<42 {
                let x = CGFloat((index * 29 + 11) % 71) / 71 * size.width
                let y = CGFloat((index * 47 + 17) % 146) / 146 * size.height
                let opacity = 0.018 + Double(index % 5) * 0.006
                let radius = CGFloat(0.28 + Double(index % 3) * 0.12)
                let rect = CGRect(x: x, y: y, width: radius, height: radius)
                let path = Path(ellipseIn: rect)
                context.fill(path, with: .color(Color.white.opacity(opacity)))
            }
        }
    }
}

private struct EdgeRailEnvironmentGrid: View {
    var body: some View {
        Canvas { context, size in
            let gridColor = Color(red: 120 / 255, green: 140 / 255, blue: 160 / 255).opacity(0.14)
            let spacing: CGFloat = 22

            var vertical = Path()
            var x: CGFloat = 0
            while x <= size.width {
                vertical.move(to: CGPoint(x: x, y: 0))
                vertical.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            context.stroke(vertical, with: .color(gridColor), lineWidth: 0.55)

            var horizontal = Path()
            var y: CGFloat = 0
            while y <= size.height {
                horizontal.move(to: CGPoint(x: 0, y: y))
                horizontal.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(horizontal, with: .color(gridColor.opacity(0.82)), lineWidth: 0.5)
        }
    }
}

private struct EdgeRailSystemGlass<S: Shape>: ViewModifier {
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.clear.interactive(), in: shape)
        } else {
            content
                .background(
                    shape
                        .fill(Color.white.opacity(0.020))
                )
                .brightness(EdgeRailLiquidGlassParameters.brightness - 1)
                .saturation(EdgeRailLiquidGlassParameters.saturate)
        }
    }
}
