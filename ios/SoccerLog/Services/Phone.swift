import Foundation

/// Best-effort E.164 normalization. Defaults to +1 for 10-digit US numbers.
enum Phone {
    static func normalize(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        // Keep a leading +, drop everything else that isn't a digit.
        let hasPlus = raw.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        let digits = raw.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }

        if hasPlus {
            return "+" + digits
        }
        switch digits.count {
        case 10:
            return "+1" + digits            // US 10-digit
        case 11 where digits.hasPrefix("1"):
            return "+" + digits             // US with country code
        default:
            return "+" + digits             // fall back: assume already includes country code
        }
    }
}
