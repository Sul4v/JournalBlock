import SwiftUI

// MARK: - Name

struct NameCard: View {
    @Binding var name: String
    @FocusState.Binding var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("What should \(AppConfig.appName) call you?")
                    .font(Theme.Typography.serif(34))
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField(
                    "",
                    text: $name,
                    prompt: Text("Your name")
                        .font(Theme.Typography.serif(22))
                        .foregroundStyle(Theme.Palette.inkTertiary.opacity(0.7))
                )
                .font(Theme.Typography.serif(22))
                .foregroundStyle(Theme.Palette.ink)
                .tint(Theme.Palette.ember)
                .textContentType(.givenName)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)

                Rectangle()
                    .fill(focused ? Theme.Palette.ember.opacity(0.55) : Theme.Palette.rule)
                    .frame(height: 1)
                    .animation(Theme.Motion.quick, value: focused)
            }
            .accessibilityLabel("Your name")

            Text("Optional. It stays on your phone.")
                .font(Theme.Typography.sans(13))
                .foregroundStyle(Theme.Palette.inkTertiary)

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .pageGutter()
    }
}

// MARK: - Quiz

struct QuizCard: View {
    let question: QuizQuestion
    @Binding var answers: QuizAnswers

    var body: some View {
        // Short questions (three or four options) otherwise leave a third of
        // the screen empty. Centring the block keeps a four-option card and a
        // six-option card looking like the same app.
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    Text(question.title)
                        .font(Theme.Typography.serif(33))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 10) {
                        ForEach(question.options) { option in
                            ChoiceRow(
                                option: option,
                                isSelected: answers.has(question, option.id),
                                allowsMultiple: question.allowsMultiple
                            ) {
                                Haptics.tap()
                                withAnimation(Theme.Motion.quick) {
                                    answers.toggle(question, option.id)
                                }
                            }
                        }
                    }
                }
                .pageGutter()
                .padding(.bottom, Theme.Space.xl)
                .frame(minHeight: geo.size.height, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct ChoiceRow: View {
    let option: QuizOption
    let isSelected: Bool
    let allowsMultiple: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: option.symbol)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(isSelected ? Theme.Palette.emberDeep : Theme.Palette.inkSecondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                Text(option.label)
                    .font(Theme.Typography.serif(17))
                    .foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                // Always in the layout, faded when it has nothing to say.
                // Inserting it on selection took its width out of the label,
                // so a one-line option reflowed to two the moment it was
                // tapped and shunted every row below it down the screen —
                // the answer moving as a consequence of answering.
                Image(systemName: indicator)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.Palette.emberDeep : Theme.Palette.control)
                    .frame(width: 16)
                    .opacity(showsIndicator ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 17)
            .frame(maxWidth: .infinity, minHeight: Theme.Space.tapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .glassEffect(
            .regular
                .tint(isSelected
                      ? Theme.Palette.ember.opacity(0.18)
                      : Theme.Palette.emberSoft.opacity(0.10))
                .interactive(),
            in: .rect(cornerRadius: 20)
        )
        .animation(Theme.Motion.quick, value: isSelected)
    }

    private var indicator: String {
        if allowsMultiple {
            isSelected ? "checkmark.circle.fill" : "circle"
        } else {
            "checkmark"
        }
    }

    /// Multi-select needs an empty box to advertise that more than one is
    /// allowed. Single-select doesn't — the tap is the answer, and it advances
    /// — so its checkmark is held in the layout and hidden rather than absent.
    private var showsIndicator: Bool {
        allowsMultiple || isSelected
    }
}

// MARK: - Sleep

/// When they wake and when they turn in. Two facts, asked plainly, because
/// everything downstream was guessing at them: the plan screen named an alarm
/// time read straight off `QuizAnswers.wakeHour`'s default, and both sittings
/// opened on a hardcoded 7:00 and 21:00.
struct SleepTimeCard: View {
    let title: String
    let blurb: String
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text(title)
                    .font(Theme.Typography.serif(32))
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(blurb)
                    .font(Theme.Typography.sans(15))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GlassCard {
                DatePicker(
                    title,
                    selection: TimeBinding.make(hour: $hour, minute: $minute),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(title)
            }

            Spacer(minLength: 0)
        }
        .pageGutter()
    }
}

/// The two stored components as the `Date` a picker wants. Shared by the sleep
/// questions and the sitting screens, which had a copy each.
enum TimeBinding {
    static func make(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: hour.wrappedValue,
                    minute: minute.wrappedValue,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                let newHour = parts.hour ?? hour.wrappedValue
                let newMinute = parts.minute ?? minute.wrappedValue
                guard newHour != hour.wrappedValue || newMinute != minute.wrappedValue else { return }
                Haptics.selection()
                hour.wrappedValue = newHour
                minute.wrappedValue = newMinute
            }
        )
    }
}

// MARK: - A sitting

/// One sitting: its questions, and the time the user will answer them.
///
/// Shown twice, morning then evening. They were on one screen to begin with,
/// which fit but read as a form — two cards of someone else's decisions with a
/// grey time chip in the corner of each. Split in two, each sitting gets a
/// wheel instead of a chip, and the wheel is the screen's obvious business
/// rather than a detail in the margin of it.
struct BlockSetupCard: View {
    let session: JournalPrompt.Session
    @Binding var hour: Int
    @Binding var minute: Int

    private let template = PromptTemplate.classicFive

    private var seeds: [PromptTemplate.Seed] { template.seeds(for: session) }

    private var title: String {
        switch session {
        case .morning: "Your morning page"
        case .evening: "And a page at night"
        }
    }

    /// What the sitting costs, and nothing else. The screen below already says
    /// what the questions are and that the time is yours to set, so a sentence
    /// explaining either was the picture captioning itself.
    private var blurb: String {
        let count = seeds.count
        let questions = "\(count) question\(count == 1 ? "" : "s")"
        return "\(questions), \(template.duration(for: session).lowercased())."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(title)
                        .font(Theme.Typography.serif(32))
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(blurb)
                        .font(Theme.Typography.sans(15))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Time and questions in one card, because they are one thing.
                // The wheel had the card to itself and the questions sat bare
                // on the background underneath, which read as a footnote about
                // the sitting rather than the half of it that matters.
                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        DatePicker(
                            "\(session.label) time",
                            selection: TimeBinding.make(hour: $hour, minute: $minute),
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(session.label) time")

                        Divider()
                            .overlay(Theme.Palette.rule)
                            .padding(.bottom, Theme.Space.md)

                        Text("What you'll answer")
                            .font(Theme.Typography.sans(12, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                            .padding(.bottom, Theme.Space.sm)

                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            ForEach(Array(seeds.enumerated()), id: \.offset) { index, seed in
                                HStack(alignment: .top, spacing: Theme.Space.sm) {
                                    Text(String(format: "%02d", index + 1))
                                        .font(Theme.Typography.sans(12, weight: .medium))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.Palette.emberDeep)
                                        .padding(.top, 4)

                                    Text(seed.variant.title)
                                        .font(Theme.Typography.serif(19))
                                        .foregroundStyle(Theme.Palette.ink)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Spacer(minLength: 0)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }

                Color.clear.frame(height: Theme.Space.md)
            }
            .pageGutter()
        }
        .scrollIndicators(.hidden)
    }
}
