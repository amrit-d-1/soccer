import Foundation
import Supabase

/// Single shared Supabase client (anon key). Auth is a single admin account (you).
enum Supa {
    static let client = SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseAnonKey
    )
}
