import WidgetKit
import SwiftUI

// MARK: - Baseball Widget

struct BaseballWidget: Widget {
    let kind = "BaseballWidget_v1"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BaseballProvider()) { entry in
            BaseballWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Baseball")
        .description("Live baseball diamond with base runners, count, plays, and line score")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Color Helper

private enum BBColor {
    static func from(_ hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6 else { return .gray }
        var rgb: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&rgb) else { return .gray }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }

    static let outfield = Color(red: 0.13, green: 0.52, blue: 0.18)
    static let infield = Color(red: 0.60, green: 0.45, blue: 0.28)
    static let dirtPath = Color(red: 0.55, green: 0.40, blue: 0.24)
    static let grass = Color(red: 0.18, green: 0.58, blue: 0.22)
    static let runner = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let ballGreen = Color(red: 0.2, green: 0.78, blue: 0.35)
    static let strikeRed = Color(red: 0.95, green: 0.25, blue: 0.22)
    static let outYellow = Color(red: 1.0, green: 0.75, blue: 0.0)
}

// MARK: - Play Event

struct BBPlayEvent: Identifiable {
    let id: String
    let text: String
    let inning: String
}

// MARK: - Game Data

struct BaseballGameData {
    let id: String
    let awayAbbr: String
    let homeAbbr: String
    let awayScore: String
    let homeScore: String
    let awayColorHex: String
    let homeColorHex: String
    let state: String
    let inning: Int
    let isTopInning: Bool
    let detail: String?
    let shortDetail: String?
    let balls: Int
    let strikes: Int
    let outs: Int
    let onFirst: Bool
    let onSecond: Bool
    let onThird: Bool
    let batterName: String?
    let pitcherName: String?
    let lastPlayText: String?
    let recentPlays: [BBPlayEvent]
    let startDate: Date?

    var isLive: Bool { state == "in" }
    var isFinal: Bool { state == "post" }
    var isScheduled: Bool { state == "pre" }

    var awayColor: Color { BBColor.from(awayColorHex) }
    var homeColor: Color { BBColor.from(homeColorHex) }

    var inningOrdinal: String {
        switch inning {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(inning)th"
        }
    }

    var inningText: String {
        let half = isTopInning ? "Top" : "Bot"
        return "\(half) \(inningOrdinal)"
    }
}

// MARK: - Entry

struct BaseballEntry: TimelineEntry {
    let date: Date
    let game: BaseballGameData?
}

// MARK: - Provider

struct BaseballProvider: TimelineProvider {
    func placeholder(in context: Context) -> BaseballEntry { sampleEntry }

    func getSnapshot(in context: Context, completion: @escaping (BaseballEntry) -> Void) {
        fetchBaseball { completion($0 ?? sampleEntry) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BaseballEntry>) -> Void) {
        // Ensure completion is called exactly once — WidgetKit preempts the
        // extension aggressively, so guarantee a fallback timeline ships.
        let lock = NSLock()
        var fired = false
        func fire(_ timeline: Timeline<BaseballEntry>) {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            lock.unlock()
            completion(timeline)
        }
        let wrappedCompletion: (Timeline<BaseballEntry>) -> Void = fire
        DispatchQueue.global().asyncAfter(deadline: .now() + 4.5) {
            fire(Timeline(entries: [self.placeholder(in: context)], policy: .after(Date().addingTimeInterval(60))))
        }

        fetchBaseball { entry in
            let result = entry ?? sampleEntry
            let hasLive = result.game?.isLive == true
            let refresh = Calendar.current.date(byAdding: .minute, value: hasLive ? 1 : 10, to: Date())!
            wrappedCompletion(Timeline(entries: [result], policy: .after(refresh)))
        }
    }

    private func fetchBaseball(completion: @escaping (BaseballEntry?) -> Void) {
        let urlString: String
        if let league = SportLeague.find("mlb") {
            urlString = league.scoreboardURL
        } else {
            urlString = "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard"
        }
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let events = json["events"] as? [[String: Any]] else {
                completion(nil)
                return
            }

            let games = events.compactMap { self.parseEvent($0) }
            guard let best = self.pickBestGame(games) else {
                completion(BaseballEntry(date: Date(), game: games.first))
                return
            }

            // Try to fetch play-by-play for the best game
            self.fetchPlays(gameID: best.id) { plays in
                let enriched = BaseballGameData(
                    id: best.id,
                    awayAbbr: best.awayAbbr, homeAbbr: best.homeAbbr,
                    awayScore: best.awayScore, homeScore: best.homeScore,
                    awayColorHex: best.awayColorHex, homeColorHex: best.homeColorHex,
                    state: best.state, inning: best.inning,
                    isTopInning: best.isTopInning,
                    detail: best.detail, shortDetail: best.shortDetail,
                    balls: best.balls, strikes: best.strikes, outs: best.outs,
                    onFirst: best.onFirst, onSecond: best.onSecond, onThird: best.onThird,
                    batterName: best.batterName, pitcherName: best.pitcherName,
                    lastPlayText: best.lastPlayText,
                    recentPlays: plays.isEmpty ? best.recentPlays : plays,
                    startDate: best.startDate
                )
                completion(BaseballEntry(date: Date(), game: enriched))
            }
        }.resume()
    }

    private func fetchPlays(gameID: String, completion: @escaping ([BBPlayEvent]) -> Void) {
        let base: String
        if let league = SportLeague.find("mlb") {
            base = league.summaryURL
        } else {
            base = "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/summary"
        }
        guard let url = URL(string: "\(base)?event=\(gameID)") else {
            completion([])
            return
        }

        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion([])
                return
            }

            var plays: [BBPlayEvent] = []

            // Try plays.allPlays or keyEvents
            let keyEvents = json["keyEvents"] as? [[String: Any]]
                ?? (json["plays"] as? [String: Any])?["allPlays"] as? [[String: Any]]
                ?? []

            for (idx, event) in keyEvents.suffix(6).enumerated() {
                let text = event["text"] as? String
                    ?? (event["type"] as? [String: Any])?["text"] as? String
                    ?? ""
                let period = event["period"] as? [String: Any]
                let inningNum = period?["number"] as? Int ?? 0
                let periodType = period?["type"] as? String ?? ""
                let half = periodType.lowercased().contains("top") ? "T" : "B"
                let inningLabel = inningNum > 0 ? "\(half)\(inningNum)" : ""
                if !text.isEmpty {
                    plays.append(BBPlayEvent(id: "p\(idx)", text: text, inning: inningLabel))
                }
            }

            completion(plays)
        }.resume()
    }

    private func pickBestGame(_ games: [BaseballGameData]) -> BaseballGameData? {
        let live = games.filter { $0.isLive }.sorted { $0.inning > $1.inning }
        if let best = live.first { return best }
        let upcoming = games.filter { $0.isScheduled }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        if let next = upcoming.first { return next }
        return games.filter { $0.isFinal }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
            .first
    }

    private func parseEvent(_ event: [String: Any]) -> BaseballGameData? {
        guard let id = event["id"] as? String,
              let competitions = event["competitions"] as? [[String: Any]],
              let comp = competitions.first,
              let competitors = comp["competitors"] as? [[String: Any]],
              let statusDict = event["status"] as? [String: Any],
              let statusType = statusDict["type"] as? [String: Any],
              let state = statusType["state"] as? String else { return nil }

        let period = statusDict["period"] as? Int ?? 0
        let detail = statusType["detail"] as? String
        let shortDetail = statusType["shortDetail"] as? String
        let dateStr = event["date"] as? String ?? ""
        let startDate = Self.parseDate(dateStr)

        let isTopInning = detail?.lowercased().contains("top") == true
            || shortDetail?.lowercased().contains("top") == true

        let away = competitors.first { ($0["homeAway"] as? String) == "away" }
        let home = competitors.first { ($0["homeAway"] as? String) == "home" }

        func teamInfo(_ c: [String: Any]?) -> (abbr: String, score: String, color: String) {
            guard let c = c, let team = c["team"] as? [String: Any] else {
                return ("TBD", "0", "666666")
            }
            return (
                team["abbreviation"] as? String ?? "TBD",
                c["score"] as? String ?? "0",
                team["color"] as? String ?? "666666"
            )
        }

        let awayInfo = teamInfo(away)
        let homeInfo = teamInfo(home)

        let situation = comp["situation"] as? [String: Any]
        let balls = situation?["balls"] as? Int ?? 0
        let strikes = situation?["strikes"] as? Int ?? 0
        let outs = situation?["outs"] as? Int ?? 0
        let onFirst = situation?["onFirst"] as? Bool ?? false
        let onSecond = situation?["onSecond"] as? Bool ?? false
        let onThird = situation?["onThird"] as? Bool ?? false

        let batter = situation?["batter"] as? [String: Any]
        let pitcher = situation?["pitcher"] as? [String: Any]
        let batterAthlete = batter?["athlete"] as? [String: Any]
        let pitcherAthlete = pitcher?["athlete"] as? [String: Any]
        let batterName = batterAthlete?["shortName"] as? String
            ?? batter?["shortName"] as? String
            ?? batter?["displayName"] as? String
        let pitcherName = pitcherAthlete?["shortName"] as? String
            ?? pitcher?["shortName"] as? String
            ?? pitcher?["displayName"] as? String

        let lastPlay = situation?["lastPlay"] as? [String: Any]
        let lastPlayText = lastPlay?["text"] as? String

        return BaseballGameData(
            id: id,
            awayAbbr: awayInfo.abbr, homeAbbr: homeInfo.abbr,
            awayScore: awayInfo.score, homeScore: homeInfo.score,
            awayColorHex: awayInfo.color, homeColorHex: homeInfo.color,
            state: state, inning: period,
            isTopInning: isTopInning,
            detail: detail, shortDetail: shortDetail,
            balls: balls, strikes: strikes, outs: outs,
            onFirst: onFirst, onSecond: onSecond, onThird: onThird,
            batterName: batterName, pitcherName: pitcherName,
            lastPlayText: lastPlayText,
            recentPlays: [],
            startDate: startDate
        )
    }

    private static func parseDate(_ s: String) -> Date? {
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: s) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        if s.hasSuffix("Z") && s.count <= 17 {
            let withSec = s.replacingOccurrences(of: "Z", with: ":00Z")
            if let d = iso.date(from: withSec) { return d }
        }
        return nil
    }

    private var sampleEntry: BaseballEntry {
        BaseballEntry(
            date: Date(),
            game: BaseballGameData(
                id: "sample_bb",
                awayAbbr: "NYY", homeAbbr: "BOS",
                awayScore: "4", homeScore: "3",
                awayColorHex: "003087", homeColorHex: "BD3039",
                state: "in", inning: 5, isTopInning: true,
                detail: "Top 5th", shortDetail: "Top 5th",
                balls: 2, strikes: 1, outs: 1,
                onFirst: true, onSecond: false, onThird: true,
                batterName: "A. Judge", pitcherName: "C. Sale",
                lastPlayText: "Judge singles to left field, Soto scores from third.",
                recentPlays: [
                    BBPlayEvent(id: "s1", text: "Soto doubles to deep center", inning: "T5"),
                    BBPlayEvent(id: "s2", text: "Stanton grounds out to short", inning: "T5"),
                    BBPlayEvent(id: "s3", text: "Judge singles, Soto scores", inning: "T5"),
                ],
                startDate: Date()
            )
        )
    }
}

// MARK: - Widget View

struct BaseballWidgetView: View {
    let entry: BaseballEntry
    @Environment(\.widgetFamily) var family

    private static let preGameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E h:mm a"
        return f
    }()

    var body: some View {
        if let game = entry.game {
            switch family {
            case .systemSmall: smallView(game)
            case .systemLarge: largeView(game)
            default: mediumView(game)
            }
        } else {
            emptyState
        }
    }

    // MARK: - Small View

    private func smallView(_ game: BaseballGameData) -> some View {
        VStack(spacing: 3) {
            // Header
            HStack(spacing: 3) {
                Image(systemName: "baseball.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.orange)
                Text("MLB")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(.secondary)
                Spacer()
                if game.isLive {
                    HStack(spacing: 2) {
                        Circle().fill(.green).frame(width: 4, height: 4)
                        Text(game.inningText)
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundColor(.green)
                    }
                } else if game.isFinal {
                    Text("FINAL")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundColor(.gray)
                }
            }

            if game.isLive {
                // Diamond with runners
                HStack(spacing: 6) {
                    diamondView(game: game, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        bsoView(game: game, dotSize: 5)
                    }
                }

                Spacer(minLength: 0)

                // Score
                compactScoreLine(game)

            } else if game.isScheduled {
                Spacer()
                preGameSmall(game)
                Spacer()
            } else {
                Spacer()
                compactScoreLine(game)
                Spacer()
            }
        }
        .padding(10)
    }

    // MARK: - Medium View

    private func mediumView(_ game: BaseballGameData) -> some View {
        HStack(spacing: 0) {
            // Left: diamond
            VStack(spacing: 4) {
                if game.isLive {
                    inningBadge(game)
                    diamondView(game: game, size: 64)
                    bsoView(game: game, dotSize: 6)
                } else if game.isScheduled {
                    diamondView(game: game, size: 56)
                    preGameCountdown(game)
                } else {
                    diamondView(game: game, size: 56)
                    Text("FINAL")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.leading, 6)

            // Right: scores + matchup + last play
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "baseball.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.orange)
                    Text("MLB")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.secondary)
                    Spacer()
                    if game.isLive {
                        HStack(spacing: 2) {
                            Circle().fill(.green).frame(width: 5, height: 5)
                            Text("LIVE")
                                .font(.system(size: 7, weight: .heavy))
                                .foregroundColor(.green)
                        }
                    }
                }

                lineScoreCompact(game)

                if game.isLive {
                    Divider().opacity(0.2)

                    // Batter vs Pitcher
                    if let batter = game.batterName, let pitcher = game.pitcherName {
                        HStack(spacing: 2) {
                            Image(systemName: "figure.baseball")
                                .font(.system(size: 7))
                                .foregroundColor(.orange)
                            Text(batter)
                                .font(.system(size: 8, weight: .bold))
                            Text("vs")
                                .font(.system(size: 7))
                                .foregroundColor(.secondary)
                            Text(pitcher)
                                .font(.system(size: 8, weight: .bold))
                        }
                        .lineLimit(1)
                    }

                    // Last play
                    if let play = game.lastPlayText {
                        Text(play)
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }

    // MARK: - Large View

    private func largeView(_ game: BaseballGameData) -> some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "baseball.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                    Text("MLB BASEBALL")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if game.isLive {
                    HStack(spacing: 3) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text(game.inningText)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.green)
                    }
                } else if game.isFinal {
                    Text("FINAL")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.gray)
                } else if let date = game.startDate {
                    Text(Self.preGameFormatter.string(from: date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider().opacity(0.3).padding(.horizontal, 14)

            // Diamond + score section
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 6) {
                    diamondView(game: game, size: 84)
                    if game.isLive {
                        bsoView(game: game, dotSize: 7)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    lineScoreFull(game)

                    if game.isLive {
                        Divider().opacity(0.2)

                        // Matchup
                        if let batter = game.batterName {
                            HStack(spacing: 3) {
                                Image(systemName: "figure.baseball")
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                                Text("AB:")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(batter)
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        if let pitcher = game.pitcherName {
                            HStack(spacing: 3) {
                                Image(systemName: "hand.raised.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.blue)
                                Text("P:")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(pitcher)
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            // Last play banner
            if game.isLive, let play = game.lastPlayText {
                HStack(spacing: 4) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                    Text(play)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
            }

            // Play-by-play feed (large only)
            if game.isLive || game.isFinal {
                let plays = game.recentPlays.suffix(4)
                if !plays.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("RECENT PLAYS")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 6)
                        .padding(.bottom, 3)

                        ForEach(Array(plays.reversed())) { play in
                            HStack(alignment: .top, spacing: 6) {
                                if !play.inning.isEmpty {
                                    Text(play.inning)
                                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                                        .foregroundColor(.orange)
                                        .frame(width: 22, alignment: .leading)
                                }
                                Text(play.text)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.primary.opacity(0.7))
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Inning progress bar
            if game.isLive {
                inningProgressBar(game)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Diamond

    private func diamondView(game: BaseballGameData, size: CGFloat) -> some View {
        let baseSize = size * 0.13
        let runnerDot = size * 0.11

        return ZStack {
            // Outfield arc
            Path { path in
                let center = CGPoint(x: size / 2, y: size * 0.55)
                path.addArc(center: center, radius: size * 0.48,
                            startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                path.closeSubpath()
            }
            .fill(BBColor.outfield.opacity(0.7))

            // Infield dirt
            Path { path in
                let home = CGPoint(x: size / 2, y: size * 0.85)
                let first = CGPoint(x: size * 0.82, y: size * 0.52)
                let second = CGPoint(x: size / 2, y: size * 0.2)
                let third = CGPoint(x: size * 0.18, y: size * 0.52)
                path.move(to: home)
                path.addLine(to: first)
                path.addLine(to: second)
                path.addLine(to: third)
                path.closeSubpath()
            }
            .fill(BBColor.infield.opacity(0.5))

            // Grass cutout in center of infield
            Path { path in
                let cx = size / 2
                let cy = size * 0.52
                let r = size * 0.14
                path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            }
            .fill(BBColor.grass.opacity(0.5))

            // Basepaths
            Path { path in
                let home = CGPoint(x: size / 2, y: size * 0.85)
                let first = CGPoint(x: size * 0.82, y: size * 0.52)
                let second = CGPoint(x: size / 2, y: size * 0.2)
                let third = CGPoint(x: size * 0.18, y: size * 0.52)
                path.move(to: home)
                path.addLine(to: first)
                path.addLine(to: second)
                path.addLine(to: third)
                path.closeSubpath()
            }
            .stroke(.white.opacity(0.75), lineWidth: 1.5)

            // Home plate
            homePlateShape(center: CGPoint(x: size / 2, y: size * 0.85), plateSize: baseSize * 0.9)
                .fill(.white)

            // Bases with runner indicators
            baseView(at: CGPoint(x: size * 0.82, y: size * 0.52),
                     size: baseSize, occupied: game.onFirst, runnerSize: runnerDot)
            baseView(at: CGPoint(x: size / 2, y: size * 0.2),
                     size: baseSize, occupied: game.onSecond, runnerSize: runnerDot)
            baseView(at: CGPoint(x: size * 0.18, y: size * 0.52),
                     size: baseSize, occupied: game.onThird, runnerSize: runnerDot)

            // Pitch count dots near home plate
            if game.isLive {
                pitchCountDots(balls: game.balls, strikes: game.strikes,
                               center: CGPoint(x: size / 2, y: size * 0.95),
                               dotSize: max(3, size * 0.04))
            }
        }
        .frame(width: size, height: size)
    }

    private func baseView(at point: CGPoint, size: CGFloat, occupied: Bool, runnerSize: CGFloat) -> some View {
        ZStack {
            // Base diamond shape
            Rectangle()
                .fill(occupied ? BBColor.runner : .white.opacity(0.35))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(45))
                .overlay(
                    Rectangle()
                        .stroke(.white.opacity(0.8), lineWidth: occupied ? 1.5 : 0.8)
                        .frame(width: size, height: size)
                        .rotationEffect(.degrees(45))
                )

            // Runner dot
            if occupied {
                Circle()
                    .fill(BBColor.runner)
                    .frame(width: runnerSize, height: runnerSize)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .overlay(
                        Circle()
                            .stroke(.white, lineWidth: 1)
                            .frame(width: runnerSize, height: runnerSize)
                    )
            }
        }
        .position(point)
    }

    private func homePlateShape(center: CGPoint, plateSize: CGFloat) -> Path {
        let s = plateSize
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y + s * 0.5))
        path.addLine(to: CGPoint(x: center.x - s * 0.5, y: center.y + s * 0.2))
        path.addLine(to: CGPoint(x: center.x - s * 0.5, y: center.y - s * 0.3))
        path.addLine(to: CGPoint(x: center.x + s * 0.5, y: center.y - s * 0.3))
        path.addLine(to: CGPoint(x: center.x + s * 0.5, y: center.y + s * 0.2))
        path.closeSubpath()
        return path
    }

    private func pitchCountDots(balls: Int, strikes: Int, center: CGPoint, dotSize: CGFloat) -> some View {
        HStack(spacing: 2) {
            // Balls (green)
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i < balls ? BBColor.ballGreen : .gray.opacity(0.25))
                    .frame(width: dotSize, height: dotSize)
            }
            Spacer().frame(width: 3)
            // Strikes (red)
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i < strikes ? BBColor.strikeRed : .gray.opacity(0.25))
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .position(center)
    }

    // MARK: - BSO (Balls, Strikes, Outs) combined

    private func bsoView(game: BaseballGameData, dotSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            // Balls
            HStack(spacing: 2) {
                Text("B")
                    .font(.system(size: dotSize * 0.9, weight: .heavy))
                    .foregroundColor(.secondary)
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < game.balls ? BBColor.ballGreen : .gray.opacity(0.25))
                        .frame(width: dotSize, height: dotSize)
                }
            }
            // Strikes
            HStack(spacing: 2) {
                Text("S")
                    .font(.system(size: dotSize * 0.9, weight: .heavy))
                    .foregroundColor(.secondary)
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < game.strikes ? BBColor.strikeRed : .gray.opacity(0.25))
                        .frame(width: dotSize, height: dotSize)
                }
            }
            // Outs
            HStack(spacing: 2) {
                Text("O")
                    .font(.system(size: dotSize * 0.9, weight: .heavy))
                    .foregroundColor(.secondary)
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < game.outs ? BBColor.outYellow : .gray.opacity(0.25))
                        .frame(width: dotSize, height: dotSize)
                }
            }
        }
    }

    // MARK: - Inning Badge

    private func inningBadge(_ game: BaseballGameData) -> some View {
        HStack(spacing: 3) {
            Image(systemName: game.isTopInning ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 6))
                .foregroundColor(.orange)
            Text(game.inningOrdinal)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(.orange.opacity(0.15)))
    }

    // MARK: - Score Lines

    private func compactScoreLine(_ game: BaseballGameData) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                Circle().fill(game.awayColor).frame(width: 6, height: 6)
                Text(game.awayAbbr)
                    .font(.system(size: 10, weight: .semibold))
                Text(game.awayScore)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
            }
            Text("-")
                .font(.system(size: 10))
                .foregroundColor(.gray)
            HStack(spacing: 3) {
                Text(game.homeScore)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                Text(game.homeAbbr)
                    .font(.system(size: 10, weight: .semibold))
                Circle().fill(game.homeColor).frame(width: 6, height: 6)
            }
        }
    }

    private func lineScoreCompact(_ game: BaseballGameData) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(game.awayColor).frame(width: 6, height: 6)
                Text(game.awayAbbr)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 34, alignment: .leading)
                Spacer()
                Text(game.awayScore)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            Divider().opacity(0.2)
            HStack(spacing: 6) {
                Circle().fill(game.homeColor).frame(width: 6, height: 6)
                Text(game.homeAbbr)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 34, alignment: .leading)
                Spacer()
                Text(game.homeScore)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
        }
    }

    private func lineScoreFull(_ game: BaseballGameData) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                Text("").frame(width: 50, alignment: .leading)
                Spacer()
                Text("R")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.secondary)
                    .frame(width: 28)
            }
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Circle().fill(game.awayColor).frame(width: 7, height: 7)
                    Text(game.awayAbbr)
                        .font(.system(size: 12, weight: .bold))
                }
                .frame(width: 60, alignment: .leading)
                Spacer()
                Text(game.awayScore)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .frame(width: 28)
            }
            Divider().opacity(0.15)
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Circle().fill(game.homeColor).frame(width: 7, height: 7)
                    Text(game.homeAbbr)
                        .font(.system(size: 12, weight: .bold))
                }
                .frame(width: 60, alignment: .leading)
                Spacer()
                Text(game.homeScore)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .frame(width: 28)
            }
        }
    }

    // MARK: - Inning Progress Bar

    private func inningProgressBar(_ game: BaseballGameData) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 2) {
                ForEach(1..<10, id: \.self) { inn in
                    ZStack {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(inn < game.inning ? .green.opacity(0.3) :
                                    inn == game.inning ? .orange.opacity(0.4) :
                                    .gray.opacity(0.15))
                            .frame(height: 14)
                        Text("\(inn)")
                            .font(.system(size: 7, weight: inn == game.inning ? .heavy : .medium))
                            .foregroundColor(inn == game.inning ? .orange : .secondary)
                    }
                }
            }
            HStack {
                HStack(spacing: 2) {
                    Image(systemName: game.isTopInning ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 5))
                        .foregroundColor(.orange)
                    Text(game.inningText)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.orange)
                }
                Spacer()
                Text("\(game.balls)-\(game.strikes)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("\(game.outs) out\(game.outs == 1 ? "" : "s")")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Pre-game

    private func preGameSmall(_ game: BaseballGameData) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                VStack(spacing: 2) {
                    Circle().fill(game.awayColor).frame(width: 8, height: 8)
                    Text(game.awayAbbr)
                        .font(.system(size: 11, weight: .bold))
                }
                Text("@")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                VStack(spacing: 2) {
                    Circle().fill(game.homeColor).frame(width: 8, height: 8)
                    Text(game.homeAbbr)
                        .font(.system(size: 11, weight: .bold))
                }
            }
            if let date = game.startDate {
                let diff = date.timeIntervalSince(entry.date)
                if diff > 0 {
                    let hours = Int(diff) / 3600
                    let mins = (Int(diff) % 3600) / 60
                    Text(hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private func preGameCountdown(_ game: BaseballGameData) -> some View {
        VStack(spacing: 2) {
            if let date = game.startDate {
                let diff = date.timeIntervalSince(entry.date)
                if diff > 0 {
                    let hours = Int(diff) / 3600
                    let mins = (Int(diff) % 3600) / 60
                    Text(hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    Text(Self.preGameFormatter.string(from: date))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "baseball.fill")
                .font(.title3)
                .foregroundColor(.gray)
            Text("No baseball games")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}
