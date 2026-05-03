import WidgetKit
import SwiftUI

// MARK: - Golf Widget

struct GolfWidget: Widget {
    let kind = "GolfWidget_v1"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GolfProvider()) { entry in
            GolfWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Golf")
        .description("Live PGA Tour leaderboard, scores, and tournament info")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry

struct GolfEntry: TimelineEntry {
    let date: Date
    let tournamentName: String
    let courseName: String
    let location: String
    let roundDisplay: String        // "R1", "R2", "R3", "R4"
    let roundNumber: Int
    let state: String               // "pre", "in", "post"
    let statusDetail: String?       // e.g. "Round 2 - In Progress"
    let golfers: [GolfGolfer]
    let cutLine: Int?               // score to par for the cut
    let startDate: Date?            // tournament start date
}

struct GolfGolfer: Identifiable {
    let id: String
    let position: String            // "T1", "2", "T3", "CUT", etc.
    let positionOrder: Int
    let name: String
    let scoreToPar: String          // "-5", "+2", "E"
    let scoreToParValue: Int        // numeric for coloring
    let todayScore: String?         // today's round score
    let thru: String?               // "Thru 14", "F", "Tee 10:30"
    let isWinner: Bool
    let isCut: Bool
}

// MARK: - Provider

struct GolfProvider: TimelineProvider {
    func placeholder(in context: Context) -> GolfEntry { sampleEntry }

    func getSnapshot(in context: Context, completion: @escaping (GolfEntry) -> Void) {
        fetchGolf { completion($0 ?? sampleEntry) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GolfEntry>) -> Void) {
        // Ensure completion is called exactly once — WidgetKit preempts the
        // extension aggressively, so guarantee a fallback timeline ships.
        let lock = NSLock()
        var fired = false
        func fire(_ timeline: Timeline<GolfEntry>) {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            lock.unlock()
            completion(timeline)
        }
        let wrappedCompletion: (Timeline<GolfEntry>) -> Void = fire
        DispatchQueue.global().asyncAfter(deadline: .now() + 4.5) {
            fire(Timeline(entries: [self.placeholder(in: context)], policy: .after(Date().addingTimeInterval(60))))
        }

        fetchGolf { entry in
            let final = entry ?? sampleEntry
            let hasLive = final.state == "in"
            let refresh = Calendar.current.date(byAdding: .minute, value: hasLive ? 2 : 30, to: Date())!
            wrappedCompletion(Timeline(entries: [final], policy: .after(refresh)))
        }
    }

    private func fetchGolf(completion: @escaping (GolfEntry?) -> Void) {
        let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/golf/pga/scoreboard")!

        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let events = json["events"] as? [[String: Any]],
                  let event = events.first else {
                completion(nil)
                return
            }

            let tournamentName = event["shortName"] as? String ?? event["name"] as? String ?? "PGA Tournament"
            let competitions = event["competitions"] as? [[String: Any]] ?? []
            let comp = competitions.first ?? [:]

            // Venue info
            let venue = comp["venue"] as? [String: Any] ?? event["venue"] as? [String: Any] ?? [:]
            let courseName = venue["fullName"] as? String ?? venue["shortName"] as? String ?? ""
            let address = venue["address"] as? [String: Any] ?? [:]
            let city = address["city"] as? String ?? ""
            let stateAbbr = address["state"] as? String ?? ""
            let location = [city, stateAbbr].filter { !$0.isEmpty }.joined(separator: ", ")

            // Status
            let statusDict = comp["status"] as? [String: Any] ?? event["status"] as? [String: Any] ?? [:]
            let statusType = statusDict["type"] as? [String: Any] ?? [:]
            let state = statusType["state"] as? String ?? "pre"
            let statusDetail = statusType["detail"] as? String ?? statusType["shortDetail"] as? String

            // Round info
            let period = statusDict["period"] as? Int ?? 1
            let roundDisplay = "R\(period)"

            // Start date
            let dateStr = event["date"] as? String ?? comp["date"] as? String ?? ""
            let startDate = self.parseDate(dateStr)

            // Competitors (golfers)
            let competitors = comp["competitors"] as? [[String: Any]] ?? []
            var golfers: [GolfGolfer] = []
            var cutLine: Int? = nil

            for c in competitors {
                let order = c["order"] as? Int ?? 99
                let athlete = c["athlete"] as? [String: Any] ?? [:]
                let name = athlete["displayName"] as? String ?? athlete["shortName"] as? String ?? "?"

                // Score to par
                let scoreRaw = c["score"] as? String ?? c["linescores"] as? String
                let scoreStr: String
                let scoreVal: Int
                if let s = scoreRaw {
                    scoreStr = s
                    scoreVal = self.parseScoreToPar(s)
                } else if let s = c["score"] as? Int {
                    scoreVal = s
                    if s == 0 { scoreStr = "E" }
                    else if s > 0 { scoreStr = "+\(s)" }
                    else { scoreStr = "\(s)" }
                } else {
                    scoreStr = "--"
                    scoreVal = 0
                }

                // Position display
                let statusValue = c["status"] as? [String: Any]
                let posType = statusValue?["type"] as? [String: Any]
                let posId = posType?["id"] as? String
                let isCut = posId == "3" || (c["status"] as? String)?.lowercased() == "cut"

                let posDisplay: String
                if isCut {
                    posDisplay = "CUT"
                } else if let tied = c["tied"] as? Bool, tied {
                    posDisplay = "T\(order)"
                } else {
                    posDisplay = "\(order)"
                }

                // Round score and thru
                let stats = c["statistics"] as? [[String: Any]] ?? []
                var todayScore: String? = nil
                var thru: String? = nil

                for stat in stats {
                    let statName = stat["name"] as? String ?? ""
                    let value = stat["displayValue"] as? String
                    if statName.lowercased().contains("today") || statName.lowercased().contains("round") {
                        todayScore = value
                    }
                    if statName.lowercased().contains("thru") {
                        thru = value
                    }
                }

                // Fallback thru from linescores
                if thru == nil {
                    let linescores = c["linescores"] as? [[String: Any]] ?? []
                    if let lastLine = linescores.last {
                        let holesCompleted = lastLine["value"] as? Int
                        if let h = holesCompleted {
                            thru = h >= 18 ? "F" : "Thru \(h)"
                        }
                    }
                }

                let winner = c["winner"] as? Bool ?? false

                golfers.append(GolfGolfer(
                    id: c["id"] as? String ?? athlete["id"] as? String ?? "\(order)",
                    position: posDisplay,
                    positionOrder: order,
                    name: name,
                    scoreToPar: scoreStr,
                    scoreToParValue: scoreVal,
                    todayScore: todayScore,
                    thru: thru,
                    isWinner: winner,
                    isCut: isCut
                ))
            }

            golfers.sort { $0.positionOrder < $1.positionOrder }

            // Try to detect cut line
            if let firstCut = golfers.first(where: { $0.isCut }) {
                cutLine = firstCut.scoreToParValue
            }

            let entry = GolfEntry(
                date: Date(),
                tournamentName: tournamentName,
                courseName: courseName,
                location: location,
                roundDisplay: roundDisplay,
                roundNumber: period,
                state: state,
                statusDetail: statusDetail,
                golfers: golfers,
                cutLine: cutLine,
                startDate: startDate
            )
            completion(entry)
        }.resume()
    }

    private func parseScoreToPar(_ s: String) -> Int {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.uppercased() == "E" { return 0 }
        return Int(trimmed) ?? 0
    }

    private func parseDate(_ s: String) -> Date? {
        let fmts = [
            "yyyy-MM-dd'T'HH:mm'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mmZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        ]
        for fmt in fmts {
            let df = DateFormatter()
            df.dateFormat = fmt
            df.timeZone = TimeZone(identifier: "UTC")
            if let d = df.date(from: s) { return d }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    private var sampleEntry: GolfEntry {
        GolfEntry(
            date: Date(),
            tournamentName: "The Masters",
            courseName: "Augusta National Golf Club",
            location: "Augusta, GA",
            roundDisplay: "R3",
            roundNumber: 3,
            state: "in",
            statusDetail: "Round 3 - In Progress",
            golfers: [
                GolfGolfer(id: "1", position: "1", positionOrder: 1, name: "Scottie Scheffler", scoreToPar: "-12", scoreToParValue: -12, todayScore: "-4", thru: "Thru 14", isWinner: false, isCut: false),
                GolfGolfer(id: "2", position: "2", positionOrder: 2, name: "Rory McIlroy", scoreToPar: "-10", scoreToParValue: -10, todayScore: "-3", thru: "Thru 16", isWinner: false, isCut: false),
                GolfGolfer(id: "3", position: "T3", positionOrder: 3, name: "Jon Rahm", scoreToPar: "-8", scoreToParValue: -8, todayScore: "-2", thru: "F", isWinner: false, isCut: false),
                GolfGolfer(id: "4", position: "T3", positionOrder: 3, name: "Collin Morikawa", scoreToPar: "-8", scoreToParValue: -8, todayScore: "E", thru: "F", isWinner: false, isCut: false),
                GolfGolfer(id: "5", position: "5", positionOrder: 5, name: "Brooks Koepka", scoreToPar: "-6", scoreToParValue: -6, todayScore: "+1", thru: "Thru 12", isWinner: false, isCut: false),
                GolfGolfer(id: "6", position: "T6", positionOrder: 6, name: "Jordan Spieth", scoreToPar: "-5", scoreToParValue: -5, todayScore: "-1", thru: "Thru 10", isWinner: false, isCut: false),
            ],
            cutLine: nil,
            startDate: Date()
        )
    }
}

// MARK: - Colors

private enum GolfColors {
    static let headerGreen = Color(red: 0.106, green: 0.369, blue: 0.125)   // #1B5E20
    static let darkGreen = Color(red: 0.133, green: 0.271, blue: 0.133)
    static let fairwayLight = Color(red: 0.180, green: 0.490, blue: 0.196)  // #2E7D32
    static let fairwayDark = Color(red: 0.075, green: 0.255, blue: 0.090)
    static let cream = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let augustaYellow = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let leaderboardBg = Color(red: 0.96, green: 0.96, blue: 0.93)
    static let rowAlt = Color(red: 0.93, green: 0.93, blue: 0.90)
    static let scoreUnder = Color(red: 0.80, green: 0.0, blue: 0.0)
    static let scoreOver = Color(red: 0.30, green: 0.30, blue: 0.30)
    static let scoreEven = Color(red: 0.13, green: 0.55, blue: 0.13)
    static let pinRed = Color(red: 0.85, green: 0.11, blue: 0.14)
}

// MARK: - Golf Hole Illustration

private struct GolfHoleIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Fairway background
                Rectangle()
                    .fill(Color(red: 0.33, green: 0.55, blue: 0.23))

                // Darker green oval (putting green)
                Ellipse()
                    .fill(Color(red: 0.20, green: 0.42, blue: 0.15))
                    .frame(width: w * 0.38, height: h * 0.38)
                    .position(x: w * 0.5, y: h * 0.22)

                // Red flag on the green
                Image(systemName: "flag.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.85, green: 0.11, blue: 0.14))
                    .position(x: w * 0.52, y: h * 0.17)

                // Tan bunker to the side
                Ellipse()
                    .fill(Color(red: 0.85, green: 0.75, blue: 0.55))
                    .frame(width: w * 0.18, height: h * 0.22)
                    .position(x: w * 0.78, y: h * 0.38)

                // White tee box at the bottom
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: w * 0.12, height: h * 0.1)
                    .position(x: w * 0.5, y: h * 0.9)

                // Leader ball between tee and green
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                    .position(x: w * 0.48, y: h * 0.55)
            }
        }
        .frame(height: 70)
        .clipped()
    }
}

// MARK: - Widget View

struct GolfWidgetView: View {
    let entry: GolfEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        case .systemLarge: largeView
        default: mediumView
        }
    }

    // MARK: - Small View

    private var smallView: some View {
        ZStack {
            fairwayBackground

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 3) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(GolfColors.pinRed)
                    Text("PGA TOUR")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    if entry.state == "in" {
                        liveIndicator(small: true)
                    } else {
                        Text(entry.roundDisplay)
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(GolfColors.augustaYellow)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Tournament name
                Text(entry.tournamentName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .padding(.horizontal, 10)

                Spacer(minLength: 4)

                if entry.state == "pre" {
                    preEventSmall
                } else {
                    // Leaderboard card
                    VStack(spacing: 0) {
                        ForEach(Array(entry.golfers.prefix(3).enumerated()), id: \.element.id) { idx, golfer in
                            smallGolferRow(golfer, isFirst: idx == 0)
                        }
                    }
                    .background(GolfColors.cream.opacity(0.95))
                    .cornerRadius(6)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var preEventSmall: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.courseName)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .padding(.horizontal, 10)

            if let start = entry.startDate {
                let diff = start.timeIntervalSince(entry.date)
                if diff > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(GolfColors.augustaYellow)
                        Text(Self.dayFormatter.string(from: start))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
    }

    private func smallGolferRow(_ golfer: GolfGolfer, isFirst: Bool) -> some View {
        HStack(spacing: 4) {
            Text(golfer.position)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(isFirst ? GolfColors.headerGreen : .gray)
                .frame(width: 22, alignment: .center)

            Text(abbreviateName(golfer.name))
                .font(.system(size: 10, weight: isFirst ? .bold : .medium))
                .foregroundColor(.black)
                .lineLimit(1)

            Spacer()

            Text(golfer.scoreToPar)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(scoreColor(golfer.scoreToParValue))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isFirst ? GolfColors.augustaYellow.opacity(0.15) : Color.clear)
    }

    // MARK: - Medium View

    private var mediumView: some View {
        ZStack {
            fairwayBackground

            VStack(spacing: 0) {
                GolfHoleIllustration()

                // Header bar
                tournamentHeader(compact: true)

                if entry.state == "pre" {
                    preEventMedium
                } else {
                    // Leaderboard
                    VStack(spacing: 0) {
                        // Column headers
                        leaderboardColumnHeader(compact: true)

                        ForEach(Array(entry.golfers.prefix(3).enumerated()), id: \.element.id) { idx, golfer in
                            mediumGolferRow(golfer, isLeader: idx == 0, isEven: idx % 2 == 0)
                        }
                    }
                    .background(GolfColors.cream.opacity(0.95))
                    .cornerRadius(6)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private var preEventMedium: some View {
        HStack(spacing: 12) {
            // Left: tournament info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(GolfColors.augustaYellow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.courseName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(entry.location)
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                if let start = entry.startDate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TEE OFF")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(GolfColors.augustaYellow)
                        Text(Self.dayFormatter.string(from: start))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        countdownText(to: start)
                    }
                }
            }
            .padding(10)

            // Right: decorative
            VStack {
                Image(systemName: "flag.fill")
                    .font(.system(size: 28))
                    .foregroundColor(GolfColors.pinRed.opacity(0.6))
                Text("R1-R4")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(10)
        }
    }

    private func mediumGolferRow(_ golfer: GolfGolfer, isLeader: Bool, isEven: Bool) -> some View {
        HStack(spacing: 0) {
            // Position
            Text(golfer.position)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundColor(isLeader ? GolfColors.headerGreen : .gray)
                .frame(width: 28, alignment: .center)

            // Name
            Text(golfer.name)
                .font(.system(size: 10, weight: isLeader ? .bold : .medium))
                .foregroundColor(.black)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)

            // Score to par
            Text(golfer.scoreToPar)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(scoreColor(golfer.scoreToParValue))
                .frame(width: 34, alignment: .center)

            // Today
            Text(golfer.todayScore ?? "--")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 28, alignment: .center)

            // Thru
            Text(golfer.thru ?? "--")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 42, alignment: .center)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            isLeader
                ? GolfColors.augustaYellow.opacity(0.15)
                : (isEven ? Color.clear : GolfColors.rowAlt.opacity(0.5))
        )
    }

    // MARK: - Large View

    private var largeView: some View {
        ZStack {
            fairwayBackground

            VStack(spacing: 0) {
                GolfHoleIllustration()

                // Header
                tournamentHeader(compact: false)

                if entry.state == "pre" {
                    preEventLarge
                } else {
                    // Full leaderboard
                    VStack(spacing: 0) {
                        leaderboardColumnHeader(compact: false)

                        let cutIdx = entry.golfers.prefix(10).firstIndex(where: { $0.isCut })

                        ForEach(Array(entry.golfers.prefix(10).enumerated()), id: \.element.id) { idx, golfer in
                            if let ci = cutIdx, idx == ci && idx > 0 {
                                cutLineRow
                            }
                            largeGolferRow(golfer, isLeader: idx == 0, isEven: idx % 2 == 0)
                        }
                    }
                    .background(GolfColors.cream.opacity(0.95))
                    .cornerRadius(8)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var preEventLarge: some View {
        VStack(spacing: 10) {
            // Course card
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(GolfColors.augustaYellow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.courseName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                        Text(entry.location)
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Divider().opacity(0.2).padding(.horizontal, 12)

                // Round schedule
                VStack(spacing: 4) {
                    ForEach(1...4, id: \.self) { round in
                        HStack {
                            Text("Round \(round)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.black.opacity(0.7))
                            Spacer()
                            if let start = entry.startDate {
                                let roundDate = Calendar.current.date(byAdding: .day, value: round - 1, to: start)
                                if let rd = roundDate {
                                    Text(Self.dayFormatter.string(from: rd))
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 10)
            }
            .background(GolfColors.cream.opacity(0.95))
            .cornerRadius(8)
            .padding(.horizontal, 10)

            // Countdown card
            if let start = entry.startDate {
                VStack(spacing: 4) {
                    Image(systemName: "flag.2.crossed.fill")
                        .font(.system(size: 20))
                        .foregroundColor(GolfColors.pinRed.opacity(0.8))
                    Text("TEE OFF")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.white.opacity(0.7))
                    countdownText(to: start)
                    Text(Self.dayFormatter.string(from: start))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(10)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func largeGolferRow(_ golfer: GolfGolfer, isLeader: Bool, isEven: Bool) -> some View {
        HStack(spacing: 0) {
            // Position
            ZStack {
                if isLeader && entry.state == "post" && golfer.isWinner {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 9))
                        .foregroundColor(GolfColors.augustaYellow)
                } else {
                    Text(golfer.position)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(isLeader ? GolfColors.headerGreen : .gray)
                }
            }
            .frame(width: 32, alignment: .center)

            // Name
            VStack(alignment: .leading, spacing: 0) {
                Text(golfer.name)
                    .font(.system(size: 11, weight: isLeader ? .bold : .medium))
                    .foregroundColor(golfer.isCut ? .gray : .black)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)

            // Score to par
            Text(golfer.scoreToPar)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(golfer.isCut ? .gray : scoreColor(golfer.scoreToParValue))
                .frame(width: 38, alignment: .center)

            // Today's round
            Text(golfer.todayScore ?? "--")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 32, alignment: .center)

            // Thru
            Text(golfer.thru ?? "--")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 46, alignment: .center)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            isLeader
                ? GolfColors.augustaYellow.opacity(0.15)
                : (isEven ? Color.clear : GolfColors.rowAlt.opacity(0.5))
        )
    }

    private var cutLineRow: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(GolfColors.pinRed.opacity(0.5))
                .frame(height: 1)
            Text("PROJECTED CUT")
                .font(.system(size: 7, weight: .heavy))
                .foregroundColor(GolfColors.pinRed.opacity(0.7))
            if let cut = entry.cutLine {
                Text(cut == 0 ? "E" : (cut > 0 ? "+\(cut)" : "\(cut)"))
                    .font(.system(size: 7, weight: .heavy, design: .rounded))
                    .foregroundColor(GolfColors.pinRed.opacity(0.7))
            }
            Rectangle()
                .fill(GolfColors.pinRed.opacity(0.5))
                .frame(height: 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    // MARK: - Shared Components

    private var fairwayBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                GolfColors.headerGreen,
                GolfColors.fairwayLight,
                GolfColors.fairwayDark
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func tournamentHeader(compact: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .font(.system(size: compact ? 9 : 10, weight: .bold))
                    .foregroundColor(GolfColors.pinRed)
                Text("PGA TOUR")
                    .font(.system(size: compact ? 8 : 9, weight: .heavy))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                if entry.state == "in" {
                    liveIndicator(small: compact)
                }

                Text(entry.roundDisplay)
                    .font(.system(size: compact ? 9 : 10, weight: .heavy))
                    .foregroundColor(GolfColors.augustaYellow)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(GolfColors.headerGreen.opacity(0.5))
                    .cornerRadius(3)
            }
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.top, compact ? 6 : 8)

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.tournamentName)
                        .font(.system(size: compact ? 13 : 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if !compact {
                        HStack(spacing: 4) {
                            Text(entry.courseName)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.7))
                            if !entry.location.isEmpty {
                                Text("|")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.4))
                                Text(entry.location)
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .lineLimit(1)
                    }
                }
                Spacer()

                if let detail = entry.statusDetail, !compact {
                    Text(detail)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.bottom, compact ? 4 : 6)
        }
    }

    private func leaderboardColumnHeader(compact: Bool) -> some View {
        HStack(spacing: 0) {
            Text("POS")
                .frame(width: compact ? 28 : 32, alignment: .center)
            Text("PLAYER")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, compact ? 4 : 2)
            Text("TOT")
                .frame(width: compact ? 34 : 38, alignment: .center)
            Text("TODAY")
                .frame(width: compact ? 28 : 32, alignment: .center)
            Text("THRU")
                .frame(width: compact ? 42 : 46, alignment: .center)
        }
        .font(.system(size: 7, weight: .heavy))
        .foregroundColor(GolfColors.headerGreen)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(GolfColors.headerGreen.opacity(0.08))
    }

    private func liveIndicator(small: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(.green)
                .frame(width: small ? 5 : 6, height: small ? 5 : 6)
            Text("LIVE")
                .font(.system(size: small ? 7 : 8, weight: .heavy))
                .foregroundColor(.green)
        }
    }

    private func countdownText(to date: Date) -> some View {
        let diff = date.timeIntervalSince(entry.date)
        let days = Int(diff) / 86400
        let hours = (Int(diff) % 86400) / 3600

        return Group {
            if diff <= 0 {
                Text("UNDERWAY")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.green)
            } else if days > 0 {
                Text("\(days)d \(hours)h")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(GolfColors.augustaYellow)
            } else {
                let mins = (Int(diff) % 3600) / 60
                Text("\(hours)h \(mins)m")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(GolfColors.augustaYellow)
            }
        }
    }

    // MARK: - Helpers

    private func scoreColor(_ value: Int) -> Color {
        if value < 0 { return GolfColors.scoreUnder }
        if value > 0 { return GolfColors.scoreOver }
        return GolfColors.scoreEven
    }

    private func abbreviateName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        guard parts.count >= 2 else { return name }
        let first = parts.first ?? ""
        let last = parts.last ?? ""
        return "\(first.prefix(1)). \(last)"
    }
}
