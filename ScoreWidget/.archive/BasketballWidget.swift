import WidgetKit
import SwiftUI

// MARK: - Basketball Widget

struct BasketballWidget: Widget {
    let kind = "BasketballWidget_v1"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BasketballProvider()) { entry in
            BasketballWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Basketball")
        .description("Live scores with shot chart on a drawn basketball court")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Models

struct ScoringPlay: Equatable {
    let x: Double            // 0-50 court coordinate
    let y: Double            // 0-28 court coordinate
    let scoreValue: Int      // 2 or 3
    let shotType: String     // "Pullup Jump Shot", "Three Point", "Layup"
    let playerName: String   // short name extracted from play text
    let teamID: String       // "home" or "away"
    let awayScore: String
    let homeScore: String
}

struct BasketballTeamInfo: Equatable {
    let abbreviation: String
    let score: String
    let colorHex: String
    let record: String?
}

enum BasketballGameState: String {
    case pre, live, post, noGame
}

// MARK: - Entry

struct BasketballEntry: TimelineEntry {
    let date: Date
    let state: BasketballGameState
    let awayTeam: BasketballTeamInfo
    let homeTeam: BasketballTeamInfo
    let period: Int
    let clock: String
    let shotClock: String?
    let possession: String?
    let leagueAbbr: String
    let isCollege: Bool
    let startDate: Date?
    let scoringPlays: [ScoringPlay]  // most recent first, up to 5
}

// MARK: - Provider

struct BasketballProvider: TimelineProvider {
    private static let basketballLeagues: [(path: String, abbr: String, isCollege: Bool)] = [
        ("basketball/nba", "NBA", false),
        ("basketball/mens-college-basketball", "NCAAM", true),
        ("basketball/womens-college-basketball", "NCAAW", true),
        ("basketball/wnba", "WNBA", false),
    ]

    private static let dateFormats: [String] = [
        "yyyy-MM-dd'T'HH:mm'Z'",
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "yyyy-MM-dd'T'HH:mmZ",
        "yyyy-MM-dd'T'HH:mm:ssZ",
    ]

    func placeholder(in context: Context) -> BasketballEntry { Self.sampleEntry }

    func getSnapshot(in context: Context, completion: @escaping (BasketballEntry) -> Void) {
        fetchBestGame { completion($0 ?? Self.sampleEntry) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BasketballEntry>) -> Void) {
        // Ensure completion is called exactly once — WidgetKit preempts the
        // extension aggressively, so guarantee a fallback timeline ships.
        let lock = NSLock()
        var fired = false
        func fire(_ timeline: Timeline<BasketballEntry>) {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            lock.unlock()
            completion(timeline)
        }
        let wrappedCompletion: (Timeline<BasketballEntry>) -> Void = fire
        DispatchQueue.global().asyncAfter(deadline: .now() + 4.5) {
            fire(Timeline(entries: [self.placeholder(in: context)], policy: .after(Date().addingTimeInterval(60))))
        }

        fetchBestGame { entry in
            let final = entry ?? Self.sampleEntry
            let refreshMinutes: Int = final.state == .live ? 1 : 15
            let refresh = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: Date())!
            wrappedCompletion(Timeline(entries: [final], policy: .after(refresh)))
        }
    }

    // MARK: - Fetch Best Game (Scoreboard scan)

    private func fetchBestGame(completion: @escaping (BasketballEntry?) -> Void) {
        let group = DispatchGroup()
        var bestCandidate: (entry: BasketballEntry, eventID: String, leaguePath: String)? = nil
        let lock = NSLock()

        for league in Self.basketballLeagues {
            group.enter()
            let urlStr = "https://site.api.espn.com/apis/site/v2/sports/\(league.path)/scoreboard"
            guard let url = URL(string: urlStr) else { group.leave(); continue }

            URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)) { data, _, _ in
                defer { group.leave() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let events = json["events"] as? [[String: Any]] else { return }

                for event in events {
                    if let parsed = Self.parseScoreboardEvent(event, league: league.abbr, isCollege: league.isCollege) {
                        let eventID = event["id"] as? String ?? ""
                        lock.lock()
                        let dominated = Self.shouldReplace(current: bestCandidate?.entry, with: parsed)
                        if dominated {
                            bestCandidate = (parsed, eventID, league.path)
                        }
                        lock.unlock()
                    }
                }
            }.resume()
        }

        group.notify(queue: .main) {
            guard let candidate = bestCandidate, !candidate.eventID.isEmpty else {
                completion(nil)
                return
            }
            // Now fetch the summary endpoint for play-by-play data
            self.fetchSummary(eventID: candidate.eventID, leaguePath: candidate.leaguePath, baseEntry: candidate.entry, completion: completion)
        }
    }

    // MARK: - Fetch Summary (Play-by-Play)

    private func fetchSummary(eventID: String, leaguePath: String, baseEntry: BasketballEntry, completion: @escaping (BasketballEntry?) -> Void) {
        let urlStr = "https://site.api.espn.com/apis/site/v2/sports/\(leaguePath)/summary?event=\(eventID)"
        guard let url = URL(string: urlStr) else {
            completion(baseEntry)
            return
        }

        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(baseEntry)
                return
            }

            let plays = Self.extractScoringPlays(from: json, baseEntry: baseEntry)

            let updated = BasketballEntry(
                date: baseEntry.date,
                state: baseEntry.state,
                awayTeam: baseEntry.awayTeam,
                homeTeam: baseEntry.homeTeam,
                period: baseEntry.period,
                clock: baseEntry.clock,
                shotClock: baseEntry.shotClock,
                possession: baseEntry.possession,
                leagueAbbr: baseEntry.leagueAbbr,
                isCollege: baseEntry.isCollege,
                startDate: baseEntry.startDate,
                scoringPlays: plays
            )
            completion(updated)
        }.resume()
    }

    // MARK: - Parse Scoreboard Event

    private static func parseScoreboardEvent(_ event: [String: Any], league: String, isCollege: Bool) -> BasketballEntry? {
        let competitions = event["competitions"] as? [[String: Any]] ?? []
        guard let comp = competitions.first else { return nil }

        let statusDict = comp["status"] as? [String: Any] ?? [:]
        let statusType = statusDict["type"] as? [String: Any] ?? [:]
        let stateStr = statusType["state"] as? String ?? "pre"
        let displayClock = statusDict["displayClock"] as? String ?? ""
        let period = statusDict["period"] as? Int ?? 0

        let state: BasketballGameState
        switch stateStr {
        case "in": state = .live
        case "post": state = .post
        default: state = .pre
        }

        let competitors = comp["competitors"] as? [[String: Any]] ?? []
        var away = BasketballTeamInfo(abbreviation: "???", score: "0", colorHex: "333333", record: nil)
        var home = BasketballTeamInfo(abbreviation: "???", score: "0", colorHex: "333333", record: nil)

        for c in competitors {
            let teamDict = c["team"] as? [String: Any] ?? [:]
            let abbr = teamDict["abbreviation"] as? String ?? "???"
            let colorHex = teamDict["color"] as? String ?? "333333"
            let score = c["score"] as? String ?? "0"
            let homeAway = c["homeAway"] as? String ?? ""
            let records = c["records"] as? [[String: Any]]
            let record = records?.first?["summary"] as? String

            let info = BasketballTeamInfo(abbreviation: abbr, score: score, colorHex: colorHex, record: record)
            if homeAway == "home" { home = info } else { away = info }
        }

        let situation = comp["situation"] as? [String: Any]
        let shotClock: String? = {
            if let sc = situation?["shotClock"] as? Int { return "\(sc)" }
            return nil
        }()
        let possession: String? = situation?["possession"] as? String

        let dateStr = comp["date"] as? String ?? event["date"] as? String ?? ""
        let startDate = parseDate(dateStr)

        return BasketballEntry(
            date: Date(),
            state: state,
            awayTeam: away,
            homeTeam: home,
            period: period,
            clock: displayClock,
            shotClock: shotClock,
            possession: possession,
            leagueAbbr: league,
            isCollege: isCollege,
            startDate: startDate,
            scoringPlays: []
        )
    }

    // MARK: - Extract Scoring Plays from Summary

    private static func extractScoringPlays(from json: [String: Any], baseEntry: BasketballEntry) -> [ScoringPlay] {
        // The summary endpoint nests plays under "plays" -> array of play items
        // Each play item has: text, type.text, coordinate.x, coordinate.y,
        //                      scoreValue, shootingPlay, awayScore, homeScore,
        //                      team.id
        var scoringPlays: [ScoringPlay] = []

        // Try multiple paths for plays data
        let playsArray: [[String: Any]]
        if let plays = json["plays"] as? [[String: Any]] {
            playsArray = plays
        } else if let playsWrapper = json["plays"] as? [String: Any],
                  let items = playsWrapper["items"] as? [[String: Any]] {
            playsArray = items
        } else {
            // Try under drives -> previous -> plays pattern, or flat keyPlays
            if let keyPlays = json["keyPlays"] as? [[String: Any]] {
                playsArray = keyPlays
            } else {
                playsArray = []
            }
        }

        // Also try scoringPlays shortcut
        let scoringPlaysArray: [[String: Any]]
        if let sp = json["scoringPlays"] as? [[String: Any]] {
            scoringPlaysArray = sp
        } else {
            scoringPlaysArray = []
        }

        let combined = scoringPlaysArray.isEmpty ? playsArray : scoringPlaysArray + playsArray

        // Determine team IDs from the header/boxscore/competitors
        let homeAbbr = baseEntry.homeTeam.abbreviation
        let awayAbbr = baseEntry.awayTeam.abbreviation
        var teamIDToSide: [String: String] = [:]

        if let header = json["header"] as? [String: Any],
           let competitions = header["competitions"] as? [[String: Any]],
           let comp = competitions.first,
           let competitors = comp["competitors"] as? [[String: Any]] {
            for c in competitors {
                let ha = c["homeAway"] as? String ?? ""
                let id = c["id"] as? String ?? ""
                let teamInfo = c["team"] as? [String: Any]
                let displayName = teamInfo?["abbreviation"] as? String ?? ""
                if !id.isEmpty {
                    teamIDToSide[id] = ha
                }
                if !displayName.isEmpty {
                    teamIDToSide[displayName] = ha
                }
            }
        }

        for play in combined {
            guard let shootingPlay = play["shootingPlay"] as? Bool, shootingPlay else { continue }
            guard let scoreValue = play["scoreValue"] as? Int, scoreValue > 0 else { continue }
            guard let coordinate = play["coordinate"] as? [String: Any],
                  let cx = coordinate["x"] as? Double,
                  let cy = coordinate["y"] as? Double else { continue }

            let text = play["text"] as? String ?? ""
            let typeDict = play["type"] as? [String: Any] ?? [:]
            let shotType = typeDict["text"] as? String ?? "Shot"
            let awayScoreVal = play["awayScore"] as? Int
            let homeScoreVal = play["homeScore"] as? Int
            let awaySc = awayScoreVal.map { String($0) } ?? baseEntry.awayTeam.score
            let homeSc = homeScoreVal.map { String($0) } ?? baseEntry.homeTeam.score

            // Determine team side
            var teamSide = "home"
            if let teamDict = play["team"] as? [String: Any] {
                let teamIDStr = teamDict["id"] as? String ?? ""
                if let side = teamIDToSide[teamIDStr] {
                    teamSide = side
                }
            }

            // If text mentions the away team abbr, assign to away
            if text.localizedCaseInsensitiveContains(awayAbbr) {
                teamSide = "away"
            } else if text.localizedCaseInsensitiveContains(homeAbbr) {
                teamSide = "home"
            }

            let playerName = Self.extractPlayerName(from: text)

            let sp = ScoringPlay(
                x: cx, y: cy,
                scoreValue: scoreValue,
                shotType: shotType,
                playerName: playerName,
                teamID: teamSide,
                awayScore: awaySc,
                homeScore: homeSc
            )
            scoringPlays.append(sp)
        }

        // Remove duplicates based on coordinates and score
        var seen = Set<String>()
        var unique: [ScoringPlay] = []
        for sp in scoringPlays {
            let key = "\(sp.x)-\(sp.y)-\(sp.awayScore)-\(sp.homeScore)"
            if seen.insert(key).inserted {
                unique.append(sp)
            }
        }

        // Return the last 5 scoring plays (most recent first)
        return Array(unique.suffix(5).reversed())
    }

    /// Extract a short player name from the play text.
    /// e.g. "Daniss Jenkins makes 19-foot pullup jump shot" -> "Jenkins"
    private static func extractPlayerName(from text: String) -> String {
        // Pattern: name is everything before "makes" or "misses"
        let keywords = [" makes ", " made ", " hits "]
        for kw in keywords {
            if let range = text.range(of: kw, options: .caseInsensitive) {
                let before = String(text[text.startIndex..<range.lowerBound])
                let parts = before.split(separator: " ")
                if let last = parts.last {
                    return String(last)
                }
                return before
            }
        }
        // Fallback: first two words
        let parts = text.split(separator: " ")
        if parts.count >= 2 { return String(parts[1]) }
        if let first = parts.first { return String(first) }
        return ""
    }

    // MARK: - Priority

    private static func shouldReplace(current: BasketballEntry?, with candidate: BasketballEntry) -> Bool {
        guard let current = current else { return true }
        let priority: [BasketballGameState] = [.live, .pre, .post, .noGame]
        let curIdx = priority.firstIndex(of: current.state) ?? 3
        let newIdx = priority.firstIndex(of: candidate.state) ?? 3
        if newIdx < curIdx { return true }
        if newIdx == curIdx && candidate.state == .pre {
            return (candidate.startDate ?? .distantFuture) < (current.startDate ?? .distantFuture)
        }
        return false
    }

    // MARK: - Date Parsing

    private static func parseDate(_ s: String) -> Date? {
        for fmt in dateFormats {
            let df = DateFormatter()
            df.dateFormat = fmt
            df.timeZone = TimeZone(identifier: "UTC")
            if let d = df.date(from: s) { return d }
        }
        let iso = ISO8601DateFormatter()
        return iso.date(from: s)
    }

    // MARK: - Sample

    static let sampleEntry = BasketballEntry(
        date: Date(),
        state: .live,
        awayTeam: BasketballTeamInfo(abbreviation: "LAL", score: "54", colorHex: "552583", record: "35-20"),
        homeTeam: BasketballTeamInfo(abbreviation: "BOS", score: "58", colorHex: "007A33", record: "42-13"),
        period: 3,
        clock: "5:42",
        shotClock: "14",
        possession: "home",
        leagueAbbr: "NBA",
        isCollege: false,
        startDate: nil,
        scoringPlays: [
            ScoringPlay(x: 25, y: 8, scoreValue: 3, shotType: "Three Point", playerName: "Tatum", teamID: "home", awayScore: "52", homeScore: "55"),
            ScoringPlay(x: 8, y: 14, scoreValue: 2, shotType: "Layup", playerName: "James", teamID: "away", awayScore: "54", homeScore: "55"),
            ScoringPlay(x: 38, y: 10, scoreValue: 2, shotType: "Pullup Jump Shot", playerName: "Brown", teamID: "home", awayScore: "54", homeScore: "57"),
            ScoringPlay(x: 42, y: 18, scoreValue: 3, shotType: "Three Point", playerName: "White", teamID: "home", awayScore: "54", homeScore: "58"),
        ]
    )
}

// MARK: - Widget View

struct BasketballWidgetView: View {
    let entry: BasketballEntry
    @Environment(\.widgetFamily) var family

    private static let countdownFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E h:mm a"
        return f
    }()

    var body: some View {
        switch family {
        case .systemMedium: mediumView
        case .systemLarge: largeView
        default: mediumView
        }
    }

    // MARK: - Medium Layout

    private var mediumView: some View {
        GeometryReader { geo in
            ZStack {
                CourtDrawing(width: geo.size.width, height: geo.size.height)
                shotDotsOverlay(width: geo.size.width, height: geo.size.height)
                courtOverlay(width: geo.size.width, height: geo.size.height, large: false)
            }
        }
    }

    // MARK: - Large Layout

    private var largeView: some View {
        GeometryReader { geo in
            let courtHeight = geo.size.height * 0.62
            VStack(spacing: 0) {
                ZStack {
                    CourtDrawing(width: geo.size.width, height: courtHeight)
                    shotDotsOverlay(width: geo.size.width, height: courtHeight)
                    courtOverlay(width: geo.size.width, height: courtHeight, large: true)
                }
                .frame(height: courtHeight)

                // Play-by-play text list below the court
                playListView(width: geo.size.width, height: geo.size.height - courtHeight)
            }
        }
    }

    // MARK: - Play List (Large widget only)

    private func playListView(width: Double, height: Double) -> some View {
        let awayColor = Color(hex: entry.awayTeam.colorHex) ?? .blue
        let homeColor = Color(hex: entry.homeTeam.colorHex) ?? .red
        let plays = Array(entry.scoringPlays.prefix(3))

        return VStack(alignment: .leading, spacing: 2) {
            if plays.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("No scoring plays yet")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(Array(plays.enumerated()), id: \.offset) { idx, play in
                    HStack(spacing: 4) {
                        // Team color indicator
                        Circle()
                            .fill(play.teamID == "home" ? homeColor : awayColor)
                            .frame(width: 6, height: 6)

                        // Score value badge
                        if play.scoreValue == 3 {
                            Text("3")
                                .font(.system(size: 8, weight: .black))
                                .foregroundColor(.yellow)
                                .frame(width: 12, height: 12)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        } else {
                            Text("2")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 12, height: 12)
                        }

                        // Player name and shot type
                        Text("\(play.playerName)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.primary)
                        Text(play.shotType)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Spacer()

                        // Running score
                        Text("\(play.awayScore)-\(play.homeScore)")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .opacity(idx == 0 ? 1.0 : 0.65)
                }
            }
        }
        .frame(width: width, height: height)
        .background(Color.black.opacity(0.85))
    }

    // MARK: - Shot Dots Overlay

    private func shotDotsOverlay(width: Double, height: Double) -> some View {
        let awayColor = Color(hex: entry.awayTeam.colorHex) ?? .blue
        let homeColor = Color(hex: entry.homeTeam.colorHex) ?? .red
        let plays = entry.scoringPlays
        let courtPadding: Double = 4
        let courtW = width - courtPadding * 2
        let courtH = height - courtPadding * 2

        return ZStack {
            ForEach(Array(plays.enumerated()), id: \.offset) { idx, play in
                let px = courtPadding + (play.x / 50.0) * courtW
                let py = courtPadding + (play.y / 28.0) * courtH
                let isNewest = idx == 0
                let opacity = isNewest ? 1.0 : max(0.35, 1.0 - Double(idx) * 0.18)
                let dotSize: CGFloat = isNewest ? 14 : max(7, 12 - CGFloat(idx) * 1.5)
                let teamColor = play.teamID == "home" ? homeColor : awayColor

                ZStack {
                    // Glow for newest
                    if isNewest {
                        Circle()
                            .fill(teamColor.opacity(0.4))
                            .frame(width: dotSize + 8, height: dotSize + 8)
                    }

                    if play.scoreValue == 3 {
                        // Three-pointer: star marker
                        ZStack {
                            Image(systemName: "star.fill")
                                .font(.system(size: dotSize * 0.9))
                                .foregroundColor(teamColor)
                                .shadow(color: .black, radius: 1.5, x: 0, y: 1)
                            Text("3")
                                .font(.system(size: dotSize * 0.4, weight: .black))
                                .foregroundColor(.white)
                        }
                    } else {
                        Circle()
                            .fill(teamColor)
                            .frame(width: dotSize, height: dotSize)
                            .shadow(color: .black.opacity(0.5), radius: 1.5, x: 0, y: 1)
                    }

                    // Label for the most recent shot
                    if isNewest && !play.playerName.isEmpty {
                        VStack(spacing: 0) {
                            Text(play.playerName)
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundColor(.white)
                            Text(shortShotType(play.shotType))
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.black.opacity(0.75))
                        )
                        .offset(y: -dotSize - 6)
                    }
                }
                .position(x: px, y: py)
                .opacity(opacity)
            }
        }
    }

    private func shortShotType(_ type: String) -> String {
        let lower = type.lowercased()
        if lower.contains("three") || lower.contains("3-pt") || lower.contains("3pt") { return "3PT" }
        if lower.contains("layup") { return "LAYUP" }
        if lower.contains("dunk") { return "DUNK" }
        if lower.contains("free throw") { return "FT" }
        if lower.contains("hook") { return "HOOK" }
        if lower.contains("tip") { return "TIP" }
        if lower.contains("pullup") || lower.contains("pull-up") { return "PULLUP" }
        if lower.contains("jumper") || lower.contains("jump shot") { return "JUMPER" }
        if lower.contains("float") { return "FLOATER" }
        if lower.contains("fade") { return "FADE" }
        return "SHOT"
    }

    // MARK: - Court Overlay (Scores/Clock)

    private func courtOverlay(width: Double, height: Double, large: Bool) -> some View {
        let awayColor = Color(hex: entry.awayTeam.colorHex) ?? .blue
        let homeColor = Color(hex: entry.homeTeam.colorHex) ?? .red

        return ZStack {
            // Subtle team color tints
            HStack(spacing: 0) {
                awayColor.opacity(0.06)
                homeColor.opacity(0.06)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // League badge top-left
            VStack {
                HStack {
                    Text(entry.leagueAbbr)
                        .font(.system(size: large ? 9 : 7, weight: .heavy))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.black.opacity(0.4)))
                    Spacer()
                    if entry.state == .live {
                        HStack(spacing: 2) {
                            Circle().fill(.green).frame(width: 5, height: 5)
                            Text("LIVE")
                                .font(.system(size: large ? 8 : 6, weight: .heavy))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.black.opacity(0.4)))
                    }
                }
                .padding(6)
                Spacer()
            }

            switch entry.state {
            case .live:
                liveOverlay(width: width, height: height, large: large,
                            awayColor: awayColor, homeColor: homeColor)
            case .pre:
                preGameOverlay(width: width, height: height, large: large,
                               awayColor: awayColor, homeColor: homeColor)
            case .post:
                postGameOverlay(width: width, height: height, large: large,
                                awayColor: awayColor, homeColor: homeColor)
            case .noGame:
                noGameOverlay(large: large)
            }
        }
    }

    // MARK: - Live Game Overlay

    private func liveOverlay(width: Double, height: Double, large: Bool,
                             awayColor: Color, homeColor: Color) -> some View {
        let scoreFontSize: CGFloat = large ? 28 : 20
        let teamFontSize: CGFloat = large ? 12 : 10

        return ZStack {
            // Center scoreboard pill
            VStack(spacing: 1) {
                // Period label
                Text(periodLabel)
                    .font(.system(size: large ? 8 : 7, weight: .heavy))
                    .foregroundColor(.white.opacity(0.9))

                // Score line: AWAY score - HOME score
                HStack(spacing: 4) {
                    Text(entry.awayTeam.abbreviation)
                        .font(.system(size: teamFontSize, weight: .heavy))
                        .foregroundColor(.white)
                    Text(entry.awayTeam.score)
                        .font(.system(size: scoreFontSize, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: awayColor.opacity(0.8), radius: 3, x: 0, y: 0)

                    Text("-")
                        .font(.system(size: scoreFontSize * 0.7, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))

                    Text(entry.homeTeam.score)
                        .font(.system(size: scoreFontSize, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: homeColor.opacity(0.8), radius: 3, x: 0, y: 0)
                    Text(entry.homeTeam.abbreviation)
                        .font(.system(size: teamFontSize, weight: .heavy))
                        .foregroundColor(.white)
                }

                // Clock
                Text(entry.clock)
                    .font(.system(size: large ? 13 : 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white)

                // Shot clock
                if let sc = entry.shotClock {
                    Text(sc)
                        .font(.system(size: large ? 9 : 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.black.opacity(0.5)))
                }

                // Possession indicator
                if let poss = entry.possession {
                    HStack(spacing: 2) {
                        if poss == "away" {
                            Image(systemName: "basketball.fill")
                                .font(.system(size: 5))
                                .foregroundColor(.orange)
                        }
                        Spacer().frame(width: 0)
                        if poss == "home" {
                            Image(systemName: "basketball.fill")
                                .font(.system(size: 5))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding(.horizontal, large ? 10 : 6)
            .padding(.vertical, large ? 6 : 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
            )
            .position(x: width / 2, y: height / 2)
        }
    }

    // MARK: - Pre-Game Overlay

    private func preGameOverlay(width: Double, height: Double, large: Bool,
                                awayColor: Color, homeColor: Color) -> some View {
        let teamFontSize: CGFloat = large ? 18 : 14
        let centerY = height / 2

        return ZStack {
            VStack(spacing: 4) {
                HStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text(entry.awayTeam.abbreviation)
                            .font(.system(size: teamFontSize, weight: .heavy))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 2, x: 0, y: 1)
                        if let record = entry.awayTeam.record {
                            Text(record)
                                .font(.system(size: large ? 9 : 7, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    Text("VS")
                        .font(.system(size: large ? 14 : 10, weight: .black))
                        .foregroundColor(.white.opacity(0.5))

                    VStack(spacing: 2) {
                        Text(entry.homeTeam.abbreviation)
                            .font(.system(size: teamFontSize, weight: .heavy))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 2, x: 0, y: 1)
                        if let record = entry.homeTeam.record {
                            Text(record)
                                .font(.system(size: large ? 9 : 7, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }

                if let start = entry.startDate {
                    let diff = start.timeIntervalSince(entry.date)
                    if diff > 0 {
                        Text(countdownString(diff))
                            .font(.system(size: large ? 12 : 9, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                        Text(Self.countdownFormatter.string(from: start))
                            .font(.system(size: large ? 8 : 6, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            )
            .position(x: width / 2, y: centerY)
        }
    }

    // MARK: - Post-Game Overlay

    private func postGameOverlay(width: Double, height: Double, large: Bool,
                                 awayColor: Color, homeColor: Color) -> some View {
        let scoreFontSize: CGFloat = large ? 26 : 18
        let teamFontSize: CGFloat = large ? 12 : 10

        let awayScore = Int(entry.awayTeam.score) ?? 0
        let homeScore = Int(entry.homeTeam.score) ?? 0
        let awayWon = awayScore > homeScore

        return ZStack {
            VStack(spacing: 2) {
                Text("FINAL")
                    .font(.system(size: large ? 10 : 8, weight: .black))
                    .foregroundColor(.white.opacity(0.8))
                if entry.period > (entry.isCollege ? 2 : 4) {
                    Text("OT")
                        .font(.system(size: large ? 8 : 7, weight: .heavy))
                        .foregroundColor(.orange)
                }

                HStack(spacing: 4) {
                    Text(entry.awayTeam.abbreviation)
                        .font(.system(size: teamFontSize, weight: .heavy))
                        .foregroundColor(.white)
                    Text(entry.awayTeam.score)
                        .font(.system(size: scoreFontSize, weight: .black, design: .rounded))
                        .foregroundColor(awayWon ? .white : .white.opacity(0.5))
                        .shadow(color: .black, radius: 2, x: 0, y: 1)

                    Text("-")
                        .font(.system(size: scoreFontSize * 0.6, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))

                    Text(entry.homeTeam.score)
                        .font(.system(size: scoreFontSize, weight: .black, design: .rounded))
                        .foregroundColor(!awayWon ? .white : .white.opacity(0.5))
                        .shadow(color: .black, radius: 2, x: 0, y: 1)
                    Text(entry.homeTeam.abbreviation)
                        .font(.system(size: teamFontSize, weight: .heavy))
                        .foregroundColor(.white)
                }

                Text(awayWon ? "\(entry.awayTeam.abbreviation) WIN" : "\(entry.homeTeam.abbreviation) WIN")
                    .font(.system(size: large ? 8 : 6, weight: .heavy))
                    .foregroundColor(.yellow)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            )
            .position(x: width / 2, y: height / 2)
        }
    }

    // MARK: - No Game Overlay

    private func noGameOverlay(large: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "basketball.fill")
                .font(.system(size: large ? 28 : 20))
                .foregroundColor(.white.opacity(0.5))
            Text("No Games")
                .font(.system(size: large ? 14 : 11, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Helpers

    private var periodLabel: String {
        if entry.isCollege {
            switch entry.period {
            case 1: return "1ST HALF"
            case 2: return "2ND HALF"
            default: return "OT"
            }
        } else {
            switch entry.period {
            case 1: return "Q1"
            case 2: return "Q2"
            case 3: return "Q3"
            case 4: return "Q4"
            default: return "OT"
            }
        }
    }

    private func countdownString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let mins = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}

// MARK: - Court Drawing

private struct CourtDrawing: View {
    let width: Double
    let height: Double

    private let hardwood = Color(red: 0.769, green: 0.635, blue: 0.396)
    private let hardwoodDark = Color(red: 0.659, green: 0.525, blue: 0.306)
    private let lineColor = Color.white.opacity(0.85)
    private let lineWidth: CGFloat = 1.2

    var body: some View {
        ZStack {
            hardwood
            plankLines

            Canvas { context, size in
                let w = size.width
                let h = size.height
                let midX = w / 2
                let midY = h / 2
                let keyWidth = w * 0.12
                let keyHeight = h * 0.55
                let threePointRadius = h * 0.42

                // Court outline
                let outline = Path(roundedRect: CGRect(x: 2, y: 2, width: w - 4, height: h - 4),
                                   cornerRadius: 4)
                context.stroke(outline, with: .color(lineColor), lineWidth: lineWidth + 0.5)

                // Half court line
                var halfLine = Path()
                halfLine.move(to: CGPoint(x: midX, y: 2))
                halfLine.addLine(to: CGPoint(x: midX, y: h - 2))
                context.stroke(halfLine, with: .color(lineColor), lineWidth: lineWidth)

                // Center circle
                let centerCircleR = min(w, h) * 0.14
                let centerCircle = Path(ellipseIn: CGRect(
                    x: midX - centerCircleR, y: midY - centerCircleR,
                    width: centerCircleR * 2, height: centerCircleR * 2))
                context.stroke(centerCircle, with: .color(lineColor), lineWidth: lineWidth)

                // Left key
                let leftKeyRect = CGRect(x: 2, y: midY - keyHeight / 2,
                                         width: keyWidth, height: keyHeight)
                let leftKey = Path(roundedRect: leftKeyRect, cornerRadius: 0)
                context.stroke(leftKey, with: .color(lineColor), lineWidth: lineWidth)

                // Left free throw circle
                let ftCircleR = keyHeight * 0.3
                let leftFTCircle = Path(ellipseIn: CGRect(
                    x: keyWidth - ftCircleR, y: midY - ftCircleR,
                    width: ftCircleR * 2, height: ftCircleR * 2))
                context.stroke(leftFTCircle, with: .color(lineColor.opacity(0.5)), lineWidth: 0.8)

                // Right key
                let rightKeyRect = CGRect(x: w - keyWidth - 2, y: midY - keyHeight / 2,
                                          width: keyWidth, height: keyHeight)
                let rightKey = Path(roundedRect: rightKeyRect, cornerRadius: 0)
                context.stroke(rightKey, with: .color(lineColor), lineWidth: lineWidth)

                // Right free throw circle
                let rightFTCircle = Path(ellipseIn: CGRect(
                    x: w - keyWidth - ftCircleR, y: midY - ftCircleR,
                    width: ftCircleR * 2, height: ftCircleR * 2))
                context.stroke(rightFTCircle, with: .color(lineColor.opacity(0.5)), lineWidth: 0.8)

                // Left three-point arc
                var leftArc = Path()
                leftArc.move(to: CGPoint(x: 2, y: midY - threePointRadius))
                leftArc.addArc(center: CGPoint(x: keyWidth * 0.4, y: midY),
                               radius: threePointRadius,
                               startAngle: .degrees(-80), endAngle: .degrees(80),
                               clockwise: false)
                leftArc.addLine(to: CGPoint(x: 2, y: midY + threePointRadius))
                context.stroke(leftArc, with: .color(lineColor), lineWidth: lineWidth)

                // Right three-point arc
                var rightArc = Path()
                rightArc.move(to: CGPoint(x: w - 2, y: midY - threePointRadius))
                rightArc.addArc(center: CGPoint(x: w - keyWidth * 0.4, y: midY),
                                radius: threePointRadius,
                                startAngle: .degrees(-100), endAngle: .degrees(100),
                                clockwise: true)
                rightArc.addLine(to: CGPoint(x: w - 2, y: midY + threePointRadius))
                context.stroke(rightArc, with: .color(lineColor), lineWidth: lineWidth)

                // Basket circles
                let basketR: CGFloat = 3
                let leftBasket = Path(ellipseIn: CGRect(
                    x: keyWidth * 0.35 - basketR, y: midY - basketR,
                    width: basketR * 2, height: basketR * 2))
                context.stroke(leftBasket, with: .color(.orange.opacity(0.8)), lineWidth: 1.5)

                let rightBasket = Path(ellipseIn: CGRect(
                    x: w - keyWidth * 0.35 - basketR, y: midY - basketR,
                    width: basketR * 2, height: basketR * 2))
                context.stroke(rightBasket, with: .color(.orange.opacity(0.8)), lineWidth: 1.5)

                // Backboard lines
                var leftBoard = Path()
                leftBoard.move(to: CGPoint(x: keyWidth * 0.25, y: midY - h * 0.08))
                leftBoard.addLine(to: CGPoint(x: keyWidth * 0.25, y: midY + h * 0.08))
                context.stroke(leftBoard, with: .color(lineColor.opacity(0.6)), lineWidth: 1.5)

                var rightBoard = Path()
                rightBoard.move(to: CGPoint(x: w - keyWidth * 0.25, y: midY - h * 0.08))
                rightBoard.addLine(to: CGPoint(x: w - keyWidth * 0.25, y: midY + h * 0.08))
                context.stroke(rightBoard, with: .color(lineColor.opacity(0.6)), lineWidth: 1.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var plankLines: some View {
        Canvas { context, size in
            let spacing: CGFloat = size.height * 0.12
            var y: CGFloat = spacing
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(hardwoodDark.opacity(0.25)), lineWidth: 0.5)
                y += spacing
            }
        }
    }
}

// MARK: - Color Hex Extension

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&rgb) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
