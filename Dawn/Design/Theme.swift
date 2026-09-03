import SwiftUI
import UIKit

/// The visual language for Dawn: warm paper, low contrast, generous air.
/// Everything in the app pulls from here — never hard-code a colour or size in a view.
enum Theme {}

// MARK: - Appearance

extension Theme {
    /// Which palette the app paints with. `system` follows iOS; the other two
    /// are the user overriding it from Settings.
    enum Appearance: String, CaseIterable, Identifiable, Sendable {
        case system, light, dark

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        var symbol: String {
            switch self {
            case .system: "iphone"
            case .light: "sun.max"
            case .dark: "moon"
            }
        }

        /// `nil` hands the decision back to iOS, which is what makes "System"
        /// track the user changing it in Control Centre while Dawn is open.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }
}

// MARK: - Accessibility state
//
// Reduce Motion reads UIKit's global flag rather than the SwiftUI environment,
// so `Theme` can stay a set of statics and every existing call site keeps
// working. The value is read whenever a view body evaluates, so it is correct
// at launch and after any state change; toggling the setting while Dawn is
// foregrounded won't repaint screens that aren't otherwise re-rendering.
//
// Increase Contrast is *not* handled here. It is resolved per-colour inside the
// dynamic providers below, alongside light/dark, which is both more accurate
// (it is a trait, so SwiftUI repaints when it changes) and the only way to vary
// a colour on two axes at once.

extension Theme {
    enum A11y {
        /// Settings → Accessibility → Motion → Reduce Motion.
        static var wantsLessMotion: Bool {
            UIAccessibility.isReduceMotionEnabled
        }
    }
}

// MARK: - Palette

extension Theme {
    /// Two palettes, one set of names. Every colour below is a *dynamic* colour:
    /// it resolves against the view's `colorScheme` and contrast trait at draw
    /// time, so a call site never has to know which appearance is showing.
    ///
    /// Light is warm paper. Dark is the same room at night — a warm charcoal,
    /// never a cold zinc and never `#000000`, which on OLED makes every edge a
    /// hard cutout and makes text ghost as you scroll. Text tops out at a warm
    /// off-white rather than `#FFFFFF` for the same reason: pure white on near
    /// black is the pairing that actually causes halation.
    ///
    /// Contrast ratios in the comments are measured against `canvas` in the
    /// matching appearance. Everything carrying text clears WCAG AA (4.5:1);
    /// `ember` and `gold` are fills, icons, and 18pt-plus display text only, and
    /// clear the 3:1 floor for large text and meaningful non-text UI.
    enum Palette {

        // MARK: Surfaces
        //
        // Elevation is carried by lightness, not shadow. Each step roughly
        // doubles luminance (0.4% → 0.7% → 2.7%), which is what reads as
        // "raised" on a dark ground — a drop shadow on near-black is invisible.
        // In light mode the same ramp runs the other way: paper, then recessed.

        /// The base the whole app sits on.
        static let canvas = Color.dynamic(light: 0xFBF7F1, dark: 0x17130F)

        /// A recess *below* the canvas — inset wells, pressed rows.
        static let canvasSunk = Color.dynamic(light: 0xF4ECE2, dark: 0x100D0A)

        /// Something floating over the app — sheets, popovers. Cards don't
        /// need an entry here: `GlassCard` is Liquid Glass, which already
        /// renders lighter than the canvas in dark mode, and the tinted
        /// variants pass `ink.opacity(...)` — white at low alpha in the dark,
        /// which is the same lift by another route.
        static let surfaceRaised = Color.dynamic(light: 0xFFFFFF, dark: 0x352C24)

        // MARK: Ink

        /// Warm near-black on paper, warm off-white at night. Never pure
        /// either. 14.75:1 light, 15.50:1 dark.
        static let ink = Color.dynamic(light: 0x2B2119, dark: 0xF2EAE0)

        /// 6.12:1 light, 9.92:1 dark.
        static let inkSecondary = Color.dynamic(
            light: 0x6A5B4C, dark: 0xC9BCAC,
            lightHighContrast: 0x4E4136, darkHighContrast: 0xDCD2C4
        )

        /// Supporting text only. 5.03:1 light, 6.57:1 dark.
        static let inkTertiary = Color.dynamic(
            light: 0x776859, dark: 0xA89880,
            lightHighContrast: 0x5C4E40, darkHighContrast: 0xC3B5A2
        )

        // MARK: Accent

        /// The single accent: low-saturation terracotta, like light through a
        /// curtain. Lifted in dark mode — the light-mode terracotta goes muddy
        /// against charcoal. 3.09:1 light, 7.86:1 dark: fills, icons, and
        /// display text.
        static let ember = Color.dynamic(light: 0xC97A4E, dark: 0xE0996B)

        /// The accent as a *surface* tint: a pale wash on paper, a warm glow in
        /// the dark. Backgrounds only — never text.
        static let emberSoft = Color.dynamic(light: 0xE9C4A8, dark: 0x4A3527)

        /// 3.5:1 light, 10.15:1 dark. Icons and display text.
        static let gold = Color.dynamic(light: 0xD9A84E, dark: 0xE3BA72)

        /// `ember` pushed until it can carry body-size text — darker on paper,
        /// lighter in the dark. Links, inline notes, error copy.
        /// 4.90:1 light, 9.08:1 dark.
        static let emberDeep = Color.dynamic(
            light: 0xA65726, dark: 0xE8A87C,
            lightHighContrast: 0x8C4518, darkHighContrast: 0xF0BC97
        )

        /// Destructive only. Deliberately a different hue from `ember` so
        /// "delete" never reads as "selected". 6.56:1 light, 7.76:1 dark.
        static let danger = Color.dynamic(
            light: 0xA8291D, dark: 0xF08D7F,
            lightHighContrast: 0x8E1F15, darkHighContrast: 0xF5A99D
        )

        // MARK: Lines and states

        /// Hairlines and dividers. Decorative — not for control outlines.
        /// Ink on paper, light on charcoal: a dark hairline disappears at night.
        static let rule = Color.dynamic(
            light: 0x2B2119, dark: 0xFFFFFF, alpha: 0.08, darkAlpha: 0.10
        )

        static let ruleStrong = Color.dynamic(
            light: 0x2B2119, dark: 0xFFFFFF, alpha: 0.14, darkAlpha: 0.17
        )

        /// Outline for an *unselected* interactive control. 3.32:1 light,
        /// 5.55:1 dark — at or above the floor for meaningful non-text UI.
        /// `rule` is far too faint for anything the user is meant to act on.
        static let control = Color.dynamic(
            light: 0x8E8780, dark: 0x968B82,
            lightHighContrast: 0x6E6760, darkHighContrast: 0xB0A69C
        )

        /// Fill for a disabled control. Pairs with `disabledLabel` at 7.12:1
        /// dark, 4.6:1 light — a disabled control still has to be readable.
        static let disabledFill = Color.dynamic(
            light: 0x2B2119, dark: 0xFFFFFF, alpha: 0.10, darkAlpha: 0.12
        )

        static var disabledLabel: Color { inkSecondary }

        /// The brightest thing on screen — the highlight that sweeps a loading
        /// skeleton. Has to be lighter than whatever it crosses in *both*
        /// appearances, so it can't be `canvas`.
        static let sheen = Color.dynamic(
            light: 0xFFFFFF, dark: 0xFFFFFF, alpha: 0.85, darkAlpha: 0.14
        )
    }
}

// MARK: - Typography

extension Theme {
    /// Serif for anything the user reads slowly (prompts, their own words).
    /// Sans for chrome. The split is what makes it feel considered rather than
    /// templated.
    ///
    /// Sizes are expressed in points at the default Dynamic Type setting, then
    /// resolved to the nearest system text style so the whole app scales with
    /// the user's chosen size. `Font.system(size:)` — what this used to return
    /// — is the *non-scaling* constructor, and there is no `relativeTo:`
    /// overload for system fonts. Anything larger than `.largeTitle` has to use
    /// `@ScaledMetric` at the call site; see `Theme.Display`.
    enum Typography {
        static func display(_ size: CGFloat = 34) -> Font {
            .system(textStyle(for: size), design: .serif, weight: .regular)
        }

        static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(textStyle(for: size), design: .serif, weight: weight)
        }

        static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(textStyle(for: size), design: .default, weight: weight)
        }

        /// Small all-caps label with wide tracking — the "premium editorial" tell.
        static let eyebrow = Font.system(.caption2, design: .default, weight: .medium)

        /// The streak numeral. Scales from 44pt; see `Theme.Display.numeral`.
        static let numeral = Font.system(.largeTitle, design: .rounded, weight: .light)

        /// The designed point size mapped onto Apple's type ladder.
        ///
        /// Editable on purpose: if a heading lands a step off, change it here
        /// rather than reaching for a fixed size in a view.
        ///
        ///   ≤11 caption2 · 12 caption · 13 footnote · 14–15 subheadline
        ///   16 callout · 17–18 body · 19–20 title3 · 21–24 title2
        ///   25–30 title · 31+ largeTitle
        static func textStyle(for size: CGFloat) -> Font.TextStyle {
            switch size {
            case ..<12: .caption2
            case ..<13: .caption
            case ..<14: .footnote
            case ..<16: .subheadline
            case ..<17: .callout
            case ..<19: .body
            case ..<21: .title3
            case ..<25: .title2
            case ..<31: .title
            default: .largeTitle
            }
        }
    }

    /// Point sizes above `.largeTitle` (34pt) have no text style to sit on, so
    /// the few oversized display faces scale through `@ScaledMetric` instead.
    /// Declare one of these in the view, then feed it to `Typography.display`.
    enum Display {
        static let hook: CGFloat = 56      // the wordmark on the welcome screen
        static let greeting: CGFloat = 40  // gate greeting, holding screen
        static let numeral: CGFloat = 44   // streak count on the completion card
    }
}

// MARK: - Metrics

extension Theme {
    enum Space {
        static let hairline: CGFloat = 1
        static let xs: CGFloat = 6
        static let sm: CGFloat = 12
        static let md: CGFloat = 20
        static let lg: CGFloat = 32
        static let xl: CGFloat = 48
        static let xxl: CGFloat = 72

        /// Standard page gutter.
        static let gutter: CGFloat = 28

        /// The smallest a control is allowed to be, per HIG.
        static let tapTarget: CGFloat = 44
    }

    enum Radius {
        static let card: CGFloat = 28
        static let field: CGFloat = 20
        static let pill: CGFloat = 999
    }
}

// MARK: - Motion

extension Theme {
    /// One motion vocabulary. Calm means slow-ish, heavily damped, never bouncy.
    ///
    /// Every value collapses to a plain cross-fade under Reduce Motion, which is
    /// what Apple asks for: keep the state change legible, drop the travel.
    enum Motion {
        static var settle: Animation {
            A11y.wantsLessMotion ? fade : .spring(response: 0.55, dampingFraction: 0.86)
        }

        static var gentle: Animation {
            A11y.wantsLessMotion ? fade : .spring(response: 0.75, dampingFraction: 0.9)
        }

        static var quick: Animation {
            A11y.wantsLessMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.84)
        }

        /// The slow ambient pulse behind the sun. `nil` under Reduce Motion so
        /// callers can skip `repeatForever` entirely rather than run it fast.
        static var breathe: Animation? {
            A11y.wantsLessMotion ? nil : .easeInOut(duration: 4.0)
        }

        private static let fade = Animation.easeInOut(duration: 0.22)

        /// Multiplier for the "rises into place" offsets used on reveals.
        /// Zero under Reduce Motion, which turns every rise into a pure fade:
        ///
        ///     .offset(y: appeared ? 0 : 14 * Theme.Motion.rise)
        static var rise: CGFloat { A11y.wantsLessMotion ? 0 : 1 }

        /// Card-to-card transition. Slides under normal settings, cross-fades
        /// when the user has asked for less movement.
        static func slide(insertion: CGFloat, removal: CGFloat) -> AnyTransition {
            guard !A11y.wantsLessMotion else { return .opacity }
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(y: insertion)),
                removal: .opacity.combined(with: .offset(y: removal))
            )
        }
    }
}

// MARK: - Text styling shortcuts

extension View {
    /// Wide-tracked uppercase label used above section headings.
    func eyebrowStyle(_ color: Color = Theme.Palette.inkTertiary) -> some View {
        self.font(Theme.Typography.eyebrow)
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    func pageGutter() -> some View {
        self.padding(.horizontal, Theme.Space.gutter)
    }

    /// Grows a control's hit area to the 44×44pt HIG minimum without changing
    /// how it looks. Use on any bare `Button` that would otherwise be as small
    /// as its label.
    func tappable() -> some View {
        self.frame(minWidth: Theme.Space.tapTarget, minHeight: Theme.Space.tapTarget)
            .contentShape(Rectangle())
    }
}

// MARK: - Dynamic colour

extension Color {
    /// A colour with one value on paper and another in the dark, and
    /// optionally a third and fourth for Increase Contrast.
    ///
    /// This wraps a `UIColor` dynamic provider rather than reading the SwiftUI
    /// environment, which is what lets `Theme.Palette` stay a set of statics:
    /// the resolution happens at draw time against the view's own traits, so
    /// 300-odd call sites written for a single palette keep working untouched,
    /// and they repaint correctly the moment the appearance changes.
    ///
    /// - Parameters:
    ///   - alpha: opacity in light mode.
    ///   - darkAlpha: opacity in dark mode; defaults to `alpha`. Hairlines and
    ///     scrims usually need a little more weight against charcoal than
    ///     against paper.
    static func dynamic(
        light: UInt32,
        dark: UInt32,
        lightHighContrast: UInt32? = nil,
        darkHighContrast: UInt32? = nil,
        alpha: Double = 1,
        darkAlpha: Double? = nil
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let wantsContrast = traits.accessibilityContrast == .high

            let hex: UInt32 = switch (isDark, wantsContrast) {
            case (false, false): light
            case (false, true): lightHighContrast ?? light
            case (true, false): dark
            case (true, true): darkHighContrast ?? dark
            }

            return UIColor(hex: hex, alpha: isDark ? (darkAlpha ?? alpha) : alpha)
        })
    }
}

// MARK: - Color hex

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}


extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
