import SwiftUI

enum LuckyCatTokens {
    enum Palette {
        static let cream = Color(hex: "#FFF1DE")
        static let creamDeep = Color(hex: "#F6DDBF")
        static let glass = Color.white.opacity(0.72)
        static let glassCreamTint = cream.opacity(0.34)
        static let glassWarmDepth = creamDeep.opacity(0.22)
        static let glassRoseTint = Color(hex: "#F6A6C8").opacity(0.34)
        static let glassRoseDepth = Color(hex: "#5A1634").opacity(0.34)
        static let glassRoseCore = Color(hex: "#381022").opacity(0.42)
        static let glassEdgeLight = Color.white.opacity(0.74)
        static let glassInnerLight = Color.white.opacity(0.28)
        static let glassRefraction = Color.white.opacity(0.18)
        static let glassPrismBlue = Color(hex: "#8FD8FF").opacity(0.30)
        static let glassPrismMint = Color(hex: "#A9F2D0").opacity(0.24)
        static let glassPrismPeach = Color(hex: "#FFC6A8").opacity(0.28)
        static let glassPrismRose = Color(hex: "#FF8FC2").opacity(0.34)
        static let glassPrismPink = Color(hex: "#FF6EAF").opacity(0.28)
        static let glassPrismBerry = Color(hex: "#A93B73").opacity(0.26)
        static let glassDeepShadow = Color(red: 72 / 255, green: 42 / 255, blue: 22 / 255).opacity(0.24)
        static let liquidHighlight = Color.white.opacity(0.62)
        static let liquidHairline = Color.white.opacity(0.36)
        static let border = Color.white.opacity(0.68)
        static let textPrimary = Color(hex: "#4B372E")
        static let textSecondary = Color(hex: "#8A7568")
        static let quotaBolt = Color(hex: "#F4C66A")
        static let quotaNumberLight = Color(hex: "#FFF6F2")
        static let quotaDivider = Color.white.opacity(0.18)
        static let quotaChipFill = Color(hex: "#7C6570").opacity(0.50)
        static let red = Color(hex: "#FF6B6B")
        static let blue = Color(hex: "#5DB8FF")
        static let green = Color(hex: "#76D86B")
        static let amber = Color(hex: "#FFB35C")
        static let cyan = Color(hex: "#4CD9EA")
        static let gold = Color(hex: "#D8A63B")
        static let goldDeep = Color(hex: "#A97717")
        static let collarRed = Color(hex: "#E9553F")
        static let idleGray = Color(hex: "#B8B1AA")
        static let shadow = Color(red: 80 / 255, green: 48 / 255, blue: 24 / 255).opacity(0.18)
        static let compactBandStroke = Color.white.opacity(0.56)
        static let compactBandGlow = creamDeep.opacity(0.10)
        static let compactPawBlend = cream.opacity(0.84)
        static let compactPawWrap = creamDeep.opacity(0.42)
        static let compactRingShadow = goldDeep.opacity(0.50)
    }

    enum Typography {
        static let title = Font.system(size: 32, weight: .bold, design: .rounded)
        static let subtitle = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let chipNumber = Font.system(size: 22, weight: .bold, design: .rounded)
        static let chipLabel = Font.system(size: 10, weight: .medium, design: .rounded)
        static let taskTitle = Font.system(size: 13, weight: .semibold, design: .rounded)
        static let taskMeta = Font.system(size: 11, weight: .regular, design: .rounded)
        static let statusPill = Font.system(size: 10, weight: .semibold, design: .rounded)
        static let sectionLabel = Font.system(size: 11, weight: .semibold, design: .rounded)
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}
