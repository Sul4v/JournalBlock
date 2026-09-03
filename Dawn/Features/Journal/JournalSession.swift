import Foundation
import Observation

/// Drives one pass through a set of prompts. Holds the in-progress text so the
/// user can move back and forth without losing anything, and only writes to the
/// store when the session is finished.
@Observable
final class JournalSession {
    enum Step: Equatable {
        case mood
        case prompt(Int)
        case complete
    }

    let session: JournalPrompt.Session
    let prompts: [JournalPrompt]
    /// Parallel to `prompts`: one array of line-strings per prompt.
    var drafts: [[String]]
    var mood: Int?
    var step: Step
    /// Set true once the user has finished, so the view can play the outro.
    private(set) var didComplete = false

    /// Skips the mood card when re-opening a session that already has a mood.
    init(
        session: JournalPrompt.Session,
        prompts: [JournalPrompt],
        existing: JournalEntry? = nil,
        startAt: Step? = nil
    ) {
        self.session = session
        self.prompts = prompts
        self.mood = existing?.mood

        let previous = existing?.answers(for: session) ?? []
        self.drafts = prompts.map { prompt in
            let saved = previous.first { $0.promptID == prompt.id }?.lines ?? []
            // Pad or trim to the prompt's current line count.
            return (0..<prompt.lineCount).map { index in
                index < saved.count ? saved[index] : ""
            }
        }

        self.step = startAt ?? (session == .morning ? .mood : .prompt(0))
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

    /// Total cards including the mood check-in.
    private var cardCount: Int {
        prompts.count + (session == .morning ? 1 : 0)
    }

    var progress: Double {
        guard cardCount > 0 else { return 1 }
        switch step {
        case .mood: return 0
        case let .prompt(index):
            let offset = session == .morning ? 1 : 0
            return Double(index + offset) / Double(cardCount)
        case .complete: return 1
        }
    }

    var stepLabel: String {
        switch step {
        case .mood: "Checking in"
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
        case .mood: mood != nil
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
        case .mood, .complete: false
        case let .prompt(index): index > 0 || session == .morning
        }
    }

    func advance() {
        switch step {
        case .mood:
            step = prompts.isEmpty ? .complete : .prompt(0)
        case let .prompt(index):
            step = index + 1 < prompts.count ? .prompt(index + 1) : .complete
        case .complete:
            break
        }
    }

    func goBack() {
        guard case let .prompt(index) = step else { return }
        step = index > 0 ? .prompt(index - 1) : .mood
    }

    func markComplete() { didComplete = true }

    /// Packaged for `JournalStore.record`.
    var payload: [(prompt: JournalPrompt, lines: [String])] {
        zip(prompts, drafts).map { ($0, $1) }
    }
}

/// The five-point check-in shown before the morning prompts.
enum Mood: Int, CaseIterable, Identifiable {
    case heavy = 1, low, level, bright, luminous

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .heavy: "Heavy"
        case .low: "Low"
        case .level: "Level"
        case .bright: "Bright"
        case .luminous: "Luminous"
        }
    }

    var symbol: String {
        switch self {
        case .heavy: "cloud.rain"
        case .low: "cloud"
        case .level: "cloud.sun"
        case .bright: "sun.max"
        case .luminous: "sparkles"
        }
    }
}
