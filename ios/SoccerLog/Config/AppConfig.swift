import Foundation

/// Reads Supabase configuration injected into Info.plist from Secrets.xcconfig.
/// Only the anon (public) key is ever present in the iOS app.
enum AppConfig {
    static let supabaseURL: URL = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: raw.trimmingCharacters(in: .whitespaces)),
              url.scheme != nil else {
            fatalError("SUPABASE_URL missing/invalid. Copy Secrets.xcconfig.example to Secrets.xcconfig and fill it in.")
        }
        return url
    }()

    static let supabaseAnonKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            fatalError("SUPABASE_ANON_KEY missing. Fill in Secrets.xcconfig.")
        }
        return key.trimmingCharacters(in: .whitespaces)
    }()

    /// Base URL of the deployed rating web page, e.g. https://your-app.vercel.app.
    /// Links are built as `<base>/r/<token>`.
    static let ratingBaseURL: String = {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "RATING_BASE_URL") as? String) ?? ""
        return raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }()

    static func ratingLink(token: UUID) -> String {
        "\(ratingBaseURL)/r/\(token.uuidString.lowercased())"
    }
}
