import SwiftUI

/// Shows a recovery phrase exactly once.
///
/// There is no "show it to me again" anywhere in the app, because we keep no
/// copy that could be shown. The dismiss button is gated behind an explicit
/// acknowledgement for that reason — this is the one screen where friction is
/// the feature.
struct RecoveryPhraseSheet: View {
    let phrase: String

    @Environment(\.dismiss) private var dismiss
    @State private var hasSaved = false
    @State private var didCopy = false

    private var words: [String] { RecoveryPhrase.words(in: phrase) }

    var body: some View {
        ZStack {
            SkyBackground(phase: DayPhase.current(), intensity: 0.55)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    SectionHeading(eyebrow: "Keep these safe", title: "Your recovery phrase")

                    Text("These twelve words are the only thing that can unlock your journal on a new phone. We don't have a copy, so we can't send them to you again or reset them for you.")
                        .font(Theme.Typography.sans(15))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    phraseCard
                    warning

                    Toggle(isOn: $hasSaved) {
                        Text("I've saved these somewhere safe")
                            .font(Theme.Typography.sans(14))
                            .foregroundStyle(Theme.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tint(Theme.Palette.ember)

                    EmberButton(title: "Done", isEnabled: hasSaved) { dismiss() }

                    Color.clear.frame(height: Theme.Space.md)
                }
                .pageGutter()
                .padding(.top, Theme.Space.lg)
            }
            .scrollIndicators(.hidden)
        }
        // Swiping this away by accident would lose the phrase silently.
        .interactiveDismissDisabled(!hasSaved)
        .animation(Theme.Motion.quick, value: hasSaved)
        .animation(Theme.Motion.quick, value: didCopy)
    }

    private var phraseCard: some View {
        GlassCard(tint: Theme.Palette.emberSoft.opacity(0.34)) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                // Numbered, because order is part of the secret and a phrase
                // written down out of order is as useless as a wrong one.
                grid

                GhostButton(
                    title: didCopy ? "Copied" : "Copy phrase",
                    systemImage: didCopy ? "checkmark" : "doc.on.doc",
                    isNested: true
                ) {
                    UIPasteboard.general.string = phrase
                    didCopy = true
                    Haptics.success()
                }
            }
        }
    }

    private var grid: some View {
        // Two fixed columns rather than adaptive. The grid fills across, so
        // it reads 1,2 / 3,4 / 5,6 — which is why every word carries its
        // number: an adaptive column count would reflow at larger text sizes
        // and silently change the reading order of a phrase where order is
        // the whole secret.
        LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading),
                      GridItem(.flexible(), alignment: .leading)],
            alignment: .leading,
            spacing: Theme.Space.sm
        ) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1)")
                        .font(Theme.Typography.sans(12))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        .frame(minWidth: 16, alignment: .trailing)
                    Text(word)
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer(minLength: 0)
                }
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery phrase")
        // Read as "one, harbor. two, lesson." so it can be transcribed by ear.
        .accessibilityValue(
            words.enumerated()
                .map { "\($0.offset + 1), \($0.element)" }
                .joined(separator: ". ")
        )
    }

    private var warning: some View {
        HStack(alignment: .center, spacing: Theme.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .accessibilityHidden(true)
            Text("Lose these words and lose this phone, and your backed-up entries are gone for good. That's what keeps them private.")
                .font(Theme.Typography.sans(13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.Palette.emberDeep)
        .padding(Theme.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Palette.gold.opacity(0.14))
        )
        .accessibilityElement(children: .combine)
    }
}
