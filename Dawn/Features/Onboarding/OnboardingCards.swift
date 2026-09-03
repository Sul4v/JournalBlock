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
    /// Single-choice questions advance on tap — an extra Continue press per
    /// question is pure friction across a seven-question flow.
    var onAutoAdvance: () -> Void

    var body: some View {
        // Short questions (three or four options) left a third of the screen
        // empty with no Continue button to anchor it. Centring the block keeps
        // a four-option card and a six-option card looking like the same app.
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(question.title)
                            .font(Theme.Typography.serif(33))
                            .foregroundStyle(Theme.Palette.ink)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let hint = question.hint {
                            Text(hint)
                                .font(Theme.Typography.sans(14))
                                .foregroundStyle(Theme.Palette.inkTertiary)
                        }
                    }

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
                                if !question.allowsMultiple {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                        onAutoAdvance()
                                    }
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

                if let indicator {
                    Image(systemName: indicator)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(isSelected ? Theme.Palette.emberDeep : Theme.Palette.control)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
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

    /// Multi-select needs an empty box to advertise that more than one is
    /// allowed. Single-select doesn't — the tap is the answer, and it advances.
    private var indicator: String? {
        if allowsMultiple {
            isSelected ? "checkmark.circle.fill" : "circle"
        } else {
            isSelected ? "checkmark" : nil
        }
    }
}

// MARK: - Journal time

struct WakeTimeCard: View {
    @Binding var hour: Int
    @Binding var minute: Int

    private var date: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                let newHour = parts.hour ?? 7
                let newMinute = parts.minute ?? 0
                if newHour != hour || newMinute != minute { Haptics.selection() }
                hour = newHour
                minute = newMinute
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("When do you want to journal?")
                    .font(Theme.Typography.serif(30))
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GlassCard {
                DatePicker("Journal time", selection: date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Journal time")
            }

            Text("\(AppConfig.appName) can wake you then and hand you the page.")
                .font(Theme.Typography.sans(13))
                .foregroundStyle(Theme.Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .pageGutter()
    }
}
