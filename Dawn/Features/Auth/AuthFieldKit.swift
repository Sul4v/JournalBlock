import SwiftUI

/// Underlined text field matching the journal's writing lines, so the account
/// screens feel like the same app rather than a bolted-on form.
struct AuthField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .next
    @FocusState.Binding var focus: AuthFocus?
    let field: AuthFocus
    var onSubmit: () -> Void = {}

    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).eyebrowStyle()

            HStack(spacing: Theme.Space.sm) {
                Group {
                    if isSecure && !isRevealed {
                        SecureField("", text: $text, prompt: promptText)
                    } else {
                        TextField("", text: $text, prompt: promptText)
                    }
                }
                .font(Theme.Typography.serif(20))
                .foregroundStyle(Theme.Palette.ink)
                .tint(Theme.Palette.ember)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .focused($focus, equals: field)
                .onSubmit(onSubmit)
                .accessibilityLabel(label)

                if isSecure {
                    Button {
                        isRevealed.toggle()
                        Haptics.tap(.light)
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .tappable()
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
                }
            }

            Rectangle()
                .fill(focus == field ? Theme.Palette.ember.opacity(0.55) : Theme.Palette.rule)
                .frame(height: 1)
                .animation(Theme.Motion.quick, value: focus)
        }
    }

    private var promptText: Text {
        Text(placeholder).foregroundStyle(Theme.Palette.inkTertiary)
    }
}

enum AuthFocus: Hashable {
    case email, password, confirmation
}

/// Inline error banner. Sits under the fields rather than in an alert — a modal
/// for a typo'd password is a good way to lose someone.
struct AuthErrorNote: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13))
            Text(message)
                .font(Theme.Typography.sans(13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.Palette.danger)
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Palette.danger.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .transition(.opacity)
    }
}

/// Password strength meter shown only on sign-up.
struct StrengthMeter: View {
    let password: String

    private var score: Double { CredentialRules.strength(of: password) }

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.rule)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * score)
                }
            }
            .frame(height: 3)

            Text(CredentialRules.strengthLabel(score))
                .font(Theme.Typography.sans(11, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 62, alignment: .trailing)
        }
        .animation(Theme.Motion.quick, value: score)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Password strength")
        .accessibilityValue(CredentialRules.strengthLabel(score))
    }

    private var color: Color {
        switch score {
        case ..<0.4: Theme.Palette.inkTertiary
        case ..<0.7: Theme.Palette.emberDeep
        default: Theme.Palette.emberDeep
        }
    }
}
