import SwiftUI

struct ChaosView: View {
    var poller: ScorePoller

    private var upsets: [Event] {
        poller.games.filter { $0.isUpset }.sorted {
            ($0.upsetMagnitude ?? 0) > ($1.upsetMagnitude ?? 0)
        }
    }

    private var liveUpsets: [Event] {
        upsets.filter { $0.isLive }
    }

    private var completedUpsets: [Event] {
        upsets.filter { $0.isFinal }
    }

    /// Chaos score: sum of all upset seed differentials
    private var chaosScore: Int {
        upsets.filter { $0.isFinal }.compactMap { $0.upsetMagnitude }.reduce(0, +)
    }

    /// Max possible chaos score (rough estimate: all higher seeds winning)
    private var maxChaosScore: Int {
        max(chaosScore, 150) // typical max is ~150 if every underdog wins
    }

    /// Cinderella teams: seeds 10+ still alive (won at least 1 game and not yet eliminated)
    private var cinderellaTeams: [(team: TeamInfo, seed: Int, wins: Int)] {
        var teamWins: [String: (team: TeamInfo, seed: Int, wins: Int)] = [:]

        for game in poller.games.filter({ $0.isFinal }) {
            guard let away = game.awayCompetitor, let home = game.homeCompetitor else { continue }
            guard let awayScore = away.scoreInt, let homeScore = home.scoreInt else { continue }

            let winner = awayScore > homeScore ? away : home
            if let seed = winner.seed, seed >= 10 {
                let key = winner.team.id
                var existing = teamWins[key] ?? (team: winner.team, seed: seed, wins: 0)
                existing.wins += 1
                teamWins[key] = existing
            }
        }

        // Filter out teams that have lost (appeared as a loser in any game)
        var eliminatedTeamIds = Set<String>()
        for game in poller.games.filter({ $0.isFinal }) {
            guard let away = game.awayCompetitor, let home = game.homeCompetitor else { continue }
            guard let awayScore = away.scoreInt, let homeScore = home.scoreInt else { continue }
            let loser = awayScore < homeScore ? away : home
            if let seed = loser.seed, seed >= 10 {
                eliminatedTeamIds.insert(loser.team.id)
            }
        }

        return teamWins.values
            .filter { !eliminatedTeamIds.contains($0.team.id) }
            .sorted { $0.wins > $1.wins }
    }

    /// Biggest upset by seed differential
    private var biggestUpset: Event? {
        completedUpsets.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Chaos Meter
                chaosMeter

                // Live Upsets
                if !liveUpsets.isEmpty {
                    sectionHeader("LIVE UPSETS", icon: "flame.fill", color: .red)
                    ForEach(liveUpsets) { game in
                        UpsetRowView(event: game, isLive: true)
                    }
                }

                // Cinderella Teams
                if !cinderellaTeams.isEmpty {
                    sectionHeader("CINDERELLA TEAMS", icon: "sparkles", color: .yellow)
                    ForEach(cinderellaTeams, id: \.team.id) { entry in
                        cinderellaRow(entry)
                    }
                }

                // All Upsets
                if !completedUpsets.isEmpty {
                    sectionHeader("ALL UPSETS (\(completedUpsets.count))", icon: "exclamationmark.triangle.fill", color: .orange)
                    ForEach(completedUpsets) { game in
                        UpsetRowView(event: game, isLive: false)
                    }
                }

                if upsets.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No upsets yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Check back when games are being played")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Chaos Meter

    private var chaosMeter: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "tornado")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text("CHAOS METER")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(chaosScore)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(chaosGradient)
            }

            // Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(chaosGradient)
                        .frame(width: max(4, geo.size.width * CGFloat(chaosScore) / CGFloat(maxChaosScore)), height: 8)
                }
            }
            .frame(height: 8)

            // Labels
            HStack {
                Text("Chalk")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Chaos")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Stats row
            HStack(spacing: 16) {
                statPill(label: "Upsets", value: "\(completedUpsets.count)", color: .orange)
                statPill(label: "Live", value: "\(liveUpsets.count)", color: .red)
                statPill(label: "Cinderellas", value: "\(cinderellaTeams.count)", color: .yellow)
                if let biggest = biggestUpset, let mag = biggest.upsetMagnitude {
                    statPill(label: "Biggest", value: "+\(mag)", color: .purple)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.orange.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
    }

    private var chaosGradient: LinearGradient {
        LinearGradient(colors: [.yellow, .orange, .red], startPoint: .leading, endPoint: .trailing)
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: - Cinderella Row

    private func cinderellaRow(_ entry: (team: TeamInfo, seed: Int, wins: Int)) -> some View {
        HStack(spacing: 10) {
            if let logoURL = entry.team.logoURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit).frame(width: 24, height: 24)
                    default:
                        Image(systemName: "basketball.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                }
            }

            Text("(\(entry.seed))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(entry.team.displayName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Spacer()

            HStack(spacing: 2) {
                ForEach(0..<entry.wins, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                }
            }

            Text("\(entry.wins) W")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.yellow)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(.yellow.opacity(0.15)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Upset Row

struct UpsetRowView: View {
    let event: Event
    let isLive: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Seed diff badge
            if let mag = event.upsetMagnitude {
                Text("+\(mag)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(magnitudeColor(mag))
                    )
            }

            // Underdog (winner)
            if let underdog = event.underdog {
                HStack(spacing: 4) {
                    if let logoURL = underdog.team.logoURL {
                        AsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18)
                            default:
                                Image(systemName: "basketball.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, height: 18)
                            }
                        }
                    }
                    Text("(\(underdog.seed ?? 0))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(underdog.team.abbreviation)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                }
            }

            // Score
            HStack(spacing: 3) {
                Text(event.awayCompetitor?.safeScore ?? "0")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                Text("-")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(event.homeCompetitor?.safeScore ?? "0")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(isLive ? .red : .primary)

            // Defeated
            Text("def.")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)

            // Favorite (loser)
            if let favorite = event.favorite {
                HStack(spacing: 4) {
                    Text("(\(favorite.seed ?? 0))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(favorite.team.abbreviation)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isLive {
                HStack(spacing: 3) {
                    Circle().fill(.red).frame(width: 5, height: 5)
                    Text("LIVE")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.red)
                }
            } else if let round = event.roundName {
                Text(round)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isLive ? Color.red.opacity(0.06) : Color.orange.opacity(0.04))
        )
        .padding(.horizontal, 8)
    }

    private func magnitudeColor(_ mag: Int) -> Color {
        if mag >= 10 { return .red }
        if mag >= 6 { return .orange }
        return .yellow.opacity(0.8)
    }
}
