import SwiftUI

/// Shown after a password-reset link lands in the app. The user already has a
/// session at this point, so this is the one screen that must not be
/// dismissable — leaving it half-done would strand them signed in with a
/// password they've forgotten.
struct NewPasswordView: View {
    @Environment(AuthController.self) private var auth

    @State private var password = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?
    @FocusState private var focus: AuthFocus?

    private var canSubmit: Bool {
        !auth.isWorking && !password.isEmpty && !confirmation.isEmpty
    }

    var body: some View {
        ZStack {
            SkyBackground(phase: .sunrise)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Text("Set a new password")
                            .font(Theme.Typography.serif(32))
                            .foregroundStyle(Theme.Palette.ink)
                        Text("You're signed in. Choose a password you'll remember this time.")
                            .font(Theme.Typography.sans(15))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    AuthField(
                        label: "New password",
                        placeholder: "At least \(CredentialRules.minimumPasswordLength) characters",
                        text: $password,
                        isSecure: true,
                        contentType: .newPassword,
                        focus: $focus,
                        field: .password,
                        onSubmit: { focus = .confirmation }
                    )

                    if !password.isEmpty {
                        StrengthMeter(password: password)
                            .transition(.opacity)
                    }

                    AuthField(
                        label: "Confirm password",
                        placeholder: "Type it again",
                        text: $confirmation,
                        isSecure: true,
                        contentType: .newPassword,
                        submitLabel: .go,
                        focus: $focus,
                        field: .confirmation,
                        onSubmit: submit
                    )

                    if let errorMessage {
                        AuthErrorNote(message: errorMessage)
                    }

                    EmberButton(
                        title: auth.isWorking ? "Saving…" : "Save password",
                        isEnabled: canSubmit,
                        action: submit
                    )
                    .padding(.top, Theme.Space.xs)

                    Color.clear.frame(height: Theme.Space.lg)
                }
                .pageGutter()
                .padding(.top, Theme.Space.xxl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(Theme.Motion.quick, value: errorMessage)
        .animation(Theme.Motion.quick, value: password.isEmpty)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus = .password }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        guard password == confirmation else {
            errorMessage = AuthFailure.passwordsDontMatch.errorDescription
            Haptics.warning()
            return
        }
        focus = nil
        Task {
            do {
                errorMessage = nil
                try await auth.updatePassword(password)
                Haptics.success()
            } catch {
                errorMessage = error.localizedDescription
                Haptics.warning()
            }
        }
    }
}
