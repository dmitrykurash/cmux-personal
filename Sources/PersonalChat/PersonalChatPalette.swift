import SwiftUI

/// Axiom Desktop's chat-ui tokens, adapted to native semantic surfaces.
struct PersonalChatPalette {
    let scheme: ColorScheme
    private var ink: Color { scheme == .dark ? .white : color(0x101014, 0x101014) }
    var canvas: Color { color(0x141416, 0xF2F2F4) }
    var canvasTop: Color { color(0x18181B, 0xF2F2F4) }
    var canvasBottom: Color { color(0x0E0E10, 0xE8E8EC) }
    var sidebar: Color { color(0x18181B, 0xECECEF) }
    var stage: Color { .white.opacity(scheme == .dark ? 0.045 : 0.72) }
    var composer: Color { .white.opacity(scheme == .dark ? 0.05 : 0.72) }
    var composerHover: Color { .white.opacity(scheme == .dark ? 0.065 : 0.78) }
    var composerFocus: Color { .white.opacity(scheme == .dark ? 0.075 : 0.80) }
    var border: Color { ink.opacity(0.08) }
    var strongBorder: Color { ink.opacity(scheme == .dark ? 0.14 : 0.15) }
    var focusBorder: Color { ink.opacity(0.30) }
    var focusRing: Color { ink.opacity(scheme == .dark ? 0.08 : 0.06) }
    var divider: Color { border }
    var text: Color { color(0xF4F4F6, 0x101014) }
    var secondary: Color { color(0xB4B4BA, 0x56565F) }
    var muted: Color { color(0x86868E, 0x84848E) }
    var faint: Color { color(0x5F5F67, 0xA6A6AF) }
    var hover: Color { ink.opacity(0.055) }
    var chip: Color { ink.opacity(scheme == .dark ? 0.07 : 0.045) }
    var selection: Color { color(0x2C2C31, 0xFFFFFF) }
    var bubble: Color { .white.opacity(scheme == .dark ? 0.075 : 0.82) }
    var accent: Color { color(0xFF7653, 0xFF7653) }
    var send: Color { color(0xF4F4F6, 0xFF7653) }
    var onAccent: Color { color(0x101014, 0x1F1F1F) }
    var success: Color { color(0x5CB86A, 0x3F9B46) }

    private func color(_ dark: UInt32, _ light: UInt32) -> Color {
        let hex = scheme == .dark ? dark : light
        return Color(red: Double((hex >> 16) & 255) / 255,
                     green: Double((hex >> 8) & 255) / 255,
                     blue: Double(hex & 255) / 255)
    }
}
