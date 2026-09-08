import Foundation

// MARK: - Questions

/// The personalisation quiz. Every question here earns its place twice: it
/// tells Dawn something it actually uses, and it makes the user articulate the
/// problem in their own words before we ask them for anything.
///
/// What "uses" means changed when the prompt set stopped being chosen from the
/// answers: these now drive the plan screen and the paywall headline rather
/// than the questions the user gets. That is still a real job — the funnel
/// works because the user has described their own problem before being sold to
/// — but it is a smaller one, and worth knowing before adding a question here.
enum QuizQuestion: String, CaseIterable, Codable, Identifiable {
    case morningShape
    case phoneLatency
    case thieves
    case wants
    case journalHistory
    case obstacle
    case minutes

    var id: String { rawValue }

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

    /// Multi-select. Nothing says so in words: the rows carry an empty circle
    /// where a single-select question carries nothing, and the footer says
    /// "Pick at least one." until something is picked. A "Choose any." line
    /// under the title as well was the same fact told three times.
    var allowsMultiple: Bool {
        self == .thieves || self == .wants
    }

    var options: [QuizOption] {
        switch self {
        case .morningShape:
            [
                .init("phone_in_bed", "Phone, before I'm out of bed", "iphone"),
                .init("alarm_then_scroll", "Alarm, then scrolling", "alarm"),
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
    var bedHour: Int = 22
    var bedMinute: Int = 30
    var committed: Bool = false

    init() {}

    /// Hand-written so a missing key falls back to the default above rather
    /// than throwing. Swift's synthesised decoder does not do this, and this
    /// struct is both persisted in `UserDefaults` and carried inside
    /// `SettingsPayload` — so a build that adds a field would otherwise fail to
    /// decode every backup written before it, taking the whole settings blob
    /// down with it. `bedHour` was the field that made this real.
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = try box.decodeIfPresent(String.self, forKey: .name) ?? ""
        selections = try box.decodeIfPresent([String: [String]].self, forKey: .selections) ?? [:]
        wakeHour = try box.decodeIfPresent(Int.self, forKey: .wakeHour) ?? 7
        wakeMinute = try box.decodeIfPresent(Int.self, forKey: .wakeMinute) ?? 0
        bedHour = try box.decodeIfPresent(Int.self, forKey: .bedHour) ?? 22
        bedMinute = try box.decodeIfPresent(Int.self, forKey: .bedMinute) ?? 30
        committed = try box.decodeIfPresent(Bool.self, forKey: .committed) ?? false
    }

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

    /// Minutes the user said they could give. Read by the plan and paywall
    /// copy only — the page itself is the same five questions for everyone.
    var committedMinutes: Int {
        Int(selected(.minutes).first ?? "5") ?? 5
    }

    /// In the user's own clock, 12- or 24-hour as their phone is set.
    var wakeTimeLabel: String { Self.label(hour: wakeHour, minute: wakeMinute) }

    /// Where the evening page lands by default: half an hour before bed, so it
    /// happens while they are still up rather than as one more thing owed once
    /// the light is off. The user retimes it on the evening sitting screen.
    var suggestedEveningTime: (hour: Int, minute: Int) {
        let minutes = (bedHour * 60 + bedMinute - 30 + 24 * 60) % (24 * 60)
        return (minutes / 60, minutes % 60)
    }

    private static func label(hour: Int, minute: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: hour, minute: minute, second: 0, of: .now
        )
        return (date ?? .now).formatted(.dateTime.hour().minute())
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

        // One line. Each of these used to carry a second sentence explaining
        // what the app would do about it — which the four rows underneath say
        // already, in more detail, with icons.
        let diagnosis: String
        switch answers.selected(.phoneLatency).first {
        case "instant":
            diagnosis = "You're on your phone before you're out of bed."
        case "under5":
            diagnosis = "You're online within five minutes of waking."
        case "under30":
            diagnosis = "You get a short head start most mornings."
        default:
            diagnosis = "You already protect your mornings."
        }

        var rows: [Row] = []

        // Counted off the page that actually gets installed, not guessed from
        // the minutes. The guess used to promise five questions to anyone who
        // picked ten minutes, and then hand them a three-question set.
        let page = PromptTemplate.classicFive
        let morning = page.seeds(for: .morning).count
        let evening = page.seeds(for: .evening).count
        rows.append(Row(
            symbol: "text.alignleft",
            title: "\(morning) question\(morning == 1 ? "" : "s") each morning",
            detail: "\(page.duration(for: .morning)). Change them any time."
        ))
        rows.append(Row(
            symbol: "moon.stars",
            title: "\(evening) more before bed",
            detail: page.duration(for: .evening)
        ))

        let thieves = answers.selected(.thieves)
        if !thieves.isEmpty {
            let names = thieves.compactMap { id in
                QuizQuestion.thieves.options.first { $0.id == id }?.label.lowercased()
            }
            rows.append(Row(
                symbol: "lock",
                title: "A gate on \(named(names))",
                detail: "Nothing opens until it's written."
            ))
        } else {
            rows.append(Row(
                symbol: "lock",
                title: "A gate on your phone",
                detail: "Nothing opens until it's written."
            ))
        }

        rows.append(Row(
            symbol: "alarm",
            title: "An alarm at \(answers.wakeTimeLabel)",
            detail: "Rings through silent mode and Focus."
        ))

        if answers.has(.journalHistory, "didnt_stick") || answers.has(.obstacle, "forgot") {
            rows.append(Row(
                symbol: "flame",
                title: "A streak you can keep",
                detail: "One line counts."
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

    /// The first two, then a count. Ticking every box on the thieves question
    /// otherwise produced "a gate on social media, news, email and slack,
    /// youtube and tiktok and games" as a heading.
    private static func named(_ items: [String]) -> String {
        guard items.count > 2 else { return list(items) }
        return "\(items[0]), \(items[1]) and \(items.count - 2) more"
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
