import SwiftUI

struct PersonalChatHoverStyle: ButtonStyle {
    var selected = false
    var radius: CGFloat = 8
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let palette = PersonalChatPalette(scheme: scheme)
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .background(selected ? palette.selection : (hovered || configuration.isPressed ? palette.hover : .clear),
                        in: RoundedRectangle(cornerRadius: radius))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovered = $0 && enabled }
    }
}
