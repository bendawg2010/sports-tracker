import SwiftUI

/// A floating score widget styled like an official Apple desktop widget
struct ScoreWidgetView: View {
    let eventId: String
    var poller: ScorePoller
    /// Optional manager so we can search all pollers when the primary one
    /// loses track of this event (e.g., after app restart or when the game
    /// moves between sports' cached lists).
    var manager: SportPollerManager?
    var onClose: (() -> Void)?
    @State private var now = Date()
    @State private var isHovered = false
    @State private var recentPlay: String = ""
    @State private var flashOpacity: Double = 0
    @State private var previousAwayScore: String = ""
    @State private var previousHomeScore: String = ""
    @State private var playRefreshTimer: Timer?
    /// Logo pop animation state
    @State private var scoringTeamLogoURL: URL?
    @State private var logoPopScale: CGFloat = 0
    @State private var logoPopOpacity: Double = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var event: Event? {
        // First check the poller this widget was pinned from
        if let e = poller.games.first(where: { $0.id == eventId }) { return e }
        // Fall back to searching every active poller (manager)
        if let mgr = manager {
            for p in mgr.pollers.values {
                if let e = p.games.first(where: { $0.id == eventId }) { return e }
            }
        }
        return nil
    }

    private var awayColor: Color {
        Color(hex: event?.awayCompetitor?.team.color) ?? .blue
    }
    private var homeColor: Color {
        Color(hex: event?.homeCompetitor?.team.color) ?? .red
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let event {
                widgetContent(event)
            } else {
                emptyState
            }

            // Close button — only visible on hover
            if isHovered {
                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity)
            }
        }
        .frame(width: 280, height: 180)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.05)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.yellow.opacity(flashOpacity))
                .allowsHitTesting(false)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .onReceive(timer) { _ in
            now = Date()
            detectScoreChange()
        }
        .onAppear {
            if let event, event.isLive {
                Task { await fetchLatestPlay(for: event.id) }
            }
            startPlayRefresh()
        }
        .onDisappear {
            playRefreshTimer?.invalidate()
        }
    }

    // MARK: - Widget Content

    private func widgetContent(_ event: Event) -> some View {
        VStack(spacing: 0) {
            // Top: round label
            HStack {
                if event.isLive {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                if let round = event.roundName {
                    Text(round)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()

            // Center: Teams + Score
            HStack(spacing: 0) {
                // Away team
                appleTeamView(event.awayCompetitor, isWinner: isWinner(event.awayCompetitor, event: event))
                    .frame(maxWidth: .infinity)

                // Score center
                ZStack {
                    VStack(spacing: 3) {
                        if event.isLive || event.isFinal {
                            HStack(spacing: 6) {
                                Text(event.awayCompetitor?.safeScore ?? "0")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(isWinner(event.awayCompetitor, event: event) ? .primary : .secondary)
                                    .contentTransition(.numericText())
                                Text(event.homeCompetitor?.safeScore ?? "0")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(isWinner(event.homeCompetitor, event: event) ? .primary : .secondary)
                                    .contentTransition(.numericText())
                            }
                        }

                        if event.isLive {
                            appleTimePill(event)
                            if let wp = event.winProbability {
                                Text("\(wp.team) \(Int(wp.probability * 100))%")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(wp.probability > 0.85 ? .green : .orange)
                                    .padding(.top, 1)
                            }
                        } else if event.isFinal {
                            Text(event.status.type.detail ?? "Final")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        } else if let date = event.startDate {
                            // Countdown timer for scheduled games
                            countdownView(to: date)
                            if let wp = event.winProbability {
                                Text("\(wp.team) \(Int(wp.probability * 100))%")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.blue.opacity(0.8))
                                    .padding(.top, 1)
                            }
                        }
                    }

                    // Logo pop animation overlay
                    if let logoURL = scoringTeamLogoURL {
                        AsyncImage(url: logoURL) { phase in
                            if case .success(let img) = phase {
                                img.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 50, height: 50)
                            }
                        }
                        .scaleEffect(logoPopScale)
                        .opacity(logoPopOpacity)
                        .allowsHitTesting(false)
                    }
                }
                .frame(minWidth: 90)

                // Home team
                appleTeamView(event.homeCompetitor, isWinner: isWinner(event.homeCompetitor, event: event))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)

            // Play-by-play text
            if event.isLive && !recentPlay.isEmpty {
                Text(recentPlay)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .id(recentPlay) // Animate when play changes
            } else if event.isFinal {
                // Show final result context
                if event.isUpset, let underdog = event.underdog, let mag = event.upsetMagnitude {
                    Text("🚨 \(underdog.team.displayName) upset! (+\(mag) seed diff)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }
            }

            Spacer()

            // Bottom: broadcast / upset
            HStack {
                if event.isUpset && event.isLive {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                        Text("UPSET")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(.orange)
                }
                Spacer()
                if let broadcast = event.competition?.broadcasts?.first?.names?.first {
                    Text(broadcast)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Countdown View

    private func countdownView(to date: Date) -> some View {
        let diff = date.timeIntervalSince(now)
        let hours = max(0, Int(diff) / 3600)
        let mins = max(0, (Int(diff) % 3600) / 60)
        let secs = max(0, Int(diff) % 60)

        return VStack(spacing: 2) {
            if diff > 0 {
                Text(hours > 0 ? String(format: "%d:%02d:%02d", hours, mins, secs) : String(format: "%d:%02d", mins, secs))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                Text("until tipoff")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text("Starting soon...")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Score Change Detection

    private func detectScoreChange() {
        guard let event else { return }
        let awayScore = event.awayCompetitor?.safeScore ?? "0"
        let homeScore = event.homeCompetitor?.safeScore ?? "0"

        if !previousAwayScore.isEmpty || !previousHomeScore.isEmpty {
            if awayScore != previousAwayScore || homeScore != previousHomeScore {
                // Determine which team scored
                let awayScored = awayScore != previousAwayScore
                let scoringCompetitor = awayScored ? event.awayCompetitor : event.homeCompetitor

                // Flash animation
                withAnimation(.easeIn(duration: 0.15)) {
                    flashOpacity = 0.35
                }
                withAnimation(.easeOut(duration: 1.5).delay(0.15)) {
                    flashOpacity = 0
                }

                // Logo pop animation — scoring team's logo pops over the score
                triggerLogoPop(logoURL: scoringCompetitor?.team.logoURL)

                // Refresh play-by-play
                Task { await fetchLatestPlay(for: event.id) }
            }
        }
        previousAwayScore = awayScore
        previousHomeScore = homeScore
    }

    private func triggerLogoPop(logoURL: URL?) {
        scoringTeamLogoURL = logoURL
        logoPopScale = 0.3
        logoPopOpacity = 0

        // Pop in: scale up + fade in
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5, blendDuration: 0)) {
            logoPopScale = 1.3
            logoPopOpacity = 0.9
        }

        // Hold briefly, then shrink + fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.5)) {
                logoPopScale = 0.5
                logoPopOpacity = 0
            }
        }

        // Clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            scoringTeamLogoURL = nil
        }
    }

    // MARK: - Play-by-Play Fetching

    private func fetchLatestPlay(for gameId: String) async {
        let urlString = "\(poller.sportLeague.summaryURL)?event=\(gameId)"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            // Get last scoring play or key event
            var latestText: String?

            // Check keyEvents first for highlight plays
            if let keyEvents = json?["keyEvents"] as? [[String: Any]], let last = keyEvents.last {
                latestText = last["text"] as? String
            }

            // Fall back to most recent play
            if latestText == nil, let plays = json?["plays"] as? [[String: Any]] {
                // Get the most recent scoring play
                let scoringPlays = plays.filter { ($0["scoreValue"] as? Int ?? 0) > 0 }
                if let latest = scoringPlays.last {
                    latestText = latest["text"] as? String
                } else if let latest = plays.last {
                    latestText = latest["text"] as? String
                }
            }

            if let text = latestText {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.recentPlay = text
                    }
                }
            }
        } catch {
            // Silently fail
        }
    }

    private func startPlayRefresh() {
        playRefreshTimer?.invalidate()
        playRefreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            guard let event, event.isLive else { return }
            Task { await fetchLatestPlay(for: event.id) }
        }
    }

    // MARK: - Team View

    private func appleTeamView(_ competitor: Competitor?, isWinner: Bool) -> some View {
        VStack(spacing: 4) {
            // Logo with team color ring
            ZStack {
                Circle()
                    .fill(Color(hex: competitor?.team.color)?.opacity(0.15) ?? .clear)
                    .frame(width: 40, height: 40)

                if let url = competitor?.team.logoURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fit).frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "basketball.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Team name
            VStack(spacing: 0) {
                if let seed = competitor?.seed {
                    Text("#\(seed)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Text(competitor?.team.abbreviation ?? "TBD")
                    .font(.system(size: 12, weight: isWinner ? .bold : .semibold, design: .rounded))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func appleTimePill(_ event: Event) -> some View {
        let period = event.status.period
        let clock = event.status.displayClock ?? ""
        let periodName: String = {
            if period > 2 { return period == 3 ? "OT" : "\(period-2)OT" }
            return period == 1 ? "1st Half" : "2nd Half"
        }()

        Text("\(periodName)  \(clock)")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.red.gradient))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "basketball")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Game unavailable")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Button("Close") { onClose?() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func isWinner(_ competitor: Competitor?, event: Event) -> Bool {
        guard let competitor,
              let other = (competitor.homeAway == "home" ? event.awayCompetitor : event.homeCompetitor),
              let score = competitor.scoreInt,
              let otherScore = other.scoreInt else { return false }
        return score > otherScore
    }
}
