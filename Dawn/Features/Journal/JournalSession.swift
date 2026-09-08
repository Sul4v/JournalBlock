import Foundation
import Observation

/// Drives one pass through a set of prompts. Holds the in-progress text so the
/// user can move back and forth without losing anything, and only writes to the
/// store when the session is finished.
@Observable
final class JournalSession {
    enum Step: Equatable {
        case prompt(Int)
        case complete
    }

    let block: JournalBlock
    let prompts: [JournalPrompt]
    /// Parallel to `prompts`: one array of line-strings per prompt.
    var drafts: [[String]]
    var step: Step
    /// Set true once the user has finished, so the view can play the outro.
    private(set) var didComplete = false

    init(
        block: JournalBlock,
        prompts: [JournalPrompt],
        existing: JournalEntry? = nil,
        startAt: Step? = nil
    ) {
        self.block = block
        self.prompts = prompts

        let previous = existing?.answers(forBlock: block.id) ?? []
        self.drafts = prompts.map { prompt in
            let saved = previous.first { $0.promptID == prompt.id }?.lines ?? []
            // Pad or trim to the prompt's current line count.
            return (0..<prompt.lineCount).map { index in
                index < saved.count ? saved[index] : ""
            }
        }

        self.step = startAt ?? .prompt(0)
        if prompts.isEmpty { self.step = .complete }
    }

    // MARK: - Position

    var promptIndex: Int? {
        if case let .prompt(index) = step { return index }
        return nil
    }

    var currentPrompt: JournalPrompt? {
        promptIndex.map { prompts[$0] }
    }

    var progress: Double {
        guard !prompts.isEmpty else { return 1 }
        switch step {
        case let .prompt(index):
            return Double(index) / Double(prompts.count)
        case .complete: return 1
        }
    }

    var stepLabel: String {
        switch step {
        case let .prompt(index): "\(index + 1) of \(prompts.count)"
        case .complete: "Done"
        }
    }

    // MARK: - Content rules

    /// A prompt counts as answered when at least its first line has content.
    /// Requiring all three lines turns a calm ritual into homework.
    func isAnswered(_ index: Int) -> Bool {
        drafts[index].contains { !$0.trimmed.isEmpty }
    }

    var canAdvance: Bool {
        switch step {
        case let .prompt(index): isAnswered(index)
        case .complete: true
        }
    }

    var isLastPrompt: Bool {
        guard let index = promptIndex else { return false }
        return index == prompts.count - 1
    }

    // MARK: - Navigation

    var canGoBack: Bool {
        switch step {
        case .complete: false
        case let .prompt(index): index > 0
        }
    }

    func advance() {
        switch step {
        case let .prompt(index):
            step = index + 1 < prompts.count ? .prompt(index + 1) : .complete
        case .complete:
            break
        }
    }

    func goBack() {
        guard case let .prompt(index) = step, index > 0 else { return }
        step = .prompt(index - 1)
    }

    func markComplete() { didComplete = true }

    /// Packaged for `JournalStore.record`.
    var payload: [(prompt: JournalPrompt, lines: [String])] {
        zip(prompts, drafts).map { ($0, $1) }
    }
}
