import SwiftUI

// MARK: - Glass card

/// The app's primary surface. Liquid Glass, warmly tinted.
///
/// The material draws its own edge — a hand-painted white hairline on top of it
/// was fighting the system's specular pass and changed appearance depending on
/// what happened to be behind the card.
struct GlassCard<Content: View>: View {
    var tint: Color = Theme.Palette.emberSoft.opacity(0.22)
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
                          ? AnyShapeStyle(Theme.Palette.ink.opacity(0.92))
                          : AnyShapeStyle(Theme.Palette.disabledFill))
            )
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
    /// Set on ghost buttons that sit *inside* a `GlassCard`. Glass on glass
    /// flattens the hierarchy, so nested instances fall back to a plain style.
    var isNested: Bool = false
    var action: () -> Void

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
            }
            .foregroundStyle(Theme.Palette.inkSecondary)
            .padding(.horizontal, Theme.Space.md)
            .frame(minHeight: Theme.Space.tapTarget)
            .contentShape(Capsule(style: .continuous))
        }
        .modifier(GhostSurface(isNested: isNested))
    }
}

/// Nested ghost buttons get a hairline capsule instead of a second glass layer.
private struct GhostSurface: ViewModifier {
    let isNested: Bool

    func body(content: Content) -> some View {
        if isNested {
            content
                .buttonStyle(PressScaleStyle())
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.Palette.ink.opacity(0.05))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.Palette.rule, lineWidth: 1)
                )
        } else {
            content.buttonStyle(.glass)
        }
    }
}

/// A small icon-only control — back chevrons, close buttons, the password eye.
/// Always at least 44×44pt, whatever the glyph measures.
struct IconButton: View {
    var systemName: String
    var accessibilityTitle: String
    var size: CGFloat = 14
    var isGlass: Bool = true
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            Image(systemName: systemName)
                .font(Theme.Typography.sans(size, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .frame(width: 22, height: 22)
                .frame(minWidth: Theme.Space.tapTarget, minHeight: Theme.Space.tapTarget)
                .contentShape(Circle())
        }
        .modifier(IconSurface(isGlass: isGlass))
        .accessibilityLabel(accessibilityTitle)
    }
}

private struct IconSurface: ViewModifier {
    let isGlass: Bool

    func body(content: Content) -> some View {
        if isGlass {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(PressScaleStyle())
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
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            Text(title)
                .font(font)
                .foregroundStyle(tint)
                .padding(.horizontal, Theme.Space.xs)
                .frame(minHeight: Theme.Space.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
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
struct WritingLine: View {
    var placeholder: String
    @Binding var text: String
    var index: Int
    var accessibilityTitle: String
    /// Minimum height of the *field*, for prompts that want a paragraph rather
    /// than a line. It has to sit here rather than on the whole line: stretching
    /// the enclosing stack just adds space under the rule, leaving a one-line
    /// field floating above a gap. Nil sizes to the text, as before.
    var minHeight: CGFloat?
    @FocusState.Binding var focused: Int?

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
            .focused($focused, equals: index)
            .submitLabel(.next)
            .accessibilityLabel(accessibilityTitle)

            Rectangle()
                .fill(focused == index ? Theme.Palette.ember.opacity(0.55) : Theme.Palette.rule)
                .frame(height: 1)
                .animation(Theme.Motion.quick, value: focused)
        }
    }
}

// MARK: - Section heading

struct SectionHeading: View {
    var eyebrow: String?
    var title: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let eyebrow {
                Text(eyebrow).eyebrowStyle()
            }
            Text(title)
                .font(Theme.Typography.serif(26))
                .foregroundStyle(Theme.Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
