import Foundation
import Supabase

/// The one `SupabaseClient` the app uses.
///
/// Auth and backup have to share a client: row-level security decides what a
/// request may touch from the JWT the client carries, so a second client with
/// its own session would be a stranger to every `auth.uid()` policy in
/// `supabase/schema.sql` and silently read back nothing.
enum SupabaseStack {
    /// Nil when the build has no keys configured — the app then runs on the
    /// local stand-ins and backup simply stays switched off.
    static let shared: SupabaseClient? = {
        guard
            let url = URL(string: AppConfig.supabaseURL),
            !AppConfig.supabaseURL.isEmpty,
            !AppConfig.supabaseAnonKey.isEmpty
        else { return nil }
        return SupabaseClient(supabaseURL: url, supabaseKey: AppConfig.supabaseAnonKey)
    }()

    static var isConfigured: Bool { shared != nil }
}
