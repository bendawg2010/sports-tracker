import Foundation

/// Defines a sport/league combination supported by ESPN's public API.
/// Each entry maps to an ESPN API path: `/sports/{sport}/{league}/scoreboard`
struct SportLeague: Codable, Identifiable, Hashable {
    let id: String
    let sport: String           // ESPN path: "football", "basketball", etc.
    let league: String          // ESPN path: "nfl", "nba", "mens-college-basketball"
    let displayName: String     // "NFL", "NBA", "NCAA Men's Basketball"
    let shortName: String       // "NFL", "NBA", "NCAAM"
    let icon: String            // SF Symbol: "football.fill", "basketball.fill"
    let category: SportCategory
    let groupID: String?        // tournament filter (e.g. "100" for NCAA tourney)
    let hasBracket: Bool
    let hasChaos: Bool          // upset tracking (seeded tournaments)
    let hasPlayByPlay: Bool
    let espnWebSegment: String  // for watch URLs: "nfl", "nba", "mens-college-basketball"
    let livePollingInterval: TimeInterval
    let idlePollingInterval: TimeInterval

    var baseURL: String {
        "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(league)"
    }
    var scoreboardURL: String { "\(baseURL)/scoreboard" }
    var summaryURL: String { "\(baseURL)/summary" }
    var espnWebGameURL: String { "https://www.espn.com/\(espnWebSegment)/game/_/gameId" }

    enum SportCategory: String, Codable, CaseIterable {
        case football = "Football"
        case basketball = "Basketball"
        case baseball = "Baseball"
        case hockey = "Hockey"
        case soccer = "Soccer"
        case other = "Other"

        var icon: String {
            switch self {
            case .football: return "football.fill"
            case .basketball: return "basketball.fill"
            case .baseball: return "baseball.fill"
            case .hockey: return "hockey.puck.fill"
            case .soccer: return "soccerball"
            case .other: return "trophy.fill"
            }
        }
    }
}

// MARK: - Full ESPN Sport Catalog

extension SportLeague {
    static let all: [SportLeague] = [
        // FOOTBALL
        SportLeague(
            id: "nfl", sport: "football", league: "nfl",
            displayName: "NFL", shortName: "NFL", icon: "football.fill",
            category: .football, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: true, espnWebSegment: "nfl",
            livePollingInterval: 5, idlePollingInterval: 300
        ),
        SportLeague(
            id: "cfb", sport: "football", league: "college-football",
            displayName: "College Football", shortName: "CFB", icon: "football.fill",
            category: .football, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: true, espnWebSegment: "college-football",
            livePollingInterval: 5, idlePollingInterval: 300
        ),

        // BASKETBALL
        SportLeague(
            id: "nba", sport: "basketball", league: "nba",
            displayName: "NBA", shortName: "NBA", icon: "basketball.fill",
            category: .basketball, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: true, espnWebSegment: "nba",
            livePollingInterval: 3, idlePollingInterval: 300
        ),
        SportLeague(
            id: "ncaam", sport: "basketball", league: "mens-college-basketball",
            displayName: "NCAA Men's Basketball", shortName: "NCAAM", icon: "basketball.fill",
            category: .basketball, groupID: "100", hasBracket: true, hasChaos: true,
            hasPlayByPlay: true, espnWebSegment: "mens-college-basketball",
            livePollingInterval: 3, idlePollingInterval: 300
        ),
        SportLeague(
            id: "ncaaw", sport: "basketball", league: "womens-college-basketball",
            displayName: "NCAA Women's Basketball", shortName: "NCAAW", icon: "basketball.fill",
            category: .basketball, groupID: "100", hasBracket: true, hasChaos: true,
            hasPlayByPlay: true, espnWebSegment: "womens-college-basketball",
            livePollingInterval: 3, idlePollingInterval: 300
        ),
        SportLeague(
            id: "wnba", sport: "basketball", league: "wnba",
            displayName: "WNBA", shortName: "WNBA", icon: "basketball.fill",
            category: .basketball, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: true, espnWebSegment: "wnba",
            livePollingInterval: 3, idlePollingInterval: 300
        ),

        // BASEBALL
        SportLeague(
            id: "mlb", sport: "baseball", league: "mlb",
            displayName: "MLB", shortName: "MLB", icon: "baseball.fill",
            category: .baseball, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: true, espnWebSegment: "mlb",
            livePollingInterval: 10, idlePollingInterval: 300
        ),

        // HOCKEY
        SportLeague(
            id: "nhl", sport: "hockey", league: "nhl",
            displayName: "NHL", shortName: "NHL", icon: "hockey.puck.fill",
            category: .hockey, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: true, espnWebSegment: "nhl",
            livePollingInterval: 5, idlePollingInterval: 300
        ),

        // SOCCER
        SportLeague(
            id: "epl", sport: "soccer", league: "eng.1",
            displayName: "Premier League", shortName: "EPL", icon: "soccerball",
            category: .soccer, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: true, espnWebSegment: "soccer",
            livePollingInterval: 5, idlePollingInterval: 300
        ),
        SportLeague(
            id: "mls", sport: "soccer", league: "usa.1",
            displayName: "MLS", shortName: "MLS", icon: "soccerball",
            category: .soccer, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: true, espnWebSegment: "soccer",
            livePollingInterval: 5, idlePollingInterval: 300
        ),
        SportLeague(
            id: "laliga", sport: "soccer", league: "esp.1",
            displayName: "La Liga", shortName: "LIGA", icon: "soccerball",
            category: .soccer, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: true, espnWebSegment: "soccer",
            livePollingInterval: 5, idlePollingInterval: 300
        ),
        SportLeague(
            id: "bundesliga", sport: "soccer", league: "ger.1",
            displayName: "Bundesliga", shortName: "BUN", icon: "soccerball",
            category: .soccer, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: true, espnWebSegment: "soccer",
            livePollingInterval: 5, idlePollingInterval: 300
        ),
        SportLeague(
            id: "seriea", sport: "soccer", league: "ita.1",
            displayName: "Serie A", shortName: "SER", icon: "soccerball",
            category: .soccer, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: true, espnWebSegment: "soccer",
            livePollingInterval: 5, idlePollingInterval: 300
        ),
        SportLeague(
            id: "ligue1", sport: "soccer", league: "fra.1",
            displayName: "Ligue 1", shortName: "L1", icon: "soccerball",
            category: .soccer, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: true, espnWebSegment: "soccer",
            livePollingInterval: 5, idlePollingInterval: 300
        ),
        SportLeague(
            id: "ucl", sport: "soccer", league: "uefa.champions",
            displayName: "Champions League", shortName: "UCL", icon: "soccerball",
            category: .soccer, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: true, espnWebSegment: "soccer",
            livePollingInterval: 5, idlePollingInterval: 300
        ),
        SportLeague(
            id: "ligamx", sport: "soccer", league: "mex.1",
            displayName: "Liga MX", shortName: "LMX", icon: "soccerball",
            category: .soccer, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: true, espnWebSegment: "soccer",
            livePollingInterval: 5, idlePollingInterval: 300
        ),

        // OTHER
        SportLeague(
            id: "pga", sport: "golf", league: "pga",
            displayName: "PGA Tour", shortName: "PGA", icon: "figure.golf",
            category: .other, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: false, espnWebSegment: "golf",
            livePollingInterval: 30, idlePollingInterval: 300
        ),
        SportLeague(
            id: "atp", sport: "tennis", league: "atp",
            displayName: "ATP Tennis", shortName: "ATP", icon: "tennisball.fill",
            category: .other, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: false, espnWebSegment: "tennis",
            livePollingInterval: 15, idlePollingInterval: 300
        ),
        SportLeague(
            id: "wta", sport: "tennis", league: "wta",
            displayName: "WTA Tennis", shortName: "WTA", icon: "tennisball.fill",
            category: .other, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: false, espnWebSegment: "tennis",
            livePollingInterval: 15, idlePollingInterval: 300
        ),
        SportLeague(
            id: "f1", sport: "racing", league: "f1",
            displayName: "Formula 1", shortName: "F1", icon: "car.fill",
            category: .other, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: false, espnWebSegment: "f1",
            livePollingInterval: 10, idlePollingInterval: 300
        ),
        SportLeague(
            id: "nascar", sport: "racing", league: "sprint",
            displayName: "NASCAR", shortName: "NAS", icon: "car.fill",
            category: .other, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: false, espnWebSegment: "racing/nascar",
            livePollingInterval: 10, idlePollingInterval: 300
        ),
        SportLeague(
            id: "ufc", sport: "mma", league: "ufc",
            displayName: "UFC", shortName: "UFC", icon: "figure.martial.arts",
            category: .other, groupID: nil, hasBracket: false, hasChaos: false,
            hasPlayByPlay: false, espnWebSegment: "mma",
            livePollingInterval: 10, idlePollingInterval: 300
        ),
    ]

    /// Catalog grouped by category for settings UI
    static var byCategory: [(SportCategory, [SportLeague])] {
        SportCategory.allCases.compactMap { cat in
            let leagues = all.filter { $0.category == cat }
            return leagues.isEmpty ? nil : (cat, leagues)
        }
    }

    /// Look up a sport by its ID
    static func find(_ id: String) -> SportLeague? {
        all.first { $0.id == id }
    }
}
