import SwiftUI

/// The one screen where the encrypted backup is explained, switched on, and
/// unlocked on a new device.
///
/// The copy here is doing real work. A user who skims this screen and loses
/// their recovery phrase loses their journal, so the warnings are deliberately
/// not softened into marketing language.
struct BackupView: View {
    @Environment(AuthController.self) private var auth
    @Environment(BackupController.self) private var backup
    @Environment(\.journalStore) private var store

    @State private var recoveryPhrase: RecoveryPhraseToken?
    @State private var showUnlock = false
    @State private var showRotateConfirm = false
    @State private var showStartOverConfirm = false
    @State private var showForgetConfirm = false
    @State private var showNoCloudPrompt = false
    @State private var showGetPhraseConfirm = false
    /// Collapsed by default: reassurance you can go and read, not a wall of it
    /// between the user and the thing they came to this screen to do.
    @State private var showsProtection = false
    @State private var message: String?

    var body: some View {
        ZStack {
            SkyBackground(phase: DayPhase.current(), intensity: 0.55)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    statusSection
                    if let message {
                        AuthErrorNote(message: message)
                    }
                    explainer
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
                Text("Backup")
                    .font(Theme.Typography.serif(17, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
            }
        }
        .animation(Theme.Motion.quick, value: message)
        .animation(Theme.Motion.quick, value: backup.status)
        .sheet(item: $recoveryPhrase) { token in
            RecoveryPhraseSheet(phrase: token.phrase)
        }
        .sheet(isPresented: $showUnlock) {
            UnlockBackupSheet()
        }
        .alert("Get a recovery phrase?", isPresented: $showGetPhraseConfirm) {
            Button("Get phrase") {
                Task { await rotate() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Twelve words that unlock your journal on a phone that doesn't have your key — if you leave iCloud Keychain, or move to a phone that isn't an iPhone. Save them somewhere safe. We can't show you the same words twice, though you can always get a fresh set.")
        }
        .alert("This phone isn't signed into iCloud", isPresented: $showNoCloudPrompt) {
            Button("Save a phrase") {
                Task { await rotate() }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Backup is on. But without iCloud, your key can't travel to a new phone by itself — a recovery phrase would be the only way to get your journal back. It's twelve words, and you can save them now or from this screen any time.")
        }
        .alert("Stop syncing on this device?", isPresented: $showForgetConfirm) {
            Button("Stop syncing", role: .destructive) {
                backup.forgetKeyOnThisDevice()
                Haptics.warning()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This phone stops backing up and won't download entries from your other devices. Everything already written here stays on the phone and stays readable. Your backup is untouched — your twelve words reconnect it. Because the key syncs, this affects your other Apple devices too.")
        }
        .alert("Start a new backup?", isPresented: $showStartOverConfirm) {
            Button("Delete backup and start over", role: .destructive) {
                Task { await startOver() }
            }
            Button("Keep trying", role: .cancel) {}
        } message: {
            Text("Everything already backed up will be deleted for good. Without your phrase nobody can read it — not you, not us — so there's nothing left to recover. Anything still on this phone is kept and backed up again.")
        }
        // An alert rather than a confirmation dialog: attached to the full-screen
        // ZStack, the dialog renders as a popover anchored to the container and
        // lands over the explainer card instead of centred.
        .alert("Get a new recovery phrase?", isPresented: $showRotateConfirm) {
            Button("Get a new phrase") {
                Task { await rotate() }
            }
            Button("Keep the old one", role: .cancel) {}
        } message: {
            Text("Your old recovery phrase stops working straight away. Your entries aren't affected.")
        }
        .task { await backup.refresh(for: auth.user) }
    }

    // MARK: - Sections

    private var explainer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Button {
                Haptics.tap(.light)
                withAnimation(Theme.Motion.quick) { showsProtection.toggle() }
            } label: {
                HStack(spacing: Theme.Space.xs) {
                    Text("Is my data private?")
                        .font(Theme.Typography.sans(15, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        .rotationEffect(.degrees(showsProtection ? 180 : 0))
                }
                // Width claimed here rather than with a trailing Spacer, so the
                // row is fully tappable without the label fighting for space.
                .frame(maxWidth: .infinity, minHeight: Theme.Space.tapTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(showsProtection ? "Hides how your journal is protected" : "Shows how your journal is protected")

            if showsProtection {
                GlassCard {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    point(
                        icon: "lock.fill",
                        text: "Encrypted on this phone before it leaves."
                    )
                    point(
                        icon: "eye.slash.fill",
                        text: "We only ever store the locked version."
                    )
                    point(
                        icon: "key.fill",
                        text: "The key stays on your devices, never on our servers."
                    )
                }
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch backup.status {
        case .unavailable:
            unavailableCard
        case .needsSetup:
            setupCard
        case .locked:
            lockedCard
        case .ready:
            readyCard
        }
    }

    private var unavailableCard: some View {
        GlassCard(tint: Theme.Palette.ink.opacity(0.04)) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text(auth.isSignedIn ? "Can't reach backup" : "Sign in to back up")
                    .font(Theme.Typography.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(auth.isSignedIn
                     ? "We couldn't check your backup just now. Your journal is safe on this phone either way."
                     : "Backup is tied to your account, so there's something to restore from on a new phone.")
                    .font(Theme.Typography.sans(13))
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if auth.isSignedIn {
                    GhostButton(title: "Try again", systemImage: "arrow.clockwise", isNested: true) {
                        Task { await backup.refresh(for: auth.user) }
                    }
                }
            }
        }
    }

    private var setupCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backup is off")
                        .font(Theme.Typography.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("One tap. Restores itself on your next iPhone.")
                        .font(Theme.Typography.sans(13))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                EmberButton(title: "Turn on backup", systemImage: "lock.shield", isEnabled: !backup.isWorking) {
                    Task { await enable() }
                }
            }
        }
    }

    private var lockedCard: some View {
        GlassCard(tint: Theme.Palette.gold.opacity(0.16)) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backup is locked")
                        .font(Theme.Typography.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("This account has a backup, but this phone doesn't have the key yet. Anything you write stays on this phone and won't be backed up until you unlock it.")
                        .font(Theme.Typography.sans(13))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                EmberButton(title: "Enter recovery phrase", systemImage: "key") {
                    showUnlock = true
                }

                // Deliberately quiet, and deliberately present. Someone who has
                // genuinely lost their phrase is otherwise stuck for good: they
                // can't unlock, and they can't start a new backup either.
                // Spacers rather than a full-width frame: centred, but the tap
                // target stays on the words. This one starts a destructive
                // flow, so a wide invisible hit area would be a trap.
                HStack {
                    Spacer(minLength: 0)
                    TextButton(title: "I've lost my phrase") {
                        showStartOverConfirm = true
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var readyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Backup is on")
                            .font(Theme.Typography.sans(16, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        Text(syncDetail)
                            .font(Theme.Typography.sans(13))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Palette.emberDeep)
                        .accessibilityHidden(true)
                }

                Divider().overlay(Theme.Palette.rule)

                HStack(spacing: Theme.Space.sm) {
                    GhostButton(
                        title: backup.isWorking ? "Syncing…" : "Sync now",
                        systemImage: "arrow.triangle.2.circlepath",
                        isNested: true
                    ) {
                        Task { await syncNow() }
                    }

                    GhostButton(
                        title: backup.hasIssuedPhrase ? "New phrase" : "Get a phrase",
                        systemImage: "key",
                        isNested: true
                    ) {
                        // Two different conversations. Replacing a phrase is a
                        // warning — the old one stops working. Getting a first
                        // one isn't dangerous at all, but it does need
                        // explaining: nobody should be handed twelve words to
                        // guard without being told what they're for.
                        if backup.hasIssuedPhrase {
                            showRotateConfirm = true
                        } else {
                            showGetPhraseConfirm = true
                        }
                    }
                    Spacer(minLength: 0)
                }

                if !backup.hasIssuedPhrase {
                    Divider().overlay(Theme.Palette.rule)
                    Text(CloudAccount.isSignedIn
                         ? "Your journal restores itself on a new iPhone. A phrase is only needed if you leave iCloud Keychain."
                         : "Without iCloud, a recovery phrase is the only way to restore your journal.")
                        .font(Theme.Typography.sans(12))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // A sync control, not a privacy one: the journal on this phone
                // stays in plain SwiftData either way, so this protects nothing
                // on a device someone else ends up holding. Deleting the app is
                // what removes the local copy.
                HStack {
                    Spacer(minLength: 0)
                    TextButton(title: "Stop syncing on this device") {
                        showForgetConfirm = true
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var syncDetail: String {
        guard let last = backup.lastSyncedAt else {
            return "Your entries sync when you finish writing."
        }
        return "Last synced \(last.formatted(.relative(presentation: .named)))."
    }

    private func point(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.emberDeep)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.sans(14))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                // Claim the width outright instead of leaving a trailing
                // Spacer to fight over it. Both are flexible, so the HStack was
                // handing the text less than the row's full width and each
                // bullet wrapped at a different, arbitrary point.
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func enable() async {
        do {
            message = nil
            try await backup.enable()
            Haptics.success()
            try? await backup.sync(store: store)
            // Everyone else's key rides iCloud Keychain to their next phone and
            // they never need to think about this. Without an iCloud account it
            // can't, and a phrase is the only way back — so say so here rather
            // than letting them find out when the phone is already gone.
            if !CloudAccount.isSignedIn { showNoCloudPrompt = true }
        } catch {
            message = error.localizedDescription
        }
    }

    /// For a phrase that was mislaid rather than leaked. Only possible from a
    /// device that can already read the backup — there is no way to reissue a
    /// phrase to someone locked out, by design.
    /// The last resort, for a phrase that is genuinely gone. See
    /// `BackupController.startOver` for why this deletes rather than re-keys.
    private func startOver() async {
        do {
            message = nil
            let phrase = try await backup.startOver()
            Haptics.success()
            recoveryPhrase = RecoveryPhraseToken(phrase: phrase)
            // Push whatever this device still holds under the new key.
            try? await backup.sync(store: store)
        } catch {
            message = error.localizedDescription
        }
    }

    private func rotate() async {
        do {
            message = nil
            let phrase = try await backup.regenerateRecoveryPhrase()
            Haptics.success()
            recoveryPhrase = RecoveryPhraseToken(phrase: phrase)
        } catch {
            message = error.localizedDescription
        }
    }

    private func syncNow() async {
        do {
            message = nil
            try await backup.sync(store: store)
            Haptics.success()
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Wraps the recovery phrase so it can drive `.sheet(item:)`.
///
/// A retroactive `String: Identifiable` conformance would do the same job in
/// one line, but it would apply to every string in the app and belongs to
/// nobody. This stays local.
struct RecoveryPhraseToken: Identifiable {
    let id = UUID()
    let phrase: String
}
