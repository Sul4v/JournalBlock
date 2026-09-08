import Foundation

// MARK: - Style

/// How a prompt asks for its answer.
///
/// The distinction matters more than it looks. `lines` is a *list* — separate
/// ruled fields that quietly ask for separate things, which is what makes
/// "three things" work. `freeform` is one box that grows. "I am grateful for…"
/// wants the list; "What's sitting on my chest this morning?" wants the box,
/// and handing that one three stubby fields turns a confession into a form.
enum PromptStyle: Equatable, Hashable, Sendable {
    case lines(Int)
    case freeform

    enum Kind: String, Codable, Sendable { case lines, freeform }

    /// The widest a list is allowed to get. Past four the card stops reading as
    /// a page and starts reading as a questionnaire.
    static let maxLines = 5

    var kind: Kind {
        switch self {
        case .lines: .lines
        case .freeform: .freeform
        }
    }

    /// How many draft slots this prompt occupies in a session. Freeform is one
    /// slot that happens to be tall, which is what lets `JournalSession` go on
    /// treating every prompt as a plain array of strings.
    var slotCount: Int {
        switch self {
        case let .lines(count): min(max(count, 1), Self.maxLines)
        case .freeform: 1
        }
    }

    /// Rough seconds to answer honestly. Feeds the "about four minutes" figure
    /// the user sees while building their page — the point of which is to keep
    /// enthusiasm during setup from writing a cheque 6am has to cash.
    var estimatedSeconds: Int {
        switch self {
        case let .lines(count): 25 * min(max(count, 1), Self.maxLines)
        case .freeform: 75
        }
    }

    /// Rebuilds a style from the two columns it is stored as.
    static func make(kind: Kind, lineCount: Int) -> PromptStyle {
        switch kind {
        case .lines: .lines(lineCount)
        case .freeform: .freeform
        }
    }
}

// MARK: - Variants

/// One way of asking a question. The swap sheet is a list of these.
struct PromptVariant: Identifiable, Hashable, Sendable {
    /// Stable and globally unique — `JournalPrompt.originKey` stores it, which
    /// is what lets the app say "reset wording" and lets a later release fix a
    /// typo in a prompt without clobbering someone's own edit.
    let key: String
    let title: String
    let hint: String
    let style: PromptStyle

    var id: String { key }

    init(_ key: String, _ title: String, _ hint: String = "", _ style: PromptStyle = .lines(1)) {
        self.key = key
        self.title = title
        self.hint = hint
        self.style = style
    }
}

// MARK: - Drafts

/// A question that has been chosen but not created yet.
///
/// Exists for the block creation flow, which collects a page before there is a
/// block to hang it on. Either half of the picker produces one: a wording
/// lifted from the catalog, which keeps its `originKey` so "reset wording"
/// still works once it's real, or one the user wrote, which has no origin
/// because there is nothing to reset it to.
struct PromptDraft: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let hint: String
    let style: PromptStyle
    /// The catalog wording this started as. Empty for a prompt the user wrote.
    let originKey: String

    init(
        id: UUID = UUID(),
        title: String,
        hint: String = "",
        style: PromptStyle = .lines(1),
        originKey: String = ""
    ) {
        self.id = id
        self.title = title
        self.hint = hint
        self.style = style
        self.originKey = originKey
    }

    init(_ variant: PromptVariant) {
        self.init(
            title: variant.title,
            hint: variant.hint,
            style: variant.style,
            originKey: variant.key
        )
    }

    /// What the question is for. A user-written one is `.open` — an open prompt
    /// is a real role, not a missing one.
    var role: PromptRole { PromptRole.owning(originKey) ?? .open }
}

// MARK: - Roles

/// What a prompt is *for*, independent of how it's worded.
///
/// Roles are the hinge of the whole feature. Templates are compositions of
/// roles; the quiz recommends roles; and the swap sheet offers other wordings
/// of the same role. That last one is where most personalisation will actually
/// happen — picking a different way to ask about gratitude takes two seconds,
/// while writing a good prompt from nothing is harder than journaling.
enum PromptRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case gratitude
    case intention
    case affirmation
    case control
    case decompression
    case protection
    case reflection
    case improvement
    case open

    var id: String { rawValue }

    /// Heading of the swap sheet.
    var label: String {
        switch self {
        case .gratitude: "Gratitude"
        case .intention: "Intention"
        case .affirmation: "Affirmation"
        case .control: "What's yours to decide"
        case .decompression: "Clearing your head"
        case .protection: "Protecting your time"
        case .reflection: "Looking back"
        case .improvement: "Doing it better"
        case .open: "An open page"
        }
    }

    /// Which half of the day this role belongs to. Evening roles can't be
    /// dragged into the morning page — a "what went well today" question at
    /// 6am has nothing to answer.
    var session: JournalPrompt.Session {
        switch self {
        case .reflection, .improvement: .evening
        default: .morning
        }
    }

    /// Other ways to ask the same thing. First entry is the default wording.
    ///
    /// Every list deliberately contains one low-bar option for people who
    /// bounce off the earnest version — someone who winces at "affirmation"
    /// still deserves a page they'll open tomorrow.
    var alternates: [PromptVariant] {
        switch self {
        case .gratitude:
            [
                .init("gratitude.three", "I am grateful for…", "", .lines(3)),
                .init("gratitude.good-now", "What's good right now?", "It doesn't have to be big.", .lines(3)),
                .init("gratitude.who", "Who made something easier for me lately?", "", .lines(2)),
                .init("gratitude.missed", "What went right yesterday that I didn't notice?", "", .lines(2)),
                .init("gratitude.would-miss", "What would I miss if it were gone today?", "", .lines(2)),
                .init("gratitude.one", "One thing about this morning that's fine.", "Just one. The bar is low on purpose.", .lines(1))
            ]
        case .intention:
            [
                .init("intention.great", "What would make today great?", "", .lines(3)),
                .init("intention.good-day", "What would make today a good day?", "Things you can actually control.", .lines(3)),
                .init("intention.one-thing", "What's the one thing that has to happen today?", "", .lines(1)),
                .init("intention.if-well", "If today goes well, what did I do?", "", .lines(2)),
                .init("intention.attention", "Where do I want my attention to go today?", "", .lines(2)),
                .init("intention.first-step", "What's the smallest useful thing I could do first?", "", .lines(1))
            ]
        case .affirmation:
            [
                .init("affirmation.daily", "Daily affirmations. I am…", "", .lines(2)),
                .init("affirmation.today-i-am", "Today, I am…", "Present tense. Write it like it's already true.", .lines(1)),
                .init("affirmation.kind-of-person", "Today I'm the kind of person who…", "", .lines(1)),
                .init("affirmation.by-tonight", "What do I want to be true of me by tonight?", "", .lines(1)),
                .init("affirmation.forget", "One thing I'm capable of that I keep forgetting.", "", .lines(1))
            ]
        case .control:
            [
                .init("control.mine", "What's actually mine to decide today?", "And what isn't.", .lines(2)),
                .init("control.not-mine", "What am I carrying that isn't mine?", "", .lines(1)),
                .init("control.let-go", "What could I let go of before 9am?", "", .lines(1))
            ]
        case .decompression:
            [
                .init("decompression.chest", "What's sitting on my chest this morning?", "Name it. That's the whole job.", .freeform),
                .init("decompression.dreading", "What am I dreading today?", "", .lines(2)),
                .init("decompression.worst-case", "What's the worst realistic version of today — and could I live with it?", "Usually the answer is yes.", .freeform),
                .init("decompression.avoiding", "What am I avoiding?", "", .lines(1))
            ]
        case .protection:
            [
                .init("protection.block", "What's the one block of time I won't give away today?", "", .lines(1)),
                .init("protection.no", "What am I saying no to today?", "", .lines(2))
            ]
        case .reflection:
            [
                .init("reflection.amazing", "3 Amazing things that happened today…", "", .lines(3)),
                .init("reflection.went-well", "What went well today?", "Three things. They can be small.", .lines(3)),
                .init("reflection.remember", "What's worth remembering about today?", "", .lines(3)),
                .init("reflection.contained", "What did today actually contain?", "", .freeform)
            ]
        case .improvement:
            [
                .init("improvement.better", "How could I have made today better?", "", .lines(2)),
                .init("improvement.differently", "What would I do differently?", "", .lines(1)),
                .init("improvement.got-away", "Where did today get away from me?", "", .lines(1)),
                .init("improvement.one-change", "One thing I'd change about today.", "", .lines(1))
            ]
        case .open:
            [
                .init("open.anything", "Anything.", "The page is yours.", .freeform),
                .init("open.on-my-mind", "What's on my mind?", "", .freeform),
                .init("open.until", "Write until you've said the thing.", "", .freeform)
            ]
        }
    }

    /// The wording a template asks for, or the role's default if the key has
    /// been retired in a later release.
    func variant(_ key: String) -> PromptVariant {
        alternates.first { $0.key == key } ?? alternates[0]
    }

    /// Finds the role a variant key belongs to, for provenance on a prompt
    /// restored from backup or written before roles existed.
    static func owning(_ key: String) -> PromptRole? {
        allCases.first { role in role.alternates.contains { $0.key == key } }
    }
}

// MARK: - Templates

/// A ready-made page. Templates are *compositions of roles*, not free-floating
/// text: every prompt a template installs is one of the variants in
/// `PromptRole.alternates`, which is what makes each of them swappable the
/// moment it lands on the user's page.
///
/// Deliberately code, not SwiftData. These ship with the app and want to be
/// editable in a release; the user's own library is the thing that gets stored.
struct PromptTemplate: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// One line, shown under the name in the gallery. Says who it's for.
    let blurb: String
    /// Provenance, where a format came from somewhere real.
    let attribution: String?
    let seeds: [Seed]

    struct Seed: Hashable, Sendable {
        let role: PromptRole
        let variantKey: String

        var variant: PromptVariant { role.variant(variantKey) }
        var session: JournalPrompt.Session { role.session }

        init(_ role: PromptRole, _ variantKey: String) {
            self.role = role
            self.variantKey = variantKey
        }
    }

    func seeds(for session: JournalPrompt.Session) -> [Seed] {
        seeds.filter { $0.session == session }
    }

    static func == (lhs: PromptTemplate, rhs: PromptTemplate) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - The catalog

extension PromptTemplate {
    /// Five, and it should stay near five. A long gallery is the blank page
    /// again with extra steps — the user hasn't journaled yet and has no basis
    /// for choosing between twelve philosophies at signup.
    static let catalog: [PromptTemplate] = [
        classicFive, oneThing, beforeTheNoise, stoicMorning, openPage
    ]

    static func template(id: String) -> PromptTemplate? {
        catalog.first { $0.id == id }
    }

    /// The set every new account starts with, and the only one onboarding
    /// installs. Three questions in the morning, two at night.
    ///
    /// The wording matches the printed journal this format comes from, at the
    /// owner's explicit instruction. Two things follow from that, and both are
    /// deliberate. The name stays off the product: "The Five Minute Journal"
    /// is a registered trademark of Intelligent Change, and shipping under it
    /// is a different order of exposure from shipping the questions. And these
    /// five strings are the one part of the catalog that is not ours — the
    /// remaining variants below were written for this app, so reach for those
    /// first if the wording ever has to change.
    static let classicFive = PromptTemplate(
        id: "classic-five",
        name: "The Classic Five",
        blurb: "Gratitude, then intention. The format most people mean by “journaling”.",
        attribution: nil,
        seeds: [
            Seed(.gratitude, "gratitude.three"),
            Seed(.intention, "intention.great"),
            Seed(.affirmation, "affirmation.daily"),
            Seed(.reflection, "reflection.amazing"),
            Seed(.improvement, "improvement.better")
        ]
    )

    /// The honest answer to "three minutes". One question, answered properly,
    /// beats three answered at a run.
    static let oneThing = PromptTemplate(
        id: "one-thing",
        name: "One Thing",
        blurb: "A single question, most mornings under a minute. Hard to fail.",
        attribution: nil,
        seeds: [
            Seed(.intention, "intention.one-thing"),
            Seed(.reflection, "reflection.went-well")
        ]
    )

    /// For the cohort that says the mornings are anxious. Names the thing
    /// first, because a gratitude prompt landing on top of dread reads as
    /// being told to cheer up.
    static let beforeTheNoise = PromptTemplate(
        id: "before-the-noise",
        name: "Before the Noise",
        blurb: "Put down what you woke up carrying, then decide what today is.",
        attribution: nil,
        seeds: [
            Seed(.decompression, "decompression.chest"),
            Seed(.control, "control.mine"),
            Seed(.intention, "intention.attention"),
            Seed(.reflection, "reflection.contained")
        ]
    )

    /// Control, then the worst case, then what's still good. Old idea, and the
    /// one that works best for people who want to feel less at the mercy of
    /// their day.
    static let stoicMorning = PromptTemplate(
        id: "stoic-morning",
        name: "What's Mine to Decide",
        blurb: "Separate what you control from what you don't, before the day does it for you.",
        attribution: "Loosely after the Stoic morning practice.",
        seeds: [
            Seed(.control, "control.mine"),
            Seed(.decompression, "decompression.worst-case"),
            Seed(.gratitude, "gratitude.would-miss"),
            Seed(.improvement, "improvement.got-away")
        ]
    )

    /// For people who already journal and want the gate, not the curriculum.
    static let openPage = PromptTemplate(
        id: "open-page",
        name: "The Open Page",
        blurb: "No questions. Just the page, and the door stays shut until it's written.",
        attribution: nil,
        seeds: [
            Seed(.open, "open.anything"),
            Seed(.reflection, "reflection.contained")
        ]
    )
}

// MARK: - Sizing a page

extension PromptTemplate {
    /// Rough seconds one half of the page takes to answer honestly.
    func estimatedSeconds(for session: JournalPrompt.Session) -> Int {
        seeds(for: session).reduce(0) { $0 + $1.variant.style.estimatedSeconds }
    }

    /// "About 2 minutes". Rounded to the nearest minute, floored at one.
    ///
    /// Shown wherever the app tells someone what a page will cost them, which
    /// is the one number setup enthusiasm must not be allowed to inflate.
    func duration(for session: JournalPrompt.Session) -> String {
        Self.duration(seconds: estimatedSeconds(for: session))
    }

    static func duration(seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        return "About \(minutes) minute\(minutes == 1 ? "" : "s")"
    }
}
