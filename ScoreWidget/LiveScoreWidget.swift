import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct LiveScoreProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScoreEntry {
        ScoreEntry(date: Date(), games: sampleGames)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScoreEntry) -> Void) {
        let acc = GameAccumulator()
        fetchGames(into: acc) { games in
            completion(ScoreEntry(date: Date(), games: games.isEmpty ? sampleGames : games))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScoreEntry>) -> Void) {
        // Shared accumulator: ship whatever we have at the deadline OR when
        // every league fetch finishes — whichever happens first.
        let accumulator = GameAccumulator()
        let lock = NSLock()
        var fired = false
        func fire(games: [SharedGame]) {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            lock.unlock()
            // Use sample data ONLY if we have absolutely nothing.
            let finalGames = games.isEmpty ? sampleGames : games
            let entry = ScoreEntry(date: Date(), games: finalGames)
            let hasLive = finalGames.contains { $0.isLive }
            let refreshDate = Calendar.current.date(
                byAdding: .minute,
                value: hasLive ? 1 : 5,
                to: Date()
            )!
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))
        }

        // Hard deadline — ships partial results even if not all sports finished
        DispatchQueue.global().asyncAfter(deadline: .now() + 4.0) {
            fire(games: accumulator.snapshot())
        }

        fetchGames(into: accumulator) { games in
            fire(games: games)
        }
    }

    /// Fetch from ESPN API for all selected sports.
    /// Writes results into the shared accumulator as they arrive so the
    /// deadline-fire path can pick up partial data. Calls `completion` with
    /// the full set once every league responds (or fails).
    private func fetchGames(
        into accumulator: GameAccumulator,
        completion: @escaping ([SharedGame]) -> Void
    ) {
        let selectedIDs = UserDefaults.standard.array(forKey: "selectedSportIDs") as? [String]
            ?? ["nba", "nfl", "mlb"]
        let leagues = selectedIDs.compactMap { SportLeague.find($0) }

        if leagues.isEmpty {
            completion([])
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "America/New_York")
        let today = dateFormatter.string(from: Date())
        let endDateStr = dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: 3, to: Date())!)

        let group = DispatchGroup()

        for league in leagues {
            group.enter()
            var urlString = "\(league.scoreboardURL)?limit=50&dates=\(today)-\(endDateStr)"
            if let groupID = league.groupID {
                urlString += "&groups=\(groupID)"
            }
            guard let url = URL(string: urlString) else {
                group.leave()
                continue
            }

            // Tight timeout — under WidgetKit budget. Per-fetch failure is
            // fine; other leagues' results still ship.
            URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2.5)) { data, _, _ in
                defer { group.leave() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let events = json["events"] as? [[String: Any]] else { return }

                let games: [SharedGame] = events.compactMap { event in
                    self.parseEvent(event)
                }
                // Make data visible to the deadline path immediately
                accumulator.add(games)
            }.resume()
        }

        group.notify(queue: .main) {
            completion(accumulator.snapshot())
        }
    }
}

/// Thread-safe accumulator so the deadline path can grab partial results.
final class GameAccumulator: @unchecked Sendable {
    private var games: [SharedGame] = []
    private let lock = NSLock()

    func add(_ newGames: [SharedGame]) {
        lock.lock(); defer { lock.unlock() }
        games.append(contentsOf: newGames)
    }

    func snapshot() -> [SharedGame] {
        lock.lock(); defer { lock.unlock() }
        return games
    }
}

extension LiveScoreProvider {
    /// Parse a single ESPN event JSON into SharedGame
    func parseEvent(_ event: [String: Any]) -> SharedGame? {
            guard let id = event["id"] as? String,
                  let dateStr = event["date"] as? String,
                  let competitions = event["competitions"] as? [[String: Any]],
                  let comp = competitions.first,
                  let competitors = comp["competitors"] as? [[String: Any]],
                  let statusDict = event["status"] as? [String: Any],
                  let statusType = statusDict["type"] as? [String: Any],
                  let state = statusType["state"] as? String else {
                return nil
            }

                let detail = statusType["detail"] as? String
                let shortDetail = statusType["shortDetail"] as? String
                let period = statusDict["period"] as? Int ?? 0
                let displayClock = statusDict["displayClock"] as? String

                // Parse date
                let startDate = parseDate(dateStr)

                // Parse round/region from notes
                var roundName: String?
                var regionName: String?
                if let notes = (event["notes"] as? [[String: Any]] ?? comp["notes"] as? [[String: Any]]),
                   let headline = notes.first?["headline"] as? String {
                    let parts = headline.components(separatedBy: " - ")
                    roundName = parts.last?.trimmingCharacters(in: .whitespaces)
                    if parts.count >= 2 {
                        regionName = parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: " Region", with: "")
                    }
                }

                // Parse broadcast
                let broadcast = (comp["broadcasts"] as? [[String: Any]])?
                    .first.flatMap { ($0["names"] as? [String])?.first }

                // Parse competitors
                let away = competitors.first { ($0["homeAway"] as? String) == "away" }
                let home = competitors.first { ($0["homeAway"] as? String) == "home" }

                func teamInfo(_ c: [String: Any]?) -> (name: String, abbr: String, score: String, seed: Int?, logo: String?, color: String?) {
                    guard let c = c, let team = c["team"] as? [String: Any] else {
                        return ("TBD", "TBD", "0", nil, nil, nil)
                    }
                    let name = team["displayName"] as? String ?? "TBD"
                    let abbr = team["abbreviation"] as? String ?? "TBD"
                    let score = c["score"] as? String ?? "0"
                    let logo = team["logo"] as? String
                    let color = team["color"] as? String
                    let seed: Int?
                    if let rank = c["curatedRank"] as? [String: Any], let current = rank["current"] as? Int, current <= 16 {
                        seed = current
                    } else {
                        seed = nil
                    }
                    return (name, abbr, score, seed, logo, color)
                }

                let awayInfo = teamInfo(away)
                let homeInfo = teamInfo(home)

                // Detect upset
                let isUpset: Bool = {
                    guard state == "post",
                          let awaySeed = awayInfo.seed, let homeSeed = homeInfo.seed,
                          let awayScore = Int(awayInfo.score), let homeScore = Int(homeInfo.score) else { return false }
                    return (awaySeed > homeSeed && awayScore > homeScore) || (homeSeed > awaySeed && homeScore > awayScore)
                }()

                // Parse moneyline odds for win probability
                let (winProbTeam, winProbValue): (String?, Double?) = {
                    if let odds = (comp["odds"] as? [[String: Any]])?.first {
                        // Try moneyline first
                        if let ml = odds["moneyline"] as? [String: Any],
                           let home = ml["home"] as? [String: Any],
                           let close = home["close"] as? [String: Any],
                           let oddsStr = close["odds"] as? String,
                           let oddsNum = Double(oddsStr) {
                            let homeProb: Double
                            if oddsNum < 0 {
                                homeProb = abs(oddsNum) / (abs(oddsNum) + 100.0)
                            } else {
                                homeProb = 100.0 / (oddsNum + 100.0)
                            }
                            let favTeam = homeProb >= 0.5 ? homeInfo.abbr : awayInfo.abbr
                            let prob = min(0.97, max(homeProb, 1.0 - homeProb))
                            return (favTeam, prob)
                        }
                        // Fall back to spread
                        if let spread = odds["spread"] as? Double {
                            let prob = 1.0 / (1.0 + exp(spread * 0.15))
                            let favTeam = prob >= 0.5 ? homeInfo.abbr : awayInfo.abbr
                            return (favTeam, min(0.97, max(prob, 1.0 - prob)))
                        }
                    }
                    // Seed-based fallback
                    if let aS = awayInfo.seed, let hS = homeInfo.seed, aS != hS {
                        let rates: [Int: Double] = [1:0.99,2:0.94,3:0.85,4:0.79,5:0.64,6:0.63,7:0.61,8:0.50,
                                                     9:0.50,10:0.39,11:0.37,12:0.36,13:0.21,14:0.15,15:0.06,16:0.01]
                        let favAbbr = aS < hS ? awayInfo.abbr : homeInfo.abbr
                        let favSeed = min(aS, hS)
                        return (favAbbr, rates[favSeed] ?? 0.50)
                    }
                    return (nil, nil)
                }()

                return SharedGame(
                    id: id,
                    awayTeam: awayInfo.name,
                    awayAbbreviation: awayInfo.abbr,
                    awayScore: awayInfo.score.isEmpty ? "0" : awayInfo.score,
                    awaySeed: awayInfo.seed,
                    awayLogo: awayInfo.logo,
                    awayColor: awayInfo.color,
                    homeTeam: homeInfo.name,
                    homeAbbreviation: homeInfo.abbr,
                    homeScore: homeInfo.score.isEmpty ? "0" : homeInfo.score,
                    homeSeed: homeInfo.seed,
                    homeLogo: homeInfo.logo,
                    homeColor: homeInfo.color,
                    state: state,
                    detail: detail,
                    shortDetail: shortDetail,
                    period: period,
                    displayClock: displayClock,
                    startDate: startDate,
                    roundName: roundName,
                    regionName: regionName,
                    broadcast: broadcast,
                    isUpset: isUpset,
                    winProbTeam: winProbTeam,
                    winProbValue: winProbValue
                )
    }

    /// Parse ESPN date strings (handles missing seconds format like "2026-03-20T16:15Z")
    private func parseDate(_ dateString: String) -> Date? {
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: dateString) { return d }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: dateString) { return d }

        // ESPN sometimes omits seconds: "2026-03-20T16:15Z"
        if dateString.hasSuffix("Z") && dateString.count <= 17 {
            let withSeconds = dateString.replacingOccurrences(of: "Z", with: ":00Z")
            if let d = iso.date(from: withSeconds) { return d }
        }

        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mmZ"
        fallback.locale = Locale(identifier: "en_US_POSIX")
        return fallback.date(from: dateString.replacingOccurrences(of: "Z", with: "+0000"))
    }
}

// MARK: - Timeline Entry

struct ScoreEntry: TimelineEntry {
    let date: Date
    let games: [SharedGame]

    var liveGames: [SharedGame] { games.filter { $0.isLive } }

    var upcomingGames: [SharedGame] {
        games.filter { $0.isScheduled }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    var finalGames: [SharedGame] {
        games.filter { $0.isFinal }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    /// Priority: live > upcoming > recent finals
    var displayGames: [SharedGame] {
        var result: [SharedGame] = []
        result.append(contentsOf: liveGames)
        result.append(contentsOf: upcomingGames)
        result.append(contentsOf: finalGames)
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Widget Definition

struct LiveScoreWidget: Widget {
    let kind: String = "LiveScoreWidget_v11"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LiveScoreProvider()) { entry in
            LiveScoreWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // Solid dark gradient — looks intentional in BOTH the
                    // active and dimmed (other-app-focused) widget states.
                    // `.fill.tertiary` desaturates to flat grey when dimmed.
                    LinearGradient(
                        colors: [Color(red: 0.06, green: 0.06, blue: 0.08),
                                 Color(red: 0.10, green: 0.10, blue: 0.12)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Live Sports Scores")
        .description("Live scores for every selected sport")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget Views

struct LiveScoreWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ScoreEntry

    var body: some View {
        switch family {
        case .systemSmall: smallWidget
        case .systemMedium: mediumWidget
        case .systemLarge: largeWidget
        default: mediumWidget
        }
    }

    // MARK: - Small

    private var smallWidget: some View {
        VStack(spacing: 4) {
            if let game = entry.displayGames.first {
                HStack {
                    if game.isLive {
                        HStack(spacing: 3) {
                            Circle().fill(Color.red).frame(width: 5, height: 5)
                            Text("LIVE").font(.system(size: 8, weight: .heavy)).foregroundColor(.red)
                        }
                    } else if game.isScheduled {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill").font(.system(size: 7)).foregroundColor(.orange)
                            Text("NEXT").font(.system(size: 8, weight: .heavy)).foregroundColor(.orange)
                        }
                    }
                    Spacer()
                    if let round = game.roundName {
                        Text(round).font(.system(size: 8, weight: .medium)).foregroundColor(.gray).lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 0) {
                    teamBlock(game.awayAbbreviation, seed: game.awaySeed)
                    VStack(spacing: 2) {
                        if game.isLive || game.isFinal {
                            scoreText(game)
                            statusLabel(game)
                        } else if game.isScheduled {
                            countdownBlock(game, large: true)
                            if let wpText = game.winProbText {
                                Text(wpText)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    teamBlock(game.homeAbbreviation, seed: game.homeSeed)
                }
                Spacer()
            } else { emptyState }
        }
        .padding(8)
    }

    // MARK: - Medium

    private var mediumWidget: some View {
        VStack(spacing: 4) {
            header
            if entry.displayGames.isEmpty {
                Spacer(); emptyState; Spacer()
            } else {
                let games = Array(entry.displayGames.prefix(3))
                ForEach(games) { game in
                    gameRow(game)
                    if game.id != games.last?.id { Divider() }
                }
            }
        }
        .padding(8)
    }

    // MARK: - Large

    private var largeWidget: some View {
        VStack(spacing: 4) {
            header
            if entry.displayGames.isEmpty {
                Spacer(); emptyState; Spacer()
            } else {
                let games = Array(entry.displayGames.prefix(6))
                ForEach(games) { game in
                    gameRow(game)
                    if game.id != games.last?.id { Divider() }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(8)
    }

    // MARK: - Components

    private var header: some View {
        HStack {
            Image(systemName: "trophy.fill").font(.system(size: 10)).foregroundColor(.orange)
            Text("Sports Tracker").font(.system(size: 11, weight: .bold))
            Spacer()
            if entry.liveGames.count > 0 {
                HStack(spacing: 3) {
                    Circle().fill(Color.red).frame(width: 5, height: 5)
                    Text("\(entry.liveGames.count) LIVE").font(.system(size: 8, weight: .heavy)).foregroundColor(.red)
                }
            } else if !entry.upcomingGames.isEmpty {
                Text("UPCOMING").font(.system(size: 8, weight: .heavy)).foregroundColor(.orange)
            }
        }
    }

    private func teamBlock(_ abbr: String, seed: Int?) -> some View {
        VStack(spacing: 3) {
            Image(systemName: "basketball.fill").font(.system(size: 20)).foregroundColor(.orange)
            HStack(spacing: 2) {
                if let seed { Text("\(seed)").font(.system(size: 8, weight: .medium)).foregroundColor(.gray) }
                Text(abbr).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func scoreText(_ game: SharedGame) -> some View {
        HStack(spacing: 4) {
            Text(game.awayScore).font(.system(size: 22, weight: .bold, design: .rounded))
            Text("-").font(.system(size: 14)).foregroundColor(.gray)
            Text(game.homeScore).font(.system(size: 22, weight: .bold, design: .rounded))
        }
        .foregroundColor(game.isLive ? .red : nil)
    }

    private func statusLabel(_ game: SharedGame) -> some View {
        Group {
            if game.isLive {
                Text(game.shortDetail ?? "Live").font(.system(size: 9, weight: .bold)).foregroundColor(.red)
            } else {
                Text("Final").font(.system(size: 9, weight: .semibold)).foregroundColor(.gray)
            }
        }
    }

    @ViewBuilder
    private func countdownBlock(_ game: SharedGame, large: Bool) -> some View {
        if let date = game.startDate {
            let diff = date.timeIntervalSince(entry.date)
            VStack(spacing: 1) {
                if diff > 0 {
                    let hours = Int(diff) / 3600
                    let mins = (Int(diff) % 3600) / 60
                    Text(hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m")
                        .font(.system(size: large ? 18 : 13, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    timeOfDay(date)
                } else {
                    Text("Starting...")
                        .font(.system(size: large ? 14 : 11, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
        } else {
            Text(game.detail ?? "TBD").font(.system(size: 11, weight: .medium)).foregroundColor(.gray)
        }
    }

    private func timeOfDay(_ date: Date) -> some View {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return Text(f.string(from: date))
            .font(.system(size: 8, weight: .medium))
            .foregroundColor(.gray)
    }

    private func gameRow(_ game: SharedGame) -> some View {
        HStack(spacing: 6) {
            if game.isLive {
                Circle().fill(Color.red).frame(width: 4, height: 4)
            } else if game.isScheduled {
                Image(systemName: "clock.fill").font(.system(size: 7)).foregroundColor(.orange)
            }

            if let seed = game.awaySeed {
                Text("\(seed)").font(.system(size: 8, weight: .medium)).foregroundColor(.gray)
            }
            Text(game.awayAbbreviation).font(.system(size: 12, weight: .semibold)).lineLimit(1).frame(width: 40, alignment: .leading)

            Spacer()

            if game.isLive || game.isFinal {
                VStack(spacing: 1) {
                    Text("\(game.awayScore) - \(game.homeScore)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(game.isLive ? .red : nil)
                    if game.isLive {
                        Text(game.shortDetail ?? "Live").font(.system(size: 7, weight: .bold)).foregroundColor(.red)
                    } else {
                        Text("Final").font(.system(size: 7, weight: .semibold)).foregroundColor(.gray)
                    }
                }
            } else if game.isScheduled {
                VStack(spacing: 1) {
                    countdownBlock(game, large: false)
                    if let wpText = game.winProbText {
                        Text(wpText)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                    }
                }
            }

            Spacer()

            Text(game.homeAbbreviation).font(.system(size: 12, weight: .semibold)).lineLimit(1).frame(width: 40, alignment: .trailing)
            if let seed = game.homeSeed {
                Text("\(seed)").font(.system(size: 8, weight: .medium)).foregroundColor(.gray)
            }
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "basketball").font(.title3).foregroundColor(.gray)
            Text("No games right now").font(.caption).foregroundColor(.gray)
        }
    }
}

// MARK: - Sample Data

let sampleGames: [SharedGame] = [
    SharedGame(
        id: "sample1", awayTeam: "Duke", awayAbbreviation: "DUKE", awayScore: "72",
        awaySeed: 4, awayLogo: nil, awayColor: "003087",
        homeTeam: "UNC", homeAbbreviation: "UNC", homeScore: "68",
        homeSeed: 1, homeLogo: nil, homeColor: "7BAFD4",
        state: "in", detail: "2nd Half - 4:32", shortDetail: "2nd 4:32",
        period: 2, displayClock: "4:32", startDate: Date(),
        roundName: "Sweet 16", regionName: "East", broadcast: "CBS",
        isUpset: true, winProbTeam: "DUKE", winProbValue: 0.62
    ),
    SharedGame(
        id: "sample2", awayTeam: "Kansas", awayAbbreviation: "KU", awayScore: "0",
        awaySeed: 1, awayLogo: nil, awayColor: "0051BA",
        homeTeam: "Kentucky", homeAbbreviation: "UK", homeScore: "0",
        homeSeed: 3, homeLogo: nil, homeColor: "0033A0",
        state: "pre", detail: "7:10 PM ET", shortDetail: "7:10 PM",
        period: 0, displayClock: nil, startDate: Date().addingTimeInterval(3600),
        roundName: "1st Round", regionName: "South", broadcast: "TNT",
        isUpset: false, winProbTeam: "KU", winProbValue: 0.85
    ),
]
