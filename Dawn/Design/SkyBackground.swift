import SwiftUI

/// A clean ivory page with a little daylight along its upper edge.
/// One wash keeps the lighting even; fine glitter catches the light above it.
struct SkyBackground: View {
    var phase: DayPhase
    /// Quieter on reading screens; full strength on the welcome and gate.
    var intensity: Double = 1.0

    @Environment(\.colorSchemeContrast) private var contrast

    private var strength: Double {
        min(max(intensity, 0), 1) * (contrast == .increased ? 0.35 : 1)
    }

    var body: some View {
        ZStack {
            Theme.Palette.canvas

            LinearGradient(
                stops: [
                    .init(color: phase.horizonTint.opacity(strength), location: 0),
                    .init(color: phase.horizonTint.opacity(strength * 0.4), location: 0.28),
                    .init(color: phase.horizonTint.opacity(0), location: 0.68),
                    .init(color: phase.horizonTint.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            AmbientGlitter(intensity: strength)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A single drawing surface for drifting dots and occasional soft glints.
/// The page underneath stays still, so the motion never changes its lighting.
private struct AmbientGlitter: View {
    let intensity: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if reduceMotion {
            GlitterCanvas(time: 0, intensity: intensity * 0.55)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: scenePhase != .active)) { timeline in
                GlitterCanvas(
                    time: timeline.date.timeIntervalSinceReferenceDate,
                    intensity: intensity
                )
            }
        }
    }
}

private struct GlitterCanvas: View {
    let time: TimeInterval
    let intensity: Double

    @Environment(\.colorScheme) private var colorScheme

    private static let flecks = GlitterFleck.field(count: 64)
    private let gold = Color.dynamic(light: 0xBB945D, dark: 0xD6AF73)
    private let glint = Color.dynamic(light: 0xC49A59, dark: 0xFFE4B4)

    var body: some View {
        Canvas { context, size in
            for fleck in Self.flecks {
                // Wrap beyond the viewport so a fleck never jumps on screen.
                let travel = (fleck.y + time / fleck.travelPeriod).truncatingRemainder(dividingBy: 1)
                let y = (1 - travel) * (size.height + 24) - 12
                let sway = sin(time / fleck.swayPeriod + fleck.phase) * fleck.sway
                let x = fleck.x * size.width + sway
                let center = CGPoint(x: x, y: y)

                let wave = (sin(time * 2 * .pi / fleck.twinklePeriod + fleck.phase) + 1) / 2
                let sparkle = pow(wave, 10)
                let appearance = colorScheme == .dark ? 1.1 : 1.0
                let opacity = (0.14 + sparkle * 0.42) * intensity * appearance
                let radius = fleck.radius

                // A tiny solid fleck carries the motion between glints.
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(gold.opacity(opacity))
                )

                if fleck.catchesLight, sparkle > 0.12 {
                    let reach = radius * (2.4 + sparkle)
                    let halo = CGRect(x: x - reach, y: y - reach,
                                      width: reach * 2, height: reach * 2)
                    context.fill(
                        Path(ellipseIn: halo),
                        with: .radialGradient(
                            Gradient(colors: [glint.opacity(sparkle * intensity * 0.18), .clear]),
                            center: center, startRadius: 0, endRadius: reach
                        )
                    )

                }
            }
        }
    }
}

private struct GlitterFleck {
    let x: Double
    let y: Double
    let radius: Double
    let phase: Double
    let travelPeriod: Double
    let swayPeriod: Double
    let sway: Double
    let twinklePeriod: Double
    let catchesLight: Bool

    static func field(count: Int) -> [Self] {
        var generator = GlitterGenerator()
        return (0..<count).map { index in
            Self(
                x: Double.random(in: 0.02...0.98, using: &generator),
                y: Double.random(in: 0...1, using: &generator),
                radius: Double.random(in: 0.55...1.3, using: &generator),
                phase: Double.random(in: 0...(2 * .pi), using: &generator),
                travelPeriod: Double.random(in: 170...290, using: &generator),
                swayPeriod: Double.random(in: 9...19, using: &generator),
                sway: Double.random(in: 8...22, using: &generator),
                twinklePeriod: Double.random(in: 5...11, using: &generator),
                catchesLight: index.isMultiple(of: 3)
            )
        }
    }
}

/// Fixed seed keeps the same field when navigating between screens.
private struct GlitterGenerator: RandomNumberGenerator {
    private var state: UInt64 = 0xDA7E

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// Time of day, bucketed into the four moods the app cares about.
enum DayPhase: String, CaseIterable {
    case predawn
    case sunrise
    case day
    case dusk

    static func current(_ date: Date = .now, calendar: Calendar = .current) -> DayPhase {
        switch calendar.component(.hour, from: date) {
        case 0..<5: .predawn
        case 5..<9: .sunrise
        case 9..<17: .day
        default: .dusk
        }
    }

    /// Restrained, opaque colors blended normally into the page. Keeping the
    /// dark stops close to the canvas avoids a luminous patch behind the text.
    var horizonTint: Color {
        switch self {
        case .predawn: .dynamic(light: 0xEEEFF4, dark: 0x211D28)
        case .sunrise: .dynamic(light: 0xF4EBE3, dark: 0x28201B)
        case .day: .dynamic(light: 0xF0F1EC, dark: 0x22211C)
        case .dusk: .dynamic(light: 0xF3EBE9, dark: 0x291F1C)
        }
    }

    var greeting: String {
        switch self {
        case .predawn: "Early start"
        case .sunrise: "Good morning"
        case .day: "Good afternoon"
        case .dusk: "Good evening"
        }
    }
}
