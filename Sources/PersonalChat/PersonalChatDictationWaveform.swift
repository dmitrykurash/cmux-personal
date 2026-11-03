import SwiftUI

/// Fixed geometry: recognition revisions cannot resize the composer.
struct PersonalChatDictationWaveform: View {
    @Bindable var dictation: PersonalChatDictation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var samples = Array(repeating: Float(0), count: 32)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(samples.indices, id: \.self) { index in
                Capsule().fill(.primary.opacity(dictation.phase == .recording ? 0.8 : 0.25))
                    .frame(width: 3, height: reduceMotion ? 8 : 4 + CGFloat(samples[index]) * 36)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 72)
        .accessibilityHidden(true)
        .onChange(of: dictation.level) {
            samples.removeFirst()
            samples.append(min(1, max(0, dictation.level)))
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: samples)
    }
}
