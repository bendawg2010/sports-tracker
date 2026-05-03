import Foundation

// MARK: - ESPN Scoreboard API Response

struct ScoreboardResponse: Codable {
    let events: [Event]

    enum CodingKeys: String, CodingKey { case events }

    init(events: [Event]) { self.events = events }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Decode each raw event as a flexible dictionary so we can expand tennis/golf
        // tournaments into individual matches (via `groupings`) when needed.
        var unkeyed = try c.nestedUnkeyedContainer(forKey: .events)
        var events: [Event] = []
        while !unkeyed.isAtEnd {
            if let rawDict = try? unkeyed.decode(AnyCodable.self) {
                events.append(contentsOf: Self.expandEvents(from: rawDict.value))
            } else {
                _ = try? unkeyed.decode(FailableEmpty.self)
            }
        }
        self.events = events
    }

    /// If the raw event has `groupings[].competitions[]` (tennis/golf format),
    /// flatten each nested competition into its own Event so UI can treat each
    /// match as a discrete game.
    private static func expandEvents(from raw: Any?) -> [Event] {
        guard let dict = raw as? [String: Any] else { return [] }

        // Tennis/golf: look for groupings
        if let groupings = dict["groupings"] as? [[String: Any]], !groupings.isEmpty {
            var results: [Event] = []
            let parentDate = dict["date"] as? String ?? ""
            let parentName = dict["name"] as? String ?? ""
            let parentShort = dict["shortName"] as? String ?? parentName
            for grouping in groupings {
                let roundHeadline = (grouping["grouping"] as? [String: Any])?["shortName"] as? String
                    ?? (grouping["grouping"] as? [String: Any])?["displayName"] as? String
                let comps = grouping["competitions"] as? [[String: Any]] ?? []
                for comp in comps {
                    var eventDict: [String: Any] = [:]
                    eventDict["id"] = comp["id"] as? String ?? UUID().uuidString
                    eventDict["date"] = comp["date"] as? String ?? parentDate
                    eventDict["name"] = buildMatchName(comp) ?? parentName
                    eventDict["shortName"] = buildMatchShortName(comp) ?? parentShort
                    eventDict["competitions"] = [comp]
                    eventDict["status"] = comp["status"] ?? dict["status"] ?? [:]
                    if let round = roundHeadline {
                        eventDict["notes"] = [["headline": round, "type": "event"]]
                    }
                    if let event = decodeEvent(from: eventDict) {
                        results.append(event)
                    }
                }
            }
            if !results.isEmpty { return results }
        }

        // Standard format
        if let event = decodeEvent(from: dict) {
            return [event]
        }
        return []
    }

    private static func buildMatchName(_ comp: [String: Any]) -> String? {
        guard let competitors = comp["competitors"] as? [[String: Any]], competitors.count >= 2 else { return nil }
        let names = competitors.compactMap { c -> String? in
            let ath = c["athlete"] as? [String: Any] ?? c["team"] as? [String: Any] ?? [:]
            return ath["displayName"] as? String ?? ath["shortName"] as? String
        }
        return names.joined(separator: " vs ")
    }

    private static func buildMatchShortName(_ comp: [String: Any]) -> String? {
        guard let competitors = comp["competitors"] as? [[String: Any]], competitors.count >= 2 else { return nil }
        let abbrs = competitors.compactMap { c -> String? in
            let ath = c["athlete"] as? [String: Any] ?? c["team"] as? [String: Any] ?? [:]
            if let abbr = ath["abbreviation"] as? String { return abbr }
            if let short = ath["shortName"] as? String { return short }
            if let name = ath["displayName"] as? String {
                return String(name.components(separatedBy: " ").last?.prefix(4) ?? "")
            }
            return nil
        }
        return abbrs.joined(separator: " vs ")
    }

    private static func decodeEvent(from dict: [String: Any]) -> Event? {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(Event.self, from: data)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(events, forKey: .events)
    }
}

/// Type-erased wrapper for decoding arbitrary JSON values
private struct AnyCodable: Decodable {
    let value: Any?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode([String: AnyCodable].self) {
            self.value = v.mapValues { $0.value as Any }
        } else if let v = try? c.decode([AnyCodable].self) {
            self.value = v.map { $0.value as Any }
        } else if let v = try? c.decode(String.self) {
            self.value = v
        } else if let v = try? c.decode(Int.self) {
            self.value = v
        } else if let v = try? c.decode(Double.self) {
            self.value = v
        } else if let v = try? c.decode(Bool.self) {
            self.value = v
        } else {
            self.value = nil
        }
    }
}

/// Placeholder used to skip unparseable array entries during decoding
private struct FailableEmpty: Decodable {
    init(from decoder: Decoder) throws {
        _ = try decoder.singleValueContainer()
    }
}

struct Event: Codable, Identifiable {
    let id: String
    let date: String
    let name: String
    let shortName: String
    let competitions: [Competition]
    let status: GameStatus
    let notes: [Note]?

    var competition: Competition? { competitions.first }

    var homeCompetitor: Competitor? {
        competition?.competitors.first { $0.homeAway == "home" }
    }

    var awayCompetitor: Competitor? {
        competition?.competitors.first { $0.homeAway == "away" }
    }

    var scoreDifference: Int? {
        guard let home = homeCompetitor?.scoreInt,
              let away = awayCompetitor?.scoreInt else { return nil }
        return abs(home - away)
    }

    var isLive: Bool {
        status.type.state == "in"
    }

    var isFinal: Bool {
        status.type.state == "post"
    }

    var isScheduled: Bool {
        status.type.state == "pre"
    }

    var startDate: Date? {
        DateFormatters.parseESPNDate(date)
    }

    /// The tournament headline from either event notes or competition notes
    /// ESPN puts it in competition.notes like: "NCAA Men's Basketball Championship - South Region - 1st Round"
    private var bracketHeadline: String? {
        if let h = notes?.first?.headline { return h }
        return competition?.notes?.first?.headline
    }

    var regionName: String? {
        guard let headline = bracketHeadline else { return nil }
        let parts = headline.components(separatedBy: " - ")
        guard parts.count >= 2 else { return nil }
        // The region is the second-to-last part: "... - South Region - 1st Round"
        let region = parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
        // Strip "Region" suffix if present: "South Region" -> "South"
        return region.replacingOccurrences(of: " Region", with: "")
    }

    var roundName: String? {
        guard let headline = bracketHeadline else { return nil }
        let parts = headline.components(separatedBy: " - ")
        return parts.last?.trimmingCharacters(in: .whitespaces)
    }

    /// Estimated win probability for the leading/favored team
    /// Pre-game: based on historical seed matchup data
    /// Live: based on score margin and time remaining
    var winProbability: (team: String, probability: Double)? {
        if isLive {
            return liveWinProbability
        } else if isScheduled {
            return pregameWinProbability
        }
        return nil
    }

    /// Pre-game win probability — uses ESPN moneyline odds when available, falls back to seed-based
    private var pregameWinProbability: (team: String, probability: Double)? {
        guard let away = awayCompetitor, let home = homeCompetitor else { return nil }

        // Try ESPN odds data first (DraftKings moneyline → real stats-based probability)
        if let odds = competition?.odds?.first,
           let homeProb = odds.homeWinProbability {
            let awayProb = 1.0 - homeProb
            // Remove vig: normalize so probabilities sum to 1
            let favorite = homeProb >= 0.5 ? home : away
            let prob = min(0.97, max(0.50, max(homeProb, awayProb)))
            return (team: favorite.team.abbreviation, probability: prob)
        }

        // Fall back to seed-based estimate
        guard let awaySeed = away.seed, let homeSeed = home.seed,
              awaySeed != homeSeed else { return nil }

        let seedWinRates: [Int: Double] = [
            1: 0.99, 2: 0.94, 3: 0.85, 4: 0.79,
            5: 0.64, 6: 0.63, 7: 0.61, 8: 0.50,
            9: 0.50, 10: 0.39, 11: 0.37, 12: 0.36,
            13: 0.21, 14: 0.15, 15: 0.06, 16: 0.01
        ]

        let favorite = awaySeed < homeSeed ? away : home
        let favSeed = min(awaySeed, homeSeed)
        let favProb = seedWinRates[favSeed] ?? 0.50

        return (team: favorite.team.abbreviation, probability: favProb)
    }

    /// Live win probability — uses ESPN situation data when available, falls back to margin-based model
    private var liveWinProbability: (team: String, probability: Double)? {
        guard let awayComp = awayCompetitor, let homeComp = homeCompetitor else { return nil }

        // Try ESPN's live predictor/situation data first
        if let situation = competition?.situation?.lastPlay?.probability {
            if let homeWP = situation.homeWinPercentage, homeWP > 0 {
                let prob = homeWP / 100.0 // ESPN returns 0-100
                let normalizedProb = prob > 1 ? prob : prob // Handle if already 0-1
                let favorite = normalizedProb >= 0.5 ? homeComp : awayComp
                let winProb = normalizedProb >= 0.5 ? normalizedProb : (1.0 - normalizedProb)
                return (team: favorite.team.abbreviation, probability: min(0.995, winProb))
            }
        }

        // Fall back to margin + time model
        guard let away = awayComp.scoreInt,
              let home = homeComp.scoreInt,
              away != home else { return nil }

        let margin = abs(away - home)
        let leader = away > home ? awayComp : homeComp
        let leaderAbbr = leader.team.abbreviation

        let period = status.period
        let clockSeconds = status.clock ?? 0
        let totalGameSeconds: Double = 2400
        let elapsedSeconds: Double
        if period >= 2 {
            elapsedSeconds = totalGameSeconds - clockSeconds
        } else {
            elapsedSeconds = 1200 - clockSeconds
        }
        let timeFraction = min(1.0, max(0.0, elapsedSeconds / totalGameSeconds))

        let timeWeight = 0.5 + (timeFraction * 2.5)
        let logitValue = Double(margin) * timeWeight * 0.15
        let probability = 1.0 / (1.0 + exp(-logitValue))

        let clampedProb = min(0.995, max(0.50, probability))

        return (team: leaderAbbr, probability: clampedProb)
    }
}

struct Competition: Codable {
    let id: String
    let competitors: [Competitor]
    let venue: Venue?
    let broadcasts: [Broadcast]?
    let notes: [Note]?
    let odds: [GameOdds]?
    let situation: GameSituation?
}

/// ESPN odds data from scoreboard API
struct GameOdds: Codable {
    let homeTeamOdds: TeamOdds?
    let awayTeamOdds: TeamOdds?
    let details: String? // e.g. "UK -3.5"
    let overUnder: Double?
    let spread: Double? // e.g. -3.5 (negative = home favored)
    let moneyline: MoneylineOdds?

    /// Convert moneyline to win probability for home team
    var homeWinProbability: Double? {
        // Try moneyline first (most accurate)
        if let homeOddsStr = moneyline?.home?.close?.odds,
           let prob = Self.moneylineToProbability(homeOddsStr) {
            return prob
        }
        // Fall back to spread conversion
        if let spread = spread {
            // Logistic model: P = 1 / (1 + e^(spread * 0.15))
            // Negative spread = home favored
            return 1.0 / (1.0 + exp(spread * 0.15))
        }
        return nil
    }

    /// Convert American moneyline odds string to implied probability
    static func moneylineToProbability(_ oddsStr: String) -> Double? {
        guard let odds = Double(oddsStr) else { return nil }
        if odds < 0 {
            // Favorite: e.g. -155 → 155/(155+100) = 60.8%
            return abs(odds) / (abs(odds) + 100.0)
        } else if odds > 0 {
            // Underdog: e.g. +130 → 100/(130+100) = 43.5%
            return 100.0 / (odds + 100.0)
        }
        return 0.50
    }
}

struct TeamOdds: Codable {
    let favorite: Bool?
    let underdog: Bool?
}

/// Per-period/per-set score (quarters, innings, sets, halves, etc.)
struct LineScore: Codable {
    let value: Double?
    let displayValue: String?
}

struct MoneylineOdds: Codable {
    let home: MoneylineSide?
    let away: MoneylineSide?
}

struct MoneylineSide: Codable {
    let close: MoneylineValue?
}

struct MoneylineValue: Codable {
    let odds: String?
}

/// ESPN situation/predictor data (live win probability)
struct GameSituation: Codable {
    let lastPlay: LastPlay?
}

struct LastPlay: Codable {
    let probability: PlayProbability?
}

struct PlayProbability: Codable {
    let homeWinPercentage: Double?
    let awayWinPercentage: Double?
}

struct Competitor: Codable {
    let id: String
    let homeAway: String
    let team: TeamInfo
    let score: String?
    let curatedRank: CuratedRank?
    let records: [TeamRecord]?
    let linescores: [LineScore]?
    let winner: Bool?
    let isServing: Bool

    enum CodingKeys: String, CodingKey {
        case id, homeAway, team, athlete, score, curatedRank, records, linescores, winner, possession
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.homeAway = (try? c.decode(String.self, forKey: .homeAway)) ?? ""
        // Some sports (tennis, golf, MMA) use `athlete` instead of `team`
        if let team = try? c.decode(TeamInfo.self, forKey: .team) {
            self.team = team
        } else if let athlete = try? c.decode(TeamInfo.self, forKey: .athlete) {
            self.team = athlete
        } else {
            self.team = TeamInfo(
                id: "", location: "", name: "", abbreviation: "",
                displayName: "", color: nil, alternateColor: nil, logo: nil
            )
        }
        self.score = try? c.decode(String.self, forKey: .score)
        self.curatedRank = try? c.decode(CuratedRank.self, forKey: .curatedRank)
        self.records = try? c.decode([TeamRecord].self, forKey: .records)
        self.linescores = try? c.decode([LineScore].self, forKey: .linescores)
        self.winner = try? c.decode(Bool.self, forKey: .winner)
        self.isServing = (try? c.decode(Bool.self, forKey: .possession)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(homeAway, forKey: .homeAway)
        try c.encode(team, forKey: .team)
        try c.encodeIfPresent(score, forKey: .score)
        try c.encodeIfPresent(curatedRank, forKey: .curatedRank)
        try c.encodeIfPresent(records, forKey: .records)
        try c.encodeIfPresent(linescores, forKey: .linescores)
        try c.encodeIfPresent(winner, forKey: .winner)
    }

    /// Safe score string — never returns nil, empty, or dashes.
    /// For tennis (individual sports) falls back to a set-score summary.
    var safeScore: String {
        if let score, !score.isEmpty, score.contains(where: { $0.isNumber }) {
            return score
        }
        // Tennis: show set scores as "6-4 3-6 7-5"
        if let ls = linescores, !ls.isEmpty {
            let sets = ls.compactMap { $0.value.map { Int($0) } }
            if !sets.isEmpty {
                return sets.map(String.init).joined(separator: " ")
            }
        }
        return "0"
    }

    /// Current game score in a tennis match (0, 15, 30, 40, Ad).
    /// Returns nil for non-tennis sports.
    var tennisGameScore: String? {
        guard let score, !score.isEmpty else { return nil }
        let valid: Set<String> = ["0", "15", "30", "40", "Ad", "love"]
        return valid.contains(score) ? score : nil
    }

    /// Whether this competitor is currently serving (tennis).
    /// Derived from ESPN's `possession` field, which we capture as `isServing`
    /// via the decoder below.
    var isServingTennis: Bool { isServing }

    var scoreInt: Int? {
        guard let score, !score.isEmpty, score.contains(where: { $0.isNumber }) else { return nil }
        return Int(score)
    }

    var seed: Int? {
        curatedRank?.current
    }
}

struct TeamInfo: Codable, Identifiable {
    let id: String
    let location: String
    let name: String
    let abbreviation: String
    let displayName: String
    let color: String?
    let alternateColor: String?
    let logo: String?

    init(
        id: String, location: String, name: String, abbreviation: String,
        displayName: String, color: String?, alternateColor: String?, logo: String?
    ) {
        self.id = id
        self.location = location
        self.name = name
        self.abbreviation = abbreviation
        self.displayName = displayName
        self.color = color
        self.alternateColor = alternateColor
        self.logo = logo
    }

    enum CodingKeys: String, CodingKey {
        case id, location, name, abbreviation, displayName
        case shortName, fullName
        case color, alternateColor, logo, flag, headshot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? ""
        self.location = (try? c.decode(String.self, forKey: .location)) ?? ""
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        // Tennis/golf athletes often only have displayName + shortName
        let displayName = (try? c.decode(String.self, forKey: .displayName))
            ?? (try? c.decode(String.self, forKey: .fullName))
            ?? ""
        self.displayName = displayName
        // Abbreviation fallback: shortName, or first+last initials, or displayName
        if let abbr = try? c.decode(String.self, forKey: .abbreviation) {
            self.abbreviation = abbr
        } else if let short = try? c.decode(String.self, forKey: .shortName) {
            self.abbreviation = short
        } else if !displayName.isEmpty {
            // Last name for individual athletes
            self.abbreviation = String(displayName.components(separatedBy: " ").last?.prefix(4) ?? "")
        } else {
            self.abbreviation = ""
        }
        self.color = try? c.decode(String.self, forKey: .color)
        self.alternateColor = try? c.decode(String.self, forKey: .alternateColor)
        // Logo: try logo, then flag.href (tennis), then headshot.href (golf/mma)
        if let logo = try? c.decode(String.self, forKey: .logo) {
            self.logo = logo
        } else if let flagObj = try? c.decode([String: String].self, forKey: .flag) {
            self.logo = flagObj["href"]
        } else if let headshotObj = try? c.decode([String: String].self, forKey: .headshot) {
            self.logo = headshotObj["href"]
        } else {
            self.logo = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(location, forKey: .location)
        try c.encode(name, forKey: .name)
        try c.encode(abbreviation, forKey: .abbreviation)
        try c.encode(displayName, forKey: .displayName)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(alternateColor, forKey: .alternateColor)
        try c.encodeIfPresent(logo, forKey: .logo)
    }

    var logoURL: URL? {
        guard let logo else { return nil }
        return URL(string: logo)
    }
}

struct CuratedRank: Codable {
    let current: Int?
}

struct TeamRecord: Codable {
    let summary: String?
    let type: String?
}

struct GameStatus: Codable {
    let clock: Double?
    let displayClock: String?
    let period: Int
    let type: StatusType
}

struct StatusType: Codable {
    let id: String
    let name: String
    let state: String
    let completed: Bool
    let detail: String?
    let shortDetail: String?
}

struct Note: Codable {
    let headline: String?
}

struct Venue: Codable {
    let fullName: String?
    let city: String?
    let state: String?
}

struct Broadcast: Codable {
    let names: [String]?
}
