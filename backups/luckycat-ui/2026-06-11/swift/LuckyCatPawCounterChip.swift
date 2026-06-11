import SwiftUI

struct LuckyCatPawCounterChip: View {
    let status: LuckyCatVisualStatus
    let count: Int
    let label: String
    var showsLabel: Bool = true

    var body: some View {
        VStack(spacing: 2) {
            LuckyCatPawIcon(tint: status.tint)
                .frame(width: 32, height: 28)
                .padding(.top, 10)

            Text("\(count)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(status.tint)

            if showsLabel {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(status.tint.opacity(0.92))
                    .lineLimit(1)
                    .padding(.top, 1)
            } else {
                HStack(spacing: 4) {
                    Capsule().fill(status.tint).frame(width: 6, height: 2)
                    Capsule().fill(status.tint).frame(width: 10, height: 2)
                }
                .padding(.top, 1)
            }
        }
        .frame(width: 48, height: 92)
        .background(
            PawTileShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.94),
                            LuckyCatTokens.Palette.cream.opacity(0.82),
                            LuckyCatTokens.Palette.creamDeep.opacity(0.62)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    PawTileShape()
                        .fill(status.tint.opacity(0.11))
                )
                .overlay(
                    PawTileShape()
                        .stroke(Color.white.opacity(0.68), lineWidth: 1)
                )
        )
        .overlay(
            PawTileShape()
                .stroke(status.tint.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: LuckyCatTokens.Palette.shadow.opacity(0.55), radius: 10, x: 0, y: 6)
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(height: 12)
                .blur(radius: 5)
                .offset(y: 6)
        }
    }
}

private struct PawTileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let insetTop: CGFloat = rect.width * 0.16
        let insetBottom: CGFloat = rect.width * 0.065
        path.move(to: CGPoint(x: rect.minX + insetTop, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - insetTop, y: rect.minY),
            control1: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY - 1),
            control2: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.minY - 1)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - insetBottom, y: rect.maxY - rect.height * 0.1),
            control1: CGPoint(x: rect.maxX + 1, y: rect.minY + rect.height * 0.16),
            control2: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.26)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX - insetBottom, y: rect.maxY - rect.height * 0.01),
            control2: CGPoint(x: rect.midX + rect.width * 0.14, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + insetBottom, y: rect.maxY - rect.height * 0.1),
            control1: CGPoint(x: rect.midX - rect.width * 0.14, y: rect.maxY),
            control2: CGPoint(x: rect.minX + insetBottom, y: rect.maxY - rect.height * 0.01)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + insetTop, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.26),
            control2: CGPoint(x: rect.minX - 1, y: rect.minY + rect.height * 0.16)
        )
        path.closeSubpath()
        return path
    }
}

private struct LuckyCatPawIcon: View {
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.66)).frame(width: 8, height: 8).offset(x: -11, y: -6)
            Circle().fill(tint.opacity(0.72)).frame(width: 8, height: 8).offset(x: -3, y: -10)
            Circle().fill(tint.opacity(0.72)).frame(width: 8, height: 8).offset(x: 5, y: -10)
            Circle().fill(tint.opacity(0.66)).frame(width: 8, height: 8).offset(x: 13, y: -6)
            Capsule().fill(tint.opacity(0.88)).frame(width: 26, height: 18).offset(x: 1, y: 7)
        }
    }
}
