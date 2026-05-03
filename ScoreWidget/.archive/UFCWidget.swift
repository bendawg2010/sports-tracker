import WidgetKit
import SwiftUI

// MARK: - UFC Widget

struct UFCWidget: Widget {
    let kind = "UFCWidget_v1"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UFCProvider()) { entry in
            UFCWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("UFC")
        .description("Live UFC fight data on the octagon")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Color Helper

private enum UFCColorHelper {
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

    static let canvasBg = color(hex: "1A1A1A")
    static let octagonMat = color(hex: "2A2A2A")
}

// MARK: - Models

struct UFCFighter: Identifiable {
    let id: String
    let name: String
    let shortName: String
    let record: String?
    let corner: String
    let flagURL: String?
    let isWinner: Bool
    let score: String?
    let sigStrikes: String?
}

struct UFCFight: Identifiable {
    let id: String
    let fighter1: UFCFighter
    let fighter2: UFCFighter
    let state: String
    let currentRound: Int?
    let totalRounds: Int?
    let displayClock: String?
    let method: String?
    let weightClass: String?
    let isMainEvent: Bool
    let cardSegment: String?
    let startDate: Date?
    let detail: String?

    var isLive: Bool { state == "in" }
    var isFinished: Bool { state == "post" }
    var isPre: Bool { state == "pre" }

    var interestScore: Int {
        var s = 0
        if isLive { s += 100 }
        if isMainEvent { s += 50 }
        if isPre, let d = startDate, d.timeIntervalSinceNow < 3600 { s += 30 }
        if isFinished { s += 10 }
        if cardSegment == "Main Card" { s += 5 }
        return s
    }

    var shortMethod: String? {
        guard let m = method else { return nil }
        let lower = m.lowercased()
        if lower.contains("ko") || lower.contains("tko") { return "KO/TKO" }
        if lower.contains("submission") || lower.contains("sub") { return "SUB" }
        if lower.contains("unanimous") { return "UD" }
        if lower.contains("split") { return "SD" }
        if lower.contains("majority") { return "MD" }
        if lower.contains("decision") { return "DEC" }
        if lower.contains("draw") { return "DRAW" }
        if lower.contains("no contest") || lower.contains("nc") { return "NC" }
        return m
    }

    var dramaticMethod: String? {
        guard let m = method else { return nil }
        let lower = m.lowercased()
        if lower.contains("ko") || lower.contains("tko") { return "KNOCKOUT" }
        if lower.contains("submission") || lower.contains("sub") { return "SUBMISSION" }
        if lower.contains("unanimous") { return "UNANIMOUS DECISION" }
        if lower.contains("split") { return "SPLIT DECISION" }
        if lower.contains("decision") { return "DECISION" }
        return shortMethod
    }

    var fightLabel: String {
        if isMainEvent { return "MAIN EVENT" }
        if cardSegment == "Main Card" { return "MAIN CARD" }
        if let cs = cardSegment { return cs.uppercased() }
        return ""
    }
}

struct UFCEvent: Identifiable {
    let id: String
    let name: String
    let shortName: String
    let venue: String?
    let city: String?
    let date: Date?
    let fights: [UFCFight]

    var featuredFight: UFCFight? {
        fights.sorted { $0.interestScore > $1.interestScore }.first
    }

    var hasLive: Bool { fights.contains { $0.isLive } }
}

// MARK: - Entry

struct UFCEntry: TimelineEntry {
    let date: Date
    let event: UFCEvent?
}

// MARK: - Provider

struct UFCProvider: TimelineProvider {
    func placeholder(in context: Context) -> UFCEntry { sampleEntry }

    func getSnapshot(in context: Context, completion: @escaping (UFCEntry) -> Void) {
        fetchEvent { completion($0 ?? sampleEntry) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UFCEntry>) -> Void) {
        // Ensure completion is called exactly once — WidgetKit preempts the
        // extension aggressively, so guarantee a fallback timeline ships.
        let lock = NSLock()
        var fired = false
        func fire(_ timeline: Timeline<UFCEntry>) {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            lock.unlock()
            completion(timeline)
        }
        let wrappedCompletion: (Timeline<UFCEntry>) -> Void = fire
        DispatchQueue.global().asyncAfter(deadline: .now() + 4.5) {
            fire(Timeline(entries: [self.placeholder(in: context)], policy: .after(Date().addingTimeInterval(60))))
        }

        fetchEvent { entry in
            let final = entry ?? sampleEntry
            let hasLive = final.event?.hasLive == true
            let refresh = Calendar.current.date(byAdding: .minute, value: hasLive ? 1 : 15, to: Date())!
            wrappedCompletion(Timeline(entries: [final], policy: .after(refresh)))
        }
    }

    private func fetchEvent(completion: @escaping (UFCEntry?) -> Void) {
        guard let league = SportLeague.find("ufc") else { completion(nil); return }
        let urlString = "\(league.scoreboardURL)?limit=50"
        guard let url = URL(string: urlString) else { completion(nil); return }

        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let events = json["events"] as? [[String: Any]],
                  let event = events.first else { completion(nil); return }

            let parsed = parseEvent(event)
            DispatchQueue.main.async {
                completion(UFCEntry(date: Date(), event: parsed))
            }
        }.resume()
    }

    private func parseEvent(_ event: [String: Any]) -> UFCEvent {
        let id = event["id"] as? String ?? "0"
        let name = event["name"] as? String ?? "UFC Event"
        let shortName = event["shortName"] as? String ?? name
        let dateStr = event["date"] as? String ?? ""
        let eventDate = parseDate(dateStr)

        var venue: String?
        var city: String?

        let competitions = event["competitions"] as? [[String: Any]] ?? []
        var fights: [UFCFight] = []

        for (index, comp) in competitions.enumerated() {
            if index == 0 {
                if let v = comp["venue"] as? [String: Any] {
                    venue = v["fullName"] as? String
                    let addr = v["address"] as? [String: Any]
                    let c = addr?["city"] as? String
                    let s = addr?["state"] as? String
                    if let c = c, let s = s { city = "\(c), \(s)" }
                    else if let c = c { city = c }
                }
            }

            guard let competitors = comp["competitors"] as? [[String: Any]],
                  competitors.count >= 2,
                  let statusDict = comp["status"] as? [String: Any],
                  let statusType = statusDict["type"] as? [String: Any],
                  let state = statusType["state"] as? String else { continue }

            let detail = statusType["detail"] as? String
            let shortDetail = statusType["shortDetail"] as? String
            let displayClock = statusDict["displayClock"] as? String
            let period = statusDict["period"] as? Int

            func parseFighter(_ c: [String: Any], corner: String) -> UFCFighter {
                let athlete = c["athlete"] as? [String: Any] ?? [:]
                let name = athlete["displayName"] as? String ?? "Fighter"
                let shortName = athlete["shortName"] as? String ?? name.components(separatedBy: " ").last ?? name
                let winner = c["winner"] as? Bool ?? false
                let score = c["score"] as? String

                var record: String?
                if let records = c["records"] as? [[String: Any]] {
                    for r in records {
                        if let summary = r["summary"] as? String { record = summary; break }
                    }
                }
                if record == nil { record = athlete["record"] as? String }

                let flagInfo = athlete["flag"] as? [String: Any]
                let flagURL = flagInfo?["href"] as? String

                var sigStrikes: String?
                if let stats = c["statistics"] as? [[String: Any]] {
                    for stat in stats {
                        if let statName = stat["name"] as? String,
                           statName == "significantStrikes" {
                            sigStrikes = stat["displayValue"] as? String
                            break
                        }
                    }
                }

                return UFCFighter(
                    id: c["id"] as? String ?? corner,
                    name: name, shortName: shortName,
                    record: record, corner: corner,
                    flagURL: flagURL, isWinner: winner, score: score,
                    sigStrikes: sigStrikes
                )
            }

            let fighter1 = parseFighter(competitors[0], corner: "red")
            let fighter2 = parseFighter(competitors[1], corner: "blue")

            var weightClass: String?
            if let typeDict = comp["type"] as? [String: Any] {
                weightClass = typeDict["text"] as? String ?? typeDict["abbreviation"] as? String
            }

            var cardSegment: String?
            var isMainEvent = false
            if let notes = comp["notes"] as? [[String: Any]] {
                for note in notes {
                    let headline = note["headline"] as? String ?? ""
                    let lower = headline.lowercased()
                    if lower.contains("main card") { cardSegment = "Main Card" }
                    else if lower.contains("prelim") { cardSegment = "Prelims" }
                    else if lower.contains("early") { cardSegment = "Early Prelims" }
                    if lower.contains("main event") { isMainEvent = true }
                }
            }
            if index == 0 { isMainEvent = true }

            var method: String?
            if state == "post" { method = detail ?? shortDetail }

            // Try to extract total rounds
            var totalRounds: Int? = nil
            if isMainEvent { totalRounds = 5 }
            else { totalRounds = 3 }

            let compDateStr = comp["date"] as? String ?? comp["startDate"] as? String ?? ""
            let fightDate = parseDate(compDateStr) ?? eventDate

            fights.append(UFCFight(
                id: comp["id"] as? String ?? "\(index)",
                fighter1: fighter1, fighter2: fighter2,
                state: state, currentRound: period, totalRounds: totalRounds,
                displayClock: displayClock, method: method,
                weightClass: weightClass, isMainEvent: isMainEvent,
                cardSegment: cardSegment, startDate: fightDate, detail: detail
            ))
        }

        return UFCEvent(
            id: id, name: name, shortName: shortName,
            venue: venue, city: city, date: eventDate, fights: fights
        )
    }

    private func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    private var sampleEntry: UFCEntry {
        UFCEntry(
            date: Date(),
            event: UFCEvent(
                id: "sample", name: "UFC 300", shortName: "UFC 300",
                venue: "T-Mobile Arena", city: "Las Vegas, NV", date: Date(),
                fights: [
                    UFCFight(
                        id: "f1",
                        fighter1: UFCFighter(id: "r1", name: "Alex Pereira", shortName: "Pereira",
                                             record: "11-2-0", corner: "red", flagURL: nil, isWinner: false, score: nil, sigStrikes: "42"),
                        fighter2: UFCFighter(id: "b1", name: "Jamahal Hill", shortName: "Hill",
                                             record: "12-2-0", corner: "blue", flagURL: nil, isWinner: false, score: nil, sigStrikes: "28"),
                        state: "in", currentRound: 2, totalRounds: 5, displayClock: "3:42",
                        method: nil, weightClass: "Light Heavyweight",
                        isMainEvent: true, cardSegment: "Main Card", startDate: nil, detail: "Round 2 - 3:42"
                    ),
                    UFCFight(
                        id: "f2",
                        fighter1: UFCFighter(id: "r2", name: "Zhang Weili", shortName: "Zhang",
                                             record: "24-3-0", corner: "red", flagURL: nil, isWinner: true, score: nil, sigStrikes: "86"),
                        fighter2: UFCFighter(id: "b2", name: "Yan Xiaonan", shortName: "Yan",
                                             record: "17-4-0", corner: "blue", flagURL: nil, isWinner: false, score: nil, sigStrikes: "51"),
                        state: "post", currentRound: 5, totalRounds: 5, displayClock: nil,
                        method: "KO/TKO", weightClass: "Strawweight",
                        isMainEvent: false, cardSegment: "Main Card", startDate: nil, detail: "KO/TKO"
                    ),
                    UFCFight(
                        id: "f3",
                        fighter1: UFCFighter(id: "r3", name: "Max Holloway", shortName: "Holloway",
                                             record: "25-7-0", corner: "red", flagURL: nil, isWinner: false, score: nil, sigStrikes: nil),
                        fighter2: UFCFighter(id: "b3", name: "Justin Gaethje", shortName: "Gaethje",
                                             record: "24-4-0", corner: "blue", flagURL: nil, isWinner: false, score: nil, sigStrikes: nil),
                        state: "pre", currentRound: nil, totalRounds: 5, displayClock: nil,
                        method: nil, weightClass: "BMF Title",
                        isMainEvent: false, cardSegment: "Main Card", startDate: nil, detail: nil
                    ),
                ]
            )
        )
    }
}

// MARK: - Widget View

struct UFCWidgetView: View {
    let entry: UFCEntry
    @Environment(\.widgetFamily) var family

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E, MMM d"
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
            if let event = entry.event {
                UFCCanvasBackground()

                if let fight = event.featuredFight {
                    mediumFightOverlay(fight, event: event)
                } else {
                    eventPreview(event)
                }
            } else {
                noEventView
            }
        }
    }

    // MARK: - Large View

    private var largeView: some View {
        ZStack {
            if let event = entry.event {
                UFCCanvasBackground()

                VStack(spacing: 0) {
                    // Featured fight with octagon
                    if let fight = event.featuredFight {
                        ZStack {
                            // Gold belt for title fights (above the octagon)
                            if fight.isMainEvent && fight.totalRounds == 5 {
                                VStack {
                                    Image(systemName: "rosette")
                                        .font(.system(size: 16))
                                        .foregroundColor(.yellow)
                                        .shadow(color: Color(red: 0.85, green: 0.65, blue: 0.13), radius: 4)
                                    Spacer()
                                }
                                .frame(height: 145)
                                .padding(.top, 22)
                            }

                            // Octagon outline
                            UFCOctagonShape()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                                .frame(width: 130, height: 130)

                            // Octagon mat fill
                            UFCOctagonShape()
                                .fill(UFCColorHelper.octagonMat.opacity(0.4))
                                .frame(width: 128, height: 128)

                            // Red + blue corner accents on octagon
                            VStack {
                                HStack {
                                    Circle().fill(Color.red.opacity(0.3)).frame(width: 8, height: 8)
                                    Spacer()
                                    Circle().fill(Color.blue.opacity(0.3)).frame(width: 8, height: 8)
                                }
                                Spacer()
                            }
                            .frame(width: 100, height: 100)

                            // Round progress + clock
                            roundProgressView(fight)

                            // Method of victory dramatic overlay
                            if fight.isFinished, let method = fight.dramaticMethod {
                                Text(method)
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(.yellow)
                                    .shadow(color: .black, radius: 4)
                                    .rotationEffect(.degrees(-8))
                                    .offset(y: 28)
                            }
                        }
                        .frame(height: 145)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .leading) {
                            fighterCornerView(fight.fighter1, isLeft: true, large: true)
                                .padding(.leading, 12)
                        }
                        .overlay(alignment: .trailing) {
                            fighterCornerView(fight.fighter2, isLeft: false, large: true)
                                .padding(.trailing, 12)
                        }
                        .overlay(alignment: .top) {
                            eventHeaderBar(event)
                                .padding(.top, 6)
                        }
                    }

                    Divider().background(Color.white.opacity(0.12)).padding(.horizontal, 12)

                    // Full fight card
                    VStack(spacing: 0) {
                        ForEach(event.fights) { fight in
                            fightCardRow(fight, isFeatured: fight.id == event.featuredFight?.id)
                            if fight.id != event.fights.last?.id {
                                Divider().background(Color.white.opacity(0.06)).padding(.leading, 36)
                            }
                        }
                    }
                    .padding(.top, 2)

                    Spacer(minLength: 0)
                }
            } else {
                noEventView
            }
        }
    }

    // MARK: - Medium Fight Overlay

    private func mediumFightOverlay(_ fight: UFCFight, event: UFCEvent) -> some View {
        HStack(spacing: 0) {
            // Red corner
            fighterCornerView(fight.fighter1, isLeft: true, large: false)
                .frame(maxWidth: .infinity)

            // Center octagon
            VStack(spacing: 0) {
                Text(event.shortName)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 8)

                // Gold belt for title fights
                if fight.isMainEvent && fight.totalRounds == 5 {
                    Image(systemName: "rosette")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                        .shadow(color: Color(red: 0.85, green: 0.65, blue: 0.13), radius: 3)
                        .padding(.top, 2)
                }

                Spacer()

                ZStack {
                    UFCOctagonShape()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 72, height: 72)

                    UFCOctagonShape()
                        .fill(UFCColorHelper.octagonMat.opacity(0.3))
                        .frame(width: 70, height: 70)

                    roundProgressView(fight)

                    // Dramatic method overlay
                    if fight.isFinished, let method = fight.dramaticMethod {
                        Text(method)
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.yellow)
                            .shadow(color: .black, radius: 3)
                            .rotationEffect(.degrees(-8))
                            .offset(y: 22)
                    }
                }

                Spacer()

                if let wc = fight.weightClass {
                    Text(wc.uppercased())
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                        .padding(.bottom, 6)
                }

                if event.hasLive {
                    HStack(spacing: 2) {
                        Circle().fill(.green).frame(width: 4, height: 4)
                        Text("LIVE").font(.system(size: 6, weight: .heavy)).foregroundColor(.green)
                    }
                    .padding(.bottom, 6)
                }
            }
            .frame(width: 105)

            // Blue corner
            fighterCornerView(fight.fighter2, isLeft: false, large: false)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Round Progress View

    private func roundProgressView(_ fight: UFCFight) -> some View {
        let current = fight.currentRound ?? 0
        let total = fight.totalRounds ?? 3
        let progress = total > 0 ? Double(current) / Double(total) : 0

        return VStack(spacing: 1) {
            if fight.isLive {
                // Circular progress ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 3)
                        .frame(width: 36, height: 36)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("R\(current)/\(total)")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }
                }

                if let clock = fight.displayClock {
                    Text(clock)
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundColor(.green)
                }
            } else if fight.isFinished {
                if let method = fight.shortMethod {
                    Text(method)
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.yellow)
                }
                if let round = fight.currentRound {
                    Text("R\(round)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
            } else {
                Text("VS")
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Fighter Corner

    private func fighterCornerView(_ fighter: UFCFighter, isLeft: Bool, large: Bool) -> some View {
        VStack(spacing: large ? 5 : 3) {
            // Corner indicator
            HStack(spacing: 3) {
                if isLeft {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: 3, height: large ? 18 : 14)
                }
                Text(fighter.corner.uppercased())
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundColor(isLeft ? .red : .blue)
                if !isLeft {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: 3, height: large ? 18 : 14)
                }
            }

            // Fighter icon placeholder
            ZStack {
                Circle()
                    .fill((isLeft ? Color.red : Color.blue).opacity(0.15))
                    .frame(width: large ? 32 : 24, height: large ? 32 : 24)
                Image(systemName: "person.fill")
                    .font(.system(size: large ? 14 : 10))
                    .foregroundColor((isLeft ? Color.red : Color.blue).opacity(0.5))
            }

            // Crown above winner's name
            if fighter.isWinner {
                Image(systemName: "crown.fill")
                    .font(.system(size: large ? 11 : 9))
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow.opacity(0.7), radius: 3)
            }

            // Name
            Text(large ? fighter.name : fighter.shortName)
                .font(.system(size: large ? 13 : 11, weight: .heavy))
                .foregroundColor(fighter.isWinner ? .yellow : .white)
                .lineLimit(large ? 2 : 1)
                .multilineTextAlignment(isLeft ? .leading : .trailing)

            // Record
            if let record = fighter.record {
                Text(record)
                    .font(.system(size: large ? 9 : 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Significant strikes
            if let strikes = fighter.sigStrikes {
                HStack(spacing: 2) {
                    Text(strikes)
                        .font(.system(size: large ? 9 : 8, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                    Text("STR")
                        .font(.system(size: large ? 7 : 6, weight: .heavy))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            // Winner badge
            if fighter.isWinner {
                HStack(spacing: 2) {
                    Image(systemName: "hand.raised.fill").font(.system(size: 7))
                    Text("WIN").font(.system(size: 7, weight: .heavy))
                }
                .foregroundColor(.yellow)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.yellow.opacity(0.2)))
            }
        }
    }

    // MARK: - Event Header

    private func eventHeaderBar(_ event: UFCEvent) -> some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "figure.martial.arts")
                    .font(.system(size: 9, weight: .bold)).foregroundColor(.red)
                Text(event.shortName)
                    .font(.system(size: 10, weight: .heavy)).foregroundColor(.white)
            }
            Spacer()
            if event.hasLive {
                HStack(spacing: 3) {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text("LIVE").font(.system(size: 8, weight: .heavy)).foregroundColor(.green)
                }
            } else if let city = event.city {
                Text(city)
                    .font(.system(size: 8, weight: .medium)).foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Fight Card Row

    private func fightCardRow(_ fight: UFCFight, isFeatured: Bool) -> some View {
        HStack(spacing: 5) {
            // Status icon
            ZStack {
                Circle()
                    .fill(fightRowColor(fight).opacity(0.12))
                    .frame(width: 22, height: 22)

                if fight.isLive {
                    Circle().fill(.green).frame(width: 6, height: 6)
                } else if fight.isFinished {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold)).foregroundColor(.green)
                } else {
                    Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1).frame(width: 8, height: 8)
                }
            }

            // Fighters
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.red).frame(width: 2, height: 9)
                    Text(fight.fighter1.shortName)
                        .font(.system(size: 9, weight: fight.fighter1.isWinner ? .heavy : .medium))
                        .foregroundColor(fight.fighter1.isWinner ? .yellow : .white)
                        .lineLimit(1)
                }
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.blue).frame(width: 2, height: 9)
                    Text(fight.fighter2.shortName)
                        .font(.system(size: 9, weight: fight.fighter2.isWinner ? .heavy : .medium))
                        .foregroundColor(fight.fighter2.isWinner ? .yellow : .white)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Fight label
            if isFeatured && fight.isLive {
                Text("NOW").font(.system(size: 6, weight: .heavy))
                    .foregroundColor(.green)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
            } else if !fight.fightLabel.isEmpty {
                Text(fight.fightLabel)
                    .font(.system(size: 6, weight: .heavy))
                    .foregroundColor(.white.opacity(0.3))
            }

            // Weight class
            if let wc = fight.weightClass {
                Text(abbreviateWeightClass(wc))
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundColor(.white.opacity(0.25))
            }

            // Result
            if fight.isLive {
                VStack(spacing: 0) {
                    Text("R\(fight.currentRound ?? 1)")
                        .font(.system(size: 8, weight: .heavy)).foregroundColor(.green)
                    if let clock = fight.displayClock {
                        Text(clock)
                            .font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundColor(.green)
                    }
                }
            } else if fight.isFinished, let method = fight.shortMethod {
                Text(method)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(.yellow)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(isFeatured && fight.isLive ? Color.green.opacity(0.04) : Color.clear)
    }

    // MARK: - Event Preview

    private func eventPreview(_ event: UFCEvent) -> some View {
        VStack(spacing: 6) {
            eventHeaderBar(event)
            if let date = event.date {
                Text(Self.dateFormatter.string(from: date))
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.7))
            }
            if let venue = event.venue, let city = event.city {
                Text("\(venue) | \(city)")
                    .font(.system(size: 9)).foregroundColor(.white.opacity(0.4)).lineLimit(1)
            }
            Spacer()
        }
        .padding(.top, 10)
    }

    // MARK: - Helpers

    private func fightRowColor(_ fight: UFCFight) -> Color {
        if fight.isLive { return .green }
        if fight.isFinished { return .gray }
        return .white
    }

    private func abbreviateWeightClass(_ wc: String) -> String {
        let lower = wc.lowercased()
        if lower.contains("heavyweight") && !lower.contains("light") { return "HW" }
        if lower.contains("light heavyweight") { return "LHW" }
        if lower.contains("middleweight") && !lower.contains("welter") { return "MW" }
        if lower.contains("welterweight") { return "WW" }
        if lower.contains("lightweight") { return "LW" }
        if lower.contains("featherweight") { return "FW" }
        if lower.contains("bantamweight") { return "BW" }
        if lower.contains("flyweight") { return "FLW" }
        if lower.contains("strawweight") { return "SW" }
        return String(wc.prefix(3)).uppercased()
    }

    private var noEventView: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.martial.arts")
                .font(.system(size: 24)).foregroundColor(.red.opacity(0.5))
            Text("No UFC events")
                .font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
            Text("Enable UFC in settings")
                .font(.system(size: 10)).foregroundColor(.gray.opacity(0.7))
        }
    }
}

// MARK: - Canvas Background

private struct UFCCanvasBackground: View {
    var body: some View {
        ZStack {
            UFCColorHelper.canvasBg

            // Subtle octagon watermark
            UFCOctagonShape()
                .stroke(Color.white.opacity(0.03), lineWidth: 2)
                .frame(width: 200, height: 200)

            // Red corner gradient (top-left)
            VStack {
                HStack {
                    LinearGradient(
                        colors: [Color.red.opacity(0.12), Color.clear],
                        startPoint: .topLeading, endPoint: .center
                    )
                    .frame(width: 80, height: 60)
                    Spacer()
                    LinearGradient(
                        colors: [Color.blue.opacity(0.12), Color.clear],
                        startPoint: .topTrailing, endPoint: .center
                    )
                    .frame(width: 80, height: 60)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Octagon Shape

struct UFCOctagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for i in 0..<8 {
            let angle = (CGFloat(i) * .pi / 4) - (.pi / 8)
            let x = cx + radius * cos(angle)
            let y = cy + radius * sin(angle)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}
