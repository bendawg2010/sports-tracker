import WidgetKit
import SwiftUI

// MARK: - Football Widget

struct FootballWidget: Widget {
    let kind = "FootballWidget_v1"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FootballProvider()) { entry in
            FootballWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Football")
        .description("Live football field with drive tracker, play-by-play, and game clock")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Models

struct FootballPlayData {
    let text: String
    let startYardsToEndzone: Int
    let endYardsToEndzone: Int
    let down: Int
    let distance: Int
    let yardage: Int
}

struct FootballDriveData {
    let teamAbbr: String
    let teamColorHex: String
    let result: String           // "TOUCHDOWN", "FIELD GOAL", "PUNT", etc.
    let description: String      // "8 plays, 75 yards, 3:42"
    let startYardsToEndzone: Int // where the drive began (0-100)
    let plays: [FootballPlayData]

    var teamColor: Color { Color(hex: teamColorHex) ?? .blue }
}

struct FootballGameData {
    let id: String
    let leagueID: String          // "nfl" or "cfb"
    let awayAbbr: String
    let homeAbbr: String
    let awayScore: String
    let homeScore: String
    let awayColorHex: String
    let homeColorHex: String
    let awayTeamID: String
    let homeTeamID: String
    let state: String              // "pre", "in", "post"
    let period: Int                // 1-4, 5=OT
    let displayClock: String?
    let detail: String?
    let shortDetail: String?
    let downDistanceText: String?
    let yardLine: Int?
    let possessionTeamID: String?
    let isRedZone: Bool
    let startDate: Date?
    let currentDrive: FootballDriveData?
    let lastCompletedDrive: FootballDriveData?

    var isLive: Bool { state == "in" }
    var isFinal: Bool { state == "post" }
    var isScheduled: Bool { state == "pre" }

    var quarterText: String {
        switch period {
        case 1: return "1ST"
        case 2: return "2ND"
        case 3: return "3RD"
        case 4: return "4TH"
        case 5: return "OT"
        default: return period > 5 ? "\(period - 4)OT" : ""
        }
    }

    var awayColor: Color { Color(hex: awayColorHex) ?? .blue }
    var homeColor: Color { Color(hex: homeColorHex) ?? .red }

    var possessingAway: Bool { possessionTeamID == awayTeamID }
    var possessingHome: Bool { possessionTeamID == homeTeamID }

    /// Yards to endzone for the first-down marker.
    /// Current yardLine minus the distance to go.
    var firstDownYardsToEndzone: Int? {
        guard let yl = yardLine, let dd = downDistanceText else { return nil }
        let dist = parseDistanceFromDD(dd)
        guard dist > 0 else { return nil }
        return max(0, yl - dist)
    }

    /// The current ball position as yardsToEndzone (0 = in the endzone, 100 = own goal).
    var ballYardsToEndzone: Int? { yardLine }

    /// Where the current drive started (yardsToEndzone).
    var driveStartYardsToEndzone: Int? { currentDrive?.startYardsToEndzone }

    private func parseDistanceFromDD(_ text: String) -> Int {
        // Parse "2nd & 7" or "3rd & Goal" from downDistanceText
        let parts = text.components(separatedBy: "&")
        guard parts.count >= 2 else { return 0 }
        let distPart = parts[1].trimmingCharacters(in: .whitespaces)
        if distPart.lowercased() == "goal" { return yardLine ?? 0 }
        return Int(distPart) ?? 0
    }
}

// MARK: - Entry

struct FootballEntry: TimelineEntry {
    let date: Date
    let game: FootballGameData?
}

// MARK: - Provider

struct FootballProvider: TimelineProvider {
    func placeholder(in context: Context) -> FootballEntry { sampleEntry }

    func getSnapshot(in context: Context, completion: @escaping (FootballEntry) -> Void) {
        fetchFootball { completion($0 ?? sampleEntry) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FootballEntry>) -> Void) {
        // Ensure completion is called exactly once — WidgetKit preempts the
        // extension aggressively, so guarantee a fallback timeline ships.
        let lock = NSLock()
        var fired = false
        func fire(_ timeline: Timeline<FootballEntry>) {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            lock.unlock()
            completion(timeline)
        }
        let wrappedCompletion: (Timeline<FootballEntry>) -> Void = fire
        DispatchQueue.global().asyncAfter(deadline: .now() + 4.5) {
            fire(Timeline(entries: [self.placeholder(in: context)], policy: .after(Date().addingTimeInterval(60))))
        }

        fetchFootball { entry in
            let final = entry ?? sampleEntry
            let hasLive = final.game?.isLive == true
            let refresh = Calendar.current.date(byAdding: .minute, value: hasLive ? 1 : 10, to: Date())!
            wrappedCompletion(Timeline(entries: [final], policy: .after(refresh)))
        }
    }

    // MARK: - Fetch Pipeline

    private func fetchFootball(completion: @escaping (FootballEntry?) -> Void) {
        let selectedIDs = UserDefaults.standard.array(forKey: "selectedSportIDs") as? [String]
            ?? ["nba", "nfl", "mlb", "f1"]

        var leagueURLs: [(String, URL)] = []
        if selectedIDs.contains("nfl"), let league = SportLeague.find("nfl") {
            if let url = URL(string: league.scoreboardURL) { leagueURLs.append(("nfl", url)) }
        }
        if selectedIDs.contains("cfb"), let league = SportLeague.find("cfb") {
            if let url = URL(string: league.scoreboardURL) { leagueURLs.append(("cfb", url)) }
        }
        if leagueURLs.isEmpty {
            if let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard") {
                leagueURLs.append(("nfl", url))
            }
        }

        let group = DispatchGroup()
        var allGames: [(FootballGameData, String)] = [] // (game, leagueID)
        let lock = NSLock()

        for (lid, url) in leagueURLs {
            group.enter()
            URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)) { data, _, _ in
                defer { group.leave() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let events = json["events"] as? [[String: Any]] else { return }

                let games = events.compactMap { self.parseScoreboardEvent($0, leagueID: lid) }
                lock.lock()
                allGames.append(contentsOf: games.map { ($0, lid) })
                lock.unlock()
            }.resume()
        }

        group.notify(queue: .main) {
            guard let (best, lid) = self.pickBestGame(allGames) else {
                completion(FootballEntry(date: Date(), game: nil))
                return
            }
            // If game is live, fetch summary for drive data
            if best.isLive {
                self.fetchSummary(gameID: best.id, leagueID: lid, baseGame: best, completion: completion)
            } else {
                completion(FootballEntry(date: Date(), game: best))
            }
        }
    }

    private func fetchSummary(gameID: String, leagueID: String, baseGame: FootballGameData,
                              completion: @escaping (FootballEntry?) -> Void) {
        guard let league = SportLeague.find(leagueID),
              let url = URL(string: "\(league.summaryURL)?event=\(gameID)") else {
            completion(FootballEntry(date: Date(), game: baseGame))
            return
        }

        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(FootballEntry(date: Date(), game: baseGame))
                return
            }

            let drives = self.parseDrives(json)
            let currentDrive = drives.last
            let lastCompleted = drives.count >= 2 ? drives[drives.count - 2] : nil

            let enriched = FootballGameData(
                id: baseGame.id,
                leagueID: leagueID,
                awayAbbr: baseGame.awayAbbr,
                homeAbbr: baseGame.homeAbbr,
                awayScore: baseGame.awayScore,
                homeScore: baseGame.homeScore,
                awayColorHex: baseGame.awayColorHex,
                homeColorHex: baseGame.homeColorHex,
                awayTeamID: baseGame.awayTeamID,
                homeTeamID: baseGame.homeTeamID,
                state: baseGame.state,
                period: baseGame.period,
                displayClock: baseGame.displayClock,
                detail: baseGame.detail,
                shortDetail: baseGame.shortDetail,
                downDistanceText: baseGame.downDistanceText,
                yardLine: baseGame.yardLine,
                possessionTeamID: baseGame.possessionTeamID,
                isRedZone: baseGame.isRedZone,
                startDate: baseGame.startDate,
                currentDrive: currentDrive,
                lastCompletedDrive: lastCompleted
            )
            completion(FootballEntry(date: Date(), game: enriched))
        }.resume()
    }

    // MARK: - Parse Drives from Summary

    private func parseDrives(_ json: [String: Any]) -> [FootballDriveData] {
        guard let drivesDict = json["drives"] as? [String: Any] else { return [] }

        var allDrives: [FootballDriveData] = []

        // Parse previous drives
        if let previous = drivesDict["previous"] as? [[String: Any]] {
            for d in previous {
                if let drive = parseSingleDrive(d) {
                    allDrives.append(drive)
                }
            }
        }
        // Parse current drive
        if let current = drivesDict["current"] as? [String: Any] {
            if let drive = parseSingleDrive(current) {
                allDrives.append(drive)
            }
        }

        return allDrives
    }

    private func parseSingleDrive(_ d: [String: Any]) -> FootballDriveData? {
        let team = d["team"] as? [String: Any]
        let abbr = team?["abbreviation"] as? String ?? "?"
        let colorHex = team?["color"] as? String
            ?? (team?["logos"] as? [[String: Any]])?.first?["color"] as? String
            ?? "666666"
        let result = d["result"] as? String ?? d["displayResult"] as? String ?? ""
        let desc = d["description"] as? String ?? ""

        var startYTE = 65 // fallback
        var plays: [FootballPlayData] = []

        if let playsArr = d["plays"] as? [[String: Any]] {
            for p in playsArr {
                let text = p["text"] as? String ?? ""
                let startDict = p["start"] as? [String: Any]
                let endDict = p["end"] as? [String: Any]
                let sYTE = startDict?["yardsToEndzone"] as? Int ?? 0
                let eYTE = endDict?["yardsToEndzone"] as? Int ?? 0
                let down = startDict?["down"] as? Int ?? 0
                let dist = startDict?["distance"] as? Int ?? 0
                let yardage = p["statYardage"] as? Int ?? 0

                plays.append(FootballPlayData(
                    text: text,
                    startYardsToEndzone: sYTE,
                    endYardsToEndzone: eYTE,
                    down: down,
                    distance: dist,
                    yardage: yardage
                ))
            }
            if let first = playsArr.first,
               let startDict = first["start"] as? [String: Any],
               let yte = startDict["yardsToEndzone"] as? Int {
                startYTE = yte
            }
        }

        // Also check drive-level start info
        if let startDict = d["start"] as? [String: Any],
           let yte = startDict["yardsToEndzone"] as? Int {
            startYTE = yte
        }

        return FootballDriveData(
            teamAbbr: abbr,
            teamColorHex: colorHex,
            result: result,
            description: desc,
            startYardsToEndzone: startYTE,
            plays: plays
        )
    }

    // MARK: - Scoreboard Parsing

    private func pickBestGame(_ games: [(FootballGameData, String)]) -> (FootballGameData, String)? {
        let live = games.filter { $0.0.isLive }
            .sorted { a, b in
                if a.0.isRedZone != b.0.isRedZone { return a.0.isRedZone }
                return a.0.period > b.0.period
            }
        if let best = live.first { return best }

        let upcoming = games.filter { $0.0.isScheduled }
            .sorted { ($0.0.startDate ?? .distantFuture) < ($1.0.startDate ?? .distantFuture) }
        if let next = upcoming.first { return next }

        let finals = games.filter { $0.0.isFinal }
            .sorted { ($0.0.startDate ?? .distantPast) > ($1.0.startDate ?? .distantPast) }
        return finals.first
    }

    private func parseScoreboardEvent(_ event: [String: Any], leagueID: String) -> FootballGameData? {
        guard let id = event["id"] as? String,
              let competitions = event["competitions"] as? [[String: Any]],
              let comp = competitions.first,
              let competitors = comp["competitors"] as? [[String: Any]],
              let statusDict = event["status"] as? [String: Any],
              let statusType = statusDict["type"] as? [String: Any],
              let state = statusType["state"] as? String else { return nil }

        let period = statusDict["period"] as? Int ?? 0
        let displayClock = statusDict["displayClock"] as? String
        let detail = statusType["detail"] as? String
        let shortDetail = statusType["shortDetail"] as? String
        let dateStr = event["date"] as? String ?? ""
        let startDate = parseDate(dateStr)

        let away = competitors.first { ($0["homeAway"] as? String) == "away" }
        let home = competitors.first { ($0["homeAway"] as? String) == "home" }

        func teamInfo(_ c: [String: Any]?) -> (abbr: String, score: String, color: String, teamID: String) {
            guard let c = c, let team = c["team"] as? [String: Any] else {
                return ("TBD", "0", "666666", "0")
            }
            let abbr = team["abbreviation"] as? String ?? "TBD"
            let score = c["score"] as? String ?? "0"
            let color = team["color"] as? String ?? "666666"
            let teamID = team["id"] as? String ?? c["id"] as? String ?? "0"
            return (abbr, score, color, teamID)
        }

        let awayInfo = teamInfo(away)
        let homeInfo = teamInfo(home)

        let situation = comp["situation"] as? [String: Any]
        let downDistanceText = situation?["downDistanceText"] as? String
        let yardLine = situation?["yardLine"] as? Int
        let possessionID = situation?["possession"] as? String
        let isRedZone = situation?["isRedZone"] as? Bool ?? false

        return FootballGameData(
            id: id,
            leagueID: leagueID,
            awayAbbr: awayInfo.abbr,
            homeAbbr: homeInfo.abbr,
            awayScore: awayInfo.score,
            homeScore: homeInfo.score,
            awayColorHex: awayInfo.color,
            homeColorHex: homeInfo.color,
            awayTeamID: awayInfo.teamID,
            homeTeamID: homeInfo.teamID,
            state: state,
            period: period,
            displayClock: displayClock,
            detail: detail,
            shortDetail: shortDetail,
            downDistanceText: downDistanceText,
            yardLine: yardLine,
            possessionTeamID: possessionID,
            isRedZone: isRedZone,
            startDate: startDate,
            currentDrive: nil,
            lastCompletedDrive: nil
        )
    }

    private func parseDate(_ s: String) -> Date? {
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

    // MARK: - Sample

    private var sampleEntry: FootballEntry {
        let samplePlays: [FootballPlayData] = [
            FootballPlayData(text: "P.Mahomes pass to T.Kelce for 22 yds", startYardsToEndzone: 75, endYardsToEndzone: 53, down: 1, distance: 10, yardage: 22),
            FootballPlayData(text: "I.Pacheco rush for 8 yds", startYardsToEndzone: 53, endYardsToEndzone: 45, down: 1, distance: 10, yardage: 8),
            FootballPlayData(text: "P.Mahomes pass to R.Rice for 12 yds", startYardsToEndzone: 45, endYardsToEndzone: 33, down: 2, distance: 2, yardage: 12),
            FootballPlayData(text: "I.Pacheco rush for -2 yds", startYardsToEndzone: 33, endYardsToEndzone: 35, down: 1, distance: 10, yardage: -2),
        ]
        let sampleDrive = FootballDriveData(
            teamAbbr: "KC", teamColorHex: "E31837", result: "",
            description: "4 plays, 40 yards, 2:15",
            startYardsToEndzone: 75, plays: samplePlays
        )

        return FootballEntry(
            date: Date(),
            game: FootballGameData(
                id: "sample_fb",
                leagueID: "nfl",
                awayAbbr: "KC",
                homeAbbr: "SF",
                awayScore: "21",
                homeScore: "17",
                awayColorHex: "E31837",
                homeColorHex: "AA0000",
                awayTeamID: "12",
                homeTeamID: "25",
                state: "in",
                period: 3,
                displayClock: "7:42",
                detail: "3rd Quarter - 7:42",
                shortDetail: "3rd 7:42",
                downDistanceText: "2nd & 7",
                yardLine: 35,
                possessionTeamID: "12",
                isRedZone: false,
                startDate: Date(),
                currentDrive: sampleDrive,
                lastCompletedDrive: nil
            )
        )
    }
}

// MARK: - Widget View

struct FootballWidgetView: View {
    let entry: FootballEntry
    @Environment(\.widgetFamily) var family

    private static let kickoffFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E h:mm a"
        return f
    }()

    var body: some View {
        if let game = entry.game {
            switch family {
            case .systemLarge: largeView(game)
            default: mediumView(game)
            }
        } else {
            emptyState
        }
    }

    // MARK: - Medium Layout

    private func mediumView(_ game: FootballGameData) -> some View {
        VStack(spacing: 0) {
            scorebar(game)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 4)

            GeometryReader { geo in
                let fieldH = geo.size.height - (game.isLive ? 22 : 0)
                VStack(spacing: 0) {
                    driveField(game: game, width: geo.size.width - 16, height: max(fieldH, 30))
                        .padding(.horizontal, 8)

                    if game.isLive, let dd = game.downDistanceText {
                        HStack(spacing: 6) {
                            Text(game.quarterText)
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.orange)
                            if let clock = game.displayClock {
                                Text(clock)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            Spacer()
                            Text(dd)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    // MARK: - Large Layout

    private func largeView(_ game: FootballGameData) -> some View {
        VStack(spacing: 0) {
            scorebar(game)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Down & distance + clock bar
            if game.isLive {
                downDistanceBar(game)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            // Field
            GeometryReader { geo in
                let playPanelCount = game.isLive ? 1 : 0
                let fieldPortion: CGFloat = playPanelCount > 0 ? 0.5 : 0.7
                let fieldH = geo.size.height * fieldPortion

                VStack(spacing: 6) {
                    driveField(game: game, width: geo.size.width - 20, height: max(fieldH, 40))
                        .padding(.horizontal, 10)

                    if game.isLive {
                        drivePlayPanel(game)
                            .padding(.horizontal, 12)
                    } else if game.isScheduled {
                        preGamePanel(game)
                            .padding(.horizontal, 12)
                    } else if game.isFinal {
                        finalPanel(game)
                            .padding(.horizontal, 12)
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - Scorebar (top)

    private func scorebar(_ game: FootballGameData) -> some View {
        HStack(spacing: 0) {
            // Away
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(game.awayColor)
                    .frame(width: 4, height: 16)
                Text(game.awayAbbr)
                    .font(.system(size: 12, weight: .bold))
                if game.possessingAway {
                    Image(systemName: "football.fill")
                        .font(.system(size: 6))
                        .foregroundColor(.yellow)
                }
                Spacer(minLength: 2)
                Text(game.awayScore)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .frame(maxWidth: .infinity)

            // Center
            VStack(spacing: 1) {
                if game.isLive {
                    HStack(spacing: 3) {
                        Circle().fill(.green).frame(width: 5, height: 5)
                        Text(game.shortDetail ?? "LIVE")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(.green)
                    }
                } else if game.isFinal {
                    Text("FINAL")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.gray)
                } else if game.isScheduled {
                    if let date = game.startDate {
                        Text(Self.kickoffFormatter.string(from: date))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.orange)
                    } else {
                        Text("TBD")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(.orange)
                    }
                }
            }
            .frame(width: 60)

            // Home
            HStack(spacing: 4) {
                Text(game.homeScore)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                Spacer(minLength: 2)
                if game.possessingHome {
                    Image(systemName: "football.fill")
                        .font(.system(size: 6))
                        .foregroundColor(.yellow)
                }
                Text(game.homeAbbr)
                    .font(.system(size: 12, weight: .bold))
                RoundedRectangle(cornerRadius: 2)
                    .fill(game.homeColor)
                    .frame(width: 4, height: 16)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Down & Distance Bar (large widget)

    private func downDistanceBar(_ game: FootballGameData) -> some View {
        HStack {
            if let dd = game.downDistanceText {
                Text(dd)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
            }
            Spacer()
            HStack(spacing: 4) {
                Text(game.quarterText)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.orange)
                if let clock = game.displayClock {
                    Text(clock)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.3)))
    }

    // MARK: - Drive Field

    private func driveField(game: FootballGameData, width: CGFloat, height: CGFloat) -> some View {
        let endZoneW = width * 0.09
        let fieldW = width - (endZoneW * 2)

        return ZStack {
            // Base green
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: "2E7D32") ?? .green)
                .frame(width: width, height: height)

            // Red zone glow
            if game.isRedZone && game.isLive {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.red.opacity(0.12))
                    .frame(width: width, height: height)
            }

            HStack(spacing: 0) {
                // Away end zone (left = away goal line)
                endZone(abbr: game.awayAbbr, color: game.awayColor, score: game.awayScore,
                         width: endZoneW, height: height, isLeft: true)

                // Playing field
                ZStack {
                    yardLines(fieldWidth: fieldW, fieldHeight: height)
                    yardNumbers(fieldWidth: fieldW, fieldHeight: height)
                    hashMarks(fieldWidth: fieldW, fieldHeight: height)

                    // Drive path
                    if game.isLive, let drive = game.currentDrive, let ballYTE = game.ballYardsToEndzone {
                        drivePath(drive: drive, currentYTE: ballYTE,
                                  fieldWidth: fieldW, fieldHeight: height)
                    }

                    // First-down marker (orange/red line)
                    if game.isLive, let fdYTE = game.firstDownYardsToEndzone {
                        markerLine(yardsToEndzone: fdYTE, fieldWidth: fieldW, fieldHeight: height,
                                   color: .orange, lineWidth: 2, dashed: true)
                    }

                    // Line of scrimmage (yellow)
                    if game.isLive, let yl = game.yardLine {
                        markerLine(yardsToEndzone: yl, fieldWidth: fieldW, fieldHeight: height,
                                   color: .yellow, lineWidth: 2.5, dashed: false)
                    }

                    // Football marker
                    if game.isLive, let yl = game.yardLine {
                        footballMarker(yardsToEndzone: yl, fieldWidth: fieldW, fieldHeight: height)
                    }
                }
                .frame(width: fieldW, height: height)
                .clipped()

                // Home end zone (right = home goal line)
                endZone(abbr: game.homeAbbr, color: game.homeColor, score: game.homeScore,
                         width: endZoneW, height: height, isLeft: false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - End Zones

    private func endZone(abbr: String, color: Color, score: String,
                         width: CGFloat, height: CGFloat, isLeft: Bool) -> some View {
        ZStack {
            Rectangle().fill(color.opacity(0.85))

            VStack(spacing: 1) {
                Text(score)
                    .font(.system(size: min(width * 0.55, 16), weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                Text(abbr)
                    .font(.system(size: min(width * 0.35, 8), weight: .heavy))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
            }
            .rotationEffect(.degrees(isLeft ? -90 : 90))

            // Goal line stripe
            Rectangle()
                .fill(.white.opacity(0.7))
                .frame(width: 2)
                .offset(x: isLeft ? width / 2 - 1 : -width / 2 + 1)
        }
        .frame(width: width, height: height)
    }

    // MARK: - Yard Lines, Numbers, Hash Marks

    private func yardLines(fieldWidth: CGFloat, fieldHeight: CGFloat) -> some View {
        ForEach(0..<11) { i in
            let xPos = CGFloat(i) * (fieldWidth / 10) - fieldWidth / 2
            Rectangle()
                .fill(.white.opacity(i == 5 ? 0.55 : 0.3))
                .frame(width: i == 5 ? 1.5 : 0.8, height: fieldHeight)
                .offset(x: xPos)
        }
    }

    private func yardNumbers(fieldWidth: CGFloat, fieldHeight: CGFloat) -> some View {
        let numbers = [10, 20, 30, 40, 50, 40, 30, 20, 10]
        return ForEach(0..<numbers.count, id: \.self) { i in
            let xPos = CGFloat(i + 1) * (fieldWidth / 10) - fieldWidth / 2
            Text("\(numbers[i])")
                .font(.system(size: max(fieldHeight * 0.12, 6), weight: .bold))
                .foregroundColor(.white.opacity(0.2))
                .offset(x: xPos, y: -fieldHeight * 0.33)
        }
    }

    private func hashMarks(fieldWidth: CGFloat, fieldHeight: CGFloat) -> some View {
        ForEach(0..<50, id: \.self) { i in
            if i % 5 != 0 {
                let xPos = CGFloat(i) * (fieldWidth / 50) - fieldWidth / 2 + fieldWidth / 100
                VStack {
                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 0.5, height: 2.5)
                    Spacer()
                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 0.5, height: 2.5)
                }
                .offset(x: xPos)
            }
        }
    }

    // MARK: - Drive Path

    /// Draws a colored arrow/line from drive start to current ball position.
    private func drivePath(drive: FootballDriveData, currentYTE: Int,
                           fieldWidth: CGFloat, fieldHeight: CGFloat) -> some View {
        let startYTE = drive.startYardsToEndzone
        let startX = xForYTE(startYTE, fieldWidth: fieldWidth)
        let endX = xForYTE(currentYTE, fieldWidth: fieldWidth)
        let midY: CGFloat = fieldHeight * 0.15

        return ZStack {
            // Shaded region showing yards gained
            let minX = min(startX, endX)
            let maxX = max(startX, endX)
            let regionWidth = maxX - minX
            if regionWidth > 1 {
                Rectangle()
                    .fill(drive.teamColor.opacity(0.25))
                    .frame(width: regionWidth, height: fieldHeight)
                    .offset(x: (minX + maxX) / 2)
            }

            // Drive arrow line
            Path { path in
                path.move(to: CGPoint(x: startX + fieldWidth / 2, y: midY))
                path.addLine(to: CGPoint(x: endX + fieldWidth / 2, y: midY))
            }
            .stroke(drive.teamColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: fieldWidth, height: fieldHeight)
            .offset(x: 0, y: 0)

            // Arrow tip
            let direction: CGFloat = endX > startX ? 1 : -1
            let tipX = endX
            Path { path in
                path.move(to: CGPoint(x: tipX + fieldWidth / 2, y: midY))
                path.addLine(to: CGPoint(x: tipX + fieldWidth / 2 - direction * 5, y: midY - 4))
                path.move(to: CGPoint(x: tipX + fieldWidth / 2, y: midY))
                path.addLine(to: CGPoint(x: tipX + fieldWidth / 2 - direction * 5, y: midY + 4))
            }
            .stroke(drive.teamColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: fieldWidth, height: fieldHeight)

            // Start marker (small circle)
            Circle()
                .fill(drive.teamColor.opacity(0.7))
                .frame(width: 5, height: 5)
                .offset(x: startX, y: midY - fieldHeight / 2)
        }
    }

    // MARK: - Marker Lines

    private func markerLine(yardsToEndzone: Int, fieldWidth: CGFloat, fieldHeight: CGFloat,
                            color: Color, lineWidth: CGFloat, dashed: Bool) -> some View {
        let xPos = xForYTE(yardsToEndzone, fieldWidth: fieldWidth)
        return Group {
            if dashed {
                Rectangle()
                    .fill(.clear)
                    .frame(width: lineWidth, height: fieldHeight)
                    .overlay(
                        VStack(spacing: 2) {
                            ForEach(0..<Int(fieldHeight / 5), id: \.self) { _ in
                                Rectangle()
                                    .fill(color.opacity(0.85))
                                    .frame(width: lineWidth, height: 3)
                            }
                        }
                    )
                    .offset(x: xPos)
            } else {
                Rectangle()
                    .fill(color.opacity(0.85))
                    .frame(width: lineWidth, height: fieldHeight)
                    .offset(x: xPos)
            }
        }
    }

    // MARK: - Football Marker

    private func footballMarker(yardsToEndzone: Int, fieldWidth: CGFloat, fieldHeight: CGFloat) -> some View {
        let xPos = xForYTE(yardsToEndzone, fieldWidth: fieldWidth)
        return Image(systemName: "football.fill")
            .font(.system(size: max(fieldHeight * 0.16, 8)))
            .foregroundColor(.brown)
            .shadow(color: .black.opacity(0.6), radius: 2)
            .offset(x: xPos, y: fieldHeight * 0.18)
    }

    // MARK: - Coordinate Helper

    /// Convert yardsToEndzone (0=in endzone, 100=own goal) to x offset from center of field.
    /// Left edge of field = away goal (endzone 0 for away, 100 for home).
    /// For the field drawing: 0 yardsToEndzone = right edge (home endzone), 100 = left edge (away endzone).
    private func xForYTE(_ yte: Int, fieldWidth: CGFloat) -> CGFloat {
        let clamped = CGFloat(max(0, min(100, yte)))
        // yardsToEndzone 100 = far left (own endzone), 0 = far right (scoring endzone)
        // We map: 100 -> left edge (-fieldWidth/2), 0 -> right edge (+fieldWidth/2)
        let fraction = clamped / 100.0
        return (fieldWidth / 2) - (fraction * fieldWidth)
    }

    // MARK: - Drive Play Panel (large widget)

    private func drivePlayPanel(_ game: FootballGameData) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let drive = game.currentDrive {
                // Drive header
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(drive.teamColor)
                        .frame(width: 3, height: 12)
                    Text("\(drive.teamAbbr) DRIVE")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.secondary)
                    Spacer()
                    if !drive.description.isEmpty {
                        Text(drive.description)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                // Last 4 plays
                let recentPlays = Array(drive.plays.suffix(4))
                ForEach(Array(recentPlays.enumerated()), id: \.offset) { idx, play in
                    HStack(alignment: .top, spacing: 4) {
                        let yardStr = play.yardage >= 0 ? "+\(play.yardage)" : "\(play.yardage)"
                        Text(yardStr)
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundColor(play.yardage > 0 ? .green : (play.yardage < 0 ? .red : .gray))
                            .frame(width: 26, alignment: .trailing)

                        Text(play.text)
                            .font(.system(size: 8, weight: .regular))
                            .foregroundColor(.primary.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            } else if let last = game.lastCompletedDrive {
                HStack(spacing: 4) {
                    Text("LAST DRIVE")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(last.teamAbbr) - \(last.result)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(last.teamColor)
                }
                if !last.description.isEmpty {
                    Text(last.description)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.2)))
    }

    // MARK: - Pre-Game Panel

    private func preGamePanel(_ game: FootballGameData) -> some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(game.awayColor)
                    .frame(width: 12, height: 12)
                Text(game.awayAbbr)
                    .font(.system(size: 14, weight: .bold))
            }

            VStack(spacing: 2) {
                Text("VS")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.secondary)
                if let date = game.startDate {
                    let diff = date.timeIntervalSince(entry.date)
                    if diff > 0 {
                        let hours = Int(diff) / 3600
                        let mins = (Int(diff) % 3600) / 60
                        Text(hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                    }
                    Text(Self.kickoffFormatter.string(from: date))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.gray)
                }
            }

            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(game.homeColor)
                    .frame(width: 12, height: 12)
                Text(game.homeAbbr)
                    .font(.system(size: 14, weight: .bold))
            }
        }
    }

    // MARK: - Final Panel

    private func finalPanel(_ game: FootballGameData) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(game.awayColor).frame(width: 4, height: 18)
                Text(game.awayAbbr).font(.system(size: 13, weight: .bold))
                Text(game.awayScore)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
            }
            Spacer()
            Text("FINAL")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(.gray)
            Spacer()
            HStack(spacing: 6) {
                Text(game.homeScore)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                Text(game.homeAbbr).font(.system(size: 13, weight: .bold))
                RoundedRectangle(cornerRadius: 2).fill(game.homeColor).frame(width: 4, height: 18)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "football.fill")
                .font(.title3)
                .foregroundColor(.gray)
            Text("No football games")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Color Extension

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&rgb) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
