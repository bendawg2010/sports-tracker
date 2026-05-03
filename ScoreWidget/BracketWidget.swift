import WidgetKit
import SwiftUI

// MARK: - Provider

struct BracketProvider: TimelineProvider {
    func placeholder(in context: Context) -> BracketEntry {
        BracketEntry(date: Date(), games: sampleBracketGames)
    }
    func getSnapshot(in context: Context, completion: @escaping (BracketEntry) -> Void) {
        if context.isPreview {
            completion(BracketEntry(date: Date(), games: sampleBracketGames)); return
        }
        Task {
            let g = await fetchScores()
            completion(BracketEntry(date: Date(), games: g.isEmpty ? sampleBracketGames : g))
        }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BracketEntry>) -> Void) {
        // Ensure completion is called exactly once — WidgetKit preempts the
        // extension aggressively, so guarantee a fallback timeline ships.
        let lock = NSLock()
        var fired = false
        func fire(_ timeline: Timeline<BracketEntry>) {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            lock.unlock()
            completion(timeline)
        }
        let wrappedCompletion: (Timeline<BracketEntry>) -> Void = fire
        DispatchQueue.global().asyncAfter(deadline: .now() + 4.5) {
            fire(Timeline(entries: [self.placeholder(in: context)], policy: .after(Date().addingTimeInterval(60))))
        }

        Task {
            let g = await fetchScores()
            let entry = BracketEntry(date: Date(), games: g.isEmpty ? sampleBracketGames : g)
            let next = Calendar.current.date(byAdding: .minute, value: g.contains { $0.isLive } ? 1 : 10, to: Date())!
            wrappedCompletion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func fetchScores() async -> [SharedGame] {
        let urls = [
            "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/scoreboard?groups=100&limit=100",
            "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/scoreboard?groups=100&limit=100&dates=20260320",
            "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/scoreboard?groups=100&limit=100&dates=20260319-20260321"
        ]
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let events = json?["events"] as? [[String: Any]], !events.isEmpty else { continue }
                let games = events.compactMap { parseEvent($0) }
                if !games.isEmpty { return games }
            } catch { continue }
        }
        return []
    }

    private func safeScore(_ s: Any?) -> String {
        guard let s = s as? String, !s.isEmpty, s.contains(where: { $0.isNumber }) else { return "0" }
        return s
    }

    private func parseEvent(_ event: [String: Any]) -> SharedGame? {
        guard let id = event["id"] as? String,
              let comps = event["competitions"] as? [[String: Any]], let comp = comps.first,
              let competitors = comp["competitors"] as? [[String: Any]],
              let status = event["status"] as? [String: Any],
              let sType = status["type"] as? [String: Any],
              let state = sType["state"] as? String else { return nil }
        let away = competitors.first { ($0["homeAway"] as? String) == "away" }
        let home = competitors.first { ($0["homeAway"] as? String) == "home" }
        let aT = away?["team"] as? [String: Any]; let hT = home?["team"] as? [String: Any]
        let aR = away?["curatedRank"] as? [String: Any]; let hR = home?["curatedRank"] as? [String: Any]
        let headline = (event["notes"] as? [[String: Any]])?.first?["headline"] as? String
            ?? (comp["notes"] as? [[String: Any]])?.first?["headline"] as? String
        let parts = headline?.components(separatedBy: " - ") ?? []
        var region: String? = nil
        var round: String? = parts.last?.trimmingCharacters(in: .whitespaces)
        if parts.count >= 2 {
            region = parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: " Region", with: "")
        }
        if round == nil {
            let season = event["season"] as? [String: Any]
            let slug = season?["slug"] as? String ?? ""
            if slug.contains("post") { round = "Tournament" }
        }
        return SharedGame(id: id, awayTeam: aT?["displayName"] as? String ?? "TBD", awayAbbreviation: aT?["abbreviation"] as? String ?? "TBD", awayScore: safeScore(away?["score"]), awaySeed: aR?["current"] as? Int, awayLogo: aT?["logo"] as? String, awayColor: aT?["color"] as? String, homeTeam: hT?["displayName"] as? String ?? "TBD", homeAbbreviation: hT?["abbreviation"] as? String ?? "TBD", homeScore: safeScore(home?["score"]), homeSeed: hR?["current"] as? Int, homeLogo: hT?["logo"] as? String, homeColor: hT?["color"] as? String, state: state, detail: sType["detail"] as? String, shortDetail: sType["shortDetail"] as? String, period: status["period"] as? Int ?? 0, displayClock: status["displayClock"] as? String, startDate: nil, roundName: round, regionName: region, broadcast: nil, isUpset: false, winProbTeam: nil, winProbValue: nil)
    }
}

// MARK: - Entry

struct BracketEntry: TimelineEntry {
    let date: Date
    let games: [SharedGame]
    var liveGames: [SharedGame] { games.filter { $0.isLive } }
    var regions: [String] {
        var seen = Set<String>()
        return games.compactMap { $0.regionName }.filter { seen.insert($0).inserted }
    }
    func gamesFor(region: String) -> [SharedGame] {
        games.filter { $0.regionName == region }
    }
    func roundsFor(region: String) -> [[SharedGame]] {
        let order = ["1st Round", "2nd Round", "Sweet 16", "Elite 8"]
        let rg = games.filter { $0.regionName == region }
        return order.map { r in rg.filter { $0.roundName == r } }.filter { !$0.isEmpty }
    }
    var finalFourGames: [SharedGame] {
        games.filter { $0.roundName == "Final Four" || $0.roundName == "Semifinals" }
    }
    var championshipGame: SharedGame? {
        games.first { $0.roundName == "Championship" || $0.roundName == "National Championship" }
    }
}

// MARK: - Widget

struct BracketWidget: Widget {
    let kind = "BracketWidget_v6"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BracketProvider()) { entry in
            BracketWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.06, green: 0.06, blue: 0.08),
                                 Color(red: 0.10, green: 0.10, blue: 0.12)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Tournament Bracket")
        .description("NCAA bracket with all 4 regions and live scores")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

// MARK: - Main View

struct BracketWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: BracketEntry

    var body: some View {
        VStack(spacing: 0) {
            header
            switch family {
            case .systemExtraLarge:
                fullBracket
            default:
                fourRegionCompact
            }
        }
        .padding(6)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "trophy.fill").font(.system(size: 9)).foregroundColor(.yellow)
            Text("NCAA Tournament").font(.system(size: 10, weight: .bold))
            Spacer()
            Text(entry.date, style: .time).font(.system(size: 7)).foregroundColor(.gray)
            if !entry.liveGames.isEmpty {
                HStack(spacing: 2) {
                    Circle().fill(Color.red).frame(width: 4, height: 4)
                    Text("\(entry.liveGames.count) LIVE").font(.system(size: 7, weight: .heavy)).foregroundColor(.red)
                }
            }
        }
        .padding(.bottom, 3)
    }

    // MARK: - Large: 2×2 grid

    private var fourRegionCompact: some View {
        let r = entry.regions
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                if r.count >= 1 { miniRegion(r[0]) }
                if r.count >= 2 { miniRegion(r[1]) }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 4) {
                if r.count >= 3 { miniRegion(r[2]) }
                if r.count >= 4 { miniRegion(r[3]) }
            }
            .frame(maxHeight: .infinity)

            if r.isEmpty {
                VStack {
                    Spacer()
                    Text("No bracket data").font(.caption).foregroundColor(.gray)
                    Spacer()
                }
            }
        }
    }

    private func miniRegion(_ region: String) -> some View {
        let regionGames = entry.gamesFor(region: region)
        return VStack(spacing: 1) {
            Text(region.uppercased())
                .font(.system(size: 7, weight: .heavy))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(regionGames) { game in
                miniMatchupRow(game)
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.1)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func miniMatchupRow(_ game: SharedGame) -> some View {
        HStack(spacing: 2) {
            if let s = game.awaySeed {
                Text("\(s)").font(.system(size: 5, weight: .medium, design: .monospaced)).foregroundColor(.gray).frame(width: 7, alignment: .trailing)
            }
            Text(game.awayAbbreviation)
                .font(.system(size: 6, weight: aLeads(game) ? .bold : .regular))
                .lineLimit(1)

            if game.isLive || game.isFinal {
                Text(game.awayScore)
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .foregroundColor(game.isLive ? .red : nil)
            }

            Text("–").font(.system(size: 5)).foregroundColor(.gray)

            if game.isLive || game.isFinal {
                Text(game.homeScore)
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .foregroundColor(game.isLive ? .red : nil)
            }

            Text(game.homeAbbreviation)
                .font(.system(size: 6, weight: hLeads(game) ? .bold : .regular))
                .lineLimit(1)
            if let s = game.homeSeed {
                Text("\(s)").font(.system(size: 5, weight: .medium, design: .monospaced)).foregroundColor(.gray).frame(width: 7, alignment: .leading)
            }

            Spacer(minLength: 0)

            if game.isLive {
                Circle().fill(Color.red).frame(width: 3, height: 3)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 1.5)
                .fill(game.isLive ? Color.red.opacity(0.08) : Color.gray.opacity(0.08))
        )
    }

    // MARK: - Extra Large: Full bracket

    private var fullBracket: some View {
        let r = entry.regions
        return VStack(spacing: 2) {
            HStack(spacing: 0) {
                if r.count >= 1 { leftRegion(r[0]) }
                topCenterColumn
                if r.count >= 2 { rightRegion(r[1]) }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Spacer()
                Image(systemName: "trophy.fill").font(.system(size: 14)).foregroundColor(.yellow)
                if let champ = entry.championshipGame {
                    matchupBox(champ).frame(width: 80)
                }
                Image(systemName: "trophy.fill").font(.system(size: 14)).foregroundColor(.yellow)
                Spacer()
            }
            .padding(.vertical, 2)

            HStack(spacing: 0) {
                if r.count >= 3 { leftRegion(r[2]) }
                bottomCenterColumn
                if r.count >= 4 { rightRegion(r[3]) }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func leftRegion(_ region: String) -> some View {
        let rounds = entry.roundsFor(region: region)
        return VStack(spacing: 0) {
            regionLabel(region)
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(rounds.enumerated()), id: \.offset) { idx, games in
                    roundColumn(games: games, roundIdx: idx)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func rightRegion(_ region: String) -> some View {
        let rounds = entry.roundsFor(region: region)
        return VStack(spacing: 0) {
            regionLabel(region)
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(rounds.enumerated().reversed()), id: \.offset) { idx, games in
                    roundColumn(games: games, roundIdx: idx)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var topCenterColumn: some View {
        VStack(spacing: 2) {
            Spacer()
            let ff = entry.finalFourGames
            if let g = ff.first { matchupBox(g).frame(width: 70) }
            else { tbdSlot }
            Spacer()
        }
        .frame(width: 76)
    }

    private var bottomCenterColumn: some View {
        VStack(spacing: 2) {
            Spacer()
            let ff = entry.finalFourGames
            if ff.count > 1 { matchupBox(ff[1]).frame(width: 70) }
            else { tbdSlot }
            Spacer()
        }
        .frame(width: 76)
    }

    private var tbdSlot: some View {
        RoundedRectangle(cornerRadius: 2)
            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
            .frame(width: 60, height: 16)
            .overlay(Text("TBD").font(.system(size: 6)).foregroundColor(.gray))
    }

    private func roundColumn(games: [SharedGame], roundIdx: Int) -> some View {
        let sp: CGFloat
        switch roundIdx {
        case 0: sp = 2
        case 1: sp = 18
        case 2: sp = 42
        case 3: sp = 90
        default: sp = 2
        }
        return VStack(spacing: sp) {
            ForEach(games) { g in matchupBox(g) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func regionLabel(_ region: String) -> some View {
        Text(region.uppercased())
            .font(.system(size: 7, weight: .heavy))
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 1)
    }

    private func matchupBox(_ game: SharedGame) -> some View {
        VStack(spacing: 0) {
            teamLine(seed: game.awaySeed, abbr: game.awayAbbreviation, score: game.awayScore,
                     winning: aLeads(game), live: game.isLive, done: game.isFinal)
            Divider()
            teamLine(seed: game.homeSeed, abbr: game.homeAbbreviation, score: game.homeScore,
                     winning: hLeads(game), live: game.isLive, done: game.isFinal)
        }
        .background(RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(game.isLive ? Color.red.opacity(0.6) : Color.gray.opacity(0.2), lineWidth: game.isLive ? 1 : 0.5))
    }

    private func teamLine(seed: Int?, abbr: String, score: String, winning: Bool, live: Bool, done: Bool) -> some View {
        HStack(spacing: 1) {
            if let s = seed {
                Text("\(s)").font(.system(size: 6, weight: .medium, design: .monospaced)).foregroundColor(.gray).frame(width: 8, alignment: .trailing)
            }
            Text(abbr).font(.system(size: 7, weight: winning ? .bold : .regular)).lineLimit(1)
            Spacer(minLength: 0)
            if live || done {
                Text(score).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundColor(live ? .red : nil)
            }
        }
        .padding(.horizontal, 2).padding(.vertical, 1.5)
    }

    private func aLeads(_ g: SharedGame) -> Bool { guard let a = g.awayScoreInt, let h = g.homeScoreInt else { return false }; return a > h }
    private func hLeads(_ g: SharedGame) -> Bool { guard let a = g.awayScoreInt, let h = g.homeScoreInt else { return false }; return h > a }
}

// MARK: - Sample Data

private let sampleBracketGames: [SharedGame] = [
    SharedGame(id: "s1", awayTeam: "Duke", awayAbbreviation: "DUKE", awayScore: "71", awaySeed: 1, awayLogo: nil, awayColor: nil, homeTeam: "Siena", homeAbbreviation: "SIE", homeScore: "65", homeSeed: 16, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "East", broadcast: nil, isUpset: false, winProbTeam: nil, winProbValue: nil),
    SharedGame(id: "s2", awayTeam: "MSU", awayAbbreviation: "MSU", awayScore: "92", awaySeed: 3, awayLogo: nil, awayColor: nil, homeTeam: "NDSU", homeAbbreviation: "NDSU", homeScore: "67", homeSeed: 14, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "East", broadcast: nil, isUpset: false, winProbTeam: nil, winProbValue: nil),
    SharedGame(id: "s5", awayTeam: "Texas", awayAbbreviation: "TEX", awayScore: "79", awaySeed: 11, awayLogo: nil, awayColor: nil, homeTeam: "BYU", homeAbbreviation: "BYU", homeScore: "71", homeSeed: 6, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "West", broadcast: nil, isUpset: true, winProbTeam: nil, winProbValue: nil),
    SharedGame(id: "s6", awayTeam: "Arkansas", awayAbbreviation: "ARK", awayScore: "97", awaySeed: 4, awayLogo: nil, awayColor: nil, homeTeam: "Hawaii", homeAbbreviation: "HAW", homeScore: "78", homeSeed: 13, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "West", broadcast: nil, isUpset: false, winProbTeam: nil, winProbValue: nil),
    SharedGame(id: "s9", awayTeam: "Nebraska", awayAbbreviation: "NEB", awayScore: "76", awaySeed: 4, awayLogo: nil, awayColor: nil, homeTeam: "Troy", homeAbbreviation: "TROY", homeScore: "47", homeSeed: 13, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "South", broadcast: nil, isUpset: false, winProbTeam: nil, winProbValue: nil),
    SharedGame(id: "s10", awayTeam: "Vanderbilt", awayAbbreviation: "VAN", awayScore: "78", awaySeed: 5, awayLogo: nil, awayColor: nil, homeTeam: "McNeese", homeAbbreviation: "MCN", homeScore: "68", homeSeed: 12, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "South", broadcast: nil, isUpset: false, winProbTeam: nil, winProbValue: nil),
    SharedGame(id: "s13", awayTeam: "Michigan", awayAbbreviation: "MICH", awayScore: "101", awaySeed: 1, awayLogo: nil, awayColor: nil, homeTeam: "Howard", homeAbbreviation: "HOW", homeScore: "80", homeSeed: 16, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "Midwest", broadcast: nil, isUpset: false, winProbTeam: nil, winProbValue: nil),
    SharedGame(id: "s14", awayTeam: "Georgia", awayAbbreviation: "UGA", awayScore: "0", awaySeed: 8, awayLogo: nil, awayColor: nil, homeTeam: "Saint Louis", homeAbbreviation: "SLU", homeScore: "0", homeSeed: 9, homeLogo: nil, homeColor: nil, state: "pre", detail: "9:40 PM", shortDetail: "9:40", period: 0, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "Midwest", broadcast: nil, isUpset: false, winProbTeam: nil, winProbValue: nil),
]
