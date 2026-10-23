// Generated from apps/web/src/lib/theme.ts by `npm run theme:native`; do not edit.
import SwiftUI
import UIKit

/// The Palee theme for the widgets: light (Frost) and dark (Graphite), like the app.
enum PaleeTheme {
    static let background = dynamic(light: 0xF4F5F7, dark: 0x17181C)
    static let panel = dynamic(light: 0xFFFFFF, dark: 0x1D1F24)
    static let text = dynamic(light: 0x17181C, dark: 0xF4F5F7)
    static let muted = dynamic(light: 0x5E6470, dark: 0xA2A8B3)
    static let border = dynamic(light: 0xDFE2E8, dark: 0x2C2F37)
    static let primary = dynamic(light: 0x2F5BFF, dark: 0x5B7CFF)
    static let primaryContrast = dynamic(light: 0xFFFFFF, dark: 0x0E0F12)
    static let spark = dynamic(light: 0xC8FF4D, dark: 0xE4FF6E)
    static let sparkContrast = dynamic(light: 0x17181C, dark: 0x17181C)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
