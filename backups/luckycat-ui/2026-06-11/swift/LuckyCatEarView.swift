import SwiftUI

struct LuckyCatEarView: View {
    enum Side {
        case left
        case right
    }

    let side: Side

    var body: some View {
        LuckyCatTriangle()
            .fill(LuckyCatTokens.Palette.creamDeep)
            .overlay(
                LuckyCatTriangle()
                    .fill(Color.pink.opacity(0.38))
                    .padding(7)
            )
            .frame(width: LuckyCatLayout.earSize, height: LuckyCatLayout.earSize + 4)
            .rotationEffect(.degrees(side == .left ? -12 : 12))
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
