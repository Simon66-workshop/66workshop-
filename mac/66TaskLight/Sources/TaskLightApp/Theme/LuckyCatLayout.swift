import CoreGraphics

enum LuckyCatLayout {
    static let compactCanvasWidth: CGFloat = 360
    static let compactCanvasHeight: CGFloat = 278
    static let compactScale: CGFloat = 0.6525
    static let compactWidth: CGFloat = compactCanvasWidth * compactScale
    static let compactHeight: CGFloat = compactCanvasHeight * compactScale
    static let compactBottomBandWidth: CGFloat = 238
    static let compactBottomBandHeight: CGFloat = 34
    static let compactBottomBandHorizontalPadding: CGFloat = 7
    static let compactBottomBandLeftTextWidth: CGFloat = 76
    static let compactBottomBandRightTextWidth: CGFloat = 76
    static let compactBottomBandCenterGap: CGFloat = 72
    static let compactBottomBandTextSize: CGFloat = 20.5
    static let compactBottomBandTextVerticalOffset: CGFloat = -3
    static let compactBottomGroupOffsetY: CGFloat = 0
    static let compactBottomRingSize: CGFloat = 55
    static let compactBottomRingShadowSize: CGFloat = 65
    static let compactBottomOrbSize: CGFloat = 46
    static let compactBottomOrbFrameSize: CGFloat = 46
    static let compactBottomOrbInset: CGFloat = 4
    static let expandedWidth: CGFloat = 800
    static let expandedHeight: CGFloat = 680
    static let cornerRadius: CGFloat = 34
    static let panelPadding: CGFloat = 22

    static let mascotWidth: CGFloat = 118
    static let mascotHeight: CGFloat = 150
    static let bellSize: CGFloat = 28
    static let orbSize: CGFloat = 54
    static let earSize: CGFloat = 38

    static let chipWidth: CGFloat = 56
    static let chipHeight: CGFloat = 74
    static let chipCornerRadius: CGFloat = 18
    static let chipSpacing: CGFloat = 12

    static let compactHeaderSpacing: CGFloat = 18
    static let summaryChipHeight: CGFloat = 42
    static let taskCardCornerRadius: CGFloat = 16
    static let observedCardCornerRadius: CGFloat = 16
    static let expandedSidebarWidth: CGFloat = 210
    static let expandedHeaderHeight: CGFloat = 34
    static let expandedMainHeight: CGFloat = expandedHeight - (panelPadding * 2) - expandedHeaderHeight - 14
    static let expandedSummaryStripHeight: CGFloat = 104
    static let expandedContentScrollHeight: CGFloat = expandedMainHeight - expandedSummaryStripHeight - 14
    static let expandedSidebarMascotWidth: CGFloat = 172
    static let expandedSidebarMascotHeight: CGFloat = 166
    static let expandedSidebarStatusHeight: CGFloat = 112
    static let expandedSidebarTabHeight: CGFloat = 34
    static let expandedSidebarTabSpacing: CGFloat = 7
}
