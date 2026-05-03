import Foundation

/// Lightweight game data shared between the main app and widget via App Group UserDefaults
struct SharedGame: Codable, Identifiable {
    let id: String
    let awayTeam: String
    let awayAbbreviation: String
    let awayScore: String
    let awaySeed: Int?
    let awayLogo: String?
    let awayColor: String?
    let homeTeam: String
    let homeAbbreviation: String
    let homeScore: String
    let homeSeed: Int?
    let homeLogo: String?
    let homeColor: String?
    let state: String // "pre", "in", "post"
    let detail: String?
    let shortDetail: String?
    let period: Int
    let displayClock: String?
    let startDate: Date?
    let roundName: String?
    let regionName: String?
    let broadcast: String?
    let isUpset: Bool
    let winProbTeam: String?
    let winProbValue: Double?

    var isLive: Bool { state == "in" }
    var isFinal: Bool { state == "post" }
    var isScheduled: Bool { state == "pre" }

    var winProbText: String? {
        guard let team = winProbTeam, let prob = winProbValue else { return nil }
        return "\(team) \(Int(prob * 100))%"
    }

    var awayScoreInt: Int? { Int(awayScore) }
    var homeScoreInt: Int? { Int(homeScore) }

    var scoreDifference: Int? {
        guard let a = awayScoreInt, let h = homeScoreInt else { return nil }
        return abs(a - h)
    }
}

enum SharedDataManager {
    static let appGroupID = "group.com.local.MarchMadnessTracker"
    static let gamesKey = "sharedGames"
    static let lastUpdatedKey = "sharedLastUpdated"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func saveGames(_ games: [SharedGame]) {
        guard let defaults = sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(games) {
            defaults.set(data, forKey: gamesKey)
            defaults.set(Date(), forKey: lastUpdatedKey)
            defaults.synchronize()
        }
    }

    static func loadGames() -> [SharedGame] {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: gamesKey),
              let games = try? JSONDecoder().decode([SharedGame].self, from: data) else {
            return []
        }
        return games
    }

    static func lastUpdated() -> Date? {
        sharedDefaults?.object(forKey: lastUpdatedKey) as? Date
    }
}
