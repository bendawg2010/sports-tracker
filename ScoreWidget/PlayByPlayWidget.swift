import WidgetKit
import SwiftUI

// MARK: - Play-by-Play Widget

struct PlayByPlayWidget: Widget {
    let kind = "PlayByPlayWidget_v1"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlayByPlayProvider()) { entry in
            PlayByPlayWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.06, green: 0.06, blue: 0.08),
                                 Color(red: 0.10, green: 0.10, blue: 0.12)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Play-by-Play")
        .description("Live play-by-play feed for one game")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Entry

struct PlayByPlayEntry: TimelineEntry {
    let date: Date
    let gameName: String
    let awayAbbr: String
    let homeAbbr: String
    let awayScore: String
    let homeScore: String
    let awaySeed: Int?
    let homeSeed: Int?
    let statusText: String
    let isLive: Bool
    let isScheduled: Bool
    let startDate: Date?
    let plays: [WidgetPlay]
    let winProbText: String?
}

struct WidgetPlay: Identifiable {
    let id: String
    let text: String
    let clock: String
    let period: Int
    let scoreValue: Int
    let awayScore: String
    let homeScore: String
    let typeName: String
}

// MARK: - Provider

struct PlayByPlayProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlayByPlayEntry {
        sampleEntry
    }

    func getSnapshot(in context: Context, completion: @escaping (PlayByPlayEntry) -> Void) {
        fetchPlayByPlay { entry in
            completion(entry ?? sampleEntry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlayByPlayEntry>) -> Void) {
        // Ensure completion is called exactly once — WidgetKit preempts the
        // extension aggressively, so guarantee a fallback timeline ships.
        let lock = NSLock()
        var fired = false
        func fire(_ timeline: Timeline<PlayByPlayEntry>) {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            lock.unlock()
            completion(timeline)
        }
        let wrappedCompletion: (Timeline<PlayByPlayEntry>) -> Void = fire
        DispatchQueue.global().asyncAfter(deadline: .now() + 4.5) {
            fire(Timeline(entries: [self.placeholder(in: context)], policy: .after(Date().addingTimeInterval(60))))
        }

        fetchPlayByPlay { entry in
            let finalEntry = entry ?? sampleEntry
            let hasLive = finalEntry.isLive
            let refreshDate = Calendar.current.date(byAdding: .minute, value: hasLive ? 1 : 5, to: Date())!
            wrappedCompletion(Timeline(entries: [finalEntry], policy: .after(refreshDate)))
        }
    }

    private func fetchPlayByPlay(completion: @escaping (PlayByPlayEntry?) -> Void) {
        // First find a live game from the scoreboard
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "America/New_York")
        let today = dateFormatter.string(from: Date())
        let endDate = dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: 5, to: Date())!)
        let scoreboardURL = "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/scoreboard?groups=100&dates=\(today)-\(endDate)&limit=100"

        guard let url = URL(string: scoreboardURL) else {
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

            // Find first live game, or most recent completed, or next upcoming
            var targetEvent: [String: Any]?
            var targetIsLive = false

            // Priority 1: Live games (prefer closest score)
            let liveEvents = events.filter { event in
                let status = (event["status"] as? [String: Any])?["type"] as? [String: Any]
                return (status?["state"] as? String) == "in"
            }
            if let live = liveEvents.first {
                targetEvent = live
                targetIsLive = true
            }

            // Priority 2: Next upcoming game
            if targetEvent == nil {
                let upcoming = events.filter { event in
                    let status = (event["status"] as? [String: Any])?["type"] as? [String: Any]
                    return (status?["state"] as? String) == "pre"
                }
                targetEvent = upcoming.first
            }

            // Priority 3: Recently completed
            if targetEvent == nil {
                let completed = events.filter { event in
                    let status = (event["status"] as? [String: Any])?["type"] as? [String: Any]
                    return (status?["state"] as? String) == "post"
                }
                targetEvent = completed.last
            }

            guard let event = targetEvent else {
                completion(nil)
                return
            }

            // Extract game info
            let comp = (event["competitions"] as? [[String: Any]])?.first
            let competitors = comp?["competitors"] as? [[String: Any]] ?? []
            let away = competitors.first { ($0["homeAway"] as? String) == "away" }
            let home = competitors.first { ($0["homeAway"] as? String) == "home" }
            let awayTeam = away?["team"] as? [String: Any]
            let homeTeam = home?["team"] as? [String: Any]
            let statusType = (event["status"] as? [String: Any])?["type"] as? [String: Any]

            let awayAbbr = awayTeam?["abbreviation"] as? String ?? "?"
            let homeAbbr = homeTeam?["abbreviation"] as? String ?? "?"
            let awayScore = away?["score"] as? String ?? "0"
            let homeScore = home?["score"] as? String ?? "0"
            let awaySeed = (away?["curatedRank"] as? [String: Any])?["current"] as? Int
            let homeSeed = (home?["curatedRank"] as? [String: Any])?["current"] as? Int
            let statusText = statusType?["shortDetail"] as? String ?? ""
            let eventId = event["id"] as? String ?? ""
            let eventState = statusType?["state"] as? String ?? ""
            let eventIsScheduled = eventState == "pre"

            // Parse start date
            let eventDateStr = event["date"] as? String ?? ""
            let eventStartDate: Date? = {
                let fmts = ["yyyy-MM-dd'T'HH:mm'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mmZ", "yyyy-MM-dd'T'HH:mm:ssZ"]
                for fmt in fmts {
                    let df = DateFormatter()
                    df.dateFormat = fmt
                    df.timeZone = TimeZone(identifier: "UTC")
                    if let d = df.date(from: eventDateStr) { return d }
                }
                return nil
            }()

            // Now fetch play-by-play from summary endpoint
            let summaryURL = "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/summary?event=\(eventId)"
            guard let sURL = URL(string: summaryURL) else {
                completion(nil)
                return
            }

            URLSession.shared.dataTask(with: URLRequest(url: sURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)) { sData, _, _ in
                var widgetPlays: [WidgetPlay] = []

                if let sData = sData,
                   let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
                   let plays = sJson["plays"] as? [[String: Any]] {

                    for play in plays {
                        guard let text = play["text"] as? String else { continue }
                        let id = play["id"] as? String ?? "\(play["sequenceNumber"] as? Int ?? 0)"
                        let clockDict = play["clock"] as? [String: Any]
                        let clock = clockDict?["displayValue"] as? String ?? ""
                        let periodDict = play["period"] as? [String: Any]
                        let period = periodDict?["number"] as? Int ?? 0
                        let scoreValue = play["scoreValue"] as? Int ?? 0
                        let pAwayScore = play["awayScore"] as? String
                            ?? (play["awayScore"] as? Int).map(String.init) ?? ""
                        let pHomeScore = play["homeScore"] as? String
                            ?? (play["homeScore"] as? Int).map(String.init) ?? ""
                        let typeDict = play["type"] as? [String: Any]
                        let typeName = typeDict?["text"] as? String ?? ""

                        widgetPlays.append(WidgetPlay(
                            id: id, text: text, clock: clock, period: period,
                            scoreValue: scoreValue, awayScore: pAwayScore,
                            homeScore: pHomeScore, typeName: typeName
                        ))
                    }
                }

                // Sort newest first
                widgetPlays.sort { a, b in
                    let seqA = Int(a.id) ?? 0
                    let seqB = Int(b.id) ?? 0
                    return seqA > seqB
                }

                // Limit to most recent plays
                let limitedPlays = Array(widgetPlays.prefix(12))

                let entry = PlayByPlayEntry(
                    date: Date(),
                    gameName: "\(awayAbbr) vs \(homeAbbr)",
                    awayAbbr: awayAbbr,
                    homeAbbr: homeAbbr,
                    awayScore: awayScore,
                    homeScore: homeScore,
                    awaySeed: awaySeed,
                    homeSeed: homeSeed,
                    statusText: statusText,
                    isLive: targetIsLive,
                    isScheduled: eventIsScheduled,
                    startDate: eventStartDate,
                    plays: limitedPlays,
                    winProbText: nil
                )
                completion(entry)
            }.resume()
        }.resume()
    }

    private var sampleEntry: PlayByPlayEntry {
        PlayByPlayEntry(
            date: Date(),
            gameName: "DUKE vs UNC",
            awayAbbr: "DUKE", homeAbbr: "UNC",
            awayScore: "72", homeScore: "68",
            awaySeed: 4, homeSeed: 1,
            statusText: "2nd 4:32",
            isLive: true,
            isScheduled: false,
            startDate: nil,
            plays: [
                WidgetPlay(id: "1", text: "Cooper Flagg makes a three-pointer", clock: "4:32", period: 2, scoreValue: 3, awayScore: "72", homeScore: "68", typeName: "Three Point"),
                WidgetPlay(id: "2", text: "RJ Davis misses a layup", clock: "4:55", period: 2, scoreValue: 0, awayScore: "69", homeScore: "68", typeName: "Field Goal"),
                WidgetPlay(id: "3", text: "Armando Bacot makes free throw 2 of 2", clock: "5:12", period: 2, scoreValue: 1, awayScore: "69", homeScore: "68", typeName: "Free Throw"),
                WidgetPlay(id: "4", text: "Foul on Tyrese Proctor", clock: "5:12", period: 2, scoreValue: 0, awayScore: "69", homeScore: "67", typeName: "Foul"),
            ],
            winProbText: "DUKE 62%"
        )
    }
}

// MARK: - Widget View

struct PlayByPlayWidgetView: View {
    let entry: PlayByPlayEntry

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

            Divider().opacity(0.3)

            // Plays list — newest first
            if entry.isScheduled, let startDate = entry.startDate {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                    let diff = startDate.timeIntervalSince(entry.date)
                    if diff > 0 {
                        let hours = Int(diff) / 3600
                        let mins = (Int(diff) % 3600) / 60
                        Text(hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                        let f = DateFormatter()
                        let _ = f.dateFormat = "E h:mm a"
                        let _ = f.timeZone = TimeZone(identifier: "America/New_York")
                        Text(f.string(from: startDate))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray)
                    } else {
                        Text("Starting soon...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    Text("Play-by-play starts at tip-off")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
                Spacer()
            } else if entry.plays.isEmpty {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.title3)
                        .foregroundColor(.gray)
                    Text("No plays yet")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                Spacer()
            } else {
                VStack(spacing: 0) {
                    ForEach(entry.plays.prefix(playLimit)) { play in
                        playRow(play)
                        if play.id != entry.plays.prefix(playLimit).last?.id {
                            Divider().opacity(0.15).padding(.leading, 28)
                        }
                    }
                }
                .padding(.top, 2)
                Spacer(minLength: 0)
            }
        }
    }

    private var playLimit: Int {
        // Medium widget fits ~4, large fits ~8
        8
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            // Away
            HStack(spacing: 3) {
                if let seed = entry.awaySeed {
                    Text("\(seed)").font(.system(size: 9, weight: .medium)).foregroundColor(.gray)
                }
                Text(entry.awayAbbr).font(.system(size: 13, weight: .bold))
            }

            Spacer()

            // Score + status
            VStack(spacing: 1) {
                if entry.isScheduled {
                    Text("UPCOMING")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.orange)
                } else {
                    HStack(spacing: 4) {
                        Text(entry.awayScore)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                        Text("-").font(.system(size: 11)).foregroundColor(.gray)
                        Text(entry.homeScore)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(entry.isLive ? .red : nil)
                    HStack(spacing: 3) {
                        if entry.isLive {
                            Circle().fill(Color.red).frame(width: 5, height: 5)
                        }
                        Text(entry.statusText)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(entry.isLive ? .red : .gray)
                    }
                }
            }

            Spacer()

            // Home
            HStack(spacing: 3) {
                Text(entry.homeAbbr).font(.system(size: 13, weight: .bold))
                if let seed = entry.homeSeed {
                    Text("\(seed)").font(.system(size: 9, weight: .medium)).foregroundColor(.gray)
                }
            }
        }
    }

    // MARK: - Play Row

    private func playRow(_ play: WidgetPlay) -> some View {
        HStack(alignment: .top, spacing: 6) {
            // Type icon
            playIcon(play)
                .frame(width: 20, height: 20)

            // Play text
            VStack(alignment: .leading, spacing: 1) {
                Text(play.text)
                    .font(.system(size: 10, weight: play.scoreValue >= 3 ? .semibold : .regular))
                    .lineLimit(2)
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    Text(timeLabel(play))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)

                    if !play.awayScore.isEmpty && !play.homeScore.isEmpty {
                        Text("\(play.awayScore)-\(play.homeScore)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.gray)
                    }

                    if play.scoreValue > 0 {
                        Text("+\(play.scoreValue)")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(playColor(play)))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(play.scoreValue >= 3 ? playColor(play).opacity(0.06) : Color.clear)
    }

    private func playIcon(_ play: WidgetPlay) -> some View {
        let lower = play.typeName.lowercased()
        let icon: String
        let color: Color

        if lower.contains("three") || lower.contains("3pt") {
            icon = "3.circle.fill"; color = .green
        } else if lower.contains("dunk") {
            icon = "figure.basketball"; color = .blue
        } else if lower.contains("field goal") || lower.contains("jumper") || lower.contains("layup") {
            icon = "basketball.fill"; color = .blue
        } else if lower.contains("free throw") {
            icon = "target"; color = .cyan
        } else if lower.contains("rebound") {
            icon = "arrow.up.circle"; color = .teal
        } else if lower.contains("turnover") {
            icon = "arrow.uturn.left.circle"; color = .red
        } else if lower.contains("steal") {
            icon = "hand.raised.fill"; color = .orange
        } else if lower.contains("block") {
            icon = "hand.raised.slash"; color = .purple
        } else if lower.contains("foul") {
            icon = "exclamationmark.triangle"; color = .yellow
        } else if lower.contains("timeout") {
            icon = "pause.circle"; color = .gray
        } else {
            icon = "circle"; color = .gray
        }

        return ZStack {
            Circle().fill(color.opacity(0.15)).frame(width: 20, height: 20)
            Image(systemName: icon).font(.system(size: 9)).foregroundColor(color)
        }
    }

    private func playColor(_ play: WidgetPlay) -> Color {
        let lower = play.typeName.lowercased()
        if lower.contains("three") || lower.contains("3pt") { return .green }
        if lower.contains("dunk") || lower.contains("field goal") || lower.contains("jumper") || lower.contains("layup") { return .blue }
        if lower.contains("free throw") { return .cyan }
        if lower.contains("turnover") { return .red }
        if lower.contains("steal") { return .orange }
        return .blue
    }

    private func timeLabel(_ play: WidgetPlay) -> String {
        let periodName: String
        if play.period > 2 {
            periodName = play.period == 3 ? "OT" : "\(play.period - 2)OT"
        } else {
            periodName = play.period == 1 ? "1H" : "2H"
        }
        return play.clock.isEmpty ? periodName : "\(periodName) \(play.clock)"
    }
}
