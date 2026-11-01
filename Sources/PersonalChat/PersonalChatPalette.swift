import SwiftUI

/// Warm neutral surfaces keep the composer distinct in both system appearances.
struct PersonalChatPalette {
    let scheme: ColorScheme
    var canvas: Color { color(0x262624, 0xFAF9F5) }
    var sidebar: Color { color(0x20201E, 0xF0EEE6) }
    var composer: Color { color(0x323230, 0xFFFFFF) }
    var border: Color { color(0x50504A, 0xDCDAD2) }
    var divider: Color { color(0x363632, 0xE4E2DA) }
    var text: Color { color(0xE9E8E2, 0x302F2B) }
    var secondary: Color { color(0xAAA9A1, 0x77766D) }
    var muted: Color { color(0x838279, 0x8C8B82) }
    var hover: Color { color(0x33332F, 0xE6E3D9) }
    var selection: Color { color(0x383833, 0xE4E0D4) }
    var bubble: Color { color(0x35352F, 0xEEECE2) }
    var accent: Color { color(0xD28D70, 0xB86949) }
    var onAccent: Color { color(0x211E1A, 0xFFFFFF) }

    private func color(_ dark: UInt32, _ light: UInt32) -> Color {
        let hex = scheme == .dark ? dark : light
        return Color(red: Double((hex >> 16) & 255) / 255,
                     green: Double((hex >> 8) & 255) / 255,
                     blue: Double(hex & 255) / 255)
    }
}
