import Foundation
import CryptoKit

/// The plaintext shape of a user's setup: their prompt library and the
/// preferences worth carrying to a new phone.
///
/// Encrypted exactly like an entry, and for the same reason — a prompt someone
/// wrote for themselves ("what am I avoiding today?") says as much about them
/// as the answer does.
struct SettingsPayload: Codable, Equatable {
    /// One sitting in the user's day. Added in schema 3.
    struct Block: Codable, Equatable {
        /// Preserved like a prompt's id, and for a stronger reason:
        /// `Prompt.blockID` and every answer ever written point at it.
        var id: UUID
        var title: String
        var hour: Int
        var minute: Int
        var order: Int
        var gatesDay: Bool
        var remindersEnabled: Bool
        var legacySession: String
    }

    struct Prompt: Codable, Equatable {
        /// Preserved, not regenerated: `PromptAnswer.promptID` points at it, so
        /// a new id would orphan every restored answer from its question.
        var id: UUID
        var title: String
        var hint: String
        var lineCount: Int
        var session: String
        var order: Int
        var isEnabled: Bool
        var isBuiltIn: Bool

        // Added in schema 2. Every one of these has to survive a v1 payload
        // that simply doesn't contain the key, which synthesised `Codable`
        // will not do for a non-optional property — hence the decoder below.
        var styleKind: String = PromptStyle.Kind.lines.rawValue
        var role: String = PromptRole.open.rawValue
        var originTemplateID: String = ""
        var originKey: String = ""

        /// Added in schema 3. Nil from a v1 or v2 device, where the prompt's
        /// `session` is all there is to go on — see `JournalStore.applyPrompts`.
        var blockID: UUID?

        init(
            id: UUID,
            title: String,
            hint: String,
            lineCount: Int,
            session: String,
            order: Int,
            isEnabled: Bool,
            isBuiltIn: Bool,
            styleKind: String = PromptStyle.Kind.lines.rawValue,
            role: String = PromptRole.open.rawValue,
            originTemplateID: String = "",
            originKey: String = "",
            blockID: UUID? = nil
        ) {
            self.id = id
            self.title = title
            self.hint = hint
            self.lineCount = lineCount
            self.session = session
            self.order = order
            self.isEnabled = isEnabled
            self.isBuiltIn = isBuiltIn
            self.styleKind = styleKind
            self.role = role
            self.originTemplateID = originTemplateID
            self.originKey = originKey
            self.blockID = blockID
        }

        /// Tolerant of anything a v1 device wrote. A phone still on the old
        /// build keeps uploading v1 payloads long after this ships, so the
        /// missing keys are the normal case, not the edge one.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            hint = try container.decode(String.self, forKey: .hint)
            lineCount = try container.decode(Int.self, forKey: .lineCount)
            session = try container.decode(String.self, forKey: .session)
            order = try container.decode(Int.self, forKey: .order)
            isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
            isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
            styleKind = try container.decodeIfPresent(String.self, forKey: .styleKind)
                ?? PromptStyle.Kind.lines.rawValue
            role = try container.decodeIfPresent(String.self, forKey: .role)
                ?? PromptRole.open.rawValue
            originTemplateID = try container.decodeIfPresent(String.self, forKey: .originTemplateID) ?? ""
            originKey = try container.decodeIfPresent(String.self, forKey: .originKey) ?? ""
            blockID = try container.decodeIfPresent(UUID.self, forKey: .blockID)
        }
    }

    /// Only what a person actually chose. Deliberately excludes `hasOnboarded`,
    /// `hasCompletedQuiz` and `hasEverSignedIn` — those describe where a given
    /// install has got to, not what the user wants, and restoring them onto a
    /// fresh device would let it skip gates it hasn't been through.
    struct Settings: Codable, Equatable {
        var displayName: String
        var strictMode: Bool
        var blockAppsUntilDone: Bool
        var appearance: String
        var alarmEnabled: Bool
        var eveningPromptsEnabled: Bool
        var wakeHour: Int
        var wakeMinute: Int
        var quizAnswers: QuizAnswers
        /// Added when the alarm and shield switches became one mode. Optional
        /// so a payload written before that still decodes; `Preferences.apply`
        /// falls back to `blockAppsUntilDone`, which carried the same meaning.
        var gateMode: String?
    }

    /// 3 since the fixed morning/evening pair became blocks. Bumping this
    /// changes the fingerprint for every existing user, so the first launch
    /// after the update pushes one extra settings blob — which is harmless and
    /// cheaper than guessing at a payload's shape.
    var schema: Int = 3
    var prompts: [Prompt]
    var settings: Settings
    /// Empty from a v1 or v2 device, which had no blocks to send.
    var blocks: [Block] = []

    init(prompts: [Prompt], settings: Settings, blocks: [Block] = []) {
        self.prompts = prompts
        self.settings = settings
        self.blocks = blocks
    }

    /// Tolerant of a v1 or v2 payload, which carries no `blocks` key at all.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        prompts = try container.decode([Prompt].self, forKey: .prompts)
        settings = try container.decode(Settings.self, forKey: .settings)
        blocks = try container.decodeIfPresent([Block].self, forKey: .blocks) ?? []
    }

    /// Canonical encoding: sorted keys so the same content always produces the
    /// same bytes. The whole change-detection scheme depends on that — see
    /// `fingerprint`.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// A hash of the content, used instead of a modification timestamp.
    ///
    /// Timestamps would mean stamping every `didSet` in `Preferences` and every
    /// prompt mutation path, and the day someone adds a preference and forgets
    /// the stamp, sync silently stops noticing it. A hash cannot be forgotten.
    var fingerprint: String {
        guard let data = try? Self.encoder.encode(self) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
