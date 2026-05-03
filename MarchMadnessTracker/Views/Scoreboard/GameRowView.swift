import SwiftUI

struct GameRowView: View {
    let event: Event
    var scoreChanged: Bool = false
    var scoringTeamId: String? = nil
    @State private var isHovered = false
    @State private var flashOpacity: Double = 0
    @State private var logoPopScale: CGFloat = 0
    @State private var logoPopOpacity: Double = 0
    @State private var scoringLogoURL: URL?

    private var awayColor: Color {
        Color(hex: event.awayCompetitor?.team.color) ?? .blue
    }

    private var homeColor: Color {
        Color(hex: event.homeCompetitor?.team.color) ?? .red
    }

    var body: some View {
        HStack(spacing: 0) {
            // Main clickable game row — opens detail window
            Button {
                NotificationCenter.default.post(
                    name: .openGameDetail,
                    object: nil,
                    userInfo: ["eventId": event.id]
                )
            } label: {
                HStack(spacing: 0) {
                    // Team color accent bar
                    VStack(spacing: 0) {
                        awayColor.frame(width: 3)
                        homeColor.frame(width: 3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.vertical, 4)

                    VStack(spacing: 6) {
                        if isTennisMatch {
                            tennisRow(competitor: event.awayCompetitor)
                            tennisRow(competitor: event.homeCompetitor)
                        } else {
                            teamRow(
                                competitor: event.awayCompetitor,
                                isWinner: event.isFinal && isWinner(event.awayCompetitor)
                            )
                            teamRow(
                                competitor: event.homeCompetitor,
                                isWinner: event.isFinal && isWinner(event.homeCompetitor)
                            )
                        }

                        // Status line
                        HStack(spacing: 4) {
                            statusView

                            if event.isUpset {
                                upsetBadge
                            }

                            Spacer()

                            if let broadcast = event.competition?.broadcasts?.first?.names?.first {
                                Text(broadcast)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .buttonStyle(.plain)

            // Widget pin button — ALWAYS visible so user can find it
            Button {
                NotificationCenter.default.post(
                    name: .createGameWidget,
                    object: nil,
                    userInfo: ["eventId": event.id]
                )
            } label: {
                VStack(spacing: 2) {
                    Spacer()
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                    Text("Pin")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .frame(width: 40)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(isHovered ? 0.15 : 0.08))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Pin as floating widget on your desktop")
        }
        .background(backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.yellow.opacity(flashOpacity))
                .allowsHitTesting(false)
        )
        .overlay {
            // Logo pop overlay — scoring team logo pops over the score
            if let url = scoringLogoURL {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                    }
                }
                .scaleEffect(logoPopScale)
                .opacity(logoPopOpacity)
                .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .onChange(of: scoreChanged) { _, changed in
            if changed {
                withAnimation(.easeIn(duration: 0.15)) { flashOpacity = 0.35 }
                withAnimation(.easeOut(duration: 1.5).delay(0.15)) { flashOpacity = 0 }

                // Logo pop for scoring team
                if let teamId = scoringTeamId {
                    let competitor = event.competition?.competitors.first { $0.team.id == teamId }
                    scoringLogoURL = competitor?.team.logoURL
                    logoPopScale = 0.3
                    logoPopOpacity = 0
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        logoPopScale = 1.2
                        logoPopOpacity = 0.85
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        withAnimation(.easeOut(duration: 0.4)) {
                            logoPopScale = 0.4
                            logoPopOpacity = 0
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        scoringLogoURL = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var backgroundStyle: some View {
        if event.isLive && event.isUpset {
            Color.orange.opacity(0.06)
        } else if event.isLive {
            Color.red.opacity(0.04)
        } else if event.isFinal && event.isUpset {
            Color.orange.opacity(0.03)
        } else {
            Color.clear
        }
    }

    private var upsetBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 7))
            Text("UPSET")
                .font(.system(size: 7, weight: .heavy))
            if let mag = event.upsetMagnitude, mag >= 5 {
                Text("+\(mag)")
                    .font(.system(size: 7, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(.orange))
    }

    // MARK: - Tennis Row
    // Detect tennis matches: linescores present AND teams look like individual players
    // (identified by missing `location` on the athlete object)
    private var isTennisMatch: Bool {
        guard let comp = event.competition, comp.competitors.count == 2 else { return false }
        let hasLineScores = comp.competitors.contains { ($0.linescores?.count ?? 0) > 0 }
        let individualSport = comp.competitors.allSatisfy { $0.team.location.isEmpty }
        return hasLineScores && individualSport
    }

    private var tennisSetCount: Int {
        event.competition?.competitors
            .map { $0.linescores?.count ?? 0 }
            .max() ?? 0
    }

    /// Live point score from api-tennis.com (if user has configured a key)
    private var tennisLivePoint: TennisLiveService.TennisPointData? {
        guard event.isLive else { return nil }
        guard let away = event.awayCompetitor?.team.displayName,
              let home = event.homeCompetitor?.team.displayName else { return nil }
        return TennisLiveService.shared.pointScore(player1: away, player2: home)
    }

    private func tennisRow(competitor: Competitor?) -> some View {
        let player = competitor
        let isWinner = player?.winner ?? false
        let linescores = player?.linescores ?? []
        let currentSetIdx = max(0, tennisSetCount - 1)
        let isAway = player?.homeAway == "away" || (player?.homeAway ?? "").isEmpty && player?.id == event.awayCompetitor?.id

        // Live point data from api-tennis.com
        let livePoint = tennisLivePoint
        // Map this player to the api-tennis "first/second" side. Our heuristic:
        // the row's away player is player1 since that's how we pass names into matchKey.
        let playerGameScore: String? = {
            guard let lp = livePoint else { return nil }
            return isAway ? lp.player1Score : lp.player2Score
        }()
        let playerIsServing: Bool = {
            if let lp = livePoint {
                return isAway ? lp.player1IsServing : !lp.player1IsServing
            }
            return player?.isServing ?? false
        }()

        return HStack(spacing: 8) {
            // Seed / rank
            if let seed = player?.seed {
                Text("\(seed)")
                    .font(.caption2).fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .trailing)
            } else {
                Spacer().frame(width: 16)
            }

            TeamLogoView(url: player?.team.logoURL, size: 18)

            // Name
            Text(player?.team.abbreviation ?? player?.team.displayName ?? "—")
                .font(.system(.subheadline, weight: isWinner ? .bold : .regular))
                .lineLimit(1)
                .frame(minWidth: 100, alignment: .leading)

            // Serving ball indicator
            if playerIsServing && event.isLive {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.orange.opacity(0.5), lineWidth: 0.5))
            }

            Spacer()

            // Set-by-set columns
            HStack(spacing: 6) {
                ForEach(Array(linescores.enumerated()), id: \.offset) { idx, ls in
                    if let v = ls.value {
                        let games = Int(v)
                        let isCurrentSet = idx == currentSetIdx && event.isLive
                        Text("\(games)")
                            .font(.system(.subheadline, design: .monospaced).weight(isCurrentSet ? .heavy : .semibold))
                            .foregroundStyle(isCurrentSet ? .primary : .secondary)
                            .frame(width: 14)
                    } else {
                        Text("-").foregroundStyle(.tertiary).frame(width: 14)
                    }
                }
            }

            // Current game score: prefer api-tennis.com live data, fall back
            // to ESPN's competitor.score (rarely populated for tennis).
            if event.isLive {
                if let pg = playerGameScore, !pg.isEmpty {
                    Text(pg)
                        .font(.system(.subheadline, design: .monospaced).weight(.heavy))
                        .foregroundStyle(.yellow)
                        .frame(width: 28)
                } else if let gameScore = player?.tennisGameScore {
                    Text(gameScore)
                        .font(.system(.subheadline, design: .monospaced).weight(.heavy))
                        .foregroundStyle(.yellow)
                        .frame(width: 28)
                }
            }
        }
    }

    private func teamRow(competitor: Competitor?, isWinner: Bool) -> some View {
        HStack(spacing: 8) {
            if let seed = competitor?.seed {
                Text("\(seed)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .trailing)
            } else {
                Spacer().frame(width: 16)
            }

            TeamLogoView(url: competitor?.team.logoURL, size: 20)

            Text(competitor?.team.abbreviation ?? "TBD")
                .font(.system(.subheadline, weight: isWinner ? .bold : .regular))
                .lineLimit(1)

            if let record = competitor?.records?.first(where: { $0.type == "total" })?.summary {
                Text("(\(record))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Show numeric score if present, otherwise tennis-style set scores
            if let raw = competitor?.score, !raw.isEmpty, raw.contains(where: { $0.isNumber }) {
                Text(raw)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(isWinner ? .bold : .regular)
            } else if let linescores = competitor?.linescores, !linescores.isEmpty {
                // Tennis set scores: "6 4 7"
                HStack(spacing: 4) {
                    ForEach(Array(linescores.enumerated()), id: \.offset) { _, ls in
                        if let v = ls.value {
                            Text("\(Int(v))")
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(isWinner ? .bold : .regular)
                        }
                    }
                }
            }

            if isWinner {
                Image(systemName: "chevron.left")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if event.isLive {
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text(event.status.type.shortDetail ?? event.status.type.detail ?? "Live")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)

                if let wp = event.winProbability {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(wp.team) \(Int(wp.probability * 100))%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(wp.probability > 0.85 ? .green : .orange)
                }
            }
        } else if event.isFinal {
            Text(event.status.type.detail ?? "Final")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let date = event.startDate {
            HStack(spacing: 4) {
                Text(DateFormatters.timeOnly.string(from: date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let wp = event.winProbability {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(wp.team) \(Int(wp.probability * 100))%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.blue.opacity(0.8))
                }
            }
        }
    }

    private func isWinner(_ competitor: Competitor?) -> Bool {
        guard let competitor, let other = (competitor.homeAway == "home" ? event.awayCompetitor : event.homeCompetitor) else {
            return false
        }
        guard let score = competitor.scoreInt, let otherScore = other.scoreInt else { return false }
        return score > otherScore
    }
}
