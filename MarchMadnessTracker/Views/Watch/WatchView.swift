import SwiftUI

/// Tab inside the popover for watching games via embedded web browser
struct WatchView: View {
    var poller: ScorePoller

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // March Madness Live button (main portal)
                Button {
                    NotificationCenter.default.post(
                        name: .openWatchPortal,
                        object: nil
                    )
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.tv.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("March Madness Live")
                                .font(.system(size: 14, weight: .bold))
                            Text("Watch all games — sign in with your TV provider")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.orange.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)

                // Multiview button
                if poller.games.filter({ $0.isLive }).count >= 2 {
                    Button {
                        NotificationCenter.default.post(
                            name: .openMultiview,
                            object: nil
                        )
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.split.2x2.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Multiview")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Watch \(poller.games.filter { $0.isLive }.count) live games at once")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.blue.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.blue.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                }

                Divider().padding(.horizontal, 12)

                // Individual live games
                let liveGames = poller.games.filter { $0.isLive }
                let upcomingGames = poller.games.filter { $0.isScheduled }

                if !liveGames.isEmpty {
                    sectionHeader("Live Now", icon: "circle.fill", color: .red)

                    ForEach(liveGames) { game in
                        watchGameRow(game)
                    }
                }

                if !upcomingGames.isEmpty {
                    sectionHeader("Upcoming", icon: "clock", color: .secondary)

                    ForEach(upcomingGames.prefix(6)) { game in
                        watchGameRow(game)
                    }
                }

                if liveGames.isEmpty && upcomingGames.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tv")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No games right now")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Open March Madness Live to browse all content")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func watchGameRow(_ game: Event) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .openWatchGame,
                object: nil,
                userInfo: ["eventId": game.id]
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if let seed = game.awayCompetitor?.seed {
                            Text("(\(seed))").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(game.awayCompetitor?.team.abbreviation ?? "TBD")
                            .font(.system(size: 12, weight: .semibold))

                        if game.isLive || game.isFinal {
                            Text(game.awayCompetitor?.score ?? "0")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }

                        Text("vs")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        if game.isLive || game.isFinal {
                            Text(game.homeCompetitor?.score ?? "0")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }

                        Text(game.homeCompetitor?.team.abbreviation ?? "TBD")
                            .font(.system(size: 12, weight: .semibold))
                        if let seed = game.homeCompetitor?.seed {
                            Text("(\(seed))").font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 6) {
                        if game.isLive {
                            HStack(spacing: 3) {
                                Circle().fill(.red).frame(width: 5, height: 5)
                                Text(game.status.type.shortDetail ?? "Live")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.red)
                            }
                        } else if let date = game.startDate {
                            Text(DateFormatters.timeOnly.string(from: date))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        if let broadcast = game.competition?.broadcasts?.first?.names?.first {
                            Text("on \(broadcast)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
