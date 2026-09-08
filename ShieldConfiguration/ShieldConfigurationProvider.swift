import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The screen the user actually hits when they open a shielded app.
///
/// The title is the wordmark and never changes. Everything situational — which
/// sitting is owed, how late it is, and how hard the screen leans on them — is
/// carried by the subtitle and the two buttons, written off
/// `GateBridge.pendingBlock`, which the app mirrors into the shared group
/// whenever the gate changes. If that mirror is empty, generic copy stands in;
/// a shield that renders nothing is a black screen the user cannot get past.
///
/// This runs on a hard deadline. The system gives the extension a few hundred
/// milliseconds to return, then falls back to Apple's default shield, so there
/// is no networking, no store access, and no date formatting here — the two
/// axes below are integer arithmetic on minutes since midnight.
final class ShieldConfigurationProvider: ShieldConfigurationDataSource {

    /// Must match `AppConfig.appName`, which lives in the app target and so
    /// cannot be imported here.
    private static let wordmark = "JournalBlock"

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        shield()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        shield()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        shield()
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        shield()
    }

    // MARK: - The screen

    /// One configuration for every kind of shielded thing. An app, a category
    /// and a web domain are all the same situation from the user's side: the
    /// page isn't written yet.
    private func shield() -> ShieldConfiguration {
        let block = GateBridge.pendingBlock
        let now = Clock.current()
        let pressure = Pressure(block: block, now: now)

        return ShieldConfiguration(
            // Solid paper rather than a blur of the app behind it. A blurred
            // feed still reads as the feed, and half the work of this screen is
            // being somewhere else.
            backgroundBlurStyle: nil,
            backgroundColor: ShieldPalette.canvas,
            icon: Self.wordmarkImage,
            title: ShieldConfiguration.Label(
                text: Copy.title(block: block, pressure: pressure),
                color: ShieldPalette.ink
            ),
            subtitle: ShieldConfiguration.Label(
                text: Copy.subtitle(block: block, pressure: pressure, now: now),
                color: ShieldPalette.inkSecondary
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: pressure.primaryButton,
                color: ShieldPalette.primaryLabel
            ),
            primaryButtonBackgroundColor: ShieldPalette.primaryFill,
            // nil removes the button entirely. The only state that earns a way
            // out is the one where the page isn't owed yet — see `Pressure`.
            secondaryButtonLabel: pressure.showsLaterButton
                ? ShieldConfiguration.Label(text: "Later", color: ShieldPalette.inkSecondary)
                : nil
        )
    }

    /// The wordmark, drawn in New York — the app's serif — rather than set in
    /// the title label.
    ///
    /// `ShieldConfiguration.Label` takes text and a colour and nothing else:
    /// there is no font parameter, and Apple renders both labels in the system
    /// sans. The icon slot is the only part of this screen that accepts our own
    /// typography, because it takes a `UIImage`.
    ///
    /// One bitmap in one fixed colour. An earlier version drew light and dark
    /// variants and registered them against traits, which is the correct way to
    /// do this everywhere except here: the shield host resolved the pair against
    /// light and drew ink-brown letters onto the dark canvas. See
    /// `ShieldPalette.wordmark`.
    private static let wordmarkImage: UIImage = {
        let pointSize: CGFloat = 40
        let base = UIFont.systemFont(ofSize: pointSize, weight: .regular)
        // `.serif` is New York, the same face `Theme.Typography.serif` asks
        // SwiftUI for.
        let font = base.fontDescriptor.withDesign(.serif)
            .map { UIFont(descriptor: $0, size: pointSize) } ?? base

        let attributed = NSAttributedString(
            string: wordmark,
            attributes: [.font: font, .foregroundColor: ShieldPalette.wordmark]
        )

        // Padding, not a tight fit: `size()` rounds the descender of the "J"
        // away and the glyph gets clipped at the baseline.
        let text = attributed.size()
        let inset = pointSize * 0.12
        let canvas = CGSize(width: text.width + inset * 2, height: text.height + inset * 2)

        return UIGraphicsImageRenderer(size: canvas).image { _ in
            attributed.draw(at: CGPoint(x: inset, y: inset))
        }
    }()

}

// MARK: - When it is

/// Minutes since midnight, read once per shield so the two axes below can never
/// disagree about what time it is.
private enum Clock {
    static func current(calendar: Calendar = .current, date: Date = Date()) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// What the hour is called. Picks the vocabulary — whether the screen can say
/// "morning" — while `Pressure` picks how hard it leans.
private enum Daypart {
    case dawn, morning, midday, afternoon, evening, night

    init(minutesOfDay: Int) {
        switch minutesOfDay / 60 {
        case 5..<8: self = .dawn
        case 8..<11: self = .morning
        case 11..<14: self = .midday
        case 14..<18: self = .afternoon
        case 18..<21: self = .evening
        default: self = .night
        }
    }
}

/// How far past the sitting's own time we are, which is the only thing that
/// decides tone. Deliberately separate from `Daypart`: a 10 PM block four hours
/// overdue should read exactly as firmly as a 7 AM one, even though the words
/// around it differ.
private enum Pressure {
    /// The page isn't owed yet. The first block of the day is monitored from
    /// midnight (see `GateScheduler`), so someone who wakes at five with a
    /// seven o'clock sitting lands here — the shield is up, but it has no
    /// business pressing them two hours before the time they chose.
    case notYet
    /// The first ninety minutes. This is the state the screen is designed for.
    case open
    /// Ninety minutes to four hours. Still warm, but it names the hour.
    case drifting
    /// Four hours or more. The warmth is withdrawn — no daypart vocabulary,
    /// no promises about the day being theirs. The fact and the count.
    case late

    init(block: GateBridge.PendingBlock?, now: Int) {
        guard let block else { self = .open; return }
        switch now - block.minutesOfDay {
        case ..<0: self = .notYet
        case 0..<90: self = .open
        case 90..<240: self = .drifting
        default: self = .late
        }
    }

    /// The one state with a way out. Everywhere else iOS's own home gesture is
    /// still there, so this is never a trap — the app just stops offering its
    /// own exit once the page is actually owed.
    var showsLaterButton: Bool { self == .notYet }

    /// Flattens with the copy. Losing the "now" is the button's half of the
    /// tone dropping out from under them.
    var primaryButton: String {
        switch self {
        case .notYet: "Write it early"
        case .open, .drifting: "Write it now"
        case .late: "Write it"
        }
    }
}

// MARK: - What it says

private enum Copy {

    /// Names the sitting. Freed up by the wordmark moving into the icon slot —
    /// before that this line was the brand, which said the same thing on every
    /// screen the user would ever see.
    static func title(block: GateBridge.PendingBlock?, pressure: Pressure) -> String {
        guard let block else { return "Your page is waiting" }
        switch pressure {
        case .notYet: return "Your page opens at \(block.timeLabel)"
        case .open: return "Your \(block.timeLabel) page is open"
        case .drifting: return "Your \(block.timeLabel) page is still open"
        // Flat, but not stripped: "page" is the noun that makes the time mean
        // anything. Without it the line is a bare timestamp with no referent —
        // the reader can't tell whether it is the current time, a deadline, or
        // something that already happened.
        case .late: return "Your \(block.timeLabel) page. Still unwritten."
        }
    }

    /// What it costs and what it buys. The daypart only colours the warm
    /// bands: by `late` the vocabulary is gone along with the warmth.
    static func subtitle(
        block: GateBridge.PendingBlock?,
        pressure: Pressure,
        now: Int
    ) -> String {
        guard let block else {
            return "Write today's page in JournalBlock and your apps come back."
        }
        let asks = questions(block.promptCount)

        switch pressure {
        case .notYet:
            return "\(asks), and the day's yours."

        case .open:
            switch Daypart(minutesOfDay: now) {
            case .dawn:
                return "Morning. \(asks), and your apps come back for the day."
            case .morning, .midday, .afternoon:
                return "\(asks), and your apps come back for the day."
            case .evening:
                return "Evening. \(asks), and your apps come back."
            case .night:
                return "\(asks), and the day's done."
            }

        case .drifting:
            switch Daypart(minutesOfDay: now) {
            case .dawn, .morning:
                return "The morning's getting on. \(asks)."
            case .midday:
                return "\(asks), whenever you're ready."
            case .afternoon:
                return "\(asks), and the rest of the day's yours."
            case .evening, .night:
                return "\(asks) before the day's out."
            }

        case .late:
            return "\(asks)."
        }
    }

    /// Spelled out through nine. Numerals read like a receipt, which is the
    /// register this screen is trying to get away from.
    private static func questions(_ count: Int) -> String {
        guard count != 1 else { return "One question" }
        let words = ["Zero", "One", "Two", "Three", "Four",
                     "Five", "Six", "Seven", "Eight", "Nine"]
        let number = (0..<words.count).contains(count) ? words[count] : "\(count)"
        return "\(number) questions"
    }
}
