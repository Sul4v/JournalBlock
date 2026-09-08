import UIKit

/// `Theme.Palette` for the Screen Time extensions.
///
/// The extensions can't import `Theme`: it is SwiftUI, it pulls in the whole
/// design system, and a shield has to be built in the few milliseconds the
/// system allows before it gives up and draws its own. These are the same hex
/// values as the app's `canvas`, `ink`, `inkSecondary` and `ember` — if you
/// change them there, change them here.
enum ShieldPalette {

    static let canvas = dynamic(light: 0xFAF9F6, dark: 0x17130F)
    static let ink = dynamic(light: 0x2B2119, dark: 0xF2EAE0)
    static let inkSecondary = dynamic(light: 0x6A5B4C, dark: 0xC9BCAC)
    static let ember = dynamic(light: 0xC97A4E, dark: 0xE0996B)

    /// The wordmark drawn into the icon slot, and the primary button. Both are
    /// *fixed* rather than dynamic, and that is deliberate.
    ///
    /// A shield is drawn by another process. `backgroundColor` survives the
    /// trip and resolves correctly, but a colour this extension resolves by
    /// hand — to tint a rendered bitmap, or seemingly for the button's label —
    /// resolves against traits that report light even when the shield is drawn
    /// dark. The result was a dark-brown wordmark on a dark ground and a button
    /// label that had all but vanished.
    ///
    /// So these three don't ask. `ember` carries the wordmark at 3.4:1 on paper
    /// and 5.4:1 in the dark; `emberDeep` under `canvas` gives the button 5.3:1
    /// either way. Fixed and legible beats correct-in-theory and invisible.
    static let wordmark = color(0xC97A4E)
    static let primaryFill = color(0xA65726)
    static let primaryLabel = color(0xFAF9F6)

    private static func dynamic(light: Int, dark: Int) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? color(dark) : color(light)
        }
    }

    private static func color(_ hex: Int) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
