import SwiftUI
import SwiftData

/// Permanent deletion, with enough friction to be deliberate and not one tap
/// more. Apple requires this to be reachable in-app once you offer accounts.
struct DeleteAccountView: View {
    @Environment(AuthController.self) private var auth
    @Environment(SubscriptionController.self) private var subs
    @Environment(Preferences.self) private var prefs
    @Environment(\.journalStore) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var confirmation = ""
    @State private var errorMessage: String?
    @State private var isDeleting = false
    @FocusState private var focused: Bool

    private let phrase = "DELETE"

    private var canDelete: Bool {
        confirmation.trimmed.uppercased() == phrase && !isDeleting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Text("Delete your account")
                                .font(Theme.Typography.serif(30))
                                .foregroundStyle(Theme.Palette.ink)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            bullet("Your account and email are removed from our servers.")
                            bullet("Every journal entry on this phone is erased.")
                            bullet("Your streak and prompts go with them.")
                        }

                        GlassCard(tint: Theme.Palette.danger.opacity(0.08)) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your subscription is separate")
                                    .font(Theme.Typography.sans(14, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.ink)
                                Text("Deleting your account does not cancel billing. Cancel in the App Store first, or you'll keep being charged.")
                                    .font(Theme.Typography.sans(13))
                                    .foregroundStyle(Theme.Palette.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Link("Open App Store subscriptions",
                                     destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                                    .font(Theme.Typography.sans(13, weight: .medium))
                                    .frame(minHeight: Theme.Space.tapTarget)
                                    .tint(Theme.Palette.emberDeep)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Type \(phrase) to confirm").eyebrowStyle()
                            TextField("", text: $confirmation, prompt: Text(phrase)
                                .font(Theme.Typography.serif(20))
                                .foregroundStyle(Theme.Palette.inkTertiary.opacity(0.6)))
                                .font(Theme.Typography.serif(20))
                                .foregroundStyle(Theme.Palette.ink)
                                .tint(Theme.Palette.ember)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .focused($focused)
                            Rectangle()
                                .fill(focused ? Theme.Palette.ember.opacity(0.55) : Theme.Palette.rule)
                                .frame(height: 1)
                        }

                        if let errorMessage {
                            AuthErrorNote(message: errorMessage)
                        }

                        Button(action: delete) {
                            Text(isDeleting ? "Deleting…" : "Delete everything")
                                .font(Theme.Typography.sans(17, weight: .semibold))
                                .foregroundStyle(canDelete ? Theme.Palette.canvas : Theme.Palette.disabledLabel)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: Theme.Space.tapTarget)
                                .padding(.vertical, 13)
                        }
                        .background(
                            Capsule().fill(
                                canDelete
                                    ? Theme.Palette.danger
                                    : Theme.Palette.disabledFill
                            )
                        )
                        .clipShape(Capsule())
                        .disabled(!canDelete)
                        .animation(Theme.Motion.quick, value: canDelete)

                        Color.clear.frame(height: Theme.Space.md)
                    }
                    .pageGutter()
                    .padding(.top, Theme.Space.md)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep my account") { dismiss() }
                        .tint(Theme.Palette.inkSecondary)
                }
            }
        }
        .animation(Theme.Motion.quick, value: errorMessage)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.Palette.danger)
                .padding(.top, 5)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.sans(15))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func delete() {
        guard canDelete else { return }
        focused = false
        isDeleting = true
        Task {
            do {
                errorMessage = nil
                // Server first: if that fails, the user still has an account
                // and we haven't destroyed their journal for nothing.
                try await auth.deleteAccount()
                await subs.bind(to: nil)
                eraseLocalData()
                Haptics.success()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isDeleting = false
                Haptics.warning()
            }
        }
    }

    /// Wipes the on-device journal and every preference, so the app returns to
    /// a genuine first-launch state.
    private func eraseLocalData() {
        try? context.delete(model: PromptAnswer.self)
        try? context.delete(model: JournalEntry.self)
        try? context.delete(model: JournalPrompt.self)
        try? context.save()
        prefs.resetAll()
        // Otherwise the next person to sign in on this phone inherits a stale
        // owner id and their journal isn't wiped when it should be.
        LocalOwnership.release()
        store.seedPromptsIfNeeded()
    }
}
