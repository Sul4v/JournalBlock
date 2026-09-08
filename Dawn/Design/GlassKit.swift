import SwiftUI

// MARK: - Glass card

/// The app's primary surface. Liquid Glass, warmly tinted.
///
/// The material draws its own edge — a hand-painted white hairline on top of it
/// was fighting the system's specular pass and changed appearance depending on
/// what happened to be behind the card.
struct GlassCard<Content: View>: View {
    /// Neutral by default. The ember wash used to be the default, which made
    /// every card in the app faintly yellow and left the tint saying nothing —
    /// a card that meant something by being warm looked like all the others.
    /// Warmth is now opt-in and carries meaning where it appears: a sitting
    /// still owed on Today, the recovery phrase, a destructive step.
    var tint: Color = Theme.Palette.ink.opacity(0.04)
    var radius: CGFloat = Theme.Radius.card
    var padding: CGFloat = Theme.Space.md
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(tint),
                in: .rect(cornerRadius: radius)
            )
            // The glass is a background, so without this a card used as a
            // button label only hit-tests where its text and icons are — the
            // padding and the gaps between them fall through, and a card that
            // reads as one big button answers only in patches.
            .contentShape(.rect(cornerRadius: radius))
    }
}

// MARK: - Primary action

/// The single strong call to action on a screen.
///
/// Solid rather than glass: the previous version painted `.glassEffect` on top
/// of an opaque capsule, so the material had nothing to refract and cost a
/// real-time pass for a sheen. Press feedback now comes from the button style.
struct EmberButton: View {
    var title: String
    var systemImage: String?
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: Theme.Space.xs + 2) {
                // At accessibility sizes a single-line label truncated to
                // "Start free t…" — the label wraps rather than clips.
                Text(title)
                    .font(Theme.Typography.sans(17, weight: .medium))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(Theme.Typography.sans(14, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isEnabled ? Theme.Palette.canvas : Theme.Palette.disabledLabel)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.Space.tapTarget)
            .padding(.vertical, 13)
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled
                          // A flat slab reads as a banner, not a control. The
                          // vertical gradient plus the top highlight below give
                          // it a lit edge, which is what says "raised".
                          ? AnyShapeStyle(LinearGradient(
                                colors: [Theme.Palette.ink.opacity(0.97),
                                         Theme.Palette.ink.opacity(0.86)],
                                startPoint: .top,
                                endPoint: .bottom))
                          : AnyShapeStyle(Theme.Palette.disabledFill))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Theme.Palette.canvas.opacity(isEnabled ? 0.28 : 0),
                                     Color.clear],
                            startPoint: .top,
                            endPoint: .bottom),
                        lineWidth: 1)
            )
            // Invisible on the dark canvas by design; on paper it lifts the
            // capsule off the card behind it.
            .shadow(color: Theme.Palette.ink.opacity(isEnabled ? 0.22 : 0),
                    radius: 10, x: 0, y: 4)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!isEnabled)
        .animation(Theme.Motion.quick, value: isEnabled)
    }
}

/// Quieter action: glass, no fill, for "skip", "later", "add another".
struct GhostButton: View {
    var title: String
    var systemImage: String?
    /// An icon after the label rather than before it. Leading icons say what
    /// kind of thing the button is; a trailing arrow says the button takes you
    /// somewhere. Pass one or the other, not both.
    var trailingImage: String?
    /// Set on ghost buttons that sit *inside* a `GlassCard`. Glass on glass
    /// flattens the hierarchy, so nested instances fall back to a plain style.
    var isNested: Bool = false
    /// How loudly the control asks to be pressed. A row of two identical soft
    /// capsules makes the user read both before choosing; the one they came
    /// for gets `.prominent` and the rest stay quiet.
    var emphasis: Emphasis = .quiet
    var action: () -> Void

    enum Emphasis {
        case quiet
        /// Filled ember. At most one per row.
        case prominent
    }

    var body: some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(Theme.Typography.sans(13, weight: .semibold))
                }
                Text(title)
                    .font(Theme.Typography.sans(15, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let trailingImage {
                    Image(systemName: trailingImage)
                        .font(Theme.Typography.sans(13, weight: .semibold))
                }
            }
            // Ember when nested, because grey text in a grey capsule on a
            // grey card is the shape every platform uses for "you can't press
            // this". The glass version has depth to say it's live; the flat
            // one has only colour. Filled, the capsule carries the colour and
            // the label goes to canvas.
            .foregroundStyle(labelTint)
            .padding(.horizontal, Theme.Space.md)
            .frame(minHeight: Theme.Space.tapTarget)
            .contentShape(Capsule(style: .continuous))
        }
        .modifier(GhostSurface(isNested: isNested, emphasis: emphasis))
    }

    private var labelTint: Color {
        switch (emphasis, isNested) {
        case (.prominent, _): Theme.Palette.canvas
        case (.quiet, true): Theme.Palette.emberDeep
        case (.quiet, false): Theme.Palette.inkSecondary
        }
    }
}

/// Nested ghost buttons get a warm capsule instead of a second glass layer.
private struct GhostSurface: ViewModifier {
    let isNested: Bool
    let emphasis: GhostButton.Emphasis

    func body(content: Content) -> some View {
        switch (emphasis, isNested) {
        case (.prominent, _):
            // Solid, and no border: the fill already draws the edge, and the
            // stroke only showed up as a second, slightly different one. The
            // gradient is the same top-lit trick `EmberButton` uses, scaled
            // down for a control that lives inside a card.
            content
                .buttonStyle(PressScaleStyle())
                .background(
                    Capsule(style: .continuous)
                        .fill(LinearGradient(
                            colors: [Theme.Palette.emberDeep.opacity(0.92),
                                     Theme.Palette.emberDeep],
                            startPoint: .top,
                            endPoint: .bottom))
                )
                // Black, not ember: a shadow tinted with the fill colour
                // reads as a halo in dark mode, where `emberDeep` is the
                // *light* end of the ramp. Black grounds the capsule on
                // paper and disappears against the night canvas, which is
                // what a shadow should do in both.
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
        case (.quiet, true):
            content
                .buttonStyle(PressScaleStyle())
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.Palette.emberSoft.opacity(0.32))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.Palette.ember.opacity(0.30), lineWidth: 1)
                )
        case (.quiet, false):
            content.buttonStyle(.glass)
        }
    }
}

/// A small icon-only control — back chevrons, close buttons, the password eye.
///
/// The glass is painted at `diameter` and the tap target is 44pt around it, so
/// the control stays comfortably hittable without drawing a button the size of
/// its own touch area. `.buttonStyle(.glass)` can't do this: it paints behind
/// whatever the label measures, and it pads horizontally more than vertically,
/// so a square glyph came out an oval and a 44pt one came out enormous.
struct IconButton: View {
    var systemName: String
    var accessibilityTitle: String
    var size: CGFloat = 14
    /// The visible circle. Chrome — back, close, the password eye — leaves this
    /// alone; a control that is the point of its screen can ask for more.
    var diameter: CGFloat = Theme.Space.iconControl
    var isGlass: Bool = true
    /// Chrome stays grey. A control that is the action of its card asks for
    /// the colour the app uses to mean "press this".
    var tint: Color = Theme.Palette.inkSecondary
    var action: () -> Void

    /// What each edge needs to grow by to reach the 44pt minimum.
    private var hitInset: CGFloat {
        max(0, (Theme.Space.tapTarget - diameter) / 2)
    }

    var body: some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            Image(systemName: systemName)
                .font(Theme.Typography.sans(size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: diameter, height: diameter)
                .modifier(IconSurface(isGlass: isGlass))
                // Grow to the tap target, claim it as the hit area, then hand
                // the layout back. A plain 44pt frame would have the control
                // occupy 44pt of the page too — which pushed whatever sits
                // beside it across, and left the circle inset from the gutter
                // so it no longer lined up with the text below it.
                .padding(hitInset)
                .contentShape(Rectangle())
                .padding(-hitInset)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(accessibilityTitle)
    }
}

private struct IconSurface: ViewModifier {
    let isGlass: Bool

    func body(content: Content) -> some View {
        if isGlass {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
        }
    }
}

/// A text-only control — "Restore", "Terms", "Forgot password?". Bare
/// `Button`s with `.buttonStyle(.plain)` collapse to the height of their label,
/// which is how six controls in the app ended up around 15pt tall.
struct TextButton: View {
    var title: String
    var font: Font = Theme.Typography.sans(13, weight: .medium)
    var tint: Color = Theme.Palette.inkSecondary
    /// Swaps the label for a spinner *in place*, so the row doesn't reflow
    /// around a control that changed width mid-tap.
    var isLoading: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            Text(title)
                .font(font)
                .foregroundStyle(tint)
                .opacity(isLoading ? 0 : 1)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(tint)
                    }
                }
                .padding(.horizontal, Theme.Space.xs)
                .frame(minHeight: Theme.Space.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "\(title), in progress" : title)
    }
}

/// Shared press feedback for the non-glass controls, so a solid button still
/// answers a finger.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !Theme.A11y.wantsLessMotion ? 0.98 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

// MARK: - Progress

/// A thin warm rule that fills as the user moves through the session.
/// Deliberately not a dot row — dots make five prompts feel like a chore list.
struct ProgressRule: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.rule)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.Palette.ember, Theme.Palette.gold],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: 2)
        .animation(Theme.Motion.settle, value: progress)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((max(0, min(1, progress)) * 100).rounded())) percent")
    }
}

// MARK: - Writing field

/// A single line of the user's writing. Underlined, not boxed — it should feel
/// like a page, not a form.
/// Generic over its focus value rather than an `Int`.
///
/// A line used to be identified by its position inside one prompt, which was
/// enough while the screen showed one prompt at a time. On a page of them,
/// "line 2" names a field in every question at once, so the caller supplies
/// whatever value is unique in its own context.
struct WritingLine<Field: Hashable>: View {
    var placeholder: String
    @Binding var text: String
    var field: Field
    var accessibilityTitle: String
    /// Minimum height of the *field*, for prompts that want a paragraph rather
    /// than a line. It has to sit here rather than on the whole line: stretching
    /// the enclosing stack just adds space under the rule, leaving a one-line
    /// field floating above a gap. Nil sizes to the text, as before.
    var minHeight: CGFloat?
    @FocusState.Binding var focused: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(Theme.Palette.inkTertiary),
                axis: .vertical
            )
            .font(Theme.Typography.serif(19))
            .foregroundStyle(Theme.Palette.ink)
            .tint(Theme.Palette.ember)
            .lineSpacing(6)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .focused($focused, equals: field)
            .submitLabel(.next)
            .accessibilityLabel(accessibilityTitle)

            Rectangle()
                .fill(focused == field ? Theme.Palette.ember.opacity(0.55) : Theme.Palette.rule)
                .frame(height: 1)
                .animation(Theme.Motion.quick, value: focused)
        }
    }
}

// MARK: - Section heading

struct SectionHeading: View {
    var title: String

    var body: some View {
        Text(title)
            .font(Theme.Typography.serif(26))
            .foregroundStyle(Theme.Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}


// MARK: - Skeleton loading

/// A placeholder block standing in for text that hasn't arrived yet.
struct SkeletonBar: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.Palette.ink.opacity(0.09))
            .frame(width: width, height: height)
    }
}

/// A slow highlight passing over a skeleton.
///
/// Deliberately unhurried — a fast shimmer signals "this is taking too long",
/// which is the opposite of what a loading state should communicate in an app
/// built around calm.
struct Shimmer: ViewModifier {
    var shape: RoundedRectangle

    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            // Not `canvas`: in dark mode that is the darkest
                            // thing on screen, and the sweep would read as a
                            // shadow crossing the skeleton rather than light.
                            Theme.Palette.sheen,
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.55)
                    .offset(x: sweep ? geo.size.width * 1.1 : -geo.size.width * 0.7)
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
        }
    }
}

extension View {
    func shimmering(in shape: RoundedRectangle) -> some View {
        modifier(Shimmer(shape: shape))
    }
}
