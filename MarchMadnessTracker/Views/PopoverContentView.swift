import SwiftUI

struct PopoverContentView: View {
    var manager: SportPollerManager
    var onToggleToolbar: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    @State private var selectedTab: Tab = .scores
    @State private var selectedSportId: String? = nil // nil = "All"
    @State private var now = Date()
    @State private var pressedSportId: String? = "__none__"
    @State private var livePulse = false
    @AppStorage("toolbarEnabled") private var toolbarEnabled = false
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    enum Tab: String, CaseIterable {
        case scores = "Scores"
        case bracket = "Bracket"
        case plays = "Plays"
        case chaos = "Chaos"
        case schedule = "Schedule"
        case watch = "Watch"

        var iconName: String {
            switch self {
            case .scores:   return "sportscourt.fill"
            case .bracket:  return "tree.fill"
            case .plays:    return "list.bullet.rectangle"
            case .chaos:    return "exclamationmark.triangle.fill"
            case .schedule: return "calendar"
            case .watch:    return "play.rectangle.fill"
            }
        }
    }

    /// Currently selected sport league (nil = all sports)
    private var selectedSport: SportLeague? {
        guard let id = selectedSportId else { return nil }
        return SportLeague.find(id)
    }

    /// The poller for the selected sport, or nil for "All"
    private var activePoller: ScorePoller? {
        guard let id = selectedSportId else { return nil }
        return manager.poller(for: id)
    }

    /// Available tabs based on selected sport
    private var availableTabs: [Tab] {
        guard let sport = selectedSport else {
            // "All" mode: just scores, schedule, watch
            return [.scores, .schedule, .watch]
        }
        var tabs: [Tab] = [.scores]
        if sport.hasBracket { tabs.append(.bracket) }
        if sport.hasPlayByPlay { tabs.append(.plays) }
        if sport.hasChaos { tabs.append(.chaos) }
        tabs.append(contentsOf: [.schedule, .watch])
        return tabs
    }

    /// All games across selected scope
    private var scopedGames: [Event] {
        if let poller = activePoller {
            return poller.games
        }
        return manager.pollers.values.flatMap(\.games)
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    /// Next upcoming game
    private var nextGame: Event? {
        let scheduled: [Event]
        if let poller = activePoller {
            scheduled = poller.scheduledGames
        } else {
            scheduled = manager.pollers.values.flatMap(\.scheduledGames)
        }
        return scheduled
            .filter { ($0.startDate ?? .distantFuture) > now }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            .first
    }

    /// Whether any scoped games are live
    private var hasLive: Bool {
        if let poller = activePoller { return poller.hasLiveGames }
        return manager.hasAnyLiveGames
    }

    /// Total live game count across the current scope
    private var scopedLiveCount: Int {
        if let poller = activePoller {
            return poller.liveGames.count
        }
        return manager.pollers.values.reduce(0) { $0 + $1.liveGames.count }
    }

    /// Whether any sports are configured
    private var hasAnySports: Bool {
        !manager.pollers.isEmpty
    }

    /// Whether we have sports configured but no data yet
    private var isInitialLoading: Bool {
        hasAnySports
            && manager.anyLoading
            && manager.pollers.values.allSatisfy { $0.games.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            // Sport switcher
            if hasAnySports {
                sportSwitcher
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            // Tab picker
            if hasAnySports {
                tabBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            Divider()

            // Content
            Group {
                if !hasAnySports {
                    emptyStateView
                } else if isInitialLoading {
                    loadingStateView
                } else if let poller = activePoller {
                    // Single sport view
                    singleSportContent(poller: poller)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    // All-sports aggregated view
                    allSportsView
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedSportId)

            Divider()

            // Footer
            footer
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.6)
                )
        }
        .frame(width: Constants.popoverWidth, height: Constants.popoverHeight)
        .onReceive(clockTimer) { _ in now = Date() }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                livePulse = true
            }
        }
        .onChange(of: selectedSportId) { _, _ in
            // Reset to scores if current tab isn't available
            if !availableTabs.contains(selectedTab) {
                selectedTab = .scores
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            // Title / branding
            if let sport = selectedSport {
                HStack(spacing: 5) {
                    Image(systemName: sport.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange, Color.yellow],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text(sport.shortName)
                        .font(.headline)
                        .fontWeight(.bold)
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text("Sports Tracker")
                        .font(.headline)
                        .fontWeight(.bold)
                }
            }

            Spacer()

            // Live / Next status
            if hasLive {
                liveBadge
            } else if let next = nextGame, let date = next.startDate {
                countdownView(to: date, teams: next)
            }
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .scaleEffect(livePulse ? 1.25 : 0.85)
                .opacity(livePulse ? 1.0 : 0.6)
            Text("\(scopedLiveCount) LIVE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.red)
                .contentTransition(.numericText())
        }
        .help("\(scopedLiveCount) live game\(scopedLiveCount == 1 ? "" : "s") in progress")
    }

    // MARK: - Sport Switcher

    private var sportSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // "All" button — shows total live count when any sport is live
                sportPill(
                    id: nil,
                    icon: "square.grid.2x2.fill",
                    label: "All",
                    liveCount: manager.hasAnyLiveGames
                        ? manager.pollers.values.reduce(0) { $0 + $1.liveGames.count }
                        : 0
                )

                // Active sports
                ForEach(manager.activeSportLeagues) { league in
                    let pollerLive = manager.poller(for: league.id)?.hasLiveGames ?? false
                    sportPill(
                        id: league.id,
                        icon: league.icon,
                        label: league.shortName,
                        liveCount: pollerLive ? 1 : 0
                    )
                }
            }
        }
    }

    private func sportPill(id: String?, icon: String, label: String, liveCount: Int) -> some View {
        let isSelected = selectedSportId == id
        let pillKey = id ?? "__all__"
        let isPressed = pressedSportId == pillKey
        let hasLiveGames = liveCount > 0

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedSportId = id
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                if id == nil, liveCount > 0 {
                    // Show total live count pill for "All"
                    Text("\(liveCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.red)
                        )
                } else if id != nil, hasLiveGames {
                    // Small red dot for individual sports with live games
                    Circle()
                        .fill(.red)
                        .frame(width: 5, height: 5)
                        .scaleEffect(livePulse ? 1.2 : 0.8)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
            )
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(.plain)
        .help(id == nil ? "Show all sports" : "Show \(label)")
        .onLongPressGesture(minimumDuration: 0.0, maximumDistance: .infinity, pressing: { pressing in
            pressedSportId = pressing ? pillKey : "__none__"
        }, perform: {})
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(availableTabs, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 11, weight: selectedTab == tab ? .bold : .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: selectedTab == tab ? .bold : .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                    )
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Show \(tab.rawValue)")
            }
        }
    }

    // MARK: - Single Sport Content

    @ViewBuilder
    private func singleSportContent(poller: ScorePoller) -> some View {
        switch selectedTab {
        case .scores:
            ScoreboardView(poller: poller)
        case .bracket:
            BracketView(poller: poller)
        case .plays:
            PlayByPlayView(poller: poller, sportLeague: selectedSport)
        case .chaos:
            ChaosView(poller: poller)
        case .schedule:
            ScheduleView(poller: poller)
        case .watch:
            WatchView(poller: poller, sportLeague: selectedSport)
        }
    }

    // MARK: - All Sports Aggregated View

    private var allSportsView: some View {
        Group {
            switch selectedTab {
            case .scores:
                allSportsScoreboard
            case .schedule:
                allSportsSchedule
            case .watch:
                // Just show ESPN Watch for all sports
                if let firstPoller = manager.pollers.values.first {
                    WatchView(poller: firstPoller, sportLeague: nil)
                } else {
                    emptyStateView
                }
            default:
                emptyStateView
            }
        }
    }

    private var allSportsScoreboard: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(manager.activeSportLeagues) { league in
                    if let poller = manager.poller(for: league.id),
                       !poller.tickerGames.isEmpty {
                        // Sport header
                        HStack(spacing: 6) {
                            Image(systemName: league.icon)
                                .font(.system(size: 11))
                            Text(league.shortName)
                                .font(.system(size: 12, weight: .bold))
                            if poller.hasLiveGames {
                                Circle().fill(.red).frame(width: 5, height: 5)
                            }
                            Spacer()
                            Text("\(poller.tickerGames.count) games")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.03))

                        ForEach(poller.tickerGames.prefix(5)) { game in
                            GameRowView(event: game,
                                       scoreChanged: poller.recentScoreChanges.contains(game.id),
                                       scoringTeamId: poller.scoringTeamIds[game.id])
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private var allSportsSchedule: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let allScheduled = manager.pollers.values.flatMap(\.scheduledGames)
                    .filter { ($0.startDate ?? .distantFuture) > Date() }
                    .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
                    .prefix(20)

                ForEach(Array(allScheduled)) { game in
                    GameRowView(event: game, scoreChanged: false, scoringTeamId: nil)
                    Divider().padding(.leading, 16)
                }

                if allScheduled.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No upcoming games")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 40)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.orange.opacity(0.18),
                                Color.yellow.opacity(0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 84, height: 84)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: 6) {
                Text("No sports enabled.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Click the gear icon to pick your sports.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Arrow pointing at the settings gear (bottom-right of popover).
            HStack(spacing: 6) {
                Spacer()
                Text("Settings")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 8)
            .padding(.trailing, 28)

            Button {
                onOpenSettings?()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gear")
                        .font(.system(size: 11, weight: .bold))
                    Text("Open Settings")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(Color.accentColor.opacity(0.15))
                )
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Loading State

    private var loadingStateView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading scores\u{2026}")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Fetching games from ESPN")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            // Show last updated from most recently updated poller
            if let latest = manager.pollers.values.compactMap(\.lastUpdated).max() {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text("Updated \(DateFormatters.lastUpdated.string(from: latest))")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .help("Last successful refresh time")
            }

            Spacer()

            // Show/Hide Ticker
            Button {
                onToggleToolbar?()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: toolbarEnabled ? "menubar.rectangle" : "menubar.arrow.up.rectangle")
                        .font(.caption)
                    Text(toolbarEnabled ? "Hide Ticker" : "Show Ticker")
                        .font(.caption2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(toolbarEnabled ? Color.accentColor : Color.primary)
            .help(toolbarEnabled ? "Hide the menu bar ticker" : "Show a live score ticker in the menu bar")

            // Refresh
            Button {
                Task { await manager.refreshAll() }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                    Text("Refresh")
                        .font(.caption2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(manager.anyLoading)
            .foregroundStyle(manager.anyLoading ? Color.secondary : Color.primary)
            .help("Refresh all scores now")

            // Settings
            Button {
                onOpenSettings?()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "gear")
                        .font(.caption)
                    Text("Settings")
                        .font(.caption2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Sports Tracker settings")

            // Quit
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "power")
                        .font(.caption)
                    Text("Quit")
                        .font(.caption2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .help("Quit Sports Tracker")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Countdown View

    private func countdownView(to date: Date, teams: Event) -> some View {
        let diff = date.timeIntervalSince(now)
        let hours = max(0, Int(diff) / 3600)
        let mins = max(0, (Int(diff) % 3600) / 60)
        let secs = max(0, Int(diff) % 60)

        return HStack(spacing: 6) {
            Image(systemName: "clock.fill")
                .font(.system(size: 9))
                .foregroundStyle(.orange)

            VStack(alignment: .trailing, spacing: 0) {
                Text("Next: \(teams.awayCompetitor?.team.abbreviation ?? "?") vs \(teams.homeCompetitor?.team.abbreviation ?? "?")")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if diff > 0 {
                    Text(hours > 0 ? String(format: "%dh %02dm %02ds", hours, mins, secs) : String(format: "%dm %02ds", mins, secs))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                } else {
                    Text("Starting\u{2026}")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
        }
        .help("Time until the next scheduled game")
    }
}
