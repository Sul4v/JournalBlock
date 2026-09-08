import SwiftUI

/// Account creation, reached only after the quiz.
///
/// Split into two stages on purpose. The first screen offers three ways in and
/// nothing else — three fields, a strength meter and a legal paragraph all
/// competing on arrival is what makes sign-up screens feel like paperwork. The
/// email form is one tap away for the minority who want it.
struct AuthFlowView: View {
    @Environment(AuthController.self) private var auth
    @Environment(Preferences.self) private var prefs

    @State private var mode: Mode
    @State private var stage: Stage = .chooser
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?
    @State private var showResetSheet = false
    @State private var resendNote: String?
    @State private var resendCooldown = 0
    @FocusState private var focus: AuthFocus?

    enum Mode { case signUp, signIn }
    enum Stage { case chooser, email, confirm }

    /// Someone who has signed in before and then signed out is a returning
    /// user, not a new lead. Opening on "Save your plan" reads as if
    /// the app has forgotten them.
    /// Set when this was reached from the welcome screen, so the chooser can
    /// offer a way back out. Nil when auth is the only thing standing between
    /// the user and the app.
    var onBack: (() -> Void)?

    /// Set when a new account still owes us the onboarding quiz. Without this,
    /// "Create one" would quietly hand someone an account that skipped the
    /// personalisation, the plan, and the commitment — and a paywall with a
    /// generic headline.
    var onWantsSignUp: (() -> Void)?

    init(
        returning: Bool = false,
        onBack: (() -> Void)? = nil,
        onWantsSignUp: (() -> Void)? = nil
    ) {
        _mode = State(initialValue: returning ? .signIn : .signUp)
        self.onBack = onBack
        self.onWantsSignUp = onWantsSignUp
    }

    private var name: String { prefs.quizAnswers.name.trimmed }

    var body: some View {
        ZStack {
            SkyBackground(phase: .sunrise)

            VStack(spacing: 0) {
                if stage != .chooser || onBack != nil { backRow }

                if stage == .confirm {
                    confirmInbox
                } else if stage == .chooser {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        Spacer(minLength: Theme.Space.lg)
                            .frame(maxHeight: 90)

                        header
                        chooser

                        if let errorMessage {
                            AuthErrorNote(message: errorMessage)
                        }

                        switcher

                        Spacer(minLength: Theme.Space.lg)
                        legal
                    }
                    .pageGutter()
                    .padding(.bottom, Theme.Space.md)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.lg) {
                            header
                            emailForm

                            if let errorMessage {
                                AuthErrorNote(message: errorMessage)
                            }

                            switcher
                            legal
                            Color.clear.frame(height: Theme.Space.lg)
                        }
                        .pageGutter()
                        .padding(.top, Theme.Space.md)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .animation(Theme.Motion.quick, value: errorMessage)
        .animation(Theme.Motion.settle, value: mode)
        .animation(Theme.Motion.settle, value: stage)
        .sheet(isPresented: $showResetSheet) {
            PasswordResetView(initialEmail: email)
                .presentationDetents([.height(340)])
                .presentationBackground(Theme.Palette.surfaceRaised)
        }
    }

    // MARK: - Chrome

    private var backRow: some View {
        HStack {
            IconButton(systemName: "chevron.left", accessibilityTitle: "Back") {
                focus = nil
                errorMessage = nil
                // From the email form, back means the chooser. From the
                // chooser, it means out of auth entirely.
                if stage == .chooser { onBack?() } else { stage = .chooser }
            }
            Spacer()
        }
        .pageGutter()
        .padding(.top, Theme.Space.sm)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(headline)
                .font(Theme.Typography.serif(32))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.sans(15))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headline: String {
        switch (stage, mode) {
        case (.email, .signUp): "Create your account"
        case (.email, .signIn): "Sign in with email"
        case (_, .signIn): "Welcome back"
        case (_, .signUp): name.isEmpty ? "Save your plan" : "Save \(name)'s plan"
        }
    }

    /// Honest about what the account actually does today: journal entries are
    /// still device-local, so this promises only what's true.
    private var subtitle: String? {
        guard stage == .chooser else { return nil }
        return mode == .signUp
            ? "Your subscription follows you to any phone."
            : "Pick up where you left off."
    }

    // MARK: - Stage one

    private var chooser: some View {
        VStack(spacing: Theme.Space.sm) {
            // "Continue with" across all three: the three buttons do the same
            // thing from the user's side, and Apple lists it as an approved
            // label alongside "Sign in with".
            AuthProviderButton(title: "Continue with Apple") {
                Image(systemName: "apple.logo")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
            } action: {
                Task {
                    do {
                        errorMessage = nil
                        try await auth.signInWithApple()
                    } catch {
                        errorMessage = error.localizedDescription
                        Haptics.warning()
                    }
                }
            }
            .disabled(auth.isWorking)

            if auth.canUseGoogle {
                AuthProviderButton(title: "Continue with Google") {
                    // The mark keeps its own colours; it's the one part of
                    // these buttons that isn't ours to restyle.
                    Image(.googleMark)
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                } action: {
                    Task {
                        do {
                            errorMessage = nil
                            try await auth.signInWithGoogle()
                        } catch {
                            errorMessage = error.localizedDescription
                            Haptics.warning()
                        }
                    }
                }
                .disabled(auth.isWorking)
            }

            AuthProviderButton(title: "Continue with email") {
                Image(systemName: "envelope")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
            } action: {
                stage = .email
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus = .email }
            }
        }
    }

    // MARK: - Waiting on the emailed link

    /// Sign-up with confirmation enabled leaves the account dormant. Dropping
    /// the user back on the form with a red error reads as "it failed" when it
    /// actually succeeded — so this is its own screen.
    private var confirmInbox: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Spacer(minLength: Theme.Space.lg).frame(maxHeight: 80)

            Image(systemName: "envelope.badge")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(Theme.Palette.ember)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Confirm your email")
                    .font(Theme.Typography.serif(32))
                    .foregroundStyle(Theme.Palette.ink)
                Text("We sent a link to \(email.trimmed). Tap it and this app will open, already signed in.")
                    .font(Theme.Typography.sans(15))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let resendNote {
                Text(resendNote)
                    .font(Theme.Typography.sans(13))
                    .foregroundStyle(Theme.Palette.ember)
                    .transition(.opacity)
            }

            VStack(spacing: Theme.Space.sm) {
                // Fallback for anyone who opens the link on a different
                // device, where the deep link can't reach this phone.
                EmberButton(title: "Sign in instead") {
                    withAnimation(Theme.Motion.settle) {
                        mode = .signIn
                        stage = .email
                        password = ""
                        confirmation = ""
                        resendNote = nil
                    }
                }

                GhostButton(
                    title: resendCooldown > 0
                        ? "Resend in \(resendCooldown)s"
                        : "Resend the link",
                    systemImage: "arrow.clockwise"
                ) {
                    guard resendCooldown == 0 else { return }
                    resend()
                }
                .disabled(resendCooldown > 0)
                .opacity(resendCooldown > 0 ? 0.5 : 1)
            }
            .padding(.top, Theme.Space.xs)

            Spacer(minLength: Theme.Space.lg)
            legal
        }
        .pageGutter()
        .padding(.bottom, Theme.Space.md)
    }

    /// Supabase rate-limits confirmation emails, so a visible cooldown is
    /// kinder than letting an impatient tap return a raw 429.
    private func resend() {
        Task {
            do {
                try await auth.resendConfirmation(to: email)
                withAnimation(Theme.Motion.quick) {
                    resendNote = "Sent again. Give it a minute to arrive."
                }
            } catch {
                withAnimation(Theme.Motion.quick) {
                    resendNote = error.localizedDescription
                }
            }
            resendCooldown = 60
            while resendCooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendCooldown -= 1
            }
        }
    }

    // MARK: - Stage two

    private var emailForm: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            AuthField(
                label: "Email",
                placeholder: "you@example.com",
                text: $email,
                contentType: .emailAddress,
                keyboard: .emailAddress,
                focus: $focus,
                field: .email,
                onSubmit: { focus = .password }
            )

            AuthField(
                label: "Password",
                placeholder: mode == .signUp
                    ? "At least \(CredentialRules.minimumPasswordLength) characters"
                    : "Your password",
                text: $password,
                isSecure: true,
                contentType: mode == .signUp ? .newPassword : .password,
                submitLabel: mode == .signUp ? .next : .go,
                focus: $focus,
                field: .password,
                onSubmit: { mode == .signUp ? (focus = .confirmation) : submit() }
            )

            if mode == .signUp {
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
                .transition(.opacity)
            }

            if mode == .signIn {
                Button("Forgot password?") { showResetSheet = true }
                    .font(Theme.Typography.sans(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.ember)
                    .buttonStyle(.plain)
            }

            EmberButton(
                title: auth.isWorking
                    ? (mode == .signUp ? "Creating account…" : "Signing in…")
                    : (mode == .signUp ? "Create account" : "Sign in"),
                isEnabled: canSubmit,
                action: submit
            )
            .padding(.top, Theme.Space.xs)
        }
    }

    // MARK: - Shared

    /// Asymmetric on purpose. Signing in is just this form under another
    /// title, so that direction flips in place. Creating an account is a
    /// journey that starts with the quiz, so that direction can only hand off
    /// to the caller — there is deliberately no path that retitles the sign-in
    /// form into a sign-up form.
    private var switcher: some View {
        HStack(spacing: 4) {
            Spacer()
            if mode == .signUp {
                Text("Already have an account?")
                    .font(Theme.Typography.sans(14))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                switchButton("Sign in") {
                    withAnimation(Theme.Motion.settle) {
                        mode = .signIn
                        errorMessage = nil
                        confirmation = ""
                    }
                }
            } else if let onWantsSignUp {
                Text("New to \(AppConfig.appName)?")
                    .font(Theme.Typography.sans(14))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                switchButton("Create one") { onWantsSignUp() }
            }
            Spacer()
        }
    }

    private func switchButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            Haptics.tap(.light)
            action()
        }
        .font(Theme.Typography.sans(14, weight: .semibold))
        .foregroundStyle(Theme.Palette.ember)
        .buttonStyle(.plain)
    }

    private var legal: some View {
        VStack(spacing: 6) {
            Text("By continuing you agree to our [Terms](\(AppConfig.termsURL)) and [Privacy Policy](\(AppConfig.privacyURL)).")
                .font(Theme.Typography.sans(11))
                .foregroundStyle(Theme.Palette.inkTertiary)
                .tint(Theme.Palette.inkSecondary)

            #if DEBUG
            if auth.usesLocalBackend {
                Text("DEBUG · local stand-in, no Supabase keys configured")
                    .font(Theme.Typography.sans(10))
                    .foregroundStyle(Theme.Palette.inkTertiary.opacity(0.7))
            }
            #endif
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private var canSubmit: Bool {
        guard !auth.isWorking, !email.trimmed.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp { return !confirmation.isEmpty }
        return true
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        Task {
            do {
                errorMessage = nil
                if mode == .signUp {
                    let needsConfirmation = try await auth.signUp(
                        email: email, password: password, confirmation: confirmation
                    )
                    if needsConfirmation {
                        Haptics.success()
                        withAnimation(Theme.Motion.settle) { stage = .confirm }
                    }
                } else {
                    try await auth.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
                Haptics.warning()
            }
        }
    }
}

// MARK: - Google button

/// Google's brand guidelines want their mark, their wording, and one of their
/// two approved surfaces — the light one on light, the dark one on dark. The
/// exact values are Google's, not Dawn's, which is why they are literals here
/// rather than palette entries. Everything else matches Dawn's buttons so the
/// row reads as one set.
/// The three ways in, styled as one set: same glass, same height, same label
/// font. Only the leading mark changes.
private struct AuthProviderButton<Icon: View>: View {
    let title: String
    @ViewBuilder var icon: Icon
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                icon
                Text(title)
                    .font(Theme.Typography.sans(16, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Password reset

struct PasswordResetView: View {
    @Environment(AuthController.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let initialEmail: String
    @State private var email: String
    @State private var message: String?
    @State private var sent = false
    @FocusState private var focus: AuthFocus?

    init(initialEmail: String) {
        self.initialEmail = initialEmail
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Reset password")
                .font(Theme.Typography.serif(26))
                .foregroundStyle(Theme.Palette.ink)

            if sent {
                Text("If there's an account for \(email.trimmed), a reset link is on its way.")
                    .font(Theme.Typography.sans(15))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                EmberButton(title: "Done") { dismiss() }
            } else {
                Text("We'll email you a link to set a new one.")
                    .font(Theme.Typography.sans(15))
                    .foregroundStyle(Theme.Palette.inkSecondary)

                AuthField(
                    label: "Email",
                    placeholder: "you@example.com",
                    text: $email,
                    contentType: .emailAddress,
                    keyboard: .emailAddress,
                    submitLabel: .go,
                    focus: $focus,
                    field: .email,
                    onSubmit: send
                )

                if let message {
                    AuthErrorNote(message: message)
                }

                Spacer()

                EmberButton(
                    title: auth.isWorking ? "Sending…" : "Send link",
                    isEnabled: !email.trimmed.isEmpty && !auth.isWorking,
                    action: send
                )
            }
        }
        .pageGutter()
        .padding(.top, Theme.Space.lg)
        .padding(.bottom, Theme.Space.md)
        // Matches the sheet's presentationBackground; painting `canvas`
        // here would cover it and flatten the sheet against the app.
        .background(Theme.Palette.surfaceRaised)
        .onAppear { if email.isEmpty { focus = .email } }
    }

    private func send() {
        Task {
            do {
                message = nil
                try await auth.sendPasswordReset(to: email)
                withAnimation(Theme.Motion.settle) { sent = true }
                Haptics.success()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
