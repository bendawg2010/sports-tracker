import Foundation

enum DateFormatters {
    static let espnDateParam: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f
    }()

    static let espnISO: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // ESPN sometimes sends dates without fractional seconds
    static let espnISONoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parse ESPN date string — handles all ESPN date variants:
    /// "2026-03-20T16:15Z" (no seconds), "2026-03-20T16:15:00Z", "2026-03-20T16:15:00.000Z"
    static func parseESPNDate(_ dateString: String) -> Date? {
        // Try with fractional seconds first
        if let d = espnISO.date(from: dateString) { return d }
        // Try without fractional seconds
        if let d = espnISONoFraction.date(from: dateString) { return d }
        // ESPN sometimes omits seconds entirely: "2026-03-20T16:15Z"
        // Add ":00" before "Z" to make it valid
        if dateString.hasSuffix("Z") && dateString.count <= 17 {
            let withSeconds = dateString.replacingOccurrences(of: "Z", with: ":00Z")
            if let d = espnISONoFraction.date(from: withSeconds) { return d }
        }
        // Last resort: DateFormatter
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mmZ"
        fallback.locale = Locale(identifier: "en_US_POSIX")
        return fallback.date(from: dateString.replacingOccurrences(of: "Z", with: "+0000"))
    }

    static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static let dayHeader: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    static let lastUpdated: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a"
        return f
    }()
}
