import Foundation
import Supabase

/// Response from the send-rating-requests edge function.
struct SendResult: Codable {
    var sent: Int
    var skipped: Int
    var failed: Int
}

private struct SendRequest: Encodable {
    var session_id: String
    var mode: String
}

/// A rating_link joined to its player's name/phone, for the "Copy links" feature.
struct LinkWithPlayer: Identifiable, Hashable {
    var token: UUID
    var playerId: UUID
    var name: String
    var phone: String?
    var hasResponded: Bool
    var id: UUID { token }
}

/// One place for all reads/writes. All statistics come from Postgres views;
/// this layer only moves rows and does trivial local counting/sorting.
@MainActor
final class DataStore: ObservableObject {
    @Published var isAuthenticated = false
    @Published var authError: String?

    let queue = OfflineQueue()

    private var client: SupabaseClient { Supa.client }

    // MARK: Auth (single admin account)

    func bootstrap() async {
        if let _ = try? await client.auth.session {
            isAuthenticated = true
        }
        Task {
            for await change in client.auth.authStateChanges {
                self.isAuthenticated = (change.session != nil)
            }
        }
    }

    func signIn(email: String, password: String) async {
        authError = nil
        do {
            try await client.auth.signIn(email: email, password: password)
            isAuthenticated = true
        } catch {
            authError = error.localizedDescription
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
        isAuthenticated = false
    }

    // MARK: Players

    func fetchPlayers(activeOnly: Bool = false) async throws -> [Player] {
        var query = client.from("player").select()
        if activeOnly { query = query.eq("is_active", value: true) }
        return try await query.order("name", ascending: true).execute().value
    }

    /// Players ordered by most-recent appearance (regulars first) for the picker.
    func fetchPlayersByRecency() async throws -> [Player] {
        async let playersTask: [Player] = client
            .from("player").select().eq("is_active", value: true).execute().value
        async let apps: [AppearanceWithDate] = client
            .from("appearance")
            .select("player_id, session(played_at)")
            .execute().value

        let players = try await playersTask
        let appearances = try await apps

        var last: [UUID: String] = [:]
        for a in appearances {
            guard let d = a.session?.playedAt else { continue }
            if let cur = last[a.playerId] { if d > cur { last[a.playerId] = d } }
            else { last[a.playerId] = d }
        }
        return players.sorted { lhs, rhs in
            let l = last[lhs.id] ?? ""
            let r = last[rhs.id] ?? ""
            if l == r { return lhs.name.lowercased() < rhs.name.lowercased() }
            return l > r    // most recent first; players never seen sink to bottom
        }
    }

    /// Appearance counts per player id for the Roster screen (row counting only).
    func fetchAppearanceCounts() async throws -> [UUID: Int] {
        let rows: [AppearancePlayerId] = try await client
            .from("appearance").select("player_id").execute().value
        var counts: [UUID: Int] = [:]
        for r in rows { counts[r.playerId, default: 0] += 1 }
        return counts
    }

    func addPlayer(name: String, phone: String?, contactId: String? = nil) async throws -> Player {
        let payload = PlayerInsert(name: name, phone: Phone.normalize(phone), contactId: contactId)
        return try await client.from("player").insert(payload).select().single().execute().value
    }

    func updatePlayer(_ id: UUID, _ patch: PlayerUpdate) async throws {
        try await client.from("player").update(patch).eq("id", value: id).execute()
    }

    /// Bulk import from Contacts. Dedupe is handled by the caller; this inserts new rows.
    func importPlayers(_ inserts: [PlayerInsert]) async throws {
        guard !inserts.isEmpty else { return }
        try await client.from("player").insert(inserts).execute()
    }

    // MARK: Sessions

    func fetchSessionSummaries() async throws -> [SessionSummary] {
        try await client
            .from("v_session_summary")
            .select()
            .order("played_at", ascending: false)
            .execute().value
    }

    func fetchSessionSummary(id: UUID) async throws -> SessionSummary? {
        let rows: [SessionSummary] = try await client
            .from("v_session_summary").select().eq("id", value: id).limit(1).execute().value
        return rows.first
    }

    func fetchAppearances(sessionId: UUID) async throws -> [Player] {
        let rows: [AppearanceWithPlayer] = try await client
            .from("appearance")
            .select("player(*)")
            .eq("session_id", value: sessionId)
            .execute().value
        return rows.compactMap { $0.player }
    }

    func fetchRatings(sessionId: UUID) async throws -> [Rating] {
        try await client.from("rating").select().eq("session_id", value: sessionId).execute().value
    }

    func fetchLinksWithPlayers(sessionId: UUID) async throws -> [LinkWithPlayer] {
        async let links: [RatingLink] = client
            .from("rating_link").select().eq("session_id", value: sessionId).execute().value
        async let ratings: [Rating] = client
            .from("rating").select("rater_id").eq("session_id", value: sessionId).execute().value
        async let players: [Player] = client.from("player").select().execute().value

        let (l, r, p) = try await (links, ratings, players)
        let responded = Set(r.map { $0.raterId })
        let byId = Dictionary(uniqueKeysWithValues: p.map { ($0.id, $0) })
        return l.compactMap { link in
            guard let player = byId[link.playerId] else { return nil }
            return LinkWithPlayer(token: link.token, playerId: link.playerId,
                                  name: player.name, phone: player.phone,
                                  hasResponded: responded.contains(link.playerId))
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// The full New-Session write: session + appearances + rating_links (for
    /// phone-having, non-opted-out players). Creating any brand-new players first.
    /// Used both for the online path and by the offline flush.
    @discardableResult
    func createSession(from item: QueuedSession) async throws -> UUID {
        // 1. Session
        let session: SessionRow = try await client
            .from("session")
            .insert(SessionInsert(playedAt: item.playedAt, location: item.location, notes: item.notes))
            .select().single().execute().value

        // 2. Resolve players (create new ones, dedupe existing by phone/contact)
        let existing = try await fetchPlayers()
        var byContact: [String: Player] = [:]
        var byPhone: [String: Player] = [:]
        for p in existing {
            if let c = p.contactId { byContact[c] = p }
            if let ph = p.phone, !ph.isEmpty { byPhone[ph] = p }
        }

        var resolved: [(id: UUID, hasPhone: Bool, optOut: Bool)] = []
        for qp in item.players {
            if let id = qp.existingId {
                resolved.append((id, !(qp.phone ?? "").isEmpty, qp.smsOptOut))
                continue
            }
            let normPhone = Phone.normalize(qp.phone)
            if let c = qp.contactId, let hit = byContact[c] {
                resolved.append((hit.id, hit.hasPhone, hit.smsOptOut)); continue
            }
            if let ph = normPhone, let hit = byPhone[ph] {
                resolved.append((hit.id, true, hit.smsOptOut)); continue
            }
            let created = try await addPlayer(name: qp.name, phone: qp.phone, contactId: qp.contactId)
            resolved.append((created.id, created.hasPhone, created.smsOptOut))
        }

        // 3. Appearances
        let appearances = resolved.map { AppearanceInsert(sessionId: session.id, playerId: $0.id) }
        if !appearances.isEmpty {
            try await client.from("appearance").insert(appearances).execute()
        }

        // 4. Rating links for reachable players
        let expires = DateParse.iso.string(from: (item.playedDateOrNow).addingTimeInterval(48 * 3600))
        let links = resolved
            .filter { $0.hasPhone && !$0.optOut }
            .map { RatingLinkInsert(sessionId: session.id, playerId: $0.id, expiresAt: expires) }
        if !links.isEmpty {
            try await client.from("rating_link").insert(links).execute()
        }
        return session.id
    }

    // MARK: Offline flush

    /// Push any queued sessions. Called on launch, on foreground, and when
    /// connectivity is restored. Removes each item only after a successful write.
    func flushQueue() async {
        for item in queue.pending {
            do {
                _ = try await createSession(from: item)
                queue.remove(item.localId)
            } catch {
                // Leave it queued; we'll try again next time connectivity returns.
                break
            }
        }
    }

    // MARK: Edge function

    func sendRatingRequests(sessionId: UUID, mode: String) async throws -> SendResult {
        try await client.functions.invoke(
            "send-rating-requests",
            options: FunctionInvokeOptions(body: SendRequest(session_id: sessionId.uuidString, mode: mode))
        ) { data, _ in
            try JSONDecoder().decode(SendResult.self, from: data)
        }
    }

    // MARK: Analytics views

    func fetchHeadcountEffect() async throws -> [HeadcountBucket] {
        try await client.from("v_headcount_effect").select().execute().value
    }
    func fetchPlayerPresence() async throws -> [PlayerPresence] {
        try await client.from("v_player_presence").select().execute().value
    }
    func fetchDisagreement() async throws -> [DisagreementRow] {
        try await client.from("v_disagreement").select().order("played_at", ascending: true).execute().value
    }
    func fetchTrend() async throws -> [TrendRow] {
        try await client.from("v_trend").select().order("played_at", ascending: true).execute().value
    }
}

// MARK: - Private join decode helpers

private struct AppearanceWithDate: Decodable {
    var playerId: UUID
    var session: SessionDatePart?
    enum CodingKeys: String, CodingKey { case playerId = "player_id", session }
}
private struct SessionDatePart: Decodable {
    var playedAt: String
    enum CodingKeys: String, CodingKey { case playedAt = "played_at" }
}
private struct AppearancePlayerId: Decodable {
    var playerId: UUID
    enum CodingKeys: String, CodingKey { case playerId = "player_id" }
}
private struct AppearanceWithPlayer: Decodable {
    var player: Player?
}

private extension QueuedSession {
    var playedDateOrNow: Date { DateParse.day(playedAt) ?? Date() }
}
