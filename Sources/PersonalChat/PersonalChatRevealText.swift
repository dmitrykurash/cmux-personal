import SwiftUI

/// A short reveal of text already received from the CLI transcript, not simulated tokens.
struct PersonalChatRevealText: View {
    let text: String
    let animate: Bool
    let completed: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    @State private var characters: [Character] = []
    @State private var fromCount = 0
    @State private var revealing = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !revealing)) { timeline in
            let duration = min(1.2, max(0.18, Double(characters.count - fromCount) / 240))
            let fraction = min(1, max(0, timeline.date.timeIntervalSince(started) / duration))
            let count = revealing ? fromCount + Int(Double(characters.count - fromCount) * fraction) : characters.count
            let visible = revealing ? String(characters.prefix(count)) : text
            Text((try? AttributedString(markdown: visible, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(visible))
                .textSelection(.enabled)
                .accessibilityLabel(text)
                .onChange(of: count) {
                    if revealing && count >= characters.count { revealing = false; completed() }
                }
        }
        .onAppear { begin(from: 0) }
        .onChange(of: text) { old, _ in begin(from: text.hasPrefix(old) ? old.count : 0) }
        .onChange(of: reduceMotion) { if reduceMotion { revealing = false; completed() } }
    }

    private func begin(from count: Int) {
        characters = Array(text)
        fromCount = min(count, characters.count)
        started = Date()
        revealing = animate && !reduceMotion && fromCount < characters.count
        if !revealing { completed() }
    }
}
