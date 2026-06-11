import SwiftUI

struct LuckyCatFaceView: View {
    let mood: LuckyCatMood

    var body: some View {
        ZStack {
            HStack(spacing: 30) {
                eye
                eye
            }
            .offset(y: -21)

            Circle()
                .fill(Color.pink.opacity(0.82))
                .frame(width: 12, height: 9)
                .offset(y: -2)

            mouth
                .offset(y: 9)

            HStack(spacing: 55) {
                whiskers
                whiskers.scaleEffect(x: -1, y: 1)
            }
            .offset(y: 11)
        }
        .foregroundStyle(LuckyCatTokens.Palette.textPrimary)
    }

    private var eye: some View {
        Group {
            switch mood {
            case .alert:
                Circle().frame(width: 8, height: 8)
            case .happy:
                Capsule().frame(width: 18, height: 6).rotationEffect(.degrees(-8))
            case .curious:
                Capsule().frame(width: 16, height: 7)
            case .focused:
                Capsule().frame(width: 20, height: 5).rotationEffect(.degrees(5))
            case .sleepy:
                Capsule().frame(width: 16, height: 4)
            }
        }
    }

    private var mouth: some View {
        Group {
            switch mood {
            case .alert:
                Text("︶")
            case .happy:
                Text("⌣")
            case .curious:
                Text("◡")
            case .focused:
                Text("﹀")
            case .sleepy:
                Text("﹏")
            }
        }
        .font(.system(size: 24, weight: .bold, design: .rounded))
    }

    private var whiskers: some View {
        VStack(spacing: 5) {
            Capsule().fill(Color.pink.opacity(0.52)).frame(width: 22, height: 3).rotationEffect(.degrees(10))
            Capsule().fill(Color.pink.opacity(0.52)).frame(width: 22, height: 3)
            Capsule().fill(Color.pink.opacity(0.52)).frame(width: 22, height: 3).rotationEffect(.degrees(-10))
        }
    }
}
