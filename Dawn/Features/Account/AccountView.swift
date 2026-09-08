import SwiftUI
import StoreKit

/// Account, subscription, and the two exits Apple requires you to offer:
/// sign out, and permanent deletion.
struct AccountView: View {
    @Environment(AuthController.self) private var auth
    @Environment(SubscriptionController.self) private var subs
    @Environment(BackupController.self) private var backup
    @Environment(Preferences.self) private var prefs
    @Environment(\.journalStore) private var store
    @Environment(\.openURL) private var openURL

    @State private var showSignOutConfirm = false
    @State private var showDelete = false
    @State private var showPaywall = false
    @State private var message: String?
    @State private var isRestoring = false

    var body: some View {
        ZStack {
            SkyBackground(phase: DayPhase.current(), intensity: 0.55)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    identity
                    subscription
                    if let message {
                        AuthErrorNote(message: message)
                    }
                    exits
                    deleteAccount
                    Color.clear.frame(height: Theme.Space.xl)
                }
                .pageGutter()
                .padding(.top, Theme.Space.sm)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Account")
                    .font(Theme.Typography.serif(17, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
            }
        }
        .animation(Theme.Motion.quick, value: message)
        .sheet(isPresented: $showDelete) {
            DeleteAccountView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(isDismissible: true)
        }
        // An alert rather than a confirmation dialog: attached to the full-screen
        // ZStack, the dialog renders as a popover anchored to the container and
        // lands over the subscription card instead of centred.
        .alert("Sign out of \(AppConfig.appName)?", isPresented: $showSignOutConfirm) {
            Button("Sign out", role: .destructive) {
                Task { await auth.signOut() }
            }
            Button("Stay signed in", role: .cancel) {}
        } message: {
            // The unbacked-up case is genuinely riskier now that signing in as
            // somebody else on this phone erases what's here, so it says so
            // rather than giving everyone the same reassuring line.
            Text(backup.status == .ready
                 ? "Your journal stays on this phone and it's backed up. You'll need your password to get back in."
                 : "Your journal isn't backed up — it exists only on this phone. Signing in with a different account here would erase it.")
        }
        .task { await subs.refreshStatus() }
    }

    // MARK: - Sections

    /// The person's own name, if we actually have one — from the account
    /// first, then whatever they typed into onboarding.
    private var personName: String? {
        if let name = auth.user?.displayName?.trimmed, !name.isEmpty { return name }
        let local = prefs.displayName.trimmed
        return local.isEmpty ? nil : local
    }

    private var identity: some View {
        GlassCard {
            HStack(spacing: Theme.Space.md) {
                Text(auth.user?.initials ?? "·")
                    .font(Theme.Typography.sans(18, weight: .medium))
                    .foregroundStyle(Theme.Palette.canvas)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Theme.Palette.ink.opacity(0.85)))

                VStack(alignment: .leading, spacing: 3) {
                    // No name to show means no line: a placeholder that just
                    // says "Your account" under a screen titled Account is
                    // filler, and the email identifies you better anyway.
                    if let personName {
                        Text(personName)
                            .font(Theme.Typography.serif(20))
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    Text(auth.user?.email ?? "Not signed in")
                        .font(personName == nil
                              ? Theme.Typography.sans(15, weight: .medium)
                              : Theme.Typography.sans(13))
                        .foregroundStyle(personName == nil ? Theme.Palette.ink : Theme.Palette.inkTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let since = auth.user?.createdAt {
                        Text("Member since \(since.formatted(.dateTime.month(.wide).year()))")
                            .font(Theme.Typography.sans(11))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var subscription: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeading(title: "Subscription")

            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(statusTitle)
                                .font(Theme.Typography.sans(16, weight: .semibold))
                                .foregroundStyle(Theme.Palette.ink)
                            Text(statusDetail)
                                .font(Theme.Typography.sans(13))
                                .foregroundStyle(Theme.Palette.inkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if subs.isSubscribed {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.Palette.emberDeep)
                                .accessibilityHidden(true)
                        }
                    }

                    Divider().overlay(Theme.Palette.rule)

                    // One filled action and one quiet one. Two identical
                    // capsules side by side gave equal weight to the thing the
                    // user came for and the thing they need once a year, and
                    // left a ragged gap where the row ran out of buttons.
                    HStack(spacing: Theme.Space.sm) {
                        if subs.isSubscribed {
                            GhostButton(title: "Manage",
                                        systemImage: "creditcard",
                                        isNested: true,
                                        emphasis: .prominent) {
                                // The App Store is the only place a subscription
                                // can actually be changed or cancelled.
                                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                    openURL(url)
                                }
                            }
                        } else {
                            GhostButton(title: "See plans",
                                        systemImage: "sparkles",
                                        isNested: true,
                                        emphasis: .prominent) {
                                showPaywall = true
                            }
                        }

                        Spacer(minLength: Theme.Space.xs)

                        TextButton(title: "Restore",
                                   font: Theme.Typography.sans(14, weight: .medium),
                                   isLoading: isRestoring) {
                            restorePurchases()
                        }
                    }
                }
            }
        }
    }

    private func restorePurchases() {
        guard !isRestoring else { return }
        Task {
            isRestoring = true
            defer { isRestoring = false }
            do {
                message = nil
                try await subs.restore()
                Haptics.success()
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private var statusTitle: String {
        switch subs.status {
        case .subscribed: "\(AppConfig.appName) \(AppConfig.tierName)"
        case .notSubscribed: "No active subscription"
        case .unknown: "Checking…"
        }
    }

    private var statusDetail: String {
        switch subs.status {
        case let .subscribed(expires, willRenew, _):
            guard let expires else { return "Active." }
            let date = expires.formatted(.dateTime.day().month(.wide).year())
            return willRenew ? "Renews \(date)." : "Access until \(date), then it ends."
        case .notSubscribed:
            return "\(AppConfig.appName) needs an active subscription to open."
        case .unknown:
            return "Confirming with the App Store."
        }
    }

    private var exits: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeading(title: "Leaving")

            GlassCard(tint: Theme.Palette.ink.opacity(0.04)) {
                Button {
                    Haptics.tap()
                    showSignOutConfirm = true
                } label: {
                    row(icon: "rectangle.portrait.and.arrow.right",
                        title: "Sign out",
                        detail: "Your journal stays on this phone.",
                        tint: Theme.Palette.ink)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Deletion is the last thing on the page and the quietest thing on it:
    /// findable when you're looking for it, never in the way when you aren't.
    private var deleteAccount: some View {
        Button {
            // Opening the screen isn't the destructive act — the warning
            // haptic belongs on a failed deletion, not on a navigation.
            // Firing it here trains people to ignore it.
            Haptics.tap(.light)
            showDelete = true
        } label: {
            Text("Delete account")
                .font(Theme.Typography.sans(13))
                .foregroundStyle(Theme.Palette.inkTertiary.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.Space.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.sans(16, weight: .medium))
                    .foregroundStyle(tint)
                Text(detail)
                    .font(Theme.Typography.sans(12))
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkTertiary)
        }
        .frame(minHeight: Theme.Space.tapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
