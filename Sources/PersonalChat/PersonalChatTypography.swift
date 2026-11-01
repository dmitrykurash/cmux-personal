import AppKit
import CoreText
import SwiftUI

enum PersonalChatTypography {
    static func register() {
        for file in ["DMSans.ttf", "PPCirka-Regular.otf", "PPCirka-Light.otf"] {
            guard let url = Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "PersonalChatAssets") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let face = weight == .medium ? "Medium" : weight == .semibold ? "SemiBold" : weight == .bold ? "Bold" : "Regular"
        return .custom("DMSans-9ptRegular_" + face, size: size)
    }

    static func display(_ size: CGFloat) -> Font {
        // PP Cirka has no Cyrillic glyphs. Keep a serif cascade instead of
        // allowing the default sans-serif fallback to break the headline.
        let descriptor = NSFontDescriptor(fontAttributes: [
            .name: "PPCirka-Regular",
            .cascadeList: [NSFontDescriptor(name: "Georgia", size: size)]
        ])
        return Font(NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size))
    }

    static func editor(_ size: CGFloat) -> NSFont {
        NSFont(name: "DMSans-9ptRegular_Regular", size: size) ?? .systemFont(ofSize: size)
    }
}
