import WidgetKit
import SwiftUI

// MARK: - Tennis Widget

struct TennisWidget: Widget {
    let kind = "TennisWidget_v1"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TennisProvider()) { entry in
            TennisWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tennis")
        .description("Live tennis match data on a drawn court")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Color Helper

private enum TennisColorHelper {
    static func color(hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        guard cleaned.count == 6 else { return .gray }
        return Color(
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
    }

    static let hardCourt = color(hex: "0050A0")
    static let clayCourt = color(hex: "CC6633")
    static let grassCourt = color(hex: "2E7D32")
    static let courtSurround = color(hex: "1B5E20")
}

// MARK: - Models

struct TennisPlayer: Identifiable {
    let id: String
    let name: String
    let shortName: String
    let ranking: Int?
    let flagURL: String?
    let isServing: Bool
    let isWinner: Bool
    let setScores: [Int]
    let currentGameScore: String?
}

struct TennisMatch: Identifiable {
    let id: String
    let player1: TennisPlayer
    let player2: TennisPlayer
    let state: String
    let currentSet: Int
    let surface: String?
    let tournamentName: String
    let roundName: String?
    let startDate: Date?
    let detail: String?
    let leagueAbbr: String
    let situationText: String?  // "Match Point", "Set Point", "Break Point"

    var isLive: Bool { state == "in" }
    var isFinished: Bool { state == "post" }
    var isPre: Bool { state == "pre" }

    var interestScore: Int {
        if isLive { return 100 }
        if isPre, let d = startDate, d.timeIntervalSinceNow < 3600 { return 50 }
        if isFinished { return 10 }
        return 1
    }
}

// MARK: - Entry

struct TennisEntry: TimelineEntry {
    let date: Date
    let match: TennisMatch?
}

// MARK: - Provider

struct TennisProvider: TimelineProvider {
    private static let tennisLeagueIDs = ["atp", "wta"]

    func placeholder(in context: Context) -> TennisEntry { sampleEntry }

    func getSnapshot(in context: Context, completion: @escaping (TennisEntry) -> Void) {
        fetchMatches { completion($0 ?? sampleEntry) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TennisEntry>) -> Void) {
        // Ensure completion is called exactly once — WidgetKit preempts the
        // extension aggressively, so guarantee a fallback timeline ships.
        let lock = NSLock()
        var fired = false
        func fire(_ timeline: Timeline<TennisEntry>) {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            lock.unlock()
            completion(timeline)
        }
        let wrappedCompletion: (Timeline<TennisEntry>) -> Void = fire
        DispatchQueue.global().asyncAfter(deadline: .now() + 4.5) {
            fire(Timeline(entries: [self.placeholder(in: context)], policy: .after(Date().addingTimeInterval(60))))
        }

        fetchMatches { entry in
            let final = entry ?? sampleEntry
            let hasLive = final.match?.isLive == true
            let refresh = Calendar.current.date(byAdding: .minute, value: hasLive ? 2 : 15, to: Date())!
            wrappedCompletion(Timeline(entries: [final], policy: .after(refresh)))
        }
    }

    private func fetchMatches(completion: @escaping (TennisEntry?) -> Void) {
        let selectedIDs = UserDefaults.standard.array(forKey: "selectedSportIDs") as? [String] ?? []
        let enabledTennis = Self.tennisLeagueIDs.filter { selectedIDs.contains($0) }
        let leagueIDs = enabledTennis.isEmpty ? ["atp"] : enabledTennis
        let leagues = leagueIDs.compactMap { SportLeague.find($0) }
        if leagues.isEmpty { completion(nil); return }

        let group = DispatchGroup()
        var allMatches: [TennisMatch] = []
        let lock = NSLock()

        // Use the ESPN web API endpoint which includes groupings with individual matches
        for league in leagues {
            group.enter()
            let webURL = "https://site.web.api.espn.com/apis/site/v2/sports/tennis/\(league.league)/scoreboard"
            guard let url = URL(string: webURL) else { group.leave(); continue }

            URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)) { data, _, _ in
                defer { group.leave() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let events = json["events"] as? [[String: Any]] else { return }

                // Tennis matches are nested inside events[].groupings[].competitions[]
                var matches: [TennisMatch] = []
                for event in events {
                    let tournamentName = event["shortName"] as? String
                        ?? event["name"] as? String ?? "Tournament"
                    var surface: String?
                    if let venue = event["venue"] as? [String: Any] {
                        surface = venue["surface"] as? String
                    }
                    if surface == nil {
                        let lower = tournamentName.lowercased()
                        if lower.contains("wimbledon") { surface = "Grass" }
                        else if lower.contains("roland") || lower.contains("french") { surface = "Clay" }
                        else { surface = "Hard" }
                    }

                    let groupings = event["groupings"] as? [[String: Any]] ?? []
                    for grouping in groupings {
                        let roundName = (grouping["grouping"] as? [String: Any])?["shortName"] as? String
                            ?? (grouping["grouping"] as? [String: Any])?["displayName"] as? String
                        let comps = grouping["competitions"] as? [[String: Any]] ?? []
                        for comp in comps {
                            if let match = parseMatchFromCompetition(
                                comp, leagueAbbr: league.shortName,
                                tournamentName: tournamentName, surface: surface,
                                roundName: roundName
                            ) {
                                matches.append(match)
                            }
                        }
                    }
                }
                lock.lock()
                allMatches.append(contentsOf: matches)
                lock.unlock()
            }.resume()
        }

        group.notify(queue: .main) {
            let sorted = allMatches.sorted { $0.interestScore > $1.interestScore }
            completion(TennisEntry(date: Date(), match: sorted.first))
        }
    }

    private func parseMatchFromCompetition(
        _ comp: [String: Any], leagueAbbr: String,
        tournamentName: String, surface: String?, roundName: String?
    ) -> TennisMatch? {
        guard let id = comp["id"] as? String,
              let competitors = comp["competitors"] as? [[String: Any]],
              competitors.count >= 2,
              let statusDict = comp["status"] as? [String: Any],
              let statusType = statusDict["type"] as? [String: Any],
              let state = statusType["state"] as? String else { return nil }

        let detail = statusType["detail"] as? String
        let period = statusDict["period"] as? Int ?? 1
        let dateStr = (comp["date"] as? String) ?? (comp["startDate"] as? String) ?? ""
        let startDate = parseDate(dateStr)

        var situationText: String?
        if let situation = comp["situation"] as? [String: Any] {
            situationText = situation["shortDetail"] as? String ?? situation["detail"] as? String
        }

        func parsePlayer(_ c: [String: Any], index: Int) -> TennisPlayer {
            let athlete = c["athlete"] as? [String: Any] ?? c["team"] as? [String: Any] ?? [:]
            let name = athlete["displayName"] as? String ?? "Player \(index + 1)"
            let shortName = athlete["shortName"] as? String ?? name.components(separatedBy: " ").last ?? name

            var ranking: Int?
            if let rank = c["curatedRank"] as? [String: Any], let cur = rank["current"] as? Int, cur > 0 {
                ranking = cur
            }
            if ranking == nil, let rank = athlete["rank"] as? Int, rank > 0 { ranking = rank }

            let flagInfo = athlete["flag"] as? [String: Any]
            let flagURL = flagInfo?["href"] as? String
            let winner = c["winner"] as? Bool ?? false

            var setScores: [Int] = []
            if let linescores = c["linescores"] as? [[String: Any]] {
                for ls in linescores {
                    if let val = ls["value"] as? Double { setScores.append(Int(val)) }
                    else if let valStr = ls["displayValue"] as? String, let val = Int(valStr) { setScores.append(val) }
                }
            }

            var gameScore: String?
            if state == "in" {
                let score = c["score"] as? String
                if let s = score, ["0", "15", "30", "40", "Ad"].contains(s) { gameScore = s }
            }

            let isServing = c["possession"] as? Bool ?? false

            return TennisPlayer(
                id: c["id"] as? String ?? "\(index)",
                name: name, shortName: shortName, ranking: ranking,
                flagURL: flagURL, isServing: isServing, isWinner: winner,
                setScores: setScores, currentGameScore: gameScore
            )
        }

        return TennisMatch(
            id: id,
            player1: parsePlayer(competitors[0], index: 0),
            player2: parsePlayer(competitors[1], index: 1),
            state: state, currentSet: period, surface: surface,
            tournamentName: tournamentName, roundName: roundName,
            startDate: startDate, detail: detail, leagueAbbr: leagueAbbr,
            situationText: situationText
        )
    }

    private func parseMatch(_ event: [String: Any], leagueAbbr: String) -> TennisMatch? {
        guard let id = event["id"] as? String,
              let competitions = event["competitions"] as? [[String: Any]],
              let comp = competitions.first,
              let competitors = comp["competitors"] as? [[String: Any]],
              competitors.count >= 2,
              let statusDict = event["status"] as? [String: Any],
              let statusType = statusDict["type"] as? [String: Any],
              let state = statusType["state"] as? String else { return nil }

        let detail = statusType["detail"] as? String
        let period = statusDict["period"] as? Int ?? 1
        let dateStr = event["date"] as? String ?? ""
        let startDate = parseDate(dateStr)

        let season = event["season"] as? [String: Any]
        let tournamentName = season?["name"] as? String
            ?? event["shortName"] as? String
            ?? event["name"] as? String ?? "Tournament"

        var roundName: String?
        if let notes = event["notes"] as? [[String: Any]], let headline = notes.first?["headline"] as? String {
            roundName = headline
        }

        var surface: String?
        if let venue = comp["venue"] as? [String: Any] {
            surface = venue["surface"] as? String
        }
        if surface == nil {
            let lower = tournamentName.lowercased()
            if lower.contains("wimbledon") { surface = "Grass" }
            else if lower.contains("roland") || lower.contains("french") { surface = "Clay" }
            else { surface = "Hard" }
        }

        // Situation text (match point, set point, break point)
        var situationText: String?
        if let situation = comp["situation"] as? [String: Any] {
            situationText = situation["shortDetail"] as? String ?? situation["detail"] as? String
        }

        func parsePlayer(_ c: [String: Any], index: Int) -> TennisPlayer {
            let athlete = c["athlete"] as? [String: Any] ?? c["team"] as? [String: Any] ?? [:]
            let name = athlete["displayName"] as? String ?? "Player \(index + 1)"
            let shortName = athlete["shortName"] as? String ?? name.components(separatedBy: " ").last ?? name

            var ranking: Int?
            if let rank = c["curatedRank"] as? [String: Any], let cur = rank["current"] as? Int, cur > 0 {
                ranking = cur
            }
            if ranking == nil, let rank = athlete["rank"] as? Int, rank > 0 { ranking = rank }

            let flagInfo = athlete["flag"] as? [String: Any]
            let flagURL = flagInfo?["href"] as? String
            let winner = c["winner"] as? Bool ?? false

            var setScores: [Int] = []
            if let linescores = c["linescores"] as? [[String: Any]] {
                for ls in linescores {
                    if let val = ls["value"] as? Double { setScores.append(Int(val)) }
                    else if let valStr = ls["displayValue"] as? String, let val = Int(valStr) { setScores.append(val) }
                }
            }

            var gameScore: String?
            if state == "in" {
                let score = c["score"] as? String
                if let s = score, ["0", "15", "30", "40", "Ad"].contains(s) { gameScore = s }
            }

            let isServing = c["possession"] as? Bool ?? false

            return TennisPlayer(
                id: c["id"] as? String ?? "\(index)",
                name: name, shortName: shortName, ranking: ranking,
                flagURL: flagURL, isServing: isServing, isWinner: winner,
                setScores: setScores, currentGameScore: gameScore
            )
        }

        return TennisMatch(
            id: id,
            player1: parsePlayer(competitors[0], index: 0),
            player2: parsePlayer(competitors[1], index: 1),
            state: state, currentSet: period, surface: surface,
            tournamentName: tournamentName, roundName: roundName,
            startDate: startDate, detail: detail, leagueAbbr: leagueAbbr,
            situationText: situationText
        )
    }

    private func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    private var sampleEntry: TennisEntry {
        TennisEntry(
            date: Date(),
            match: TennisMatch(
                id: "sample1",
                player1: TennisPlayer(
                    id: "p1", name: "Novak Djokovic", shortName: "Djokovic",
                    ranking: 1, flagURL: nil, isServing: true, isWinner: false,
                    setScores: [6, 3, 5], currentGameScore: "30"
                ),
                player2: TennisPlayer(
                    id: "p2", name: "Carlos Alcaraz", shortName: "Alcaraz",
                    ranking: 2, flagURL: nil, isServing: false, isWinner: false,
                    setScores: [4, 6, 4], currentGameScore: "40"
                ),
                state: "in", currentSet: 3, surface: "Hard",
                tournamentName: "US Open", roundName: "Semifinal",
                startDate: nil, detail: "3rd Set", leagueAbbr: "ATP",
                situationText: "Break Point"
            )
        )
    }
}

// MARK: - Widget View

struct TennisWidgetView: View {
    let entry: TennisEntry
    @Environment(\.widgetFamily) var family

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemLarge: largeView
        default: mediumView
        }
    }

    // MARK: - Small View

    private var smallView: some View {
        ZStack {
            if let match = entry.match {
                TennisCourtDrawing(surface: match.surface ?? "Hard")
                smallOverlay(match)
            } else {
                noMatchView
            }
        }
    }

    // MARK: - Medium View

    private var mediumView: some View {
        ZStack {
            if let match = entry.match {
                TennisCourtDrawing(surface: match.surface ?? "Hard")
                mediumOverlay(match)
            } else {
                noMatchView
            }
        }
    }

    // MARK: - Large View

    private var largeView: some View {
        Group {
            if let match = entry.match {
                largeContent(match)
            } else {
                noMatchView
            }
        }
    }

    private func activeServiceBox(for match: TennisMatch) -> ActiveServiceBox {
        guard match.isLive else { return .none }
        // Player 1 is shown at the TOP of the court, player 2 at the bottom.
        // When a player serves, the receiving box is on the OPPOSITE side.
        // Determine deuce vs ad from current game score parity.
        let serverScore: String?
        let serverIsTop: Bool
        if match.player1.isServing {
            serverScore = match.player1.currentGameScore
            serverIsTop = true
        } else if match.player2.isServing {
            serverScore = match.player2.currentGameScore
            serverIsTop = false
        } else {
            return .none
        }

        // Deuce side = even number of points played by server (score 0 or 30), Ad = odd (15 or 40 or Ad)
        let isDeuceSide: Bool
        switch serverScore ?? "0" {
        case "0", "30": isDeuceSide = true
        case "15", "40", "Ad": isDeuceSide = false
        default: isDeuceSide = true
        }

        if serverIsTop {
            // Top server, receiving box is on bottom half
            return isDeuceSide ? .bottomDeuce : .bottomAd
        } else {
            // Bottom server, receiving box is on top half
            return isDeuceSide ? .topDeuce : .topAd
        }
    }

    private func largeContent(_ match: TennisMatch) -> some View {
        VStack(spacing: 0) {
            // Top header row
            HStack(spacing: 6) {
                Image(systemName: "tennisball.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.yellow)
                Text(match.leagueAbbr)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white.opacity(0.85))
                Text("·")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white.opacity(0.4))
                Text(match.tournamentName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let round = match.roundName {
                    Text("·")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white.opacity(0.4))
                    Text(round)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer()
                statusBadge(match)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // BIG Court (~60% of remaining height)
            GeometryReader { geo in
                ZStack {
                    TennisCourtDrawing(
                        surface: match.surface ?? "Hard",
                        activeServiceBox: activeServiceBox(for: match)
                    )

                    // Player labels on baselines
                    VStack {
                        // Top player label (player1)
                        playerBaselineLabel(match.player1, match: match)
                            .padding(.top, 4)
                        Spacer()
                        // Bottom player label (player2)
                        playerBaselineLabel(match.player2, match: match)
                            .padding(.bottom, 4)
                    }

                    // Bouncing ball marker at active service corner
                    ballMarker(for: match, geo: geo)
                }
            }
            .frame(height: 170)
            .padding(.horizontal, 10)

            // Stats panel below court
            largeStatsPanel(match)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
    }

    private func playerBaselineLabel(_ player: TennisPlayer, match: TennisMatch) -> some View {
        HStack(spacing: 5) {
            if player.isServing && match.isLive {
                Image(systemName: "tennisball.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow.opacity(0.6), radius: 2)
            }
            if let rank = player.ranking {
                Text("#\(rank)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
            }
            Text(player.shortName.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(player.isWinner ? .yellow : .white)
                .shadow(color: .black.opacity(0.7), radius: 2)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.black.opacity(0.55))
        )
    }

    private func ballMarker(for match: TennisMatch, geo: GeometryProxy) -> some View {
        let box = activeServiceBox(for: match)
        let w = geo.size.width
        let h = geo.size.height
        // Approximate court inset and singles inset used by TennisCourtDrawing
        let courtInset: CGFloat = 12
        let courtW = w - courtInset * 2
        let courtH = h - courtInset * 2
        let singlesInset = courtW * 0.1
        let serviceDepth = courtH * 0.29

        var pos: CGPoint = .zero
        var visible = true
        switch box {
        case .topDeuce:
            pos = CGPoint(
                x: courtInset + singlesInset + (courtW - singlesInset * 2) * 0.25,
                y: courtInset + serviceDepth * 0.5
            )
        case .topAd:
            pos = CGPoint(
                x: courtInset + singlesInset + (courtW - singlesInset * 2) * 0.75,
                y: courtInset + serviceDepth * 0.5
            )
        case .bottomDeuce:
            pos = CGPoint(
                x: courtInset + singlesInset + (courtW - singlesInset * 2) * 0.75,
                y: courtInset + courtH - serviceDepth * 0.5
            )
        case .bottomAd:
            pos = CGPoint(
                x: courtInset + singlesInset + (courtW - singlesInset * 2) * 0.25,
                y: courtInset + courtH - serviceDepth * 0.5
            )
        case .none:
            visible = false
        }

        return Group {
            if visible {
                Image(systemName: "tennisball.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow.opacity(0.9), radius: 4)
                    .shadow(color: .black.opacity(0.5), radius: 1)
                    .position(pos)
            }
        }
    }

    private func largeStatsPanel(_ match: TennisMatch) -> some View {
        VStack(spacing: 6) {
            // Full set-by-set scoreboard
            VStack(spacing: 0) {
                scoreboardHeaderRow(match)
                    .padding(.bottom, 2)
                scoreboardRow(match.player1, match: match, compact: false)
                Divider().background(Color.white.opacity(0.15)).padding(.horizontal, 4)
                scoreboardRow(match.player2, match: match, compact: false)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.55)))

            // Bottom row: game score BIG + surface + situation
            HStack(spacing: 8) {
                // BIG current game score
                if match.isLive,
                   let g1 = match.player1.currentGameScore,
                   let g2 = match.player2.currentGameScore {
                    HStack(spacing: 6) {
                        Text(g1)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("–")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                        Text(g2)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.55)))
                }

                // Surface
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundColor(surfaceColor(match.surface ?? "Hard"))
                    Text((match.surface ?? "Hard").uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.45)))

                Spacer()

                // Situation badge (RED for match/break point)
                if let sit = match.situationText, match.isLive {
                    largeSituationBadge(sit)
                }

                // Serve count (1st/2nd serve) pulled from detail if available
                if match.isLive, let detail = match.detail,
                   detail.lowercased().contains("serve") {
                    Text(detail.uppercased())
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                }
            }
        }
    }

    private func largeSituationBadge(_ text: String) -> some View {
        let lower = text.lowercased()
        let isCritical = lower.contains("match point") || lower.contains("break point")
        let color: Color = isCritical ? .red : (lower.contains("set point") ? .orange : .yellow)
        return HStack(spacing: 3) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
            Text(text.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.25)))
        .overlay(Capsule().stroke(color.opacity(0.8), lineWidth: 1))
    }

    // MARK: - Small Overlay

    private func smallOverlay(_ match: TennisMatch) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(match.leagueAbbr)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                statusBadge(match)
            }
            .padding(.horizontal, 12).padding(.top, 10)

            Spacer()

            // Serve indicator on court
            if match.isLive {
                HStack {
                    if match.player1.isServing {
                        Image(systemName: "tennisball.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                            .shadow(color: .yellow.opacity(0.5), radius: 3)
                    }
                    Spacer()
                    if match.player2.isServing {
                        Image(systemName: "tennisball.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                            .shadow(color: .yellow.opacity(0.5), radius: 3)
                    }
                }
                .padding(.horizontal, 16)
            }

            // Current game score on court near net
            if match.isLive, let g1 = match.player1.currentGameScore, let g2 = match.player2.currentGameScore {
                gameScoreOverlay(g1, g2, compact: true)
                    .padding(.bottom, 2)
            }

            Spacer()

            // TV scoreboard overlay
            VStack(spacing: 2) {
                scoreboardRow(match.player1, match: match, compact: true)
                Divider().background(Color.white.opacity(0.2)).padding(.horizontal, 4)
                scoreboardRow(match.player2, match: match, compact: true)
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.65)))
            .padding(.horizontal, 8)

            // Situation badges
            if let sit = match.situationText, match.isLive {
                situationBadge(sit)
                    .padding(.top, 2)
            }

            // Surface
            HStack(spacing: 3) {
                Circle().fill(surfaceColor(match.surface ?? "Hard")).frame(width: 4, height: 4)
                Text((match.surface ?? "Hard").uppercased())
                    .font(.system(size: 6, weight: .heavy))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Medium Overlay

    private func mediumOverlay(_ match: TennisMatch) -> some View {
        HStack(spacing: 0) {
            // Left: tournament info + court details
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "tennisball.fill")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.yellow)
                    Text(match.leagueAbbr)
                        .font(.system(size: 9, weight: .heavy)).foregroundColor(.white.opacity(0.8))
                    statusBadge(match)
                }

                Text(match.tournamentName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                if let round = match.roundName {
                    Text(round)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                // Serve indicator
                if match.isLive {
                    HStack(spacing: 3) {
                        Image(systemName: "tennisball.fill")
                            .font(.system(size: 7)).foregroundColor(.yellow)
                        Text(match.player1.isServing ? match.player1.shortName : match.player2.shortName)
                            .font(.system(size: 8, weight: .bold)).foregroundColor(.yellow)
                        Text("serving")
                            .font(.system(size: 7)).foregroundColor(.white.opacity(0.5))
                    }
                }

                // Current game score on court
                if match.isLive, let g1 = match.player1.currentGameScore, let g2 = match.player2.currentGameScore {
                    gameScoreOverlay(g1, g2, compact: false)
                }

                // Situation badge
                if let sit = match.situationText, match.isLive {
                    situationBadge(sit)
                }

                // Surface
                HStack(spacing: 3) {
                    Circle().fill(surfaceColor(match.surface ?? "Hard")).frame(width: 6, height: 6)
                    Text(match.surface ?? "Hard")
                        .font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                }

                if match.isPre, let date = match.startDate {
                    Text(Self.timeFormatter.string(from: date))
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.yellow)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            // Right: TV-style scoreboard
            VStack(spacing: 0) {
                // Header row
                scoreboardHeaderRow(match)
                    .padding(.bottom, 3)

                // Player 1
                scoreboardRow(match.player1, match: match, compact: false)
                Divider().background(Color.white.opacity(0.15)).padding(.horizontal, 4)
                // Player 2
                scoreboardRow(match.player2, match: match, compact: false)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.6)))
            .padding(.trailing, 12).padding(.vertical, 10)
        }
    }

    // MARK: - Scoreboard Components

    private func scoreboardHeaderRow(_ match: TennisMatch) -> some View {
        HStack(spacing: 0) {
            Text("").frame(maxWidth: .infinity, alignment: .leading)

            let maxSets = max(match.player1.setScores.count, match.player2.setScores.count, 1)
            ForEach(0..<maxSets, id: \.self) { i in
                let isCurrent = match.isLive && i == maxSets - 1
                Text("S\(i + 1)")
                    .font(.system(size: 7, weight: isCurrent ? .black : .heavy))
                    .foregroundColor(isCurrent ? .white.opacity(0.7) : .white.opacity(0.35))
                    .frame(width: 20)
            }

            if match.isLive {
                Text("GM")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundColor(.yellow.opacity(0.6))
                    .frame(width: 22)
            }
        }
    }

    private func scoreboardRow(_ player: TennisPlayer, match: TennisMatch, compact: Bool) -> some View {
        HStack(spacing: 0) {
            // Serve indicator
            if player.isServing && match.isLive {
                Image(systemName: "tennisball.fill")
                    .font(.system(size: compact ? 5 : 6))
                    .foregroundColor(.yellow)
                    .frame(width: compact ? 8 : 10)
            } else {
                Color.clear.frame(width: compact ? 8 : 10)
            }

            // Player name + ranking
            HStack(spacing: 2) {
                if let rank = player.ranking {
                    Text("\(rank)")
                        .font(.system(size: compact ? 6 : 7, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
                Text(player.shortName)
                    .font(.system(size: compact ? 9 : 11, weight: player.isWinner ? .heavy : .semibold))
                    .foregroundColor(player.isWinner ? .yellow : .white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Set scores
            let maxSets = max(match.player1.setScores.count, match.player2.setScores.count, 1)
            let otherScores = player.id == match.player1.id ? match.player2.setScores : match.player1.setScores

            ForEach(0..<maxSets, id: \.self) { i in
                let score = i < player.setScores.count ? player.setScores[i] : nil
                let otherScore = i < otherScores.count ? otherScores[i] : nil
                let isCurrent = match.isLive && i == maxSets - 1
                let wonSet = score != nil && otherScore != nil && score! > otherScore! && !isCurrent

                ZStack {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.12))
                    }
                    if wonSet {
                        RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.1))
                    }

                    if let s = score {
                        Text("\(s)")
                            .font(.system(size: compact ? 10 : 13, weight: isCurrent ? .black : wonSet ? .heavy : .semibold, design: .rounded))
                            .foregroundColor(wonSet ? .green : isCurrent ? .white : .white.opacity(0.7))
                    } else {
                        Text("-").font(.system(size: compact ? 9 : 11)).foregroundColor(.white.opacity(0.3))
                    }
                }
                .frame(width: 20, height: compact ? 18 : 22)
            }

            // Current game score
            if match.isLive {
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(Color.yellow.opacity(0.15))
                    Text(player.currentGameScore ?? "-")
                        .font(.system(size: compact ? 10 : 12, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)
                }
                .frame(width: 22, height: compact ? 18 : 22)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Game Score on Court

    private func gameScoreOverlay(_ score1: String, _ score2: String, compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 10) {
            Text(score1)
                .font(.system(size: compact ? 14 : 18, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Rectangle()
                .fill(.white.opacity(0.4))
                .frame(width: 1, height: compact ? 16 : 22)
            Text(score2)
                .font(.system(size: compact ? 14 : 18, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 3 : 5)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.5)))
    }

    // MARK: - Situation Badge

    private func situationBadge(_ text: String) -> some View {
        let lower = text.lowercased()
        let badgeColor: Color
        if lower.contains("match point") { badgeColor = .red }
        else if lower.contains("set point") { badgeColor = .orange }
        else if lower.contains("break point") { badgeColor = .yellow }
        else { badgeColor = .white.opacity(0.6) }

        return Text(text.uppercased())
            .font(.system(size: 7, weight: .heavy))
            .foregroundColor(badgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(badgeColor.opacity(0.2)))
    }

    // MARK: - Status Badge

    private func statusBadge(_ match: TennisMatch) -> some View {
        Group {
            if match.isLive {
                HStack(spacing: 2) {
                    Circle().fill(.green).frame(width: 4, height: 4)
                    Text("LIVE").font(.system(size: 7, weight: .heavy)).foregroundColor(.green)
                }
            } else if match.isFinished {
                Text("FINAL").font(.system(size: 7, weight: .heavy)).foregroundColor(.white.opacity(0.5))
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Helpers

    private func surfaceColor(_ surface: String) -> Color {
        switch surface.lowercased() {
        case "clay": return TennisColorHelper.clayCourt
        case "grass": return TennisColorHelper.grassCourt
        case "hard": return TennisColorHelper.hardCourt
        default: return .gray
        }
    }

    private var noMatchView: some View {
        VStack(spacing: 6) {
            Image(systemName: "tennisball.fill")
                .font(.system(size: 20)).foregroundColor(.yellow.opacity(0.6))
            Text("No matches")
                .font(.system(size: 12, weight: .medium)).foregroundColor(.gray)
            Text("Enable ATP or WTA in settings")
                .font(.system(size: 9)).foregroundColor(.gray.opacity(0.7))
        }
    }
}

// MARK: - Active Service Box

enum ActiveServiceBox {
    case topDeuce, topAd, bottomDeuce, bottomAd, none
}

// MARK: - Court Drawing

private struct TennisCourtDrawing: View {
    let surface: String
    var activeServiceBox: ActiveServiceBox = .none

    private var courtColor: Color {
        switch surface.lowercased() {
        case "clay": return TennisColorHelper.clayCourt
        case "grass": return TennisColorHelper.grassCourt
        default: return TennisColorHelper.hardCourt
        }
    }

    private var surroundColor: Color {
        switch surface.lowercased() {
        case "clay": return TennisColorHelper.color(hex: "8B4513")
        case "grass": return TennisColorHelper.color(hex: "1B5E20")
        default: return TennisColorHelper.color(hex: "003366")
        }
    }

    var body: some View {
        GeometryReader { _ in
            let lineColor = Color.white.opacity(0.6)
            let lineW: CGFloat = 1.0

            ZStack {
                surroundColor

                let courtInset: CGFloat = 12
                RoundedRectangle(cornerRadius: 2)
                    .fill(courtColor)
                    .padding(courtInset)

                Canvas { context, size in
                    let m = courtInset
                    let court = CGRect(x: m, y: m, width: size.width - m * 2, height: size.height - m * 2)
                    let midX = court.midX
                    let midY = court.midY
                    let serviceDepthPre = court.height * 0.29
                    let singlesInsetPre = court.width * 0.1
                    let singlesRectPre = court.insetBy(dx: singlesInsetPre, dy: 0)

                    // Highlight active service box BEFORE stroking lines
                    if activeServiceBox != .none {
                        let halfW = (singlesRectPre.width) / 2
                        let yTop = court.minY + serviceDepthPre
                        let yBot = court.maxY - serviceDepthPre
                        var boxRect = CGRect.zero
                        switch activeServiceBox {
                        case .topDeuce:
                            // Deuce (right side from server view looking up from bottom) = left half in screen coords
                            boxRect = CGRect(x: singlesRectPre.minX, y: court.minY, width: halfW, height: yTop - court.minY)
                        case .topAd:
                            boxRect = CGRect(x: midX, y: court.minY, width: halfW, height: yTop - court.minY)
                        case .bottomDeuce:
                            // Deuce from bottom server view = right half in screen coords
                            boxRect = CGRect(x: midX, y: yBot, width: halfW, height: court.maxY - yBot)
                        case .bottomAd:
                            boxRect = CGRect(x: singlesRectPre.minX, y: yBot, width: halfW, height: court.maxY - yBot)
                        case .none:
                            break
                        }
                        context.fill(Path(boxRect), with: .color(Color.yellow.opacity(0.35)))
                    }

                    // Outer boundary
                    context.stroke(Path(court), with: .color(lineColor), lineWidth: lineW)

                    // Singles sidelines
                    let singlesInset = court.width * 0.1
                    let singlesRect = court.insetBy(dx: singlesInset, dy: 0)
                    context.stroke(Path(singlesRect), with: .color(lineColor), lineWidth: lineW)

                    // Net
                    var net = Path()
                    net.move(to: CGPoint(x: court.minX, y: midY))
                    net.addLine(to: CGPoint(x: court.maxX, y: midY))
                    context.stroke(net, with: .color(Color.white.opacity(0.8)), lineWidth: 1.5)

                    // Net posts (small dots at edges)
                    let postR: CGFloat = 2
                    context.fill(Path(ellipseIn: CGRect(x: court.minX - postR, y: midY - postR, width: postR * 2, height: postR * 2)),
                                 with: .color(Color.white.opacity(0.5)))
                    context.fill(Path(ellipseIn: CGRect(x: court.maxX - postR, y: midY - postR, width: postR * 2, height: postR * 2)),
                                 with: .color(Color.white.opacity(0.5)))

                    // Service boxes
                    let serviceDepth = court.height * 0.29

                    var topService = Path()
                    topService.move(to: CGPoint(x: singlesRect.minX, y: court.minY + serviceDepth))
                    topService.addLine(to: CGPoint(x: singlesRect.maxX, y: court.minY + serviceDepth))
                    context.stroke(topService, with: .color(lineColor), lineWidth: lineW)

                    var bottomService = Path()
                    bottomService.move(to: CGPoint(x: singlesRect.minX, y: court.maxY - serviceDepth))
                    bottomService.addLine(to: CGPoint(x: singlesRect.maxX, y: court.maxY - serviceDepth))
                    context.stroke(bottomService, with: .color(lineColor), lineWidth: lineW)

                    // Center service lines
                    var cs1 = Path()
                    cs1.move(to: CGPoint(x: midX, y: court.minY + serviceDepth))
                    cs1.addLine(to: CGPoint(x: midX, y: midY))
                    context.stroke(cs1, with: .color(lineColor), lineWidth: lineW)

                    var cs2 = Path()
                    cs2.move(to: CGPoint(x: midX, y: midY))
                    cs2.addLine(to: CGPoint(x: midX, y: court.maxY - serviceDepth))
                    context.stroke(cs2, with: .color(lineColor), lineWidth: lineW)

                    // Center marks on baselines
                    let markLen: CGFloat = 4
                    var topMark = Path()
                    topMark.move(to: CGPoint(x: midX, y: court.minY))
                    topMark.addLine(to: CGPoint(x: midX, y: court.minY + markLen))
                    context.stroke(topMark, with: .color(lineColor), lineWidth: lineW)

                    var bottomMark = Path()
                    bottomMark.move(to: CGPoint(x: midX, y: court.maxY))
                    bottomMark.addLine(to: CGPoint(x: midX, y: court.maxY - markLen))
                    context.stroke(bottomMark, with: .color(lineColor), lineWidth: lineW)
                }
            }
        }
    }
}
