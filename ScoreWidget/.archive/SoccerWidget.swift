import WidgetKit
import SwiftUI

// MARK: - Soccer Widget

struct SoccerWidget: Widget {
    let kind = "SoccerWidget_v1"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SoccerProvider()) { entry in
            SoccerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Soccer")
        .description("Live soccer match with goals, cards, and event timeline on pitch")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Color Helper

private enum SCColor {
    static func from(_ hex: String?) -> Color {
        guard let hex = hex else { return .gray }
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

    static let pitch = Color(red: 0.11, green: 0.37, blue: 0.13)
    static let pitchLight = Color(red: 0.14, green: 0.42, blue: 0.16)
    static let pitchLine = Color.white.opacity(0.35)
}

// MARK: - Match Event

struct MatchEvent: Identifiable {
    let id: String
    let minute: String
    let type: EventType
    let playerName: String
    let teamSide: TeamSide  // home or away

    enum EventType: String {
        case goal
        case yellowCard
        case redCard
        case substitution
        case penaltyGoal
        case ownGoal

        var icon: String {
            switch self {
            case .goal, .penaltyGoal: return "soccerball"
            case .yellowCard: return "rectangle.fill"
            case .redCard: return "rectangle.fill"
            case .substitution: return "arrow.left.arrow.right"
            case .ownGoal: return "soccerball"
            }
        }

        var color: Color {
            switch self {
            case .goal, .penaltyGoal: return .white
            case .yellowCard: return .yellow
            case .redCard: return .red
            case .substitution: return .cyan
            case .ownGoal: return .orange
            }
        }

        var label: String {
            switch self {
            case .goal: return "GOAL"
            case .penaltyGoal: return "PEN"
            case .yellowCard: return "YC"
            case .redCard: return "RC"
            case .substitution: return "SUB"
            case .ownGoal: return "OG"
            }
        }
    }

    enum TeamSide: String {
        case home, away
    }
}

// MARK: - Match Model

struct SoccerMatch: Identifiable {
    let id: String
    let homeTeam: String
    let homeAbbr: String
    let homeScore: Int?
    let homeColor: String?
    let awayTeam: String
    let awayAbbr: String
    let awayScore: Int?
    let awayColor: String?
    let state: String
    let matchMinute: String?
    let halfIndicator: String?
    let startDate: Date?
    let detail: String?
    let shortDetail: String?
    let leagueName: String
    let leagueAbbr: String
    let homePossession: Double?
    let awayPossession: Double?
    let events: [MatchEvent]

    var isLive: Bool { state == "in" }
    var isFinished: Bool { state == "post" }
    var isPre: Bool { state == "pre" }

    var interestScore: Int {
        if isLive { return 100 }
        if isPre, let d = startDate, d.timeIntervalSinceNow < 3600 { return 50 }
        if isFinished { return 10 }
        return 1
    }

    var homeGoals: [MatchEvent] {
        events.filter { $0.teamSide == .home && ($0.type == .goal || $0.type == .penaltyGoal) }
    }
    var awayGoals: [MatchEvent] {
        events.filter { $0.teamSide == .away && ($0.type == .goal || $0.type == .penaltyGoal) }
    }
}

// MARK: - Entry

struct SoccerEntry: TimelineEntry {
    let date: Date
    let match: SoccerMatch?
    let upcomingMatches: [SoccerMatch]
}

// MARK: - Provider

struct SoccerProvider: TimelineProvider {
    private static let soccerLeagueIDs = [
        "epl", "mls", "laliga", "bundesliga", "seriea", "ligue1", "ucl", "ligamx"
    ]

    func placeholder(in context: Context) -> SoccerEntry { sampleEntry }

    func getSnapshot(in context: Context, completion: @escaping (SoccerEntry) -> Void) {
        fetchMatches { completion($0 ?? sampleEntry) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SoccerEntry>) -> Void) {
        // Ensure completion is called exactly once — WidgetKit preempts the
        // extension aggressively, so guarantee a fallback timeline ships.
        let lock = NSLock()
        var fired = false
        func fire(_ timeline: Timeline<SoccerEntry>) {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            lock.unlock()
            completion(timeline)
        }
        let wrappedCompletion: (Timeline<SoccerEntry>) -> Void = fire
        DispatchQueue.global().asyncAfter(deadline: .now() + 4.5) {
            fire(Timeline(entries: [self.placeholder(in: context)], policy: .after(Date().addingTimeInterval(60))))
        }

        fetchMatches { entry in
            let result = entry ?? sampleEntry
            let hasLive = result.match?.isLive == true
            let refresh = Calendar.current.date(byAdding: .minute, value: hasLive ? 1 : 10, to: Date())!
            wrappedCompletion(Timeline(entries: [result], policy: .after(refresh)))
        }
    }

    private func fetchMatches(completion: @escaping (SoccerEntry?) -> Void) {
        let selectedIDs = UserDefaults.standard.array(forKey: "selectedSportIDs") as? [String] ?? []
        let enabledSoccer = Self.soccerLeagueIDs.filter { selectedIDs.contains($0) }
        let leagueIDs = enabledSoccer.isEmpty ? ["epl"] : enabledSoccer
        let leagues = leagueIDs.compactMap { SportLeague.find($0) }

        if leagues.isEmpty {
            completion(nil)
            return
        }

        let group = DispatchGroup()
        var allMatches: [SoccerMatch] = []
        let lock = NSLock()

        for league in leagues {
            group.enter()
            let urlString = "\(league.scoreboardURL)?limit=20"
            guard let url = URL(string: urlString) else { group.leave(); continue }

            URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)) { data, _, _ in
                defer { group.leave() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let events = json["events"] as? [[String: Any]] else { return }

                let matches: [SoccerMatch] = events.compactMap {
                    self.parseMatch($0, leagueName: league.displayName, leagueAbbr: league.shortName)
                }
                lock.lock()
                allMatches.append(contentsOf: matches)
                lock.unlock()
            }.resume()
        }

        group.notify(queue: .main) {
            let sorted = allMatches.sorted { $0.interestScore > $1.interestScore }
            let featured = sorted.first
            let upcoming = Array(sorted.dropFirst().prefix(5))
            completion(SoccerEntry(date: Date(), match: featured, upcomingMatches: upcoming))
        }
    }

    private func parseMatch(_ event: [String: Any], leagueName: String, leagueAbbr: String) -> SoccerMatch? {
        guard let id = event["id"] as? String,
              let competitions = event["competitions"] as? [[String: Any]],
              let comp = competitions.first,
              let competitors = comp["competitors"] as? [[String: Any]],
              let statusDict = event["status"] as? [String: Any],
              let statusType = statusDict["type"] as? [String: Any],
              let state = statusType["state"] as? String else { return nil }

        let detail = statusType["detail"] as? String
        let shortDetail = statusType["shortDetail"] as? String
        let displayClock = statusDict["displayClock"] as? String
        let period = statusDict["period"] as? Int ?? 0
        let dateStr = event["date"] as? String ?? ""
        let startDate = Self.parseDate(dateStr)

        var halfIndicator: String?
        var matchMinute: String?

        if state == "in" {
            matchMinute = displayClock
            if let d = detail?.lowercased() {
                if d.contains("halftime") || d.contains("half time") {
                    halfIndicator = "HT"; matchMinute = "HT"
                } else if d.contains("extra time") || d.contains("et") {
                    halfIndicator = "ET"
                } else if d.contains("penalty") || d.contains("pk") || d.contains("shootout") {
                    halfIndicator = "PK"
                } else if period == 1 {
                    halfIndicator = "1H"
                } else if period == 2 {
                    halfIndicator = "2H"
                }
            } else {
                halfIndicator = period <= 1 ? "1H" : "2H"
            }
            if let d = detail, d.contains("+") {
                matchMinute = d
            }
        }

        let home = competitors.first { ($0["homeAway"] as? String) == "home" }
        let away = competitors.first { ($0["homeAway"] as? String) == "away" }

        func teamInfo(_ c: [String: Any]?) -> (name: String, abbr: String, score: Int?, color: String?) {
            guard let c = c, let team = c["team"] as? [String: Any] else {
                return ("TBD", "TBD", nil, nil)
            }
            return (
                team["displayName"] as? String ?? "TBD",
                team["abbreviation"] as? String ?? "TBD",
                (c["score"] as? String).flatMap { Int($0) },
                team["color"] as? String
            )
        }

        let homeInfo = teamInfo(home)
        let awayInfo = teamInfo(away)

        // Possession
        var homePoss: Double?
        var awayPoss: Double?

        if let stats = home?["statistics"] as? [[String: Any]] {
            for stat in stats {
                if (stat["name"] as? String) == "possessionPct" {
                    homePoss = (stat["displayValue"] as? String).flatMap { Double($0) }.map { $0 / 100.0 }
                }
            }
        }
        if let stats = away?["statistics"] as? [[String: Any]] {
            for stat in stats {
                if (stat["name"] as? String) == "possessionPct" {
                    awayPoss = (stat["displayValue"] as? String).flatMap { Double($0) }.map { $0 / 100.0 }
                }
            }
        }

        // Parse match details (goals, cards, subs)
        var matchEvents: [MatchEvent] = []
        let homeID = (home?["id"] as? String) ?? (home?["team"] as? [String: Any])?["id"] as? String ?? ""

        if let details = comp["details"] as? [[String: Any]] {
            for (idx, det) in details.enumerated() {
                let clock = det["clock"] as? [String: Any]
                let minute = clock?["displayValue"] as? String ?? ""

                let typeDict = det["type"] as? [String: Any]
                let typeText = (typeDict?["text"] as? String ?? "").lowercased()
                let typeId = typeDict?["id"] as? String ?? ""

                let athletesArray = det["athletesInvolved"] as? [[String: Any]]
                let playerName = athletesArray?.first?["shortName"] as? String
                    ?? athletesArray?.first?["displayName"] as? String
                    ?? ""

                let teamId = det["team"] as? [String: Any]
                let detTeamId = teamId?["id"] as? String ?? ""
                let side: MatchEvent.TeamSide = detTeamId == homeID ? .home : .away

                let eventType: MatchEvent.EventType?
                if typeText.contains("goal") && typeText.contains("own") {
                    eventType = .ownGoal
                } else if typeText.contains("penalty") && typeText.contains("goal") {
                    eventType = .penaltyGoal
                } else if typeText.contains("goal") || typeId == "1" {
                    eventType = .goal
                } else if typeText.contains("yellow") || typeId == "3" {
                    eventType = .yellowCard
                } else if typeText.contains("red") || typeId == "5" || typeId == "6" {
                    eventType = .redCard
                } else if typeText.contains("sub") || typeId == "7" || typeId == "8" {
                    eventType = .substitution
                } else {
                    eventType = nil
                }

                if let et = eventType {
                    matchEvents.append(MatchEvent(
                        id: "\(id)_\(idx)",
                        minute: minute,
                        type: et,
                        playerName: playerName,
                        teamSide: side
                    ))
                }
            }
        }

        return SoccerMatch(
            id: id,
            homeTeam: homeInfo.name, homeAbbr: homeInfo.abbr, homeScore: homeInfo.score,
            homeColor: homeInfo.color,
            awayTeam: awayInfo.name, awayAbbr: awayInfo.abbr, awayScore: awayInfo.score,
            awayColor: awayInfo.color,
            state: state, matchMinute: matchMinute, halfIndicator: halfIndicator,
            startDate: startDate, detail: detail, shortDetail: shortDetail,
            leagueName: leagueName, leagueAbbr: leagueAbbr,
            homePossession: homePoss, awayPossession: awayPoss,
            events: matchEvents
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

    private var sampleEntry: SoccerEntry {
        SoccerEntry(
            date: Date(),
            match: SoccerMatch(
                id: "sample1",
                homeTeam: "Arsenal", homeAbbr: "ARS", homeScore: 2,
                homeColor: "EF0107",
                awayTeam: "Chelsea", awayAbbr: "CHE", awayScore: 1,
                awayColor: "034694",
                state: "in", matchMinute: "67'", halfIndicator: "2H",
                startDate: nil, detail: "67' - 2nd Half",
                shortDetail: "67'", leagueName: "Premier League", leagueAbbr: "EPL",
                homePossession: 0.58, awayPossession: 0.42,
                events: [
                    MatchEvent(id: "e1", minute: "23'", type: .goal, playerName: "Saka", teamSide: .home),
                    MatchEvent(id: "e2", minute: "38'", type: .yellowCard, playerName: "Caicedo", teamSide: .away),
                    MatchEvent(id: "e3", minute: "45'", type: .goal, playerName: "Palmer", teamSide: .away),
                    MatchEvent(id: "e4", minute: "61'", type: .goal, playerName: "Havertz", teamSide: .home),
                    MatchEvent(id: "e5", minute: "55'", type: .substitution, playerName: "Mudryk", teamSide: .away),
                ]
            ),
            upcomingMatches: []
        )
    }
}

// MARK: - Widget View

struct SoccerWidgetView: View {
    let entry: SoccerEntry
    @Environment(\.widgetFamily) var family

    private static let kickoffFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E h:mm a"
        return f
    }()

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        switch family {
        case .systemLarge: largeView
        default: mediumView
        }
    }

    // MARK: - Medium View

    private var mediumView: some View {
        ZStack {
            if let match = entry.match {
                pitchStage(match: match, compact: true)
            } else {
                ZStack {
                    pitchBackground(compact: true, match: nil)
                    emptyView
                }
            }
        }
    }

    // MARK: - Large View

    private var largeView: some View {
        ZStack {
            if let match = entry.match {
                pitchStage(match: match, compact: false)
            } else {
                ZStack {
                    pitchBackground(compact: false, match: nil)
                    emptyView
                }
            }
        }
    }

    // MARK: - Pitch Stage (pitch fills entire widget, everything drawn on it)

    private func pitchStage(match: SoccerMatch, compact: Bool) -> some View {
        ZStack {
            pitchBackground(compact: compact, match: match)
            if compact {
                mediumMatchOverlay(match)
            } else {
                largeMatchOverlay(match)
            }
        }
    }

    // MARK: - Pitch Drawing

    private func pitchBackground(compact: Bool, match: SoccerMatch?) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let lc = SCColor.pitchLine
            let lw: CGFloat = 1.0

            // Possession heat-map tint
            let homeTint: Double = {
                guard let m = match, let hp = m.homePossession, let ap = m.awayPossession else { return 0.0 }
                return hp > ap ? 0.28 : 0.10
            }()
            let awayTint: Double = {
                guard let m = match, let hp = m.homePossession, let ap = m.awayPossession else { return 0.0 }
                return ap > hp ? 0.28 : 0.10
            }()
            let homeTintColor: Color = match.map { SCColor.from($0.homeColor) } ?? .clear
            let awayTintColor: Color = match.map { SCColor.from($0.awayColor) } ?? .clear

            ZStack {
                SCColor.pitch

                // Alternating stripes
                HStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { i in
                        Rectangle()
                            .fill(i % 2 == 0 ? Color.clear : SCColor.pitchLight.opacity(0.15))
                            .frame(width: w / 10)
                    }
                }

                // Possession heat-map halves
                HStack(spacing: 0) {
                    Rectangle().fill(homeTintColor.opacity(homeTint))
                        .frame(width: w / 2)
                    Rectangle().fill(awayTintColor.opacity(awayTint))
                        .frame(width: w / 2)
                }
                .allowsHitTesting(false)

                Canvas { context, size in
                    let margin: CGFloat = compact ? 8 : 12
                    let field = CGRect(
                        x: margin, y: margin,
                        width: size.width - margin * 2,
                        height: size.height - margin * 2
                    )
                    let midX = field.midX
                    let midY = field.midY

                    // Touchlines
                    context.stroke(Path(field), with: .color(lc), lineWidth: lw)

                    // Halfway line
                    var half = Path()
                    half.move(to: CGPoint(x: midX, y: field.minY))
                    half.addLine(to: CGPoint(x: midX, y: field.maxY))
                    context.stroke(half, with: .color(lc), lineWidth: lw)

                    // Center circle
                    let cr = min(field.width, field.height) * (compact ? 0.17 : 0.15)
                    context.stroke(
                        Path(ellipseIn: CGRect(x: midX - cr, y: midY - cr, width: cr * 2, height: cr * 2)),
                        with: .color(lc), lineWidth: lw
                    )

                    // Center dot
                    let dr: CGFloat = 2
                    context.fill(
                        Path(ellipseIn: CGRect(x: midX - dr, y: midY - dr, width: dr * 2, height: dr * 2)),
                        with: .color(lc)
                    )

                    // Penalty areas
                    let penW = field.width * 0.14
                    let penH = field.height * 0.55
                    let penY = midY - penH / 2
                    context.stroke(Path(CGRect(x: field.minX, y: penY, width: penW, height: penH)),
                                   with: .color(lc), lineWidth: lw)
                    context.stroke(Path(CGRect(x: field.maxX - penW, y: penY, width: penW, height: penH)),
                                   with: .color(lc), lineWidth: lw)

                    // Goal areas
                    let goalW = penW * 0.45
                    let goalH = penH * 0.5
                    let goalY = midY - goalH / 2
                    context.stroke(Path(CGRect(x: field.minX, y: goalY, width: goalW, height: goalH)),
                                   with: .color(lc), lineWidth: lw)
                    context.stroke(Path(CGRect(x: field.maxX - goalW, y: goalY, width: goalW, height: goalH)),
                                   with: .color(lc), lineWidth: lw)

                    // Corner arcs
                    let cornerR: CGFloat = compact ? 5 : 7
                    let corners: [(CGPoint, CGFloat, CGFloat)] = [
                        (CGPoint(x: field.minX, y: field.minY), 0, .pi / 2),
                        (CGPoint(x: field.maxX, y: field.minY), .pi / 2, .pi),
                        (CGPoint(x: field.maxX, y: field.maxY), .pi, .pi * 1.5),
                        (CGPoint(x: field.minX, y: field.maxY), .pi * 1.5, .pi * 2),
                    ]
                    for (center, start, end) in corners {
                        var arc = Path()
                        arc.addArc(center: center, radius: cornerR,
                                   startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
                        context.stroke(arc, with: .color(lc), lineWidth: lw)
                    }
                }
            }
        }
    }

    // MARK: - Medium Match Overlay

    private func mediumMatchOverlay(_ match: SoccerMatch) -> some View {
        GeometryReader { geo in
            ZStack {
                // Header: league + status
                VStack {
                    HStack {
                        leagueBadge(match)
                        Spacer()
                        if match.isLive { livePulse }
                        else if match.isFinished { ftBadge }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    Spacer()
                }

                if match.isPre {
                    preMatchView(match, compact: true)
                } else {
                    // Main score display
                    VStack(spacing: 0) {
                        Spacer().frame(height: 28)

                        HStack(spacing: 0) {
                            // Home side
                            teamScoreColumn(
                                abbr: match.homeAbbr, score: match.homeScore,
                                color: match.homeColor, goals: match.homeGoals,
                                compact: true
                            )
                            .frame(maxWidth: .infinity)

                            // Center minute
                            VStack(spacing: 2) {
                                if let minute = match.matchMinute {
                                    Text(minute)
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                                }
                                if let half = match.halfIndicator, half != "HT" {
                                    Text(half)
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                if match.isFinished {
                                    Text("FT")
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .frame(width: 56)

                            // Away side
                            teamScoreColumn(
                                abbr: match.awayAbbr, score: match.awayScore,
                                color: match.awayColor, goals: match.awayGoals,
                                compact: true
                            )
                            .frame(maxWidth: .infinity)
                        }

                        Spacer(minLength: 4)

                        // Event timeline strip
                        if !match.events.isEmpty {
                            eventTimeline(match.events.prefix(6), compact: true)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 2)
                        }

                        // Possession bar
                        if let hp = match.homePossession, let ap = match.awayPossession {
                            possessionBar(home: hp, away: ap, match: match, compact: true)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Large Match Overlay

    private func largeMatchOverlay(_ match: SoccerMatch) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                leagueBadge(match)
                Spacer()
                if match.isLive { livePulse }
                else if match.isFinished { ftBadge }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Spacer().frame(height: 8)

            if match.isPre {
                preMatchView(match, compact: false)
            } else {
                // Score section
                HStack(spacing: 0) {
                    teamScoreColumn(
                        abbr: match.homeAbbr, score: match.homeScore,
                        color: match.homeColor, goals: match.homeGoals,
                        compact: false
                    )
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 2) {
                        if let minute = match.matchMinute {
                            Text(minute)
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        }
                        if let half = match.halfIndicator, half != "HT" {
                            Text(half)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        if match.isFinished {
                            Text("FULL TIME")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .frame(width: 70)

                    teamScoreColumn(
                        abbr: match.awayAbbr, score: match.awayScore,
                        color: match.awayColor, goals: match.awayGoals,
                        compact: false
                    )
                    .frame(maxWidth: .infinity)
                }

                Spacer().frame(height: 6)

                // Possession bar
                if let hp = match.homePossession, let ap = match.awayPossession {
                    possessionBar(home: hp, away: ap, match: match, compact: false)
                        .padding(.horizontal, 24)
                }

                Spacer().frame(height: 8)

                // Goal markers on pitch area
                if !match.events.isEmpty {
                    goalMarkersRow(match)
                        .padding(.horizontal, 14)
                }

                Spacer().frame(height: 6)

                // Full event timeline
                Divider().opacity(0.3).padding(.horizontal, 14)

                fullEventList(match)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Team Score Column

    private func teamScoreColumn(
        abbr: String, score: Int?, color: String?,
        goals: [MatchEvent], compact: Bool
    ) -> some View {
        VStack(spacing: compact ? 2 : 4) {
            // Team color dot
            Circle()
                .fill(SCColor.from(color))
                .frame(width: compact ? 14 : 18, height: compact ? 14 : 18)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))

            Text(abbr)
                .font(.system(size: compact ? 13 : 16, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)

            if let s = score {
                Text("\(s)")
                    .font(.system(size: compact ? 28 : 36, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            }

            // Goal scorers
            if !goals.isEmpty && !compact {
                VStack(spacing: 1) {
                    ForEach(goals.prefix(3)) { g in
                        HStack(spacing: 2) {
                            Image(systemName: "soccerball")
                                .font(.system(size: 6))
                                .foregroundColor(.white.opacity(0.7))
                            Text("\(g.playerName) \(g.minute)")
                                .font(.system(size: 7, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Event Timeline Strip (compact, bottom of medium)

    private func eventTimeline<C: Collection>(_ events: C, compact: Bool) -> some View where C.Element == MatchEvent {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(Array(events)) { event in
                HStack(spacing: 2) {
                    eventIcon(event, size: compact ? 8 : 10)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.playerName.components(separatedBy: " ").last ?? event.playerName)
                            .font(.system(size: compact ? 6 : 7, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(event.minute)
                            .font(.system(size: compact ? 5 : 6, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black.opacity(0.35))
                )
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Goal Markers Row (large, shows goals spatially)

    private func goalMarkersRow(_ match: SoccerMatch) -> some View {
        HStack(spacing: 0) {
            // Home goals (left side)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(match.homeGoals.prefix(4)) { g in
                    HStack(spacing: 3) {
                        Image(systemName: "soccerball")
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                        Text("\(g.playerName) \(g.minute)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Away goals (right side)
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(match.awayGoals.prefix(4)) { g in
                    HStack(spacing: 3) {
                        Text("\(g.minute) \(g.playerName)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                        Image(systemName: "soccerball")
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Full Event List (large widget)

    private func fullEventList(_ match: SoccerMatch) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MATCH EVENTS")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
            .padding(.bottom, 3)

            let allEvents = match.events.sorted { $0.minute < $1.minute }
            ForEach(allEvents.prefix(8)) { event in
                HStack(spacing: 6) {
                    Text(event.minute)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 28, alignment: .trailing)

                    eventIcon(event, size: 10)

                    Text(event.playerName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)

                    Spacer()

                    Text(event.teamSide == .home ? match.homeAbbr : match.awayAbbr)
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.vertical, 2)

                if event.id != allEvents.prefix(8).last?.id {
                    Divider().opacity(0.15)
                }
            }
        }
    }

    // MARK: - Event Icon

    private func eventIcon(_ event: MatchEvent, size: CGFloat) -> some View {
        Group {
            switch event.type {
            case .goal, .penaltyGoal:
                Image(systemName: "soccerball")
                    .font(.system(size: size))
                    .foregroundColor(.white)
            case .ownGoal:
                Image(systemName: "soccerball")
                    .font(.system(size: size))
                    .foregroundColor(.orange)
            case .yellowCard:
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.yellow)
                    .frame(width: size * 0.7, height: size)
            case .redCard:
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.red)
                    .frame(width: size * 0.7, height: size)
            case .substitution:
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: size * 0.8))
                    .foregroundColor(.cyan)
            }
        }
    }

    // MARK: - Possession Bar

    private func possessionBar(home: Double, away: Double, match: SoccerMatch, compact: Bool) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text("\(Int(home * 100))%")
                    .font(.system(size: compact ? 8 : 10, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("POSSESSION")
                    .font(.system(size: compact ? 6 : 7, weight: .heavy))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("\(Int(away * 100))%")
                    .font(.system(size: compact ? 8 : 10, weight: .bold))
                    .foregroundColor(.white)
            }
            GeometryReader { geo in
                HStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SCColor.from(match.homeColor).opacity(0.8))
                        .frame(width: geo.size.width * CGFloat(home))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SCColor.from(match.awayColor).opacity(0.8))
                        .frame(width: geo.size.width * CGFloat(away))
                }
            }
            .frame(height: compact ? 4 : 5)
        }
    }

    // MARK: - Pre-match

    private func preMatchView(_ match: SoccerMatch, compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 10) {
            Spacer()
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Circle()
                        .fill(SCColor.from(match.homeColor))
                        .frame(width: compact ? 28 : 36, height: compact ? 28 : 36)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                    Text(match.homeAbbr)
                        .font(.system(size: compact ? 14 : 18, weight: .heavy))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("VS")
                        .font(.system(size: compact ? 12 : 16, weight: .black))
                        .foregroundColor(.white.opacity(0.6))
                    if let date = match.startDate {
                        let diff = date.timeIntervalSince(entry.date)
                        if diff > 0 {
                            let hours = Int(diff) / 3600
                            let mins = (Int(diff) % 3600) / 60
                            if hours >= 24 {
                                Text(Self.kickoffFormatter.string(from: date))
                                    .font(.system(size: compact ? 9 : 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                            } else {
                                Text("\(hours)h \(mins)m")
                                    .font(.system(size: compact ? 14 : 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.yellow)
                            }
                        }
                        Text(Self.shortTimeFormatter.string(from: date))
                            .font(.system(size: compact ? 8 : 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .frame(width: compact ? 60 : 80)

                VStack(spacing: 4) {
                    Circle()
                        .fill(SCColor.from(match.awayColor))
                        .frame(width: compact ? 28 : 36, height: compact ? 28 : 36)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                    Text(match.awayAbbr)
                        .font(.system(size: compact ? 14 : 18, weight: .heavy))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            Spacer()
        }
    }

    // MARK: - Badges

    private func leagueBadge(_ match: SoccerMatch) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "soccerball")
                .font(.system(size: 8, weight: .bold))
            Text(match.leagueAbbr)
                .font(.system(size: 8, weight: .heavy))
        }
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.black.opacity(0.3)))
    }

    private var livePulse: some View {
        HStack(spacing: 3) {
            Circle().fill(.red).frame(width: 5, height: 5)
            Text("LIVE")
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.red.opacity(0.4)))
    }

    private var ftBadge: some View {
        Text("FT")
            .font(.system(size: 8, weight: .heavy))
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.15)))
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "soccerball")
                .font(.system(size: 24))
                .foregroundColor(.gray)
            Text("No matches")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.gray)
            Text("Enable soccer leagues in settings")
                .font(.system(size: 10))
                .foregroundColor(.gray.opacity(0.7))
        }
    }
}
