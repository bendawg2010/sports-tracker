import WidgetKit
import SwiftUI

// MARK: - Hockey Widget

struct HockeyWidget: Widget {
    let kind = "HockeyWidget_v1"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HockeyProvider()) { entry in
            HockeyWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Hockey")
        .description("Live NHL action on a drawn hockey rink")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Color Helper

private enum HockeyColorHelper {
    static func color(hex: String) -> Color? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&rgb) else { return nil }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

// MARK: - Models

struct HockeyEntry: TimelineEntry {
    let date: Date
    let state: HockeyGameState
    let awayTeam: HockeyTeamInfo
    let homeTeam: HockeyTeamInfo
    let period: Int
    let clock: String
    let awayShotsOnGoal: Int?
    let homeShotsOnGoal: Int?
    let powerPlay: HockeyPowerPlay?
    let startDate: Date?
    let recentPlays: [HockeyPlay]
    let scoringPlays: [HockeyScoringPlay]
    let penalizedPlayers: [HockeyPenalty]
}

enum HockeyGameState: String {
    case pre, live, post, noGame
}

struct HockeyTeamInfo {
    let abbreviation: String
    let score: String
    let colorHex: String
    let record: String?
}

struct HockeyPowerPlay {
    let teamAbbr: String
    let strength: String
    let timeRemaining: String?
}

struct HockeyPlay: Identifiable {
    let id: String
    let text: String
    let type: HockeyPlayType
    let periodNumber: Int
    let clockTime: String
    let teamAbbr: String?
}

enum HockeyPlayType: String {
    case goal, penalty, shot, other
}

struct HockeyScoringPlay: Identifiable {
    let id: String
    let scorerName: String
    let teamAbbr: String
    let period: Int
    let clockTime: String
    let isHome: Bool
}

struct HockeyPenalty: Identifiable {
    let id: String
    let playerName: String
    let teamAbbr: String
    let minutes: Int
    let timeRemaining: String?
    let infraction: String?
}

// MARK: - Provider

struct HockeyProvider: TimelineProvider {
    func placeholder(in context: Context) -> HockeyEntry { sampleEntry }

    func getSnapshot(in context: Context, completion: @escaping (HockeyEntry) -> Void) {
        fetchHockey { completion($0 ?? sampleEntry) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HockeyEntry>) -> Void) {
        // Ensure completion is called exactly once — WidgetKit preempts the
        // extension aggressively, so guarantee a fallback timeline ships.
        let lock = NSLock()
        var fired = false
        func fire(_ timeline: Timeline<HockeyEntry>) {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            lock.unlock()
            completion(timeline)
        }
        let wrappedCompletion: (Timeline<HockeyEntry>) -> Void = fire
        DispatchQueue.global().asyncAfter(deadline: .now() + 4.5) {
            fire(Timeline(entries: [self.placeholder(in: context)], policy: .after(Date().addingTimeInterval(60))))
        }

        fetchHockey { entry in
            let final = entry ?? sampleEntry
            let refreshMinutes: Int = final.state == .live ? 1 : 15
            let refresh = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: Date())!
            wrappedCompletion(Timeline(entries: [final], policy: .after(refresh)))
        }
    }

    private func fetchHockey(completion: @escaping (HockeyEntry?) -> Void) {
        let urlStr = "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard"
        guard let url = URL(string: urlStr) else { completion(nil); return }

        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let events = json["events"] as? [[String: Any]] else {
                completion(nil)
                return
            }

            var entries: [HockeyEntry] = []
            for event in events {
                if let entry = self.parseEvent(event) {
                    entries.append(entry)
                }
            }

            let live = entries.filter { $0.state == .live }
            if let best = live.first {
                // If live, try to fetch detailed plays via summary
                self.fetchSummary(for: best, events: events, completion: completion)
                return
            }
            let upcoming = entries.filter { $0.state == .pre }
                .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            if let next = upcoming.first { completion(next); return }
            let recent = entries.filter { $0.state == .post }.first
            completion(recent)
        }.resume()
    }

    private func fetchSummary(for entry: HockeyEntry, events: [[String: Any]], completion: @escaping (HockeyEntry?) -> Void) {
        // Find event ID for the live game
        guard let eventID = events.first(where: { event -> Bool in
            let comps = event["competitions"] as? [[String: Any]] ?? []
            guard let comp = comps.first,
                  let st = comp["status"] as? [String: Any],
                  let sType = st["type"] as? [String: Any],
                  sType["state"] as? String == "in" else { return false }
            return true
        })?["id"] as? String else {
            completion(entry)
            return
        }

        let summaryURL = "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/summary?event=\(eventID)"
        guard let url = URL(string: summaryURL) else { completion(entry); return }

        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(entry)
                return
            }

            var recentPlays: [HockeyPlay] = []
            var scoringPlays: [HockeyScoringPlay] = []
            var penalties: [HockeyPenalty] = []

            // Parse scoring plays
            if let plays = json["scoringPlays"] as? [[String: Any]] {
                for (i, play) in plays.enumerated() {
                    let text = play["text"] as? String ?? ""
                    let per = play["period"] as? [String: Any]
                    let periodNum = per?["number"] as? Int ?? 0
                    let clock = play["clock"] as? [String: Any]
                    let clockStr = clock?["displayValue"] as? String ?? ""
                    let team = play["team"] as? [String: Any]
                    let teamAbbr = team?["abbreviation"] as? String ?? ""

                    // Extract scorer name from text (usually first part)
                    let parts = text.components(separatedBy: " - ")
                    let scorer = parts.count > 1 ? parts[1].components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? text : text
                    let shortScorer = scorer.components(separatedBy: " ").last ?? scorer

                    let isHome = teamAbbr == entry.homeTeam.abbreviation

                    scoringPlays.append(HockeyScoringPlay(
                        id: "sp\(i)",
                        scorerName: shortScorer,
                        teamAbbr: teamAbbr,
                        period: periodNum,
                        clockTime: clockStr,
                        isHome: isHome
                    ))
                }
            }

            // Parse recent plays
            if let plays = json["plays"] as? [[String: Any]] {
                let recent = plays.suffix(6)
                for (i, play) in recent.enumerated() {
                    let text = play["text"] as? String ?? ""
                    let typeDict = play["type"] as? [String: Any]
                    let typeText = typeDict?["text"] as? String ?? ""
                    let per = play["period"] as? [String: Any]
                    let periodNum = per?["number"] as? Int ?? 0
                    let clock = play["clock"] as? [String: Any]
                    let clockStr = clock?["displayValue"] as? String ?? ""
                    let team = play["team"] as? [String: Any]
                    let teamAbbr = team?["abbreviation"] as? String

                    let playType: HockeyPlayType
                    let lower = typeText.lowercased()
                    if lower.contains("goal") { playType = .goal }
                    else if lower.contains("penalty") { playType = .penalty }
                    else if lower.contains("shot") { playType = .shot }
                    else { playType = .other }

                    recentPlays.append(HockeyPlay(
                        id: "rp\(i)", text: text, type: playType,
                        periodNumber: periodNum, clockTime: clockStr, teamAbbr: teamAbbr
                    ))
                }
            }

            // Parse penalties from plays
            if let plays = json["plays"] as? [[String: Any]] {
                for (i, play) in plays.enumerated() {
                    let typeDict = play["type"] as? [String: Any]
                    let typeText = typeDict?["text"] as? String ?? ""
                    guard typeText.lowercased().contains("penalty") else { continue }
                    let text = play["text"] as? String ?? ""
                    let team = play["team"] as? [String: Any]
                    let teamAbbr = team?["abbreviation"] as? String ?? ""
                    let playerName = text.components(separatedBy: " - ").last?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? text
                    let shortName = playerName.components(separatedBy: " ").last ?? playerName

                    penalties.append(HockeyPenalty(
                        id: "pen\(i)",
                        playerName: shortName,
                        teamAbbr: teamAbbr,
                        minutes: 2,
                        timeRemaining: nil,
                        infraction: typeText
                    ))
                }
            }

            let enriched = HockeyEntry(
                date: entry.date,
                state: entry.state,
                awayTeam: entry.awayTeam,
                homeTeam: entry.homeTeam,
                period: entry.period,
                clock: entry.clock,
                awayShotsOnGoal: entry.awayShotsOnGoal,
                homeShotsOnGoal: entry.homeShotsOnGoal,
                powerPlay: entry.powerPlay,
                startDate: entry.startDate,
                recentPlays: recentPlays.reversed(),
                scoringPlays: scoringPlays,
                penalizedPlayers: Array(penalties.suffix(4))
            )
            completion(enriched)
        }.resume()
    }

    private func parseEvent(_ event: [String: Any]) -> HockeyEntry? {
        let competitions = event["competitions"] as? [[String: Any]] ?? []
        guard let comp = competitions.first else { return nil }

        let statusDict = comp["status"] as? [String: Any] ?? [:]
        let statusType = statusDict["type"] as? [String: Any] ?? [:]
        let stateStr = statusType["state"] as? String ?? "pre"
        let displayClock = statusDict["displayClock"] as? String ?? ""
        let period = statusDict["period"] as? Int ?? 0

        let state: HockeyGameState
        switch stateStr {
        case "in": state = .live
        case "post": state = .post
        default: state = .pre
        }

        let competitors = comp["competitors"] as? [[String: Any]] ?? []
        var away = HockeyTeamInfo(abbreviation: "???", score: "0", colorHex: "333333", record: nil)
        var home = HockeyTeamInfo(abbreviation: "???", score: "0", colorHex: "333333", record: nil)
        var awaySog: Int?
        var homeSog: Int?

        for c in competitors {
            let teamDict = c["team"] as? [String: Any] ?? [:]
            let abbr = teamDict["abbreviation"] as? String ?? "???"
            let colorHex = teamDict["color"] as? String ?? "333333"
            let score = c["score"] as? String ?? "0"
            let homeAway = c["homeAway"] as? String ?? ""
            let records = c["records"] as? [[String: Any]]
            let record = records?.first?["summary"] as? String

            let stats = c["statistics"] as? [[String: Any]] ?? []
            for stat in stats {
                if stat["name"] as? String == "shotsOnGoal" || stat["abbreviation"] as? String == "SOG" {
                    if let val = stat["displayValue"] as? String {
                        let sog = Int(val)
                        if homeAway == "home" { homeSog = sog } else { awaySog = sog }
                    }
                }
            }

            let info = HockeyTeamInfo(abbreviation: abbr, score: score, colorHex: colorHex, record: record)
            if homeAway == "home" { home = info } else { away = info }
        }

        var powerPlay: HockeyPowerPlay?
        if let situation = comp["situation"] as? [String: Any] {
            if let ppTeam = situation["teamWithAdvantage"] as? String,
               let strength = situation["strength"] as? String {
                let timeRem = situation["timeRemaining"] as? String
                let teamAbbr = ppTeam == "home" ? home.abbreviation : away.abbreviation
                powerPlay = HockeyPowerPlay(teamAbbr: teamAbbr, strength: strength, timeRemaining: timeRem)
            }
        }

        let dateStr = comp["date"] as? String ?? event["date"] as? String ?? ""
        let startDate = parseDate(dateStr)

        return HockeyEntry(
            date: Date(), state: state,
            awayTeam: away, homeTeam: home,
            period: period, clock: displayClock,
            awayShotsOnGoal: awaySog, homeShotsOnGoal: homeSog,
            powerPlay: powerPlay, startDate: startDate,
            recentPlays: [], scoringPlays: [], penalizedPlayers: []
        )
    }

    private func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    private var sampleEntry: HockeyEntry {
        HockeyEntry(
            date: Date(), state: .live,
            awayTeam: HockeyTeamInfo(abbreviation: "TOR", score: "3", colorHex: "00205B", record: "38-22-6"),
            homeTeam: HockeyTeamInfo(abbreviation: "BOS", score: "2", colorHex: "FFB81C", record: "42-15-8"),
            period: 2, clock: "8:34",
            awayShotsOnGoal: 18, homeShotsOnGoal: 22,
            powerPlay: HockeyPowerPlay(teamAbbr: "TOR", strength: "5v4", timeRemaining: "1:23"),
            startDate: nil,
            recentPlays: [
                HockeyPlay(id: "rp0", text: "Goal - Marner (PP)", type: .goal, periodNumber: 2, clockTime: "10:12", teamAbbr: "TOR"),
                HockeyPlay(id: "rp1", text: "Penalty - McAvoy (Tripping)", type: .penalty, periodNumber: 2, clockTime: "11:35", teamAbbr: "BOS"),
                HockeyPlay(id: "rp2", text: "Shot on goal - Matthews", type: .shot, periodNumber: 2, clockTime: "9:50", teamAbbr: "TOR"),
            ],
            scoringPlays: [
                HockeyScoringPlay(id: "sp0", scorerName: "Matthews", teamAbbr: "TOR", period: 1, clockTime: "15:22", isHome: false),
                HockeyScoringPlay(id: "sp1", scorerName: "Pastrnak", teamAbbr: "BOS", period: 1, clockTime: "8:05", isHome: true),
                HockeyScoringPlay(id: "sp2", scorerName: "Nylander", teamAbbr: "TOR", period: 1, clockTime: "3:41", isHome: false),
                HockeyScoringPlay(id: "sp3", scorerName: "Marchand", teamAbbr: "BOS", period: 2, clockTime: "14:10", isHome: true),
                HockeyScoringPlay(id: "sp4", scorerName: "Marner", teamAbbr: "TOR", period: 2, clockTime: "10:12", isHome: false),
            ],
            penalizedPlayers: [
                HockeyPenalty(id: "pen0", playerName: "McAvoy", teamAbbr: "BOS", minutes: 2, timeRemaining: "1:23", infraction: "Tripping"),
            ]
        )
    }
}

// MARK: - Widget View

struct HockeyWidgetView: View {
    let entry: HockeyEntry
    @Environment(\.widgetFamily) var family

    private static let countdownFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E h:mm a"
        return f
    }()

    var body: some View {
        switch family {
        case .systemLarge: largeView
        default: mediumView
        }
    }

    // MARK: - Medium

    private var mediumView: some View {
        GeometryReader { geo in
            ZStack {
                HockeyRinkDrawing(width: geo.size.width, height: geo.size.height)

                switch entry.state {
                case .live: liveMediumOverlay(geo.size)
                case .pre: preGameOverlay(geo.size)
                case .post: postGameOverlay(geo.size)
                case .noGame: noGameOverlay
                }
            }
        }
    }

    // MARK: - Large

    private var largeView: some View {
        GeometryReader { geo in
            let rinkH = geo.size.height * 0.55
            VStack(spacing: 0) {
                // Rink area
                ZStack {
                    HockeyRinkDrawing(width: geo.size.width, height: rinkH)
                    switch entry.state {
                    case .live: liveMediumOverlay(CGSize(width: geo.size.width, height: rinkH))
                    case .pre: preGameOverlay(CGSize(width: geo.size.width, height: rinkH))
                    case .post: postGameOverlay(CGSize(width: geo.size.width, height: rinkH))
                    case .noGame: noGameOverlay
                    }
                }
                .frame(height: rinkH)

                // Bottom area: recent plays + penalty box
                ZStack {
                    Color(red: 0.08, green: 0.08, blue: 0.12)

                    HStack(spacing: 0) {
                        // Recent plays feed
                        VStack(alignment: .leading, spacing: 0) {
                            Text("RECENT PLAYS")
                                .font(.system(size: 7, weight: .heavy))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.leading, 8)
                                .padding(.top, 4)

                            ForEach(Array(entry.recentPlays.prefix(4))) { play in
                                HStack(spacing: 4) {
                                    playIcon(play.type)
                                        .font(.system(size: 7))
                                        .frame(width: 12)
                                    if let abbr = play.teamAbbr {
                                        Text(abbr)
                                            .font(.system(size: 7, weight: .heavy))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    Text(play.text)
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(play.clockTime)
                                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)

                        // Penalty box
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 3) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.red)
                                Text("PENALTY BOX")
                                    .font(.system(size: 7, weight: .heavy))
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .padding(.leading, 6)
                            .padding(.top, 4)

                            if entry.penalizedPlayers.isEmpty {
                                Text("Empty")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.3))
                                    .padding(.leading, 6)
                                    .padding(.top, 4)
                            } else {
                                ForEach(entry.penalizedPlayers) { pen in
                                    HStack(spacing: 3) {
                                        Text(pen.teamAbbr)
                                            .font(.system(size: 7, weight: .heavy))
                                            .foregroundColor(.white.opacity(0.5))
                                        Text(pen.playerName)
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text("\(pen.minutes)m")
                                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                                            .foregroundColor(.yellow)
                                        if let tr = pen.timeRemaining {
                                            Text(tr)
                                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(width: geo.size.width * 0.38)
                        .background(Color.red.opacity(0.06))
                    }
                }
            }
        }
    }

    // MARK: - Live Medium Overlay

    private func liveMediumOverlay(_ size: CGSize) -> some View {
        let w = size.width
        let h = size.height
        let awayC = HockeyColorHelper.color(hex: entry.awayTeam.colorHex) ?? .blue
        let homeC = HockeyColorHelper.color(hex: entry.homeTeam.colorHex) ?? .red

        return ZStack {
            // Team color tints
            HStack(spacing: 0) {
                awayC.opacity(0.06)
                homeC.opacity(0.06)
            }
            .clipShape(RoundedRectangle(cornerRadius: min(w, h) * 0.15))

            // NHL + LIVE badge
            VStack {
                HStack {
                    Text("NHL")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundColor(.black.opacity(0.7))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(.white.opacity(0.6)))
                    Spacer()
                    HStack(spacing: 2) {
                        Circle().fill(.green).frame(width: 5, height: 5)
                        Text("LIVE").font(.system(size: 6, weight: .heavy)).foregroundColor(.green)
                    }
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(.black.opacity(0.4)))
                }
                .padding(.horizontal, 8).padding(.top, 6)
                Spacer()
            }

            // Scoring play markers on rink
            ForEach(entry.scoringPlays) { sp in
                let goalX: CGFloat = sp.isHome ? w * 0.88 : w * 0.12
                let yOffset = goalYOffset(for: sp, total: entry.scoringPlays.filter { $0.isHome == sp.isHome }.count,
                                           index: entry.scoringPlays.filter { $0.isHome == sp.isHome }.firstIndex(where: { $0.id == sp.id }) ?? 0,
                                           height: h)
                VStack(spacing: 0) {
                    Image(systemName: "hockey.puck.fill")
                        .font(.system(size: 6))
                        .foregroundColor(.black.opacity(0.7))
                    Text(sp.scorerName)
                        .font(.system(size: 5, weight: .bold))
                        .foregroundColor(.black.opacity(0.6))
                    Text("P\(sp.period) \(sp.clockTime)")
                        .font(.system(size: 4, weight: .medium))
                        .foregroundColor(.black.opacity(0.4))
                }
                .position(x: goalX, y: yOffset)
            }

            // Away team left
            VStack(spacing: 2) {
                Text(entry.awayTeam.abbreviation)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.black.opacity(0.85))
                Text(entry.awayTeam.score)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.black)
                    .shadow(color: awayC, radius: 3)
            }
            .position(x: w * 0.20, y: h * 0.5)

            // Home team right
            VStack(spacing: 2) {
                Text(entry.homeTeam.abbreviation)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.black.opacity(0.85))
                Text(entry.homeTeam.score)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.black)
                    .shadow(color: homeC, radius: 3)
            }
            .position(x: w * 0.80, y: h * 0.5)

            // Center ice: period + clock
            VStack(spacing: 1) {
                Text(periodLabel)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(.black.opacity(0.7))
                Text(entry.clock)
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundColor(.black.opacity(0.9))
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.5)))
            .position(x: w / 2, y: h * 0.5)

            // Shot count comparison bars
            if let awaySog = entry.awayShotsOnGoal, let homeSog = entry.homeShotsOnGoal {
                let maxSog = max(awaySog, homeSog, 1)
                // Away shots bar (left side)
                VStack(spacing: 1) {
                    Text("SOG")
                        .font(.system(size: 5, weight: .heavy))
                        .foregroundColor(.black.opacity(0.4))
                    HStack(spacing: 1) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(awayC.opacity(0.6))
                            .frame(width: max(CGFloat(awaySog) / CGFloat(maxSog) * w * 0.12, 4), height: 4)
                        Text("\(awaySog)")
                            .font(.system(size: 6, weight: .heavy))
                            .foregroundColor(.black.opacity(0.6))
                    }
                    .frame(width: w * 0.15)
                }
                .position(x: w * 0.20, y: h * 0.82)

                // Home shots bar (right side)
                VStack(spacing: 1) {
                    Text("SOG")
                        .font(.system(size: 5, weight: .heavy))
                        .foregroundColor(.black.opacity(0.4))
                    HStack(spacing: 1) {
                        Text("\(homeSog)")
                            .font(.system(size: 6, weight: .heavy))
                            .foregroundColor(.black.opacity(0.6))
                        RoundedRectangle(cornerRadius: 1)
                            .fill(homeC.opacity(0.6))
                            .frame(width: max(CGFloat(homeSog) / CGFloat(maxSog) * w * 0.12, 4), height: 4)
                        Spacer(minLength: 0)
                    }
                    .frame(width: w * 0.15)
                }
                .position(x: w * 0.80, y: h * 0.82)
            }

            // Power play indicator on rink
            if let pp = entry.powerPlay {
                VStack(spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 7))
                            .foregroundColor(.yellow)
                        Text("PP \(pp.teamAbbr)")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(.yellow)
                        Text(pp.strength)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    if let time = pp.timeRemaining {
                        Text(time)
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(.red.opacity(0.75)))
                .position(x: w / 2, y: h * 0.18)
            }
        }
    }

    // MARK: - Pre-Game Overlay

    private func preGameOverlay(_ size: CGSize) -> some View {
        let w = size.width
        let h = size.height

        return ZStack {
            VStack {
                HStack {
                    Text("NHL").font(.system(size: 7, weight: .heavy))
                        .foregroundColor(.black.opacity(0.7))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(.white.opacity(0.6)))
                    Spacer()
                }
                .padding(.horizontal, 8).padding(.top, 6)
                Spacer()
            }

            VStack(spacing: 4) {
                Text(entry.awayTeam.abbreviation)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.black.opacity(0.85))
                if let r = entry.awayTeam.record {
                    Text(r).font(.system(size: 7, weight: .medium)).foregroundColor(.black.opacity(0.5))
                }
            }
            .position(x: w * 0.22, y: h / 2)

            VStack(spacing: 4) {
                Text(entry.homeTeam.abbreviation)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.black.opacity(0.85))
                if let r = entry.homeTeam.record {
                    Text(r).font(.system(size: 7, weight: .medium)).foregroundColor(.black.opacity(0.5))
                }
            }
            .position(x: w * 0.78, y: h / 2)

            VStack(spacing: 2) {
                Text("VS").font(.system(size: 14, weight: .black)).foregroundColor(.black.opacity(0.3))
                if let start = entry.startDate {
                    let diff = start.timeIntervalSince(entry.date)
                    if diff > 0 {
                        Text(countdownString(diff))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.red.opacity(0.8))
                        Text(Self.countdownFormatter.string(from: start))
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(.black.opacity(0.4))
                    }
                }
            }
            .position(x: w / 2, y: h / 2)
        }
    }

    // MARK: - Post-Game Overlay

    private func postGameOverlay(_ size: CGSize) -> some View {
        let w = size.width
        let h = size.height
        let awayScore = Int(entry.awayTeam.score) ?? 0
        let homeScore = Int(entry.homeTeam.score) ?? 0
        let awayWon = awayScore > homeScore

        return ZStack {
            VStack(spacing: 2) {
                Text(entry.awayTeam.abbreviation)
                    .font(.system(size: 10, weight: .heavy)).foregroundColor(.black.opacity(0.85))
                Text(entry.awayTeam.score)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(awayWon ? .black : .black.opacity(0.4))
                if awayWon {
                    Text("WIN").font(.system(size: 7, weight: .heavy)).foregroundColor(.red)
                }
            }
            .position(x: w * 0.22, y: h / 2)

            VStack(spacing: 2) {
                Text(entry.homeTeam.abbreviation)
                    .font(.system(size: 10, weight: .heavy)).foregroundColor(.black.opacity(0.85))
                Text(entry.homeTeam.score)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(!awayWon ? .black : .black.opacity(0.4))
                if !awayWon {
                    Text("WIN").font(.system(size: 7, weight: .heavy)).foregroundColor(.red)
                }
            }
            .position(x: w * 0.78, y: h / 2)

            VStack(spacing: 1) {
                Text("FINAL").font(.system(size: 12, weight: .black)).foregroundColor(.black.opacity(0.7))
                if entry.period == 4 {
                    Text("OT").font(.system(size: 8, weight: .heavy)).foregroundColor(.red.opacity(0.8))
                } else if entry.period >= 5 {
                    Text("SO").font(.system(size: 8, weight: .heavy)).foregroundColor(.red.opacity(0.8))
                }
            }
            .position(x: w / 2, y: h / 2)
        }
    }

    // MARK: - No Game

    private var noGameOverlay: some View {
        VStack(spacing: 4) {
            Image(systemName: "hockey.puck.fill")
                .font(.system(size: 20)).foregroundColor(.black.opacity(0.3))
            Text("No Games")
                .font(.system(size: 11, weight: .bold)).foregroundColor(.black.opacity(0.4))
        }
    }

    // MARK: - Helpers

    private var periodLabel: String {
        switch entry.period {
        case 1: return "1ST"
        case 2: return "2ND"
        case 3: return "3RD"
        case 4: return "OT"
        case 5: return "SO"
        default: return "\(entry.period)OT"
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

    private func goalYOffset(for sp: HockeyScoringPlay, total: Int, index: Int, height: CGFloat) -> CGFloat {
        let base = height * 0.25
        let spacing = min(height * 0.12, 16.0)
        return base + CGFloat(index) * spacing
    }

    private func playIcon(_ type: HockeyPlayType) -> some View {
        switch type {
        case .goal:
            return Image(systemName: "light.beacon.max.fill").foregroundColor(.red)
        case .penalty:
            return Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
        case .shot:
            return Image(systemName: "hockey.puck.fill").foregroundColor(.white.opacity(0.5))
        case .other:
            return Image(systemName: "circle.fill").foregroundColor(.white.opacity(0.3))
        }
    }
}

// MARK: - Rink Drawing

private struct HockeyRinkDrawing: View {
    let width: Double
    let height: Double

    private let iceColor = Color(red: 0.92, green: 0.95, blue: 0.98)
    private let redLine = Color.red
    private let blueLine = Color(red: 0.0, green: 0.2, blue: 0.6)

    var body: some View {
        ZStack {
            iceColor

            Canvas { context, size in
                let w = size.width
                let h = size.height
                let midX = w / 2
                let midY = h / 2
                let cornerR = min(w, h) * 0.15
                let inset: CGFloat = 3

                // Rink outline
                let rinkRect = CGRect(x: inset, y: inset, width: w - inset * 2, height: h - inset * 2)
                let rinkOutline = Path(roundedRect: rinkRect, cornerRadius: cornerR)
                context.stroke(rinkOutline, with: .color(.black.opacity(0.3)), lineWidth: 2)

                // Red center line
                var centerLine = Path()
                centerLine.move(to: CGPoint(x: midX, y: inset))
                centerLine.addLine(to: CGPoint(x: midX, y: h - inset))
                context.stroke(centerLine, with: .color(redLine.opacity(0.7)), lineWidth: 2.5)

                // Blue lines
                let blueOff = w * 0.21
                for xPos in [midX - blueOff, midX + blueOff] {
                    var line = Path()
                    line.move(to: CGPoint(x: xPos, y: inset))
                    line.addLine(to: CGPoint(x: xPos, y: h - inset))
                    context.stroke(line, with: .color(blueLine.opacity(0.6)), lineWidth: 2)
                }

                // Center face-off circle
                let centerR = min(w, h) * 0.18
                let centerCircle = Path(ellipseIn: CGRect(x: midX - centerR, y: midY - centerR, width: centerR * 2, height: centerR * 2))
                context.stroke(centerCircle, with: .color(redLine.opacity(0.5)), lineWidth: 1.5)

                // Center dot
                let dotR: CGFloat = 3
                context.fill(Path(ellipseIn: CGRect(x: midX - dotR, y: midY - dotR, width: dotR * 2, height: dotR * 2)),
                             with: .color(redLine.opacity(0.6)))

                // Face-off circles in zones
                let faceoffR = min(w, h) * 0.12
                let fxOff = w * 0.20
                let fyOff = h * 0.30

                let faceoffs = [
                    CGPoint(x: fxOff, y: midY - fyOff), CGPoint(x: fxOff, y: midY + fyOff),
                    CGPoint(x: w - fxOff, y: midY - fyOff), CGPoint(x: w - fxOff, y: midY + fyOff),
                ]

                for pos in faceoffs {
                    let circle = Path(ellipseIn: CGRect(x: pos.x - faceoffR, y: pos.y - faceoffR, width: faceoffR * 2, height: faceoffR * 2))
                    context.stroke(circle, with: .color(redLine.opacity(0.35)), lineWidth: 1)
                    context.fill(Path(ellipseIn: CGRect(x: pos.x - dotR, y: pos.y - dotR, width: dotR * 2, height: dotR * 2)),
                                 with: .color(redLine.opacity(0.5)))
                }

                // Goal creases
                let creaseR = h * 0.12
                var leftCrease = Path()
                leftCrease.addArc(center: CGPoint(x: inset + w * 0.015, y: midY), radius: creaseR,
                                  startAngle: .degrees(-70), endAngle: .degrees(70), clockwise: false)
                context.stroke(leftCrease, with: .color(blueLine.opacity(0.5)), lineWidth: 1.5)
                context.fill(leftCrease, with: .color(blueLine.opacity(0.08)))

                var rightCrease = Path()
                rightCrease.addArc(center: CGPoint(x: w - inset - w * 0.015, y: midY), radius: creaseR,
                                   startAngle: .degrees(110), endAngle: .degrees(250), clockwise: false)
                context.stroke(rightCrease, with: .color(blueLine.opacity(0.5)), lineWidth: 1.5)
                context.fill(rightCrease, with: .color(blueLine.opacity(0.08)))

                // Goal lines
                let goalX = w * 0.08
                for xPos in [goalX, w - goalX] {
                    var line = Path()
                    line.move(to: CGPoint(x: xPos, y: inset + cornerR * 0.3))
                    line.addLine(to: CGPoint(x: xPos, y: h - inset - cornerR * 0.3))
                    context.stroke(line, with: .color(redLine.opacity(0.35)), lineWidth: 1.2)
                }

                // Goal nets
                let netW: CGFloat = 4
                let netH = h * 0.08
                for xPos in [inset, w - inset - netW] {
                    let net = Path(roundedRect: CGRect(x: xPos, y: midY - netH / 2, width: netW, height: netH), cornerRadius: 1)
                    context.fill(net, with: .color(.gray.opacity(0.3)))
                    context.stroke(net, with: .color(.gray.opacity(0.5)), lineWidth: 0.8)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: min(width, height) * 0.15))
    }
}
