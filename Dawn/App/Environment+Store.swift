import SwiftUI
import SwiftData

extension EnvironmentValues {
    /// Injected once at the app root. The `preview` fallback keeps SwiftUI
    /// previews and unit tests from needing the real container.
    @Entry var journalStore: JournalStore = .preview
}

extension JournalStore {
    /// An in-memory store, used as the environment default.
    static let preview: JournalStore = {
        let container = try! ModelContainer(
            for: JournalEntry.self, JournalPrompt.self, PromptAnswer.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = JournalStore(context: container.mainContext)
        store.prepareLibrary()
        return store
    }()
}
