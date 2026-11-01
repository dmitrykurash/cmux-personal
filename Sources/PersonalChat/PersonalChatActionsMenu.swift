import SwiftUI

struct PersonalChatActionsMenu<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = PersonalChatPalette(scheme: scheme)
        Menu(content: content) {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovered ? palette.text : palette.muted)
                .frame(width: 28, height: 28)
                .background(hovered ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .tint(hovered ? palette.text : palette.muted)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
        .accessibilityLabel(label).help(label)
    }
}
