import Foundation

// MARK: - Questions

/// The personalisation quiz. Every question here earns its place twice: it
/// tells Dawn something it actually uses, and it makes the user articulate the
/// problem in their own words before we ask them for anything.
enum QuizQuestion: String, CaseIterable, Codable, Identifiable {
    case morningShape
    case phoneLatency
    case thieves
    case wants
    case journalHistory
    case obstacle
    case minutes

    var id: String { rawValue }

    var eyebrow: String {
        switch self {
        case .morningShape: "Where you are now"
        case .phoneLatency: "Where you are now"
        case .thieves: "What's in the way"
        case .wants: "What you want back"
        case .journalHistory: "Your history"
        case .obstacle: "Your history"
        case .minutes: "Your commitment"
        }
    }

    var title: String {
        switch self {
        case .morningShape: "How do your mornings actually start?"
        case .phoneLatency: "How long before you check your phone?"
        case .thieves: "What pulls you in first?"
        case .wants: "What do you want your mornings to give you?"
        case .journalHistory: "Have you journaled before?"
        case .obstacle: "What got in the way last time?"
        case .minutes: "How long can you give it each morning?"
        }
    }

    var hint: String? {
        switch self {
        case .thieves, .wants: "Choose any."
        case .morningShape: nil
        default: nil
        }
    }

    var allowsMultiple: Bool {
        self == .thieves || self == .wants
    }

    var options: [QuizOption] {
        switch self {
        case .morningShape:
            [
                .init("phone_in_bed", "Phone, before I'm out of bed", "iphone"),
                .init("alarm_then_scroll", "Alarm, then straight to scrolling", "alarm"),
                .init("coffee_then_phone", "Coffee first, phone soon after", "cup.and.saucer"),
                .init("decent", "I've got a decent routine", "checkmark.seal")
            ]
        case .phoneLatency:
            [
                .init("instant", "Instantly", "bolt"),
                .init("under5", "Under five minutes", "timer"),
                .init("under30", "Fifteen to thirty minutes", "clock"),
                .init("hour", "An hour or more", "sunrise")
            ]
        case .thieves:
            [
                .init("social", "Social media", "bubble.left.and.bubble.right"),
                .init("news", "News", "newspaper"),
                .init("work", "Email and Slack", "envelope"),
                .init("video", "YouTube and TikTok", "play.rectangle"),
                .init("games", "Games", "gamecontroller")
            ]
        case .wants:
            [
                .init("calm", "Calm", "leaf"),
                .init("focus", "Focus", "target"),
                .init("gratitude", "Gratitude", "heart"),
                .init("less_anxiety", "Less anxiety", "wind"),
                .init("control", "A sense of control", "hand.raised"),
                .init("time", "Time back", "hourglass")
            ]
        case .journalHistory:
            [
                .init("never", "Never", "circle.dotted"),
                .init("didnt_stick", "Tried, didn't stick", "arrow.uturn.backward"),
                .init("on_off", "On and off", "waveform.path"),
                .init("regular", "Regularly", "book.closed")
            ]
        case .obstacle:
            [
                .init("forgot", "I forgot", "questionmark.circle"),
                .init("no_time", "No time in the morning", "clock.badge.exclamationmark"),
                .init("pointless", "It felt pointless", "cloud"),
                .init("new", "Nothing — I'm new to this", "sparkles")
            ]
        case .minutes:
            [
                .init("3", "Three minutes", "gauge.low"),
                .init("5", "Five minutes", "gauge.medium"),
                .init("10", "Ten minutes", "gauge.high")
            ]
        }
    }
}

struct QuizOption: Identifiable, Hashable {
    let id: String
    let label: String
    let symbol: String

    init(_ id: String, _ label: String, _ symbol: String) {
        self.id = id
        self.label = label
        self.symbol = symbol
    }
}

// MARK: - Answers

/// Everything the quiz collected. Persisted so the plan screen, the paywall
/// headline, and the first journal session can all speak back to it.
struct QuizAnswers: Codable, Equatable {
    var name: String = ""
    var selections: [String: [String]] = [:]
    var wakeHour: Int = 7
    var wakeMinute: Int = 0
    var committed: Bool = false

    func selected(_ question: QuizQuestion) -> [String] {
        selections[question.rawValue] ?? []
    }

    func has(_ question: QuizQuestion, _ optionID: String) -> Bool {
        selected(question).contains(optionID)
    }

    func isAnswered(_ question: QuizQuestion) -> Bool {
        !selected(question).isEmpty
    }

    mutating func toggle(_ question: QuizQuestion, _ optionID: String) {
        var current = selected(question)
        if question.allowsMultiple {
            if let index = current.firstIndex(of: optionID) {
                current.remove(at: index)
            } else {
                current.append(optionID)
            }
        } else {
            current = [optionID]
        }
        selections[question.rawValue] = current
    }

    /// Minutes the user said they could give, used to size the prompt set.
    var committedMinutes: Int {
        Int(selected(.minutes).first ?? "5") ?? 5
    }
}

// MARK: - The reflected-back plan

/// Turns the quiz into something that reads like it was written for this
/// person. Every line here is derived from an answer they gave — no generic
/// filler, because the whole point of a long flow is that it earns the paywall.
struct MorningPlan {
    let headline: String
    let diagnosis: String
    let rows: [Row]
    let paywallHeadline: String

    struct Row: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    static func make(from answers: QuizAnswers) -> MorningPlan {
        let name = answers.name.trimmed
        let greeting = name.isEmpty ? "Your morning reset" : "\(name)'s morning reset"

        let diagnosis: String
        switch answers.selected(.phoneLatency).first {
        case "instant":
            diagnosis = "You reach for your phone before your feet hit the floor. \(AppConfig.appName) puts a page between you and the screen."
        case "under5":
            diagnosis = "You're online within five minutes of waking. That's the window \(AppConfig.appName) takes back."
        case "under30":
            diagnosis = "You get a short head start most mornings. \(AppConfig.appName) makes it deliberate instead of accidental."
        default:
            diagnosis = "You already protect your mornings. \(AppConfig.appName) gives that habit somewhere to land."
        }

        var rows: [Row] = []

        // Counted off the page that actually gets installed, not guessed from
        // the minutes. The guess used to promise five questions to anyone who
        // picked ten minutes, and then hand them a three-question set.
        let page = PromptPlan.make(from: answers)
        let count = page.morning.count
        rows.append(Row(
            symbol: "text.alignleft",
            title: "\(count) question\(count == 1 ? "" : "s") each morning",
            detail: "\(page.morningDuration) of writing. Change any of them later in Settings."
        ))

        let thieves = answers.selected(.thieves)
        if !thieves.isEmpty {
            let names = thieves.compactMap { id in
                QuizQuestion.thieves.options.first { $0.id == id }?.label.lowercased()
            }
            rows.append(Row(
                symbol: "lock",
                title: "A gate on \(list(names))",
                detail: "Shut until the page is written. No snooze, no skip."
            ))
        } else {
            rows.append(Row(
                symbol: "lock",
                title: "A gate on your phone",
                detail: "Nothing else opens until the page is written."
            ))
        }

        let time = String(format: "%02d:%02d", answers.wakeHour, answers.wakeMinute)
        rows.append(Row(
            symbol: "alarm",
            title: "An alarm at \(time)",
            detail: "Rings through silent mode and Focus, then hands you the page."
        ))

        if answers.has(.journalHistory, "didnt_stick") || answers.has(.obstacle, "forgot") {
            rows.append(Row(
                symbol: "flame",
                title: "A streak you can actually keep",
                detail: "One line counts. The point is showing up, not writing well."
            ))
        }

        let wants = answers.selected(.wants).compactMap { id in
            QuizQuestion.wants.options.first { $0.id == id }?.label.lowercased()
        }
        let paywall: String
        if wants.isEmpty {
            paywall = "Your mornings, back under your control."
        } else {
            paywall = "Your mornings, rebuilt around \(list(Array(wants.prefix(3))))."
        }

        return MorningPlan(
            headline: greeting,
            diagnosis: diagnosis,
            rows: rows,
            paywallHeadline: paywall
        )
    }

    /// "a, b and c"
    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}
