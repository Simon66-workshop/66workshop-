import SwiftUI

struct LuckyCatBellView: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(LuckyCatTokens.Palette.collarRed)
                .frame(width: 92, height: 12)

            Circle()
                .fill(LuckyCatTokens.Palette.gold)
                .frame(width: LuckyCatLayout.bellSize, height: LuckyCatLayout.bellSize)
                .overlay(Circle().stroke(Color.white.opacity(0.42), lineWidth: 1))

            Circle()
                .fill(LuckyCatTokens.Palette.goldDeep)
                .frame(width: 5, height: 5)
                .offset(y: 4)
        }
    }
}
