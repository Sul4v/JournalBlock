import SwiftUI

/// The light in the room changes through the day. The background follows it.
/// Kept deliberately pale — this is a warm room at sunrise, not a screensaver.
struct SkyBackground: View {
    var phase: DayPhase
    /// Set true on the journal gate, where we want a touch more presence.
    var intensity: Double = 1.0

    @State private var drift: Double = 0

    var body: some View {
        ZStack {
            Theme.Palette.canvas

            // Horizon wash: warm light pooling at the top of the screen.
            LinearGradient(
                stops: phase.stops(intensity: intensity),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // A soft sun, low and off-centre. It breathes very slowly.
            RadialGradient(
                colors: [phase.sunTint.opacity(0.55 * intensity), .clear],
                center: UnitPoint(x: 0.78, y: 0.06 + drift * 0.02),
                startRadius: 0,
                endRadius: 420
            )
            .blendMode(.plusLighter)
            .ignoresSafeArea()

            // Dust in a sunbeam. Small points of warm light that fade in and
            // out on their own clocks and bob a few points as they do — the
            // room catching light rather than anything sliding across it.
            Glimmer(tint: phase.glimmerTint, intensity: intensity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Paper grain. Very low opacity; it kills the plastic look of flat gradients.
            GrainOverlay()
                .opacity(0.035)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            // `breathe` is nil under Reduce Motion — the sun then simply holds
            // its position rather than pulsing forever.
            guard let breathe = Theme.Motion.breathe else { return }
            withAnimation(breathe.repeatForever(autoreverses: true)) {
                drift = 1
            }
        }
    }
}

/// Time of day, bucketed into the four moods the app cares about.
enum DayPhase: String, CaseIterable {
    case predawn    // before first light
    case sunrise    // the app's home turf
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

    /// A touch more saturated than `sunTint`. Glimmer has to differ from the
    /// canvas in hue as well as brightness, or it disappears into the paper —
    /// and in the dark it is the one thing allowed to actually sparkle, so it
    /// stays bright while everything around it drops.
    var glimmerTint: Color {
        switch self {
        case .predawn: .dynamic(light: 0xC4AED6, dark: 0x9A86C4)
        case .sunrise: .dynamic(light: 0xEFAF6C, dark: 0xE0A468)
        case .day: .dynamic(light: 0xEFC176, dark: 0xDDB77A)
        case .dusk: .dynamic(light: 0xE59A72, dark: 0xD9906E)
        }
    }

    /// The sun itself. Drawn with `.plusLighter`, so in the dark these are
    /// *additive* — the values are dim on purpose. A tint picked to look right
    /// on paper blows out to a white hole against charcoal.
    var sunTint: Color {
        switch self {
        case .predawn: .dynamic(light: 0xD9C7E0, dark: 0x241D34)
        case .sunrise: .dynamic(light: 0xFFD3A1, dark: 0x3A2410)
        case .day: .dynamic(light: 0xFFE9C9, dark: 0x302512)
        case .dusk: .dynamic(light: 0xF3C0A0, dark: 0x331C10)
        }
    }

    /// The horizon wash. On paper it is warm light pooling at the top of the
    /// screen; in the dark it is the same pool, lifted just far enough off the
    /// canvas to read as light rather than as banding.
    func stops(intensity: Double) -> [Gradient.Stop] {
        let a: Color, b: Color
        switch self {
        case .predawn:
            a = .dynamic(light: 0xEBE2EF, dark: 0x1E1826)
            b = .dynamic(light: 0xF9EFE8, dark: 0x181420)
        case .sunrise:
            a = .dynamic(light: 0xFFE7CE, dark: 0x261A10)
            b = .dynamic(light: 0xFDF1E4, dark: 0x1B1510)
        case .day:
            a = .dynamic(light: 0xFBECD8, dark: 0x211A13)
            b = .dynamic(light: 0xFDF4EA, dark: 0x1A1510)
        case .dusk:
            a = .dynamic(light: 0xF9E2D2, dark: 0x241713)
            b = .dynamic(light: 0xFAF0E7, dark: 0x1B1410)
        }
        return [
            .init(color: a.opacity(intensity), location: 0),
            .init(color: b.opacity(intensity), location: 0.42),
            .init(color: Theme.Palette.canvas, location: 1)
        ]
    }

    /// Greeting used on the gate and home screen.
    var greeting: String {
        switch self {
        case .predawn: "Early start"
        case .sunrise: "Good morning"
        case .day: "Good afternoon"
        case .dusk: "Good evening"
        }
    }
}

/// Cheap procedural grain, drawn once into a Canvas.
private struct GrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            var generator = SystemRandomNumberGenerator()
            let count = Int(size.width * size.height / 900)
            for _ in 0..<count {
                let x = Double.random(in: 0...size.width, using: &generator)
                let y = Double.random(in: 0...size.height, using: &generator)
                let s = Double.random(in: 0.6...1.4, using: &generator)
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                    with: .color(Theme.Palette.ink)
                )
            }
        }
        .drawingGroup()
    }
}


/// Dust hanging in a sunbeam.
///
/// Small specks, not soft patches: each one floats a Lissajous path (two
/// different periods on x and y, so it never traces a visible loop) and flashes
/// as it turns through the light. Size and brightness are inversely paired —
/// the big ones are out of focus and dim, the small ones sharp and bright —
/// which is what gives the field depth rather than looking like flat confetti.
///
/// One `Canvas` inside a `TimelineView` rather than N animated views: seventy
/// SwiftUI views each running `repeatForever` is a lot of view-tree churn for
/// something nobody should consciously notice.
private struct Glimmer: View {
    let tint: Color
    var intensity: Double

    /// For people who need it, "subtle" is still motion — so this switches off
    /// rather than slowing down.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Built once. Regenerating per frame would make the field boil.
    private let motes = Mote.field(count: 70)

    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                Canvas { ctx, size in
                    let t = context.date.timeIntervalSinceReferenceDate
                    for mote in motes {
                        draw(mote, at: t, in: ctx, size: size)
                    }
                }
            }
        }
    }

    private func draw(
        _ mote: Mote,
        at time: TimeInterval,
        in ctx: GraphicsContext,
        size: CGSize
    ) {
        // Flash. Eased so a speck sits dark a little longer than it sits lit,
        // which is what stops the field pulsing in unison.
        let wave = (sin(((time / mote.flashPeriod) + mote.phase) * 2 * .pi) + 1) / 2
        let alpha = mote.peak * pow(wave, 1.4) * intensity
        guard alpha > 0.012 else { return }

        // Two periods, deliberately not multiples of each other, so the path
        // never closes into something the eye can follow.
        let driftX = sin(((time / mote.swayPeriodX) + mote.phase) * 2 * .pi) * mote.swayX
        let driftY = sin(((time / mote.swayPeriodY) + mote.phase * 0.6) * 2 * .pi) * mote.swayY

        let centre = CGPoint(
            x: mote.x * size.width + driftX,
            y: mote.y * size.height + driftY
        )
        let r = mote.radius
        let rect = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)

        // Radial rather than a flat dot: a hard edge at this size reads as a
        // dead pixel, not a speck of light.
        ctx.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [tint.opacity(alpha), .clear]),
                center: centre,
                startRadius: 0,
                endRadius: r
            )
        )
    }
}

private struct Mote {
    let x: Double
    let y: Double
    let radius: Double
    let peak: Double
    let phase: Double
    let flashPeriod: Double
    let swayX: Double
    let swayY: Double
    let swayPeriodX: Double
    let swayPeriodY: Double

    /// Seeded so the field is identical every launch — a scatter that
    /// reshuffles on each appearance reads as a glitch.
    static func field(count: Int) -> [Mote] {
        var rng = SeededGenerator(seed: 0xDA7E)
        return (0..<count).map { _ in
            // Weighted towards the top, where the sun sits.
            let y = pow(Double.random(in: 0...1, using: &rng), 1.5)
            let radius = Double.random(in: 1.8...6.0, using: &rng)
            // Depth: the out-of-focus ones are bigger and fainter.
            let focus = 1 - ((radius - 1.8) / 4.2)
            return Mote(
                x: Double.random(in: -0.03...1.03, using: &rng),
                y: y,
                radius: radius,
                peak: (0.16 + 0.30 * focus) * Double.random(in: 0.75...1.15, using: &rng),
                phase: Double.random(in: 0...1, using: &rng),
                flashPeriod: Double.random(in: 3.0...9.0, using: &rng),
                swayX: Double.random(in: 5...22, using: &rng),
                swayY: Double.random(in: 8...30, using: &rng),
                swayPeriodX: Double.random(in: 11...26, using: &rng),
                swayPeriodY: Double.random(in: 14...33, using: &rng)
            )
        }
    }
}

/// Tiny deterministic LCG. Enough for scattering dust.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
