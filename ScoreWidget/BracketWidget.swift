import WidgetKit
import SwiftUI

// MARK: - Bracket Widget Provider

struct BracketProvider: TimelineProvider {
    func placeholder(in context: Context) -> BracketEntry {
        BracketEntry(date: Date(), games: sampleGames)
    }

    func getSnapshot(in context: Context, completion: @escaping (BracketEntry) -> Void) {
        let games = SharedDataManager.loadGames()
        completion(BracketEntry(date: Date(), games: games.isEmpty ? sampleGames : games))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BracketEntry>) -> Void) {
        let games = SharedDataManager.loadGames()
        let entry = BracketEntry(date: Date(), games: games.isEmpty ? sampleGames : games)
        let hasLive = games.contains { $0.isLive }
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: hasLive ? 2 : 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct BracketEntry: TimelineEntry {
    let date: Date
    let games: [SharedGame]

    var liveGames: [SharedGame] { games.filter { $0.isLive } }
    var recentResults: [SharedGame] {
        let live = liveGames
        if !live.isEmpty { return live }
        return games.filter { $0.isFinal }.suffix(8).reversed()
    }
}

// MARK: - Widget Definition

struct BracketWidget: Widget {
    let kind: String = "BracketWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BracketProvider()) { entry in
            BracketWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tournament Bracket")
        .description("March Madness bracket & results at a glance")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Widget View

struct BracketWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: BracketEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumBracket
        case .systemLarge:
            largeBracket
        default:
            mediumBracket
        }
    }

    // MARK: - Medium: Recent results list

    private var mediumBracket: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                Text("Tournament Results")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Text("\(entry.games.filter { $0.isFinal }.count) games played")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if entry.recentResults.isEmpty {
                Spacer()
                Text("No results yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(entry.recentResults.prefix(3))) { game in
                    bracketResultRow(game)
                    if game.id != entry.recentResults.prefix(3).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(4)
    }

    // MARK: - Large: Bracket-style grouped by round

    private var largeBracket: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.yellow)
                Text("March Madness Bracket")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                if !entry.liveGames.isEmpty {
                    HStack(spacing: 3) {
                        Circle().fill(.red).frame(width: 5, height: 5)
                        Text("\(entry.liveGames.count) LIVE")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.red)
                    }
                }
            }

            // Group by round
            let grouped = Dictionary(grouping: entry.recentResults) { $0.roundName ?? "Tournament" }
            let rounds = ["1st Round", "2nd Round", "Sweet 16", "Elite 8", "Final Four", "Championship"]

            ScrollView {
                ForEach(rounds, id: \.self) { round in
                    if let games = grouped[round], !games.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(round)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.top, 4)

                            ForEach(Array(games.prefix(4))) { game in
                                bracketResultRow(game)
                            }
                            if games.count > 4 {
                                Text("+\(games.count - 4) more")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 4)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(4)
    }

    // MARK: - Result Row

    private func bracketResultRow(_ game: SharedGame) -> some View {
        HStack(spacing: 6) {
            // Team color bar
            VStack(spacing: 0) {
                (Color(hex: game.awayColor) ?? .blue).frame(width: 2)
                (Color(hex: game.homeColor) ?? .red).frame(width: 2)
            }
            .frame(height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 1))

            // Away
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 2) {
                    if let seed = game.awaySeed {
                        Text("\(seed)")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(game.awayAbbreviation)
                        .font(.system(size: 10, weight: awayWins(game) ? .bold : .regular))
                }
            }
            .frame(width: 50, alignment: .leading)

            // Score
            if game.isLive || game.isFinal {
                Text("\(game.awayScore)-\(game.homeScore)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(game.isLive ? .red : .primary)
                    .frame(width: 40)
            } else {
                Text(game.shortDetail ?? "—")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
            }

            // Home
            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 2) {
                    Text(game.homeAbbreviation)
                        .font(.system(size: 10, weight: homeWins(game) ? .bold : .regular))
                    if let seed = game.homeSeed {
                        Text("\(seed)")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 50, alignment: .trailing)

            Spacer()

            // Status
            if game.isLive {
                Circle().fill(.red).frame(width: 4, height: 4)
            } else if game.isUpset {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 1)
    }

    // MARK: - Helpers

    private func awayWins(_ game: SharedGame) -> Bool {
        guard let a = game.awayScoreInt, let h = game.homeScoreInt else { return false }
        return a > h
    }

    private func homeWins(_ game: SharedGame) -> Bool {
        guard let a = game.awayScoreInt, let h = game.homeScoreInt else { return false }
        return h > a
    }
}

private extension Color {
    init?(hex: String?) {
        guard let hex = hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let int = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
