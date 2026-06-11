import SwiftUI

struct LuckyCatMascotView: View {
    let status: LuckyCatVisualStatus
    var large: Bool = false

    private var width: CGFloat { large ? 160 : LuckyCatLayout.mascotWidth }
    private var height: CGFloat { large ? 204 : LuckyCatLayout.mascotHeight }

    var body: some View {
        ZStack {
            LuckyCatStatusOrb(status: status, size: large ? 64 : LuckyCatLayout.orbSize, pulsing: status == .running)
                .offset(x: large ? 52 : 30, y: large ? -66 : -48)

            RoundedRectangle(cornerRadius: large ? 48 : 42, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            LuckyCatTokens.Palette.cream,
                            LuckyCatTokens.Palette.cream.opacity(0.92),
                            LuckyCatTokens.Palette.creamDeep.opacity(0.72)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: large ? 48 : 42, style: .continuous)
                        .stroke(Color.white.opacity(0.74), lineWidth: 1)
                )

            LuckyCatEarView(side: .left)
                .offset(x: large ? -48 : -36, y: large ? -77 : -58)
            LuckyCatEarView(side: .right)
                .offset(x: large ? 48 : 36, y: large ? -77 : -58)

            LuckyCatFaceView(mood: status.mood)
                .offset(y: large ? -14 : -10)

            LuckyCatBellView()
                .offset(y: large ? 70 : 54)
        }
        .frame(width: width, height: height)
    }
}
