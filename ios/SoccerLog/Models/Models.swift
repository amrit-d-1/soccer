import Foundation

// MARK: - Date helpers
//
// `played_at` is a Postgres `date` ("2026-07-25"); timestamptz values are ISO8601.
// We keep raw strings from the DB and expose parsed Dates so decoding never fails
// on the mismatch between `date` and full timestamps.

enum DateParse {
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func day(_ s: String?) -> Date? {
        guard let s else { return nil }
        return dayFormatter.date(from: String(s.prefix(10)))
    }

    static func timestamp(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? isoNoFraction.date(from: s)
    }
}

// MARK: - Core tables

struct Player: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var phone: String?
    var contactId: String?
    var isActive: Bool
    var smsOptOut: Bool
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, phone
        case contactId = "contact_id"
        case isActive = "is_active"
        case smsOptOut = "sms_opt_out"
        case createdAt = "created_at"
    }

    var hasPhone: Bool { !(phone ?? "").isEmpty }
}

struct SessionRow: Codable, Identifiable, Hashable {
    var id: UUID
    var playedAt: String
    var location: String?
    var notes: String?
    var ratingsCloseAt: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case playedAt = "played_at"
        case location, notes
        case ratingsCloseAt = "ratings_close_at"
        case createdAt = "created_at"
    }

    var playedDate: Date? { DateParse.day(playedAt) }
    var closeDate: Date? { DateParse.timestamp(ratingsCloseAt) }
}

struct Appearance: Codable, Identifiable, Hashable {
    var id: UUID?
    var sessionId: UUID
    var playerId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case playerId = "player_id"
    }
}

struct Rating: Codable, Identifiable, Hashable {
    var id: UUID?
    var sessionId: UUID
    var raterId: UUID
    var overall: Int
    var balance: Int?
    var comment: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case raterId = "rater_id"
        case overall, balance, comment
        case createdAt = "created_at"
    }
}

struct RatingLink: Codable, Identifiable, Hashable {
    var token: UUID
    var sessionId: UUID
    var playerId: UUID
    var expiresAt: String?
    var usedAt: String?

    var id: UUID { token }

    enum CodingKeys: String, CodingKey {
        case token
        case sessionId = "session_id"
        case playerId = "player_id"
        case expiresAt = "expires_at"
        case usedAt = "used_at"
    }
}

// MARK: - Insert payloads (server generates ids / defaults)

struct SessionInsert: Encodable {
    var playedAt: String
    var location: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case playedAt = "played_at"
        case location, notes
    }
}

struct AppearanceInsert: Encodable {
    var sessionId: UUID
    var playerId: UUID
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case playerId = "player_id"
    }
}

struct RatingLinkInsert: Encodable {
    var sessionId: UUID
    var playerId: UUID
    var expiresAt: String?
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case playerId = "player_id"
        case expiresAt = "expires_at"
    }
}

struct PlayerInsert: Encodable {
    var name: String
    var phone: String?
    var contactId: String?
    enum CodingKeys: String, CodingKey {
        case name, phone
        case contactId = "contact_id"
    }
}

struct PlayerUpdate: Encodable {
    var name: String?
    var phone: String?
    var isActive: Bool?
    var smsOptOut: Bool?
    enum CodingKeys: String, CodingKey {
        case name, phone
        case isActive = "is_active"
        case smsOptOut = "sms_opt_out"
    }
}

// MARK: - Analytics view DTOs (all stats computed in Postgres)

struct SessionSummary: Codable, Identifiable, Hashable {
    var id: UUID
    var playedAt: String
    var location: String?
    var notes: String?
    var ratingsCloseAt: String?
    var headcount: Int
    var responseCount: Int
    var responseRate: Double?
    var meanOverall: Double?
    var stddevOverall: Double?
    var meanBalance: Double?
    var isLowResponse: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case playedAt = "played_at"
        case location, notes
        case ratingsCloseAt = "ratings_close_at"
        case headcount
        case responseCount = "response_count"
        case responseRate = "response_rate"
        case meanOverall = "mean_overall"
        case stddevOverall = "stddev_overall"
        case meanBalance = "mean_balance"
        case isLowResponse = "is_low_response"
    }

    var playedDate: Date? { DateParse.day(playedAt) }
    var closeDate: Date? { DateParse.timestamp(ratingsCloseAt) }
}

struct HeadcountBucket: Codable, Identifiable, Hashable {
    var bucket: String
    var sessionCount: Int
    var meanRating: Double?
    var nRatings: Int
    var id: String { bucket }

    enum CodingKeys: String, CodingKey {
        case bucket
        case sessionCount = "session_count"
        case meanRating = "mean_rating"
        case nRatings = "n_ratings"
    }
}

struct PlayerPresence: Codable, Identifiable, Hashable {
    var playerId: UUID
    var name: String
    var appearances: Int
    var meanWith: Double?
    var meanWithout: Double?
    var nWith: Int
    var nWithout: Int
    var globalMean: Double?
    var adjustedWith: Double?
    var deltaAdjusted: Double?
    var hasEnoughData: Bool
    var id: UUID { playerId }

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case name, appearances
        case meanWith = "mean_with"
        case meanWithout = "mean_without"
        case nWith = "n_with"
        case nWithout = "n_without"
        case globalMean = "global_mean"
        case adjustedWith = "adjusted_with"
        case deltaAdjusted = "delta_adjusted"
        case hasEnoughData = "has_enough_data"
    }
}

struct DisagreementRow: Codable, Identifiable, Hashable {
    var sessionId: UUID
    var playedAt: String
    var stddevOverall: Double?
    var meanBalance: Double?
    var nRatings: Int
    var id: UUID { sessionId }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case playedAt = "played_at"
        case stddevOverall = "stddev_overall"
        case meanBalance = "mean_balance"
        case nRatings = "n_ratings"
    }

    var playedDate: Date? { DateParse.day(playedAt) }
}

struct TrendRow: Codable, Identifiable, Hashable {
    var playedAt: String
    var meanOverall: Double?
    var nRatings: Int
    var rollingAvg4: Double?
    var id: String { playedAt }

    enum CodingKeys: String, CodingKey {
        case playedAt = "played_at"
        case meanOverall = "mean_overall"
        case nRatings = "n_ratings"
        case rollingAvg4 = "rolling_avg_4"
    }

    var playedDate: Date? { DateParse.day(playedAt) }
}
