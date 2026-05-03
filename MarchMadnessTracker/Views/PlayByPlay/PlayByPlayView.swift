import SwiftUI

struct PlayByPlayView: View {
    var poller: ScorePoller
    var sportLeague: SportLeague? = nil
    @State private var selectedGame: Event?
    @State private var plays: [PlayEvent] = []
    @State private var isLoadingPlays = false
    @State private var autoRefreshTimer: Timer?

    private var activeGames: [Event] {
        // Show live games first, then recent finals, then upcoming
        let live = poller.liveGames.sorted { ($0.scoreDifference ?? 999) < ($1.scoreDifference ?? 999) }
        let recent = poller.completedGames
            .filter { Calendar.current.isDateInToday($0.startDate ?? .distantPast) }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        return live + recent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Game selector
            if activeGames.isEmpty {
                emptyState
            } else {
                gamePicker
                Divider()

                if let game = selectedGame {
                    // Game header
                    gameHeader(game)
                    Divider()

                    // Play-by-play feed
                    if isLoadingPlays {
                        ProgressView("Loading plays...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if plays.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No plays yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        playFeed
                    }
                }
            }
        }
        .onAppear {
            if selectedGame == nil, let first = activeGames.first {
                selectedGame = first
                Task { await loadPlays(for: first) }
            }
            startAutoRefresh()
        }
        .onDisappear {
            autoRefreshTimer?.invalidate()
        }
        .onChange(of: poller.lastUpdated) { _, _ in
            // Update selected game with fresh data
            if let selected = selectedGame,
               let updated = poller.games.first(where: { $0.id == selected.id }) {
                selectedGame = updated
            }
        }
    }

    // MARK: - Game Picker

    private var gamePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(activeGames) { game in
                    gamePickerChip(game)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func gamePickerChip(_ game: Event) -> some View {
        let isSelected = selectedGame?.id == game.id
        return Button {
            selectedGame = game
            Task { await loadPlays(for: game) }
        } label: {
            HStack(spacing: 4) {
                if game.isLive {
                    Circle().fill(.red).frame(width: 5, height: 5)
                }
                Text(game.awayCompetitor?.team.abbreviation ?? "?")
                    .font(.system(size: 10, weight: .semibold))
                if game.isLive || game.isFinal {
                    Text("\(game.awayCompetitor?.safeScore ?? "0")-\(game.homeCompetitor?.safeScore ?? "0")")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                } else {
                    Text("vs")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Text(game.homeCompetitor?.team.abbreviation ?? "?")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Game Header

    private func gameHeader(_ game: Event) -> some View {
        HStack(spacing: 12) {
            // Away
            HStack(spacing: 4) {
                if let url = game.awayCompetitor?.team.logoURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20) }
                        else { Image(systemName: "basketball.fill").font(.caption).foregroundStyle(.secondary).frame(width: 20, height: 20) }
                    }
                }
                if let seed = game.awayCompetitor?.seed {
                    Text("(\(seed))").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Text(game.awayCompetitor?.team.abbreviation ?? "TBD")
                    .font(.system(size: 12, weight: .semibold))
            }

            // Score
            if game.isLive || game.isFinal {
                HStack(spacing: 4) {
                    Text(game.awayCompetitor?.safeScore ?? "0")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                    Text("-")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(game.homeCompetitor?.safeScore ?? "0")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(game.isLive ? .red : .primary)
            }

            // Home
            HStack(spacing: 4) {
                Text(game.homeCompetitor?.team.abbreviation ?? "TBD")
                    .font(.system(size: 12, weight: .semibold))
                if let seed = game.homeCompetitor?.seed {
                    Text("(\(seed))").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                if let url = game.homeCompetitor?.team.logoURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20) }
                        else { Image(systemName: "basketball.fill").font(.caption).foregroundStyle(.secondary).frame(width: 20, height: 20) }
                    }
                }
            }

            Spacer()

            // Status
            if game.isLive {
                HStack(spacing: 3) {
                    Circle().fill(.red).frame(width: 5, height: 5)
                    Text(game.status.type.shortDetail ?? "LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.red)
                }
            } else if game.isFinal {
                Text(game.status.type.shortDetail ?? "Final")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Play Feed

    private var playFeed: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(plays.enumerated()), id: \.element.id) { index, play in
                    PlayRowView(play: play)

                    if index < plays.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sportscourt")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No active games")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Play-by-play will appear when games are live")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadPlays(for game: Event) async {
        isLoadingPlays = true
        defer { isLoadingPlays = false }

        let baseURL = sportLeague?.summaryURL ?? poller.sportLeague.summaryURL
        let urlString = "\(baseURL)?event=\(game.id)"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            var parsedPlays: [PlayEvent] = []

            // Parse plays from the summary endpoint
            if let playsData = json?["plays"] as? [[String: Any]] {
                for play in playsData {
                    if let parsed = PlayEvent.from(play) {
                        parsedPlays.append(parsed)
                    }
                }
            }

            // Also check keyEvents for highlighted plays
            if let keyEvents = json?["keyEvents"] as? [[String: Any]] {
                for play in keyEvents {
                    if let parsed = PlayEvent.from(play) {
                        if !parsedPlays.contains(where: { $0.id == parsed.id }) {
                            var highlighted = parsed
                            highlighted.isKeyEvent = true
                            parsedPlays.append(highlighted)
                        }
                    }
                }
            }

            // Sort most recent first
            parsedPlays.sort { $0.sequenceNumber > $1.sequenceNumber }

            await MainActor.run {
                self.plays = parsedPlays
            }
        } catch {
            // Silently fail
        }
    }

    private func startAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            guard let game = selectedGame, game.isLive else { return }
            Task { await loadPlays(for: game) }
        }
    }
}

// MARK: - Play Event Model

struct PlayEvent: Identifiable {
    let id: String
    let text: String
    let shortText: String?
    let period: Int
    let clock: String
    let sequenceNumber: Int
    let scoreValue: Int
    let awayScore: String
    let homeScore: String
    let teamId: String?
    let type: PlayType
    var isKeyEvent: Bool = false

    enum PlayType: String {
        case threePointer = "Three Point"
        case fieldGoal = "Field Goal"
        case freeThrow = "Free Throw"
        case rebound = "Rebound"
        case turnover = "Turnover"
        case steal = "Steal"
        case block = "Block"
        case foul = "Foul"
        case dunk = "Dunk"
        case timeout = "Timeout"
        case jumpBall = "Jump Ball"
        case substitution = "Substitution"
        case other = "Other"

        var icon: String {
            switch self {
            case .threePointer: return "3.circle.fill"
            case .fieldGoal: return "basketball.fill"
            case .freeThrow: return "target"
            case .rebound: return "arrow.up.circle"
            case .turnover: return "arrow.uturn.left.circle"
            case .steal: return "hand.raised.fill"
            case .block: return "hand.raised.slash"
            case .foul: return "exclamationmark.triangle"
            case .dunk: return "figure.basketball"
            case .timeout: return "pause.circle"
            case .jumpBall: return "arrow.up.arrow.down"
            case .substitution: return "arrow.left.arrow.right"
            case .other: return "circle"
            }
        }

        var color: Color {
            switch self {
            case .threePointer: return .green
            case .fieldGoal, .dunk: return .blue
            case .freeThrow: return .cyan
            case .turnover: return .red
            case .steal: return .orange
            case .block: return .purple
            case .foul: return .yellow
            case .rebound: return .teal
            default: return .secondary
            }
        }
    }

    static func from(_ dict: [String: Any]) -> PlayEvent? {
        guard let id = dict["id"] as? String ?? (dict["sequenceNumber"] as? Int).map({ String($0) }),
              let text = dict["text"] as? String else { return nil }

        let typeDict = dict["type"] as? [String: Any]
        let typeName = typeDict?["text"] as? String ?? ""
        let clockDict = dict["clock"] as? [String: Any]
        let clockText = clockDict?["displayValue"] as? String ?? ""
        let periodDict = dict["period"] as? [String: Any]
        let periodNum = periodDict?["number"] as? Int ?? 0

        let playType: PlayType = {
            let lower = typeName.lowercased()
            if lower.contains("three point") || lower.contains("3pt") { return .threePointer }
            if lower.contains("dunk") { return .dunk }
            if lower.contains("field goal") || lower.contains("jumper") || lower.contains("layup") { return .fieldGoal }
            if lower.contains("free throw") { return .freeThrow }
            if lower.contains("rebound") { return .rebound }
            if lower.contains("turnover") { return .turnover }
            if lower.contains("steal") { return .steal }
            if lower.contains("block") { return .block }
            if lower.contains("foul") { return .foul }
            if lower.contains("timeout") { return .timeout }
            if lower.contains("jump ball") { return .jumpBall }
            if lower.contains("substitution") { return .substitution }
            return .other
        }()

        return PlayEvent(
            id: id,
            text: text,
            shortText: dict["shortText"] as? String,
            period: periodNum,
            clock: clockText,
            sequenceNumber: dict["sequenceNumber"] as? Int ?? 0,
            scoreValue: dict["scoreValue"] as? Int ?? 0,
            awayScore: dict["awayScore"] as? String ?? (dict["awayScore"] as? Int).map(String.init) ?? "",
            homeScore: dict["homeScore"] as? String ?? (dict["homeScore"] as? Int).map(String.init) ?? "",
            teamId: dict["team"] as? String ?? (dict["team"] as? [String: Any])?["id"] as? String,
            type: playType,
            isKeyEvent: false
        )
    }
}

// MARK: - Play Row View

struct PlayRowView: View {
    let play: PlayEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Icon
            ZStack {
                Circle()
                    .fill(play.type.color.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: play.type.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(play.type.color)
            }

            // Play text
            VStack(alignment: .leading, spacing: 3) {
                Text(play.text)
                    .font(.system(size: 11, weight: play.isKeyEvent || play.scoreValue >= 3 ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    // Time
                    Text(timeLabel)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    // Score after play
                    if !play.awayScore.isEmpty && !play.homeScore.isEmpty {
                        Text("\(play.awayScore) - \(play.homeScore)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    // Score value badge
                    if play.scoreValue > 0 {
                        Text("+\(play.scoreValue)")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(play.type.color))
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            play.isKeyEvent || play.scoreValue >= 3
                ? play.type.color.opacity(0.04)
                : Color.clear
        )
    }

    private var timeLabel: String {
        let periodName: String
        if play.period > 2 {
            periodName = play.period == 3 ? "OT" : "\(play.period - 2)OT"
        } else {
            periodName = play.period == 1 ? "1H" : "2H"
        }
        return play.clock.isEmpty ? periodName : "\(periodName) \(play.clock)"
    }
}
