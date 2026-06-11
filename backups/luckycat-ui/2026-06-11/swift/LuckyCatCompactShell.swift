import SwiftUI

struct LuckyCatCompactShell<Content: View>: View {
    let status: LuckyCatVisualStatus
    let progress: CGFloat
    let highlightsBell: Bool
    let statusTitle: String
    let elapsedLabel: String
    let content: Content

    @State private var bellSwing = false

    init(
        status: LuckyCatVisualStatus,
        progress: CGFloat,
        highlightsBell: Bool = false,
        statusTitle: String,
        elapsedLabel: String,
        @ViewBuilder content: () -> Content
    ) {
        self.status = status
        self.progress = progress
        self.highlightsBell = highlightsBell
        self.statusTitle = statusTitle
        self.elapsedLabel = elapsedLabel
        self.content = content()
    }

    var body: some View {
        ZStack {
            ZStack {
                panelBackdrop
                shellSurface

                content

                leftPawRepair
                outerPaws
                leftPawShellWrap
                pawSeamBlend
                bottomCollar
                sidePawSupport
            }
            .compositingGroup()
            .mask(panelMask)

            floatingSideBell
        }
        .frame(width: LuckyCatLayout.compactCanvasWidth, height: LuckyCatLayout.compactCanvasHeight)
    }

    private var panelBackdrop: some View {
        ZStack {
            LuckyCatShellShape()
                .fill(.regularMaterial)
                .overlay(
                    LuckyCatShellShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.92),
                                    LuckyCatTokens.Palette.cream.opacity(0.88),
                                    LuckyCatTokens.Palette.creamDeep.opacity(0.68)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )

            VStack {
                Spacer()
                HStack {
                    LuckyCatOuterPawShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.96),
                                    LuckyCatTokens.Palette.cream.opacity(0.92),
                                    LuckyCatTokens.Palette.creamDeep.opacity(0.74)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 52, height: 29)
                        .offset(x: 13, y: -1)
                    Spacer()
                    LuckyCatOuterPawShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.96),
                                    LuckyCatTokens.Palette.cream.opacity(0.92),
                                    LuckyCatTokens.Palette.creamDeep.opacity(0.74)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 58, height: 33)
                }
                .padding(.horizontal, 26)
                .offset(y: -9)
            }

            HStack {
                Spacer()
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.96),
                                    LuckyCatTokens.Palette.cream.opacity(0.92),
                                    LuckyCatTokens.Palette.creamDeep.opacity(0.74)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 36)
                        .offset(x: 1, y: 11)
                    Capsule(style: .continuous)
                        .fill(LuckyCatTokens.Palette.cream.opacity(0.9))
                        .frame(width: 10, height: 76)
                        .offset(x: 14, y: 6)
                    Circle()
                        .fill(LuckyCatTokens.Palette.cream.opacity(0.94))
                        .frame(width: 34, height: 34)
                        .offset(x: 13, y: 0)
                    Spacer()
                }
                .padding(.trailing, 4)
            }
        }
        .shadow(color: LuckyCatTokens.Palette.shadow.opacity(0.2), radius: 10, x: 0, y: 6)
    }

    private var panelMask: some View {
        ZStack {
            LuckyCatShellShape()
                .fill(Color.white)

            VStack {
                Spacer()
                HStack {
                    LuckyCatOuterPawShape()
                        .fill(Color.white)
                        .frame(width: 52, height: 29)
                        .offset(x: 13, y: -1)
                    Spacer()
                    LuckyCatOuterPawShape()
                        .fill(Color.white)
                        .frame(width: 58, height: 33)
                }
                .padding(.horizontal, 26)
                .offset(y: -5)
            }

            HStack {
                Spacer()
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 46, height: 36)
                        .offset(x: 1, y: 11)
                    Capsule(style: .continuous)
                        .fill(Color.white)
                        .frame(width: 10, height: 76)
                        .offset(x: 14, y: 6)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 34, height: 34)
                        .offset(x: 13, y: 0)
                    Spacer()
                }
                .padding(.trailing, 4)
            }
        }
    }

    private var shellSurface: some View {
        ZStack {
            LuckyCatShellShape()
                .fill(.regularMaterial)
                .overlay(
                    LuckyCatShellShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.92),
                                    LuckyCatTokens.Palette.cream.opacity(0.90),
                                    LuckyCatTokens.Palette.creamDeep.opacity(0.72)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    LuckyCatShellShape()
                        .stroke(Color.white.opacity(0.76), lineWidth: 1.1)
                )
                .overlay(
                    LuckyCatShellShape()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.58),
                                    LuckyCatTokens.Palette.creamDeep.opacity(0.34),
                                    LuckyCatTokens.Palette.creamDeep.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.8
                        )
                        .blur(radius: 0.4)
                )
                .overlay(innerGlow)
                .overlay(bottomBellyBlend)
                .overlay(
                    LuckyCatShellShape()
                        .stroke(Color.white.opacity(0.24), lineWidth: 7)
                        .padding(5)
                        .blur(radius: 1.6)
                )
                .overlay(shellSheen)
                .shadow(color: LuckyCatTokens.Palette.shadow.opacity(0.4), radius: 14, x: 0, y: 8)
                .clipShape(LuckyCatShellShape())
                .shadow(color: status.glow.opacity(0.17), radius: 11, x: 0, y: 0)

            faceAccents
            outlineRails
            earPair
        }
    }

    private var innerGlow: some View {
        LuckyCatShellShape()
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.72),
                        status.glow.opacity(0.20),
                        LuckyCatTokens.Palette.creamDeep.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 7
            )
            .blur(radius: 7)
            .padding(5)
    }

    private var bottomBellyBlend: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            LuckyCatTokens.Palette.cream.opacity(0.18),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 220
                    )
                )
                .frame(width: 324, height: 146)
                .offset(y: 114)

            Ellipse()
                .stroke(LuckyCatTokens.Palette.creamDeep.opacity(0.16), lineWidth: 10)
                .frame(width: 314, height: 138)
                .blur(radius: 6.2)
                .offset(y: 116)
        }
        .mask(LuckyCatShellShape())
    }

    private var shellSheen: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.0),
                Color.white.opacity(0.16),
                status.glow.opacity(0.06),
                Color.white.opacity(0.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 86, height: 320)
        .blur(radius: 10)
        .rotationEffect(.degrees(18))
        .offset(x: 42, y: -10)
        .blendMode(.screen)
        .mask(LuckyCatShellShape())
        .allowsHitTesting(false)
    }

    private var pawSeamBlend: some View {
        VStack {
            Spacer()
            HStack {
                leftSeamBridge
                    .offset(x: 18, y: 2)
                Spacer()
            }
            .padding(.horizontal, 21)
            .offset(y: -22)
        }
        .allowsHitTesting(false)
    }

    private var leftSeamBridge: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            LuckyCatTokens.Palette.cream.opacity(0.82),
                            LuckyCatTokens.Palette.creamDeep.opacity(0.28)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 102, height: 14)
                .blur(radius: 0.2)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.72),
                            LuckyCatTokens.Palette.cream.opacity(0.24),
                            Color.clear
                        ],
                        center: .top,
                        startRadius: 1,
                        endRadius: 28
                    )
                )
                .frame(width: 118, height: 20)
                .offset(y: -4)
        }
    }

    private var earPair: some View {
        HStack {
            LuckyCatShellEar(side: .left)
            Spacer()
            LuckyCatShellEar(side: .right)
        }
        .padding(.horizontal, 35)
        .offset(y: -86)
    }

    private var faceAccents: some View {
        ZStack {
            HStack(spacing: 14) {
                Capsule().fill(LuckyCatTokens.Palette.creamDeep).frame(width: 8, height: 18)
                Capsule().fill(LuckyCatTokens.Palette.creamDeep).frame(width: 8, height: 18)
                Capsule().fill(LuckyCatTokens.Palette.creamDeep).frame(width: 8, height: 18)
            }
            .offset(y: -80)

            LuckyCatShellFace()
                .scaleEffect(0.84)
                .offset(x: 2, y: -64)

            HStack(spacing: 112) {
                LuckyCatAccentWhisker()
                LuckyCatAccentWhisker(mirrored: true)
            }
            .offset(y: 2)
        }
    }

    private var outlineRails: some View {
        LuckyCatShellInnerRail()
            .stroke(Color.white.opacity(0.38), lineWidth: 2)
            .blur(radius: 0.4)
            .padding(.horizontal, 11)
            .padding(.top, 16)
            .padding(.bottom, 15)
    }

    private var bottomCollar: some View {
        VStack {
            Spacer()
            ZStack {
                mergedBottomBand

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                LuckyCatTokens.Palette.shadow.opacity(0.24),
                                LuckyCatTokens.Palette.shadow.opacity(0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 6,
                            endRadius: 38
                        )
                    )
                    .frame(width: LuckyCatLayout.compactBottomRingShadowSize, height: LuckyCatLayout.compactBottomRingShadowSize)
                    .offset(y: 4)
                    .blur(radius: 4)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.82),
                                LuckyCatTokens.Palette.gold.opacity(0.94),
                                LuckyCatTokens.Palette.goldDeep
                            ],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: 34
                        )
                    )
                    .frame(width: LuckyCatLayout.compactBottomRingSize, height: LuckyCatLayout.compactBottomRingSize)
                    .overlay(Circle().stroke(Color.white.opacity(0.46), lineWidth: 1))
                    .overlay(
                        Circle()
                            .stroke(LuckyCatTokens.Palette.compactRingShadow, lineWidth: 4)
                            .padding(2)
                            .blur(radius: 0.3)
                    )
                    .overlay(
                        Circle()
                            .stroke(LuckyCatTokens.Palette.shadow.opacity(0.18), lineWidth: 8)
                            .padding(-2)
                            .blur(radius: 3)
                            .mask(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.black.opacity(0.95), Color.black.opacity(0.25), Color.clear],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                            )
                    )
                    .overlay(
                        LuckyCatStatusOrb(
                            status: status,
                            size: LuckyCatLayout.compactBottomOrbSize,
                            pulsing: status == .running,
                            showsGlow: false,
                            style: .embedded
                        )
                        .frame(width: LuckyCatLayout.compactBottomOrbFrameSize, height: LuckyCatLayout.compactBottomOrbFrameSize)
                        .clipShape(Circle())
                        .padding(LuckyCatLayout.compactBottomOrbInset)
                    )
            }
            .offset(y: LuckyCatLayout.compactBottomGroupOffsetY)
        }
    }

    private var leftPawRepair: some View {
        VStack {
            Spacer()
            HStack {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.92),
                                    LuckyCatTokens.Palette.compactPawBlend,
                                    LuckyCatTokens.Palette.creamDeep.opacity(0.34)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 98, height: 18)
                        .blur(radius: 0.2)

                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.74),
                                    LuckyCatTokens.Palette.cream.opacity(0.22),
                                    Color.clear
                                ],
                                center: .top,
                                startRadius: 1,
                                endRadius: 28
                            )
                        )
                        .frame(width: 118, height: 22)
                        .offset(y: -4)

                    Ellipse()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.52),
                                    LuckyCatTokens.Palette.cream.opacity(0.20),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 102, height: 10)
                        .offset(y: -5)
                }
                .offset(x: 26, y: -10)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(false)
    }

    private var mergedBottomBand: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.92),
                        LuckyCatTokens.Palette.cream.opacity(0.88),
                        LuckyCatTokens.Palette.creamDeep.opacity(0.60)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: LuckyCatLayout.compactBottomBandWidth, height: LuckyCatLayout.compactBottomBandHeight)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(LuckyCatTokens.Palette.compactBandStroke, lineWidth: 1)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(LuckyCatTokens.Palette.compactBandGlow, lineWidth: 3)
                    .blur(radius: 3)
            )
            .overlay(
                HStack(spacing: 0) {
                    Text(statusTitle)
                        .font(.system(size: LuckyCatLayout.compactBottomBandTextSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
                        .tracking(0)
                        .lineLimit(1)
                        .minimumScaleFactor(0.38)
                        .frame(width: LuckyCatLayout.compactBottomBandLeftTextWidth, alignment: .leading)
                        .shadow(color: Color.white.opacity(0.74), radius: 1.2, x: 0, y: 0.5)

                    Spacer(minLength: LuckyCatLayout.compactBottomBandCenterGap)

                    Text(elapsedLabel)
                        .font(.system(size: LuckyCatLayout.compactBottomBandTextSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(LuckyCatTokens.Palette.textPrimary.opacity(0.9))
                        .tracking(0)
                        .lineLimit(1)
                        .minimumScaleFactor(0.38)
                        .frame(width: LuckyCatLayout.compactBottomBandRightTextWidth, alignment: .trailing)
                        .shadow(color: Color.white.opacity(0.74), radius: 1.2, x: 0, y: 0.5)
                }
                .padding(.horizontal, LuckyCatLayout.compactBottomBandHorizontalPadding)
                .offset(y: LuckyCatLayout.compactBottomBandTextVerticalOffset)
            )
    }

    private var outerPaws: some View {
        VStack {
            Spacer()
            HStack {
                LuckyCatOuterPaw()
                    .offset(x: 20, y: -10)
                    .scaleEffect(0.88, anchor: .top)
                Spacer()
                LuckyCatOuterPaw()
            }
            .padding(.horizontal, 27)
            .offset(y: -7)
        }
    }

    private var leftPawShellWrap: some View {
        VStack {
            Spacer()
            HStack {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.90),
                                    LuckyCatTokens.Palette.compactPawBlend,
                                    LuckyCatTokens.Palette.compactPawWrap
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 96, height: 15)
                        .blur(radius: 0.2)

                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.66),
                                    LuckyCatTokens.Palette.cream.opacity(0.18),
                                    Color.clear
                                ],
                                center: .top,
                                startRadius: 1,
                                endRadius: 22
                            )
                        )
                        .frame(width: 108, height: 18)
                        .offset(y: -1)

                    Ellipse()
                        .fill(
                            LinearGradient(
                                colors: [
                                    LuckyCatTokens.Palette.cream.opacity(0.42),
                                    Color.white.opacity(0.22),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 92, height: 10)
                        .offset(y: -2)
                }
                .offset(x: 25, y: -8)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(false)
    }

    private var sidePawSupport: some View {
        HStack {
            Spacer()
            VStack(spacing: 0) {
                LuckyCatSidePaw()
                    .offset(x: 6, y: 6)
                Spacer()
            }
            .padding(.trailing, 2)
        }
        .allowsHitTesting(false)
    }

    private var floatingSideBell: some View {
        LuckyCatFloatingBellAssembly(
            status: status,
            highlightsBell: highlightsBell,
            bellSwing: bellSwing
        )
        .zIndex(100)
        .allowsHitTesting(false)
        .onAppear {
            bellSwing = true
        }
    }
}

private struct LuckyCatFloatingBellAssembly: View {
    let status: LuckyCatVisualStatus
    let highlightsBell: Bool
    let bellSwing: Bool

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(LuckyCatTokens.Palette.collarRed)
                .frame(width: 8, height: 20)
                .position(x: 328, y: 71)

            ZStack {
                Capsule(style: .continuous)
                    .fill(LuckyCatTokens.Palette.collarRed)
                    .frame(width: 7, height: 76)
                    .position(x: 18, y: 38)

                Circle()
                    .stroke(LuckyCatTokens.Palette.goldDeep.opacity(0.92), lineWidth: 2.4)
                    .frame(width: 12, height: 12)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: 8, height: 8)
                    )
                    .position(x: 18, y: 76)

                bellBody
                    .position(x: 18, y: 95)
            }
            .frame(width: 54, height: 122)
            .rotationEffect(.degrees(bellSwing ? 5 : -5), anchor: .top)
            .offset(x: bellSwing ? 1.5 : -1.5)
            .animation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true), value: bellSwing)
            .position(x: 328, y: 84)
        }
    }

    private var bellBody: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            LuckyCatTokens.Palette.gold.opacity(0.98),
                            LuckyCatTokens.Palette.gold,
                            LuckyCatTokens.Palette.goldDeep
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 24
                    )
                )
                .shadow(color: highlightsBell ? status.glow.opacity(0.22) : Color.clear, radius: 8, x: 0, y: 0)
                .frame(width: 36, height: 36)
                .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1))

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(LuckyCatTokens.Palette.goldDeep.opacity(0.9))
                .frame(width: 4, height: 10)
                .offset(y: 4)
        }
    }
}

private struct LuckyCatShellEar: View {
    enum Side {
        case left
        case right
    }

    let side: Side

    var body: some View {
        LuckyCatTriangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.92),
                        LuckyCatTokens.Palette.creamDeep.opacity(0.88)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                LuckyCatTriangle()
                    .fill(Color(red: 1.0, green: 0.63, blue: 0.60).opacity(0.88))
                    .padding(7)
            )
            .overlay(
                LuckyCatTriangle()
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
            )
            .frame(width: 40, height: 44)
            .rotationEffect(.degrees(side == .left ? -10 : 10))
            .offset(x: side == .left ? -1 : 1, y: 5)
            .shadow(color: LuckyCatTokens.Palette.shadow.opacity(0.18), radius: 9, x: 0, y: 4)
    }
}

private struct LuckyCatShellShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = rect.minX + 21
        let right = rect.maxX - 21
        let top = rect.minY + 48
        let bottom = rect.maxY - 21
        let earTop = rect.minY + 16
        let leftEarOuter = CGPoint(x: rect.minX + 33, y: top + 18)
        let leftEarPeak = CGPoint(x: rect.minX + 55, y: earTop + 10)
        let leftEarInner = CGPoint(x: rect.minX + 105, y: top + 6)
        let rightEarInner = CGPoint(x: rect.maxX - 105, y: top + 6)
        let rightEarPeak = CGPoint(x: rect.maxX - 55, y: earTop + 10)
        let rightEarOuter = CGPoint(x: rect.maxX - 33, y: top + 18)

        path.move(to: CGPoint(x: left + 62, y: bottom - 1))
        path.addCurve(
            to: CGPoint(x: left, y: top + 52),
            control1: CGPoint(x: left - 18, y: bottom + 6),
            control2: CGPoint(x: left - 15, y: top + 76)
        )
        path.addCurve(
            to: leftEarOuter,
            control1: CGPoint(x: left + 11, y: top + 20),
            control2: CGPoint(x: rect.minX + 20, y: top + 21)
        )
        path.addCurve(
            to: leftEarPeak,
            control1: CGPoint(x: rect.minX + 40, y: top + 4),
            control2: CGPoint(x: rect.minX + 49, y: earTop + 12)
        )
        path.addCurve(
            to: leftEarInner,
            control1: CGPoint(x: rect.minX + 75, y: rect.minY + 26),
            control2: CGPoint(x: rect.minX + 89, y: top - 7)
        )
        path.addCurve(
            to: rightEarInner,
            control1: CGPoint(x: rect.midX - 108, y: top - 12),
            control2: CGPoint(x: rect.midX + 108, y: top - 12)
        )
        path.addCurve(
            to: rightEarPeak,
            control1: CGPoint(x: rect.maxX - 89, y: top - 7),
            control2: CGPoint(x: rect.maxX - 75, y: rect.minY + 26)
        )
        path.addCurve(
            to: rightEarOuter,
            control1: CGPoint(x: rect.maxX - 49, y: earTop + 12),
            control2: CGPoint(x: rect.maxX - 40, y: top + 5)
        )
        path.addCurve(
            to: CGPoint(x: right, y: top + 52),
            control1: CGPoint(x: rect.maxX - 20, y: top + 21),
            control2: CGPoint(x: right - 11, y: top + 20)
        )
        path.addCurve(
            to: CGPoint(x: right - 58, y: bottom),
            control1: CGPoint(x: right + 6, y: top + 62),
            control2: CGPoint(x: right + 9, y: bottom - 34)
        )
        path.addCurve(
            to: CGPoint(x: left + 62, y: bottom - 1),
            control1: CGPoint(x: rect.midX + 28, y: bottom + 19),
            control2: CGPoint(x: rect.midX - 54, y: bottom + 20)
        )
        path.closeSubpath()
        return path
    }
}

private struct LuckyCatShellInnerRail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.insetBy(dx: 16, dy: 16)
        let left = inset.minX + 18
        let right = inset.maxX - 18
        let top = inset.minY + 25
        let bottom = inset.maxY - 12
        let earTop = inset.minY + 10
        let leftEarOuter = CGPoint(x: inset.minX + 28, y: top + 11)
        let leftEarPeak = CGPoint(x: inset.minX + 44, y: earTop + 7)
        let leftEarInner = CGPoint(x: inset.minX + 82, y: top + 4)
        let rightEarInner = CGPoint(x: inset.maxX - 82, y: top + 4)
        let rightEarPeak = CGPoint(x: inset.maxX - 44, y: earTop + 7)
        let rightEarOuter = CGPoint(x: inset.maxX - 28, y: top + 11)

        path.move(to: CGPoint(x: left + 48, y: bottom - 1))
        path.addCurve(
            to: CGPoint(x: left, y: top + 40),
            control1: CGPoint(x: left - 10, y: bottom + 2),
            control2: CGPoint(x: left - 6, y: top + 58)
        )
        path.addCurve(
            to: leftEarOuter,
            control1: CGPoint(x: left + 9, y: top + 17),
            control2: CGPoint(x: inset.minX + 18, y: top + 15)
        )
        path.addCurve(
            to: leftEarPeak,
            control1: CGPoint(x: inset.minX + 33, y: top + 1),
            control2: CGPoint(x: inset.minX + 39, y: earTop + 8)
        )
        path.addCurve(
            to: leftEarInner,
            control1: CGPoint(x: inset.minX + 60, y: inset.minY + 17),
            control2: CGPoint(x: inset.minX + 70, y: top - 3)
        )
        path.addCurve(
            to: rightEarInner,
            control1: CGPoint(x: inset.midX - 88, y: top + 2),
            control2: CGPoint(x: inset.midX + 88, y: top + 2)
        )
        path.addCurve(
            to: rightEarPeak,
            control1: CGPoint(x: inset.maxX - 70, y: top - 3),
            control2: CGPoint(x: inset.maxX - 60, y: inset.minY + 17)
        )
        path.addCurve(
            to: rightEarOuter,
            control1: CGPoint(x: inset.maxX - 39, y: earTop + 8),
            control2: CGPoint(x: inset.maxX - 33, y: top + 1)
        )
        path.addCurve(
            to: CGPoint(x: right, y: top + 40),
            control1: CGPoint(x: inset.maxX - 18, y: top + 15),
            control2: CGPoint(x: right - 9, y: top + 17)
        )
        path.addCurve(
            to: CGPoint(x: right - 46, y: bottom),
            control1: CGPoint(x: right + 1, y: top + 54),
            control2: CGPoint(x: right + 4, y: bottom - 26)
        )
        path.addCurve(
            to: CGPoint(x: left + 48, y: bottom - 1),
            control1: CGPoint(x: inset.midX + 22, y: bottom + 11),
            control2: CGPoint(x: inset.midX - 38, y: bottom + 12)
        )
        path.closeSubpath()
        return path
    }
}

private struct LuckyCatAccentWhisker: View {
    var mirrored: Bool = false

    var body: some View {
        VStack(spacing: 7) {
            Capsule().fill(Color(red: 1.0, green: 0.61, blue: 0.58).opacity(0.95)).frame(width: 16, height: 3)
                .rotationEffect(.degrees(mirrored ? -16 : 16))
            Capsule().fill(Color(red: 1.0, green: 0.61, blue: 0.58).opacity(0.95)).frame(width: 17, height: 3)
            Capsule().fill(Color(red: 1.0, green: 0.61, blue: 0.58).opacity(0.95)).frame(width: 16, height: 3)
                .rotationEffect(.degrees(mirrored ? 16 : -16))
        }
    }
}

private struct LuckyCatShellFace: View {
    var body: some View {
        ZStack {
            HStack(spacing: 66) {
                LuckyCatClosedEye()
                LuckyCatClosedEye()
            }

            Circle()
                .fill(Color(red: 1.0, green: 0.67, blue: 0.64))
                .frame(width: 12, height: 9)
                .offset(y: 11)

            HStack(spacing: 48) {
                Capsule()
                    .fill(Color(red: 1.0, green: 0.74, blue: 0.76).opacity(0.55))
                    .frame(width: 14, height: 5)
                    .rotationEffect(.degrees(-18))
                Capsule()
                    .fill(Color(red: 1.0, green: 0.74, blue: 0.76).opacity(0.55))
                    .frame(width: 14, height: 5)
                    .rotationEffect(.degrees(18))
            }
            .offset(y: 22)

            LuckyCatSmile()
                .stroke(Color(red: 0.93, green: 0.48, blue: 0.43), lineWidth: 2.8)
                .frame(width: 46, height: 22)
                .offset(y: 22)
        }
    }
}

private struct LuckyCatClosedEye: View {
    var body: some View {
        ArcCurve(startAngle: .degrees(18), endAngle: .degrees(162))
            .stroke(LuckyCatTokens.Palette.textPrimary.opacity(0.92), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            .frame(width: 34, height: 18)
    }
}

private struct LuckyCatSmile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 1))
        path.addCurve(
            to: CGPoint(x: rect.minX + 4, y: rect.midY + 2),
            control1: CGPoint(x: rect.midX - 6, y: rect.midY + 6),
            control2: CGPoint(x: rect.minX + 14, y: rect.maxY)
        )
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 1))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 4, y: rect.midY + 2),
            control1: CGPoint(x: rect.midX + 6, y: rect.midY + 6),
            control2: CGPoint(x: rect.maxX - 14, y: rect.maxY)
        )
        return path
    }
}

private struct ArcCurve: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY + 4),
            radius: min(rect.width, rect.height) / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

private struct LuckyCatOuterPaw: View {
    @State private var shimmer = false

    var body: some View {
        ZStack {
            LuckyCatOuterPawShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.99),
                            LuckyCatTokens.Palette.cream.opacity(0.96),
                            LuckyCatTokens.Palette.creamDeep.opacity(0.84)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            LuckyCatOuterPawShape()
                .stroke(Color.white.opacity(0.74), lineWidth: 1)

            LuckyCatOuterPawShape()
                .stroke(Color.white.opacity(0.22), lineWidth: 5)
                .padding(1)
                .blur(radius: 1.2)

            HStack(spacing: 9) {
                Capsule().fill(Color(red: 0.98, green: 0.67, blue: 0.62).opacity(0.95)).frame(width: 4, height: 15)
                Capsule().fill(Color(red: 0.98, green: 0.67, blue: 0.62).opacity(0.95)).frame(width: 4, height: 15)
                Capsule().fill(Color(red: 0.98, green: 0.67, blue: 0.62).opacity(0.95)).frame(width: 4, height: 15)
            }
            .offset(y: -1)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.34),
                    Color.white.opacity(0.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .opacity(shimmer ? 0.36 : 0.18)
            .blur(radius: 3)
            .mask(LuckyCatOuterPawShape())
        }
        .frame(width: 58, height: 36)
        .shadow(color: LuckyCatTokens.Palette.shadow.opacity(0.14), radius: 7, x: 0, y: 3)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
    }
}

private struct LuckyCatOuterPawShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = rect.minY + 5
        let bottom = rect.maxY - 1
        let left = rect.minX + 4
        let right = rect.maxX - 4
        let midX = rect.midX

        path.move(to: CGPoint(x: midX - 8, y: bottom))
        path.addCurve(
            to: CGPoint(x: left + 1, y: top + 22),
            control1: CGPoint(x: midX - 18, y: bottom),
            control2: CGPoint(x: left + 1, y: bottom - 3)
        )
        path.addCurve(
            to: CGPoint(x: midX, y: top + 4),
            control1: CGPoint(x: left + 7, y: top + 5),
            control2: CGPoint(x: midX - 9, y: top + 1)
        )
        path.addCurve(
            to: CGPoint(x: right - 1, y: top + 22),
            control1: CGPoint(x: midX + 9, y: top + 1),
            control2: CGPoint(x: right - 7, y: top + 5)
        )
        path.addCurve(
            to: CGPoint(x: midX + 8, y: bottom),
            control1: CGPoint(x: right - 1, y: bottom - 3),
            control2: CGPoint(x: midX + 18, y: bottom)
        )
        path.closeSubpath()
        return path
    }
}

private struct LuckyCatSidePaw: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.98),
                        LuckyCatTokens.Palette.cream.opacity(0.95),
                        LuckyCatTokens.Palette.creamDeep.opacity(0.82)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 44, height: 36)
            .overlay(
                HStack(spacing: 7) {
                    Capsule().fill(Color(red: 0.98, green: 0.67, blue: 0.62).opacity(0.95)).frame(width: 4, height: 15)
                    Capsule().fill(Color(red: 0.98, green: 0.67, blue: 0.62).opacity(0.95)).frame(width: 4, height: 15)
                    Capsule().fill(Color(red: 0.98, green: 0.67, blue: 0.62).opacity(0.95)).frame(width: 4, height: 15)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            )
            .shadow(color: LuckyCatTokens.Palette.shadow.opacity(0.16), radius: 6, x: 0, y: 4)
    }
}

private struct LuckyCatPawGlyph: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle().fill(color).frame(width: 4, height: 4).offset(x: -5, y: -4)
            Circle().fill(color).frame(width: 4, height: 4).offset(x: 0, y: -6)
            Circle().fill(color).frame(width: 4, height: 4).offset(x: 5, y: -4)
            Capsule().fill(color).frame(width: 11, height: 8).offset(y: 3)
        }
    }
}

private struct LuckyCatTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
