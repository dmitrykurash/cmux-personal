import AppKit
import SwiftUI

struct PersonalChatWelcomeHeading: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 28) {
            if let url = Bundle.main.url(forResource: "personal-symbol", withExtension: "png", subdirectory: "PersonalChatAssets"),
               let mark = NSImage(contentsOf: url) {
                Image(nsImage: mark).resizable().interpolation(.high).scaledToFit().frame(height: 40)
                    .accessibilityHidden(true)
            }
            ViewThatFits(in: .horizontal) {
                heading(size: 56)
                heading(size: 42)
            }
        }.onAppear { revealed = true }
    }

    private func heading(size: CGFloat) -> some View {
        Text(String(localized: "personal.welcome.short", defaultValue: "What can we work on?", bundle: PersonalChatStrings.bundle))
            .font(PersonalChatTypography.display(size)).tracking(-size * 0.045)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .offset(y: revealed || reduceMotion ? 0 : size * 1.15)
            .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 1.05).delay(0.08), value: revealed)
            .clipped()
    }
}
