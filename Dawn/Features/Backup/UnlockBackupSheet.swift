import SwiftUI

/// Takes a recovery phrase and unlocks the backup on this device.
///
/// One field for the whole phrase rather than twelve boxes: the common case is
/// pasting from a password manager, and twelve fields turn that into twelve
/// separate paste operations.
struct UnlockBackupSheet: View {
    @Environment(BackupController.self) private var backup
    @Environment(\.journalStore) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var message: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            SkyBackground(phase: DayPhase.current(), intensity: 0.55)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    SectionHeading(title: "Enter your phrase")

                    Text("The twelve words you saved when you turned on backup. Order matters; capitals and punctuation don't.")
                        .font(Theme.Typography.sans(15))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    field

                    if let message {
                        AuthErrorNote(message: message)
                    }

                    EmberButton(
                        title: backup.isWorking ? "Unlocking…" : "Unlock backup",
                        systemImage: "lock.open",
                        isEnabled: isComplete && !backup.isWorking
                    ) {
                        Task { await unlock() }
                    }

                    // This can arrive unprompted at launch, so there has to be
                    // an obvious way past it that isn't guessing at a swipe.
                    HStack {
                        Spacer(minLength: 0)
                        TextButton(title: "Not now") { dismiss() }
                        Spacer(minLength: 0)
                    }

                    Color.clear.frame(height: Theme.Space.md)
                }
                .pageGutter()
                .padding(.top, Theme.Space.lg)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.never)
        }
        .animation(Theme.Motion.quick, value: message)
        .animation(Theme.Motion.quick, value: status)
        .onAppear { isFocused = true }
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("harbor lesson autumn ripple …", text: $input, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Theme.Palette.ink)
                // All three fight a fixed wordlist: capitals get added, and
                // autocorrect will happily turn a valid BIP39 word into an
                // invalid English one.
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .focused($isFocused)
                .lineLimit(3, reservesSpace: true)
                .padding(.vertical, Theme.Space.xs)

            Rectangle()
                .fill(isFocused ? Theme.Palette.ember : Theme.Palette.ruleStrong)
                .frame(height: 1)

            suggestions
            statusLine
        }
    }

    /// Completions for the word being typed. Every BIP39 word is unique in its
    /// first four letters, so this usually collapses to one tap.
    @ViewBuilder
    private var suggestions: some View {
        let options = RecoveryPhrase.completions(for: trailingFragment)
        if !options.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(options, id: \.self) { word in
                        Button {
                            complete(with: word)
                        } label: {
                            Text(word)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(Theme.Palette.ink)
                                .padding(.horizontal, Theme.Space.sm)
                                .frame(minHeight: Theme.Space.tapTarget)
                                .background(
                                    Capsule().fill(Theme.Palette.emberSoft.opacity(0.45))
                                )
                                // Without an explicit shape the tappable area
                                // is the glyphs themselves, so a tap landing in
                                // the capsule's padding does nothing at all.
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: Theme.Space.tapTarget)
        }
    }

    private var statusLine: some View {
        Text(status)
            .font(Theme.Typography.sans(12))
            .foregroundStyle(isComplete ? Theme.Palette.emberDeep : Theme.Palette.inkTertiary)
    }

    // MARK: - Input state

    /// The half-typed word at the end, if the user hasn't hit space yet.
    private var trailingFragment: String {
        guard let last = input.last, last.isLetter else { return "" }
        let fragment = RecoveryPhrase.words(in: input).last ?? ""
        // Once a word is complete there is nothing left to suggest.
        return RecoveryPhrase.completions(for: fragment) == [fragment] ? "" : fragment
    }

    private var typedWords: [String] { RecoveryPhrase.words(in: input) }

    /// Words the user has actually finished. The last one doesn't count until
    /// they type a separator — otherwise the field accuses them of a mistake
    /// halfway through spelling a perfectly good word.
    private var settledWords: [String] {
        var words = typedWords
        if let last = input.last, last.isLetter, !words.isEmpty { words.removeLast() }
        return words
    }

    private var isComplete: Bool { RecoveryPhrase.isValid(input) }

    /// Deliberately never says "wrong phrase" — that's a server answer. This
    /// only reports what can be known on the device.
    private var status: String {
        if let first = settledWords.first(where: { BIP39Wordlist.index(of: $0) == nil }) {
            return "\"\(first)\" isn't one of the words."
        }
        if isComplete { return "All twelve words look right." }
        if typedWords.count > RecoveryPhrase.wordCount {
            return "That's \(typedWords.count) words — a phrase is twelve."
        }
        if typedWords.count == RecoveryPhrase.wordCount {
            // Every word is real but the checksum failed, which almost always
            // means two of them are the wrong way round.
            return "Twelve words, but something's off — check the order."
        }
        return "\(typedWords.count) of \(RecoveryPhrase.wordCount) words."
    }

    private func complete(with word: String) {
        var words = typedWords
        if !words.isEmpty { words.removeLast() }
        words.append(word)
        let completed = words.joined(separator: " ") + " "

        input = completed
        Haptics.tap(.light)
    }

    private func unlock() async {
        do {
            message = nil
            try await backup.unlock(with: input)
            Haptics.success()
            // Pull immediately: the point of unlocking is to get the entries
            // back, and a silent success looks like nothing happened.
            try? await backup.sync(store: store)
            dismiss()
        } catch {
            Haptics.warning()
            message = error.localizedDescription
        }
    }
}
