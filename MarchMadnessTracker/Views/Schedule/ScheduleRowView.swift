import SwiftUI

struct ScheduleRowView: View {
    let event: Event

    var body: some View {
        HStack(spacing: 10) {
            // Time
            VStack {
                if let date = event.startDate {
                    Text(DateFormatters.timeOnly.string(from: date))
                        .font(.system(size: 13, weight: .semibold))
                } else if let detail = event.status.type.detail {
                    // ESPN puts time in status detail like "7:10 PM ET"
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Text("TBD")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 75, alignment: .leading)

            // Teams
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let seed = event.awayCompetitor?.seed {
                        Text("(\(seed))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    TeamLogoView(url: event.awayCompetitor?.team.logoURL, size: 14)
                    Text(event.awayCompetitor?.team.displayName ?? "TBD")
                        .font(.caption)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let seed = event.homeCompetitor?.seed {
                        Text("(\(seed))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    TeamLogoView(url: event.homeCompetitor?.team.logoURL, size: 14)
                    Text(event.homeCompetitor?.team.displayName ?? "TBD")
                        .font(.caption)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Broadcast & round info
            VStack(alignment: .trailing, spacing: 2) {
                if let broadcast = event.competition?.broadcasts?.first?.names?.first {
                    Text(broadcast)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let round = event.roundName {
                    Text(round)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
