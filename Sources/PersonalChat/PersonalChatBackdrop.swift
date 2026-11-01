import SwiftUI

struct PersonalChatBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                bloom(width: 780, height: 640).rotationEffect(.degrees(-14)).offset(x: 120, y: 250)
                bloom(width: 720, height: 560).rotationEffect(.degrees(23)).opacity(0.8).offset(x: 1190, y: 130)
                bloom(width: 900, height: 620).rotationEffect(.degrees(8)).opacity(0.7).offset(x: 640, y: 830)
            }.frame(width: 2000, height: 1400)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }

    private func bloom(width: CGFloat, height: CGFloat) -> some View {
        Ellipse().fill(scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.92))
            .frame(width: width, height: height).blur(radius: 90)
    }
}
