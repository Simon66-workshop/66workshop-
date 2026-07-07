import SwiftUI

enum EdgeRail3D {
    static let pitch: Double = -11.5
    static let perspective: Double = 0.62
    static let contentPitch: Double = -6
    static let contentPerspective: Double = 0.56
    static let contentOffsetX: CGFloat = -1.2
    static let sideWidth: CGFloat = 6
    static let sideCornerRadius: CGFloat = 4
}

enum EdgeRailLiquidGlassParameters {
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

enum EdgeRailLiquidGlassV04 {
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

enum EdgeRailGlassOptics {
    static let thicknessWidth: CGFloat = 4.6
    static let refractionWidth: CGFloat = 8
    static let refractiveBlueGray = Color(red: 80 / 255, green: 100 / 255, blue: 120 / 255)
    static let shadowBlueGray = Color(red: 40 / 255, green: 50 / 255, blue: 70 / 255)
}

enum EdgeRailGlassText {
    static let countLabel = Color(red: 22 / 255, green: 32 / 255, blue: 46 / 255).opacity(0.76)
    static let countValue = Color(red: 10 / 255, green: 20 / 255, blue: 32 / 255).opacity(0.98)
    static let quotaNumber = Color(red: 24 / 255, green: 34 / 255, blue: 48 / 255).opacity(0.74)
}

struct EdgeRailCapArc: Shape {
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

struct EdgeRailMicroNoise: View {
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

struct EdgeRailEnvironmentGrid: View {
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

struct EdgeRailSystemGlass<S: Shape>: ViewModifier {
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
