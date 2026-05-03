import WidgetKit
import SwiftUI

// MARK: - F1 Widget

struct F1Widget: Widget {
    let kind = "F1Widget_v1"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: F1Provider()) { entry in
            F1WidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Formula 1")
        .description("Live race positions, session schedule, and results")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry

struct F1Entry: TimelineEntry {
    let date: Date
    let raceName: String
    let circuitName: String
    let circuitCity: String
    let circuitCountry: String
    let sessions: [F1Session]
    let drivers: [F1Driver]
    let raceState: F1RaceState
    let activeSessionType: String?
    let flagURL: String?
}

enum F1RaceState: String {
    case preWeekend
    case preRace
    case live
    case postRace
    case postWeekend
}

struct F1Session: Identifiable {
    let id: String
    let type: String
    let state: String
    let date: Date?
    let detail: String?
    let isRace: Bool
    let isSprint: Bool
}

struct F1Driver: Identifiable {
    let id: String
    let position: Int
    let name: String
    let shortName: String
    let teamName: String
    let teamColor: Color
    let flagURL: String?
    let isWinner: Bool
}

// MARK: - Team Colors

private enum F1TeamColor {
    static func color(for teamName: String) -> Color {
        let lower = teamName.lowercased()
        if lower.contains("red bull") && !lower.contains("rb ") && !lower.contains("vcarb") && !lower.contains("visa") {
            return Color(red: 0x36/255, green: 0x71/255, blue: 0xC6/255)
        }
        if lower.contains("ferrari") {
            return Color(red: 0xE8/255, green: 0x00/255, blue: 0x2D/255)
        }
        if lower.contains("mercedes") {
            return Color(red: 0x27/255, green: 0xF4/255, blue: 0xD2/255)
        }
        if lower.contains("mclaren") {
            return Color(red: 0xFF/255, green: 0x80/255, blue: 0x00/255)
        }
        if lower.contains("aston") {
            return Color(red: 0x22/255, green: 0x99/255, blue: 0x71/255)
        }
        if lower.contains("alpine") {
            return Color(red: 0xFF/255, green: 0x87/255, blue: 0xBC/255)
        }
        if lower.contains("williams") {
            return Color(red: 0x64/255, green: 0xC4/255, blue: 0xFF/255)
        }
        if lower.contains("rb ") || lower.contains("vcarb") || lower.contains("visa") || lower.contains("racing bulls") {
            return Color(red: 0x66/255, green: 0x92/255, blue: 0xFF/255)
        }
        if lower.contains("sauber") || lower.contains("kick") || lower.contains("stake") {
            return Color(red: 0x52/255, green: 0xE2/255, blue: 0x52/255)
        }
        if lower.contains("haas") {
            return Color(red: 0xB6/255, green: 0xBA/255, blue: 0xBD/255)
        }
        return Color(white: 0.5)
    }

    /// Fallback: map driver short name to team color when team name is unavailable
    static func colorByDriver(_ shortName: String) -> Color {
        let sn = shortName.lowercased()
        // Red Bull
        if sn.contains("verstappen") || sn.contains("perez") || sn.contains("pérez") { return color(for: "Red Bull") }
        // Ferrari
        if sn.contains("leclerc") || sn.contains("sainz") || sn.contains("hamilton") || sn.contains("bearman") { return color(for: "Ferrari") }
        // Mercedes
        if sn.contains("russell") || sn.contains("antonelli") { return color(for: "Mercedes") }
        // McLaren
        if sn.contains("norris") || sn.contains("piastri") { return color(for: "McLaren") }
        // Aston Martin
        if sn.contains("alonso") || sn.contains("stroll") { return color(for: "Aston Martin") }
        // Alpine
        if sn.contains("gasly") || sn.contains("doohan") || sn.contains("ocon") { return color(for: "Alpine") }
        // Williams
        if sn.contains("albon") || sn.contains("colapinto") || sn.contains("sainz") { return color(for: "Williams") }
        // RB / VCARB
        if sn.contains("tsunoda") || sn.contains("lawson") || sn.contains("ricciardo") || sn.contains("hadjar") { return color(for: "RB VCARB") }
        // Sauber
        if sn.contains("bottas") || sn.contains("zhou") || sn.contains("hulkenberg") || sn.contains("bortoleto") { return color(for: "Sauber") }
        // Haas
        if sn.contains("magnussen") || sn.contains("ocon") { return color(for: "Haas") }
        return Color(white: 0.5)
    }
}

// MARK: - Provider

struct F1Provider: TimelineProvider {
    func placeholder(in context: Context) -> F1Entry { Self.sampleEntry }

    func getSnapshot(in context: Context, completion: @escaping (F1Entry) -> Void) {
        fetchF1 { completion($0 ?? Self.sampleEntry) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<F1Entry>) -> Void) {
        // Ensure completion is called exactly once — WidgetKit preempts the
        // extension aggressively, so guarantee a fallback timeline ships.
        let lock = NSLock()
        var fired = false
        func fire(_ timeline: Timeline<F1Entry>) {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            lock.unlock()
            completion(timeline)
        }
        let wrappedCompletion: (Timeline<F1Entry>) -> Void = fire
        DispatchQueue.global().asyncAfter(deadline: .now() + 4.5) {
            fire(Timeline(entries: [self.placeholder(in: context)], policy: .after(Date().addingTimeInterval(60))))
        }

        fetchF1 { entry in
            let final = entry ?? Self.sampleEntry
            let hasLive = final.raceState == .live
            let refresh = Calendar.current.date(byAdding: .minute, value: hasLive ? 1 : 15, to: Date())!
            wrappedCompletion(Timeline(entries: [final], policy: .after(refresh)))
        }
    }

    private func fetchF1(completion: @escaping (F1Entry?) -> Void) {
        let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/racing/f1/scoreboard")!

        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let events = json["events"] as? [[String: Any]],
                  let event = events.first else {
                completion(nil)
                return
            }

            let raceName = event["shortName"] as? String ?? event["name"] as? String ?? "Grand Prix"
            let circuit = event["circuit"] as? [String: Any] ?? [:]
            let circuitName = circuit["fullName"] as? String ?? ""
            let address = circuit["address"] as? [String: Any] ?? [:]
            let city = address["city"] as? String ?? ""
            let country = address["country"] as? String ?? ""

            var sessions: [F1Session] = []
            var drivers: [F1Driver] = []
            var raceState: F1RaceState = .preWeekend
            var activeSessionType: String?

            let competitions = event["competitions"] as? [[String: Any]] ?? []
            for comp in competitions {
                let typeDict = comp["type"] as? [String: Any] ?? [:]
                let typeAbbr = typeDict["abbreviation"] as? String ?? "?"
                let statusDict = comp["status"] as? [String: Any] ?? [:]
                let statusType = statusDict["type"] as? [String: Any] ?? [:]
                let state = statusType["state"] as? String ?? "pre"
                let detail = statusType["detail"] as? String

                let dateStr = comp["date"] as? String ?? comp["startDate"] as? String ?? ""
                let sessionDate = Self.parseDate(dateStr)

                let isRace = typeAbbr == "Race"
                let isSprint = typeAbbr.lowercased().contains("sprint")

                sessions.append(F1Session(
                    id: typeAbbr,
                    type: typeAbbr,
                    state: state,
                    date: sessionDate,
                    detail: detail,
                    isRace: isRace,
                    isSprint: isSprint
                ))

                // Parse competitors from any session that has results or is live
                if state == "in" || state == "post" {
                    let competitors = comp["competitors"] as? [[String: Any]] ?? []

                    // For "in" sessions, always grab drivers; for "post", prefer the race
                    if state == "in" || (isRace && state == "post") || drivers.isEmpty {
                        var parsed: [F1Driver] = []
                        for c in competitors {
                            let order = c["order"] as? Int ?? 99
                            let athlete = c["athlete"] as? [String: Any] ?? [:]
                            let displayName = athlete["displayName"] as? String ?? "?"
                            let shortName = athlete["shortName"] as? String ?? "?"
                            let flag = athlete["flag"] as? [String: Any]
                            let flagHref = flag?["href"] as? String
                            let winner = c["winner"] as? Bool ?? false

                            let teamDict = c["team"] as? [String: Any] ?? [:]
                            let teamDisplayName = teamDict["displayName"] as? String
                                ?? teamDict["name"] as? String ?? ""

                            let teamColor: Color
                            if !teamDisplayName.isEmpty {
                                teamColor = F1TeamColor.color(for: teamDisplayName)
                            } else {
                                teamColor = F1TeamColor.colorByDriver(shortName)
                            }

                            parsed.append(F1Driver(
                                id: c["id"] as? String ?? "\(order)",
                                position: order,
                                name: displayName,
                                shortName: shortName,
                                teamName: teamDisplayName,
                                teamColor: teamColor,
                                flagURL: flagHref,
                                isWinner: winner
                            ))
                        }
                        parsed.sort { $0.position < $1.position }
                        drivers = parsed
                    }

                    if state == "in" {
                        activeSessionType = typeAbbr
                    }
                }
            }

            // Determine race state
            let hasLive = sessions.contains { $0.state == "in" }
            let allPost = !sessions.isEmpty && sessions.allSatisfy { $0.state == "post" }
            let raceSession = sessions.first { $0.isRace }

            if hasLive {
                raceState = .live
            } else if raceSession?.state == "post" || allPost {
                raceState = .postRace
            } else if raceSession?.state == "pre" && sessions.contains(where: { $0.state == "post" }) {
                raceState = .preRace
            } else {
                raceState = .preWeekend
            }

            let entry = F1Entry(
                date: Date(),
                raceName: raceName,
                circuitName: circuitName,
                circuitCity: city,
                circuitCountry: country,
                sessions: sessions,
                drivers: drivers,
                raceState: raceState,
                activeSessionType: activeSessionType,
                flagURL: nil
            )
            completion(entry)
        }.resume()
    }

    private static func parseDate(_ s: String) -> Date? {
        for fmt in Self.dateFormats {
            let df = DateFormatter()
            df.dateFormat = fmt
            df.timeZone = TimeZone(identifier: "UTC")
            if let d = df.date(from: s) { return d }
        }
        return Self.isoFormatter.date(from: s)
    }

    private static let dateFormats = [
        "yyyy-MM-dd'T'HH:mm'Z'",
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "yyyy-MM-dd'T'HH:mmZ",
        "yyyy-MM-dd'T'HH:mm:ssZ"
    ]

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    static let sampleEntry: F1Entry = {
        let sampleDrivers: [F1Driver] = [
            F1Driver(id: "1", position: 1, name: "Max Verstappen", shortName: "M. Verstappen", teamName: "Red Bull Racing", teamColor: F1TeamColor.color(for: "Red Bull"), flagURL: nil, isWinner: true),
            F1Driver(id: "2", position: 2, name: "Lando Norris", shortName: "L. Norris", teamName: "McLaren", teamColor: F1TeamColor.color(for: "McLaren"), flagURL: nil, isWinner: false),
            F1Driver(id: "3", position: 3, name: "Charles Leclerc", shortName: "C. Leclerc", teamName: "Ferrari", teamColor: F1TeamColor.color(for: "Ferrari"), flagURL: nil, isWinner: false),
            F1Driver(id: "4", position: 4, name: "Lewis Hamilton", shortName: "L. Hamilton", teamName: "Ferrari", teamColor: F1TeamColor.color(for: "Ferrari"), flagURL: nil, isWinner: false),
            F1Driver(id: "5", position: 5, name: "Carlos Sainz", shortName: "C. Sainz", teamName: "Williams", teamColor: F1TeamColor.color(for: "Williams"), flagURL: nil, isWinner: false),
            F1Driver(id: "6", position: 6, name: "Oscar Piastri", shortName: "O. Piastri", teamName: "McLaren", teamColor: F1TeamColor.color(for: "McLaren"), flagURL: nil, isWinner: false),
            F1Driver(id: "7", position: 7, name: "George Russell", shortName: "G. Russell", teamName: "Mercedes", teamColor: F1TeamColor.color(for: "Mercedes"), flagURL: nil, isWinner: false),
            F1Driver(id: "8", position: 8, name: "Fernando Alonso", shortName: "F. Alonso", teamName: "Aston Martin", teamColor: F1TeamColor.color(for: "Aston Martin"), flagURL: nil, isWinner: false),
            F1Driver(id: "9", position: 9, name: "Pierre Gasly", shortName: "P. Gasly", teamName: "Alpine", teamColor: F1TeamColor.color(for: "Alpine"), flagURL: nil, isWinner: false),
            F1Driver(id: "10", position: 10, name: "Yuki Tsunoda", shortName: "Y. Tsunoda", teamName: "RB", teamColor: F1TeamColor.color(for: "RB VCARB"), flagURL: nil, isWinner: false),
        ]

        return F1Entry(
            date: Date(),
            raceName: "Japanese Grand Prix",
            circuitName: "Suzuka International Racing Course",
            circuitCity: "Suzuka",
            circuitCountry: "Japan",
            sessions: [
                F1Session(id: "FP1", type: "FP1", state: "post", date: Date().addingTimeInterval(-86400), detail: "Complete", isRace: false, isSprint: false),
                F1Session(id: "Qual", type: "Qual", state: "post", date: Date().addingTimeInterval(-3600), detail: "Complete", isRace: false, isSprint: false),
                F1Session(id: "Race", type: "Race", state: "in", date: Date().addingTimeInterval(-1800), detail: "Lap 42/53", isRace: true, isSprint: false),
            ],
            drivers: sampleDrivers,
            raceState: .live,
            activeSessionType: "Race",
            flagURL: nil
        )
    }()
}

// MARK: - Widget View

struct F1WidgetView: View {
    let entry: F1Entry
    @Environment(\.widgetFamily) var family

    private static let sessionTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E h:mm a"
        return f
    }()

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    // Dark background for F1 timing tower look
    private static let towerBG = Color(red: 0.08, green: 0.08, blue: 0.10)
    private static let towerRowBG = Color(white: 0.14)

    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        case .systemLarge: largeView
        default: mediumView
        }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        ZStack {
            Self.towerBG

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 4) {
                    Text("F1")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.red)
                    Spacer()
                    if entry.raceState == .live {
                        liveIndicator
                    }
                }
                .padding(.bottom, 2)

                Text(entry.raceName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Session info line
                if let activeType = entry.activeSessionType {
                    Text(sessionLabel(activeType))
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.gray)
                        .padding(.bottom, 3)
                } else if entry.raceState == .postRace {
                    Text("FINAL CLASSIFICATION")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundColor(.gray)
                        .padding(.bottom, 3)
                } else if let next = entry.sessions.first(where: { $0.state == "pre" }) {
                    HStack(spacing: 3) {
                        Text(sessionLabel(next.type))
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(.gray)
                        if let d = next.date {
                            Text(Self.shortTimeFormatter.string(from: d))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(Color(white: 0.5))
                        }
                    }
                    .padding(.bottom, 3)
                } else {
                    Spacer().frame(height: 3)
                }

                // Position tower -- show top 5 in small
                if !entry.drivers.isEmpty {
                    VStack(spacing: 1.5) {
                        ForEach(Array(entry.drivers.prefix(5).enumerated()), id: \.element.id) { idx, driver in
                            smallPositionBar(driver: driver, isLeader: idx == 0)
                        }
                    }
                } else if let next = entry.sessions.first(where: { $0.state == "pre" }) {
                    Spacer()
                    countdownBlock(next)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
        }
    }

    private func smallPositionBar(driver: F1Driver, isLeader: Bool) -> some View {
        HStack(spacing: 0) {
            // Position number
            Text("\(driver.position)")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 16, alignment: .center)

            // Team color strip
            Rectangle()
                .fill(driver.teamColor)
                .frame(width: 3)

            // Driver name
            Text(abbreviatedName(driver.shortName))
                .font(.system(size: 9, weight: isLeader ? .heavy : .semibold, design: .monospaced))
                .foregroundColor(isLeader ? .white : Color(white: 0.85))
                .lineLimit(1)
                .padding(.leading, 4)

            Spacer(minLength: 0)

            if driver.isWinner {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.yellow)
            }
        }
        .frame(height: 16)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(isLeader
                    ? LinearGradient(colors: [driver.teamColor.opacity(0.35), Self.towerRowBG], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Self.towerRowBG, Self.towerRowBG], startPoint: .leading, endPoint: .trailing)
                )
        )
    }

    // MARK: - Medium Widget

    private var mediumView: some View {
        ZStack {
            Self.towerBG

            HStack(spacing: 0) {
                // Left: Race info + session schedule
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("F1")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundColor(.red)
                        if entry.raceState == .live {
                            liveIndicator
                        }
                    }

                    Text(entry.raceName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    Text("\(entry.circuitCity), \(entry.circuitCountry)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(white: 0.5))

                    Spacer(minLength: 2)

                    // Session schedule mini-list
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(entry.sessions) { session in
                            mediumSessionRow(session)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.vertical, 10)

                // Thin separator
                Rectangle()
                    .fill(Color(white: 0.25))
                    .frame(width: 1)
                    .padding(.vertical, 8)

                // Right: Position tower
                VStack(alignment: .leading, spacing: 0) {
                    if !entry.drivers.isEmpty {
                        // Session header
                        HStack(spacing: 3) {
                            if let activeType = entry.activeSessionType {
                                Text(sessionLabel(activeType).uppercased())
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.white)
                            } else if entry.raceState == .postRace {
                                Text("CLASSIFICATION")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.white)
                            } else {
                                Text("GRID")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .padding(.bottom, 3)

                        VStack(spacing: 1.5) {
                            ForEach(Array(entry.drivers.prefix(8).enumerated()), id: \.element.id) { idx, driver in
                                mediumPositionBar(driver: driver, isLeader: idx == 0)
                            }
                        }
                    } else {
                        // No drivers yet -- show countdown
                        Spacer()
                        if let next = entry.sessions.first(where: { $0.state == "pre" }) {
                            countdownBlock(next)
                        }
                        Spacer()
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
        }
    }

    private func mediumPositionBar(driver: F1Driver, isLeader: Bool) -> some View {
        HStack(spacing: 0) {
            // Position
            Text("\(driver.position)")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundColor(positionTextColor(driver.position))
                .frame(width: 16, alignment: .center)

            // Team color strip
            RoundedRectangle(cornerRadius: 1)
                .fill(driver.teamColor)
                .frame(width: 3, height: 12)

            // Driver surname
            Text(surname(driver.shortName))
                .font(.system(size: 9, weight: isLeader ? .heavy : .medium, design: .monospaced))
                .foregroundColor(isLeader ? .white : Color(white: 0.82))
                .lineLimit(1)
                .padding(.leading, 4)

            Spacer(minLength: 0)

            if driver.isWinner {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.yellow)
                    .padding(.trailing, 2)
            }
        }
        .frame(height: 15)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(isLeader
                    ? LinearGradient(colors: [driver.teamColor.opacity(0.3), Self.towerRowBG], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Self.towerRowBG, Self.towerRowBG], startPoint: .leading, endPoint: .trailing)
                )
        )
    }

    private func mediumSessionRow(_ session: F1Session) -> some View {
        HStack(spacing: 4) {
            Text(sessionShortLabel(session.type))
                .font(.system(size: 8, weight: session.isRace ? .black : .semibold, design: .monospaced))
                .foregroundColor(session.isRace ? .red : Color(white: 0.7))
                .frame(width: 30, alignment: .leading)

            if session.state == "post" {
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.green)
            } else if session.state == "in" {
                Circle().fill(.green).frame(width: 4, height: 4)
                Text("LIVE")
                    .font(.system(size: 6, weight: .black))
                    .foregroundColor(.green)
            } else if let date = session.date {
                Text(Self.shortTimeFormatter.string(from: date))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Color(white: 0.45))
            }
        }
    }

    // MARK: - Large Widget

    private var largeView: some View {
        ZStack {
            Self.towerBG

            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text("F1")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(.red)
                            Text(entry.raceName.uppercased())
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        Text("\(entry.circuitName)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(white: 0.5))
                            .lineLimit(1)
                        Text("\(entry.circuitCity), \(entry.circuitCountry)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(white: 0.4))
                    }

                    Spacer()

                    if entry.raceState == .live {
                        liveIndicator
                    } else if let next = entry.sessions.first(where: { $0.state == "pre" }) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("NEXT")
                                .font(.system(size: 7, weight: .black))
                                .foregroundColor(Color(white: 0.5))
                            Text(sessionLabel(next.type))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                            if let d = next.date {
                                Text(Self.sessionTimeFormatter.string(from: d))
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(Color(white: 0.45))
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

                // Session row (horizontal)
                HStack(spacing: 0) {
                    ForEach(entry.sessions) { session in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(sessionDotColor(session))
                                .frame(width: 5, height: 5)
                            Text(sessionShortLabel(session.type))
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(sessionLabelColor(session))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

                // Separator
                Rectangle()
                    .fill(Color(white: 0.22))
                    .frame(height: 1)
                    .padding(.horizontal, 10)

                // Position tower header
                HStack(spacing: 0) {
                    Text("POS")
                        .frame(width: 28, alignment: .center)
                    Text("")
                        .frame(width: 4)
                    Text("DRIVER")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 6)
                    if entry.raceState == .postRace || entry.raceState == .live {
                        Text(entry.raceState == .postRace ? "RESULT" : "STATUS")
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(white: 0.4))
                .padding(.horizontal, 14)
                .padding(.vertical, 4)

                // Position tower -- up to 15 in large
                if !entry.drivers.isEmpty {
                    VStack(spacing: 1) {
                        ForEach(Array(entry.drivers.prefix(15).enumerated()), id: \.element.id) { idx, driver in
                            largePositionBar(driver: driver, isLeader: idx == 0)
                        }
                    }
                    .padding(.horizontal, 10)
                } else {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "flag.checkered")
                                .font(.system(size: 24))
                                .foregroundColor(Color(white: 0.3))
                            Text("Awaiting session data")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(white: 0.4))
                        }
                        Spacer()
                    }
                    Spacer()
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func largePositionBar(driver: F1Driver, isLeader: Bool) -> some View {
        HStack(spacing: 0) {
            // Position number
            ZStack {
                if isLeader {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(driver.teamColor)
                        .frame(width: 24, height: 18)
                }
                Text("\(driver.position)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(isLeader ? .white : positionTextColor(driver.position))
            }
            .frame(width: 28, alignment: .center)

            // Team color bar
            RoundedRectangle(cornerRadius: 1)
                .fill(driver.teamColor)
                .frame(width: 4, height: 16)

            // Driver name
            Text(surname(driver.shortName).uppercased())
                .font(.system(size: 11, weight: isLeader ? .heavy : .medium, design: .monospaced))
                .foregroundColor(isLeader ? .white : Color(white: 0.85))
                .lineLimit(1)
                .padding(.leading, 6)

            Spacer(minLength: 0)

            // Winner trophy or position status
            if driver.isWinner {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.yellow)
                    .padding(.trailing, 4)
            } else if driver.position <= 3 && entry.raceState == .postRace {
                Image(systemName: "medal.fill")
                    .font(.system(size: 8))
                    .foregroundColor(podiumColor(driver.position))
                    .padding(.trailing, 4)
            } else if driver.position <= 10 {
                Text("P\(driver.position)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.trailing, 4)
            }
        }
        .frame(height: 19)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    isLeader
                        ? LinearGradient(colors: [driver.teamColor.opacity(0.35), Self.towerRowBG.opacity(0.95)], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [Self.towerRowBG, Self.towerRowBG.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                )
        )
    }

    // MARK: - Shared Components

    private var liveIndicator: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(.green)
                .frame(width: 5, height: 5)
            Text("LIVE")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundColor(.green)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color.green.opacity(0.15))
        )
    }

    private func countdownBlock(_ session: F1Session) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sessionLabel(session.type))
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(session.isRace ? .red : .orange)

            if let date = session.date {
                let diff = date.timeIntervalSince(entry.date)
                if diff > 0 {
                    let days = Int(diff) / 86400
                    let hours = (Int(diff) % 86400) / 3600
                    let mins = (Int(diff) % 3600) / 60
                    if days > 0 {
                        Text("\(days)d \(hours)h")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    } else {
                        Text("\(hours)h \(mins)m")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                } else {
                    Text("NOW")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.green)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sessionLabel(_ type: String) -> String {
        switch type {
        case "FP1": return "Practice 1"
        case "FP2": return "Practice 2"
        case "FP3": return "Practice 3"
        case "Qual": return "Qualifying"
        case "Race": return "Race"
        default:
            if type.lowercased().contains("sprint") { return "Sprint" }
            return type
        }
    }

    private func sessionShortLabel(_ type: String) -> String {
        switch type {
        case "FP1": return "FP1"
        case "FP2": return "FP2"
        case "FP3": return "FP3"
        case "Qual": return "Q"
        case "Race": return "R"
        default:
            if type.lowercased().contains("sprint") { return "SP" }
            return type
        }
    }

    private func sessionDotColor(_ session: F1Session) -> Color {
        if session.state == "in" { return .green }
        if session.state == "post" { return Color(white: 0.5) }
        return Color(white: 0.3)
    }

    private func sessionLabelColor(_ session: F1Session) -> Color {
        if session.state == "in" { return .green }
        if session.state == "post" { return Color(white: 0.55) }
        if session.isRace { return .red }
        return Color(white: 0.5)
    }

    private func positionTextColor(_ pos: Int) -> Color {
        switch pos {
        case 1: return .yellow
        case 2: return Color(white: 0.85)
        case 3: return .orange
        default: return Color(white: 0.65)
        }
    }

    private func podiumColor(_ pos: Int) -> Color {
        switch pos {
        case 1: return .yellow
        case 2: return Color(white: 0.8)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return Color(white: 0.5)
        }
    }

    /// Extract surname from "L. Hamilton" -> "HAMILTON" or "Hamilton"
    private func surname(_ shortName: String) -> String {
        let parts = shortName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts.dropFirst().joined(separator: " "))
        }
        return shortName
    }

    /// Abbreviate to fit small widget: "M. Verstappen" -> "VER"
    private func abbreviatedName(_ shortName: String) -> String {
        let s = surname(shortName).uppercased()
        if s.count >= 3 {
            return String(s.prefix(3))
        }
        return s
    }
}
