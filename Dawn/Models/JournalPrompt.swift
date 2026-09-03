import Foundation
import SwiftData

/// A question the user answers.
///
/// Installed from a `PromptTemplate` — the app picks one from the quiz — and
/// then owned outright by the user, who can reword it, swap it for another
/// phrasing of the same role, switch it off, reorder it, or delete it.
///
/// Note what is *not* here: no notion of a prompt being sacred. The old model
/// made template prompts undeletable so the app could never be left with
/// nothing to ask. That protected the wrong thing — the invariant worth holding
/// is "at least one morning question exists", not "these five rows are
/// immortal", and it lives in `JournalStore` where it can be enforced across
/// every mutation path. See `JournalStore.wouldStrandMorning`.
@Model
final class JournalPrompt {
    #Index<JournalPrompt>([\.order])

    var id: UUID = UUID()
    var title: String = ""
    /// Short grey hint under the question. Optional.
    var hint: String = ""
    /// Number of writing lines, when `style` is `.lines`. Meaningless for
    /// freeform prompts, which always occupy exactly one slot.
    var lineCount: Int = 1
    /// Raw value of `PromptStyle.Kind`. Stored beside `lineCount` rather than
    /// as one encoded blob so both stay queryable and a SwiftData migration
    /// stays lightweight.
    var styleKindRaw: String = PromptStyle.Kind.lines.rawValue
    /// Raw value of `PromptRole`. What the question is *for*, which is what
    /// the swap sheet offers alternatives from.
    var roleRaw: String = PromptRole.open.rawValue
    /// Raw value of `Session`. Stored as String so adding sessions later is non-breaking.
    var sessionRaw: String = Session.morning.rawValue
    var order: Int = 0
    var isEnabled: Bool = true
    /// True when this arrived from a template rather than being written by
    /// hand. Provenance only — it grants no protection from deletion.
    var isBuiltIn: Bool = false
    /// Which template installed this, and which wording it started as. Empty
    /// for a prompt the user wrote. Together they let the app show where a
    /// question came from and offer to put the original wording back.
    var originTemplateID: String = ""
    var originKey: String = ""

    var session: Session {
        get { Session(rawValue: sessionRaw) ?? .morning }
        set { sessionRaw = newValue.rawValue }
    }

    var role: PromptRole {
        get { PromptRole(rawValue: roleRaw) ?? .open }
        set { roleRaw = newValue.rawValue }
    }

    var style: PromptStyle {
        get {
            PromptStyle.make(
                kind: PromptStyle.Kind(rawValue: styleKindRaw) ?? .lines,
                lineCount: lineCount
            )
        }
        set {
            styleKindRaw = newValue.kind.rawValue
            lineCount = newValue.slotCount
        }
    }

    /// The wording this prompt started as, if it came from a template and that
    /// variant still ships. Nil once the user has written their own.
    var origin: PromptVariant? {
        guard !originKey.isEmpty else { return nil }
        return PromptRole.owning(originKey)?.variant(originKey)
    }

    /// True when the user has changed the wording away from the variant they
    /// installed — the only case where offering "reset wording" makes sense.
    var isEdited: Bool {
        guard let origin else { return false }
        return origin.title != title || origin.hint != hint
    }

    init(
        title: String,
        hint: String = "",
        style: PromptStyle = .lines(1),
        role: PromptRole = .open,
        session: Session = .morning,
        order: Int,
        isBuiltIn: Bool = false,
        isEnabled: Bool = true,
        originTemplateID: String = "",
        originKey: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.hint = hint
        self.lineCount = style.slotCount
        self.styleKindRaw = style.kind.rawValue
        self.roleRaw = role.rawValue
        self.sessionRaw = session.rawValue
        self.order = order
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.originTemplateID = originTemplateID
        self.originKey = originKey
    }

    enum Session: String, Codable, CaseIterable, Identifiable {
        case morning
        case evening

        var id: String { rawValue }

        var label: String {
            switch self {
            case .morning: "Morning"
            case .evening: "Evening"
            }
        }

        var icon: String {
            switch self {
            case .morning: "sun.horizon"
            case .evening: "moon.stars"
            }
        }
    }
}

// MARK: - Installing a template

extension JournalPrompt {
    /// Builds the rows for a template's page. Order is the order given.
    static func rows(
        for seeds: [PromptTemplate.Seed],
        from template: PromptTemplate,
        startingAt start: Int = 0
    ) -> [JournalPrompt] {
        seeds.enumerated().map { offset, seed in
            let variant = seed.variant
            return JournalPrompt(
                title: variant.title,
                hint: variant.hint,
                style: variant.style,
                role: seed.role,
                session: seed.session,
                order: start + offset,
                isBuiltIn: true,
                originTemplateID: template.id,
                originKey: variant.key
            )
        }
    }

    /// Every row a template installs, morning then evening.
    static func rows(for template: PromptTemplate) -> [JournalPrompt] {
        rows(
            for: template.seeds(for: .morning) + template.seeds(for: .evening),
            from: template
        )
    }

    /// The page a set of quiz answers earns.
    static func rows(for plan: PromptPlan) -> [JournalPrompt] {
        rows(for: plan.morning + plan.evening, from: plan.template)
    }

    /// The set installed when there are no answers to go on — a fresh install
    /// that hasn't been through the quiz, or a library repaired after being
    /// emptied.
    static func defaultSet() -> [JournalPrompt] {
        rows(for: .classicFive)
    }
}
