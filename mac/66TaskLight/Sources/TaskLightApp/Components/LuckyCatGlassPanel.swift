import SwiftUI

struct LuckyCatGlassPanel<Content: View>: View {
    let status: LuckyCatVisualStatus
    let content: Content

    init(status: LuckyCatVisualStatus, @ViewBuilder content: () -> Content) {
        self.status = status
        self.content = content()
    }

    var body: some View {
        content
            .padding(LuckyCatLayout.panelPadding)
            .background(background)
            .overlay(border)
            .shadow(color: LuckyCatTokens.Palette.shadow, radius: 34, x: 0, y: 14)
            .shadow(color: status.glow, radius: 28, x: 0, y: 0)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: LuckyCatLayout.cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: LuckyCatLayout.cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                LuckyCatTokens.Palette.cream.opacity(0.82),
                                LuckyCatTokens.Palette.creamDeep.opacity(0.45),
                                Color.white.opacity(0.26)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(patternOverlay)
            .clipShape(RoundedRectangle(cornerRadius: LuckyCatLayout.cornerRadius, style: .continuous))
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: LuckyCatLayout.cornerRadius, style: .continuous)
            .strokeBorder(LuckyCatTokens.Palette.border, lineWidth: 1)
    }

    private var patternOverlay: some View {
        Canvas { context, size in
            let dot = Color.white.opacity(0.1)
            let step: CGFloat = 20
            for x in stride(from: 10 as CGFloat, through: size.width, by: step) {
                for y in stride(from: 10 as CGFloat, through: size.height, by: step) {
                    context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(dot))
                }
            }
        }
        .opacity(0.45)
        .blendMode(.screen)
    }
}
