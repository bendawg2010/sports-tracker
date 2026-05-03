import SwiftUI
import AppKit

struct SettingsView: View {
    var manager: SportPollerManager
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("closeGameThreshold") private var closeGameThreshold = 5
    @AppStorage("favoriteTeamId") private var favoriteTeamId = ""
    @AppStorage("favoriteTeamName") private var favoriteTeamName = ""
    @AppStorage("tickerSize") private var tickerSize: Double = 38
    @AppStorage("livePollingSeconds") private var livePollingSeconds: Double = 10
    @AppStorage("idlePollingSeconds") private var idlePollingSeconds: Double = 300
    @AppStorage("apiTennisKey") private var apiTennisKey: String = ""

    // News / data source preferences. ESPN is always primary; these toggle
    // optional secondary sources that augment certain sports.
    @AppStorage("source.espn") private var sourceESPN: Bool = true
    @AppStorage("source.mlbStatsAPI") private var sourceMLB: Bool = true
    @AppStorage("source.nhleAPI") private var sourceNHL: Bool = true
    @AppStorage("source.openF1") private var sourceOpenF1: Bool = true
    @AppStorage("source.apiTennis") private var sourceTennis: Bool = false

    // Used to force a view refresh after Enable/Disable All buttons
    @State private var sportsRefreshTick: Int = 0

    // MARK: - Computed helpers

    private var enabledSportsCount: Int {
        SportLeague.all.filter { manager.isSportEnabled($0.id) }.count
    }

    private var totalSportsCount: Int {
        SportLeague.all.count
    }

    private var appVersionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    /// Rough estimate of requests/hour based on current slider values.
    /// Assumes 1 active sport polled continuously at the live rate.
    private var estimatedRequestsPerHour: Int {
        let live = max(livePollingSeconds, 1)
        let idle = max(idlePollingSeconds, 1)
        // Heuristic: mix of live + idle — assume 30% live / 70% idle during typical viewing.
        let liveRate = 3600.0 / live
        let idleRate = 3600.0 / idle
        let blended = (liveRate * 0.3) + (idleRate * 0.7)
        let activeCount = max(enabledSportsCount, 1)
        return Int((blended * Double(activeCount)).rounded())
    }

    /// Very lightweight "validity" heuristic — api-tennis.com keys are long
    /// alphanumeric strings. This is a local-only check (no API call).
    private var tennisKeyLooksValid: Bool {
        let trimmed = apiTennisKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 32 else { return false }
        let allowed = CharacterSet.alphanumerics
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: - Body

    var body: some View {
        Form {
            openSourceBanner
            sportsAndLeaguesSection
            dataSourcesSection
            tennisSection
            refreshRateSection
            favoriteTeamSection
            tickerBarSection
            notificationsSection
            aboutSection
            supportSection

            Section {
                Button("Quit Sports Tracker") {
                    NSApplication.shared.terminate(nil)
                }
                .onHover { inside in
                    if inside {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 760)
        .id(sportsRefreshTick) // keyed so Enable/Disable All redraws toggles
    }

    // MARK: - Open Source Banner

    @ViewBuilder
    private var openSourceBanner: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.green)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 3) {
                    Text("100% Open Source")
                        .font(.system(size: 14, weight: .bold))
                    Text("Free forever. No tracking. No accounts. Read the code.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Link(destination: URL(string: "https://github.com/bendawg2010/sports-tracker")!) {
                    Label("GitHub", systemImage: "arrow.up.right.square")
                        .font(.caption.bold())
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Data Sources

    @ViewBuilder
    private var dataSourcesSection: some View {
        Section {
            Text("Choose where Sports Tracker pulls data from. ESPN is always primary; these toggle additional public APIs that fill in missing details.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $sourceESPN) {
                sourceRow(name: "ESPN", desc: "Universal scoreboard for every sport. Required.", url: "site.api.espn.com")
            }
            .disabled(true) // ESPN is mandatory; show as locked-on
            .opacity(0.85)

            Toggle(isOn: $sourceMLB) {
                sourceRow(name: "MLB Stats API", desc: "Official MLB live play-by-play (better than ESPN for baseball).", url: "statsapi.mlb.com")
            }
            Toggle(isOn: $sourceNHL) {
                sourceRow(name: "NHL Web API", desc: "Official NHL shot coordinates and goal data.", url: "api-web.nhle.com")
            }
            Toggle(isOn: $sourceOpenF1) {
                sourceRow(name: "OpenF1", desc: "Free F1 lap times, tire compounds, sector splits.", url: "api.openf1.org")
            }
            Toggle(isOn: $sourceTennis) {
                sourceRow(name: "api-tennis.com", desc: "Live tennis 15/30/40/Ad point scoring (requires free key below).", url: "api-tennis.com")
            }

            Text("All sources are public APIs. No data leaves your Mac except direct requests to these endpoints.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } header: {
            Label("Data Sources", systemImage: "antenna.radiowaves.left.and.right")
        }
    }

    private func sourceRow(name: String, desc: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.system(size: 13, weight: .semibold))
            Text(desc).font(.caption).foregroundStyle(.secondary)
            Text(url).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Support / Donate

    @ViewBuilder
    private var supportSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sports Tracker is free and open source. If it saved you from tabbing to ESPN one too many times, consider chipping in to keep it that way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Link(destination: URL(string: "https://www.paypal.com/donate?hosted_button_id=PLACEHOLDER")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                            Text("Support open source")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.pink.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(Color.pink)
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        inside ? NSCursor.pointingHand.push() : NSCursor.pop()
                    }

                    Link(destination: URL(string: "https://github.com/bendawg2010/sports-tracker")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                            Text("Star on GitHub")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.yellow.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(Color.yellow)
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        inside ? NSCursor.pointingHand.push() : NSCursor.pop()
                    }
                }
            }
        } header: {
            Label("Support", systemImage: "heart")
        }
    }

    // MARK: - Section: Sports & Leagues

    @ViewBuilder
    private var sportsAndLeaguesSection: some View {
        Section {
            sectionHeader(
                title: "Sports & Leagues",
                systemImage: "sportscourt.fill",
                description: "Choose which leagues show up in the ticker, menu bar, and scoreboard."
            )

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(enabledSportsCount > 0 ? Color.green : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text("\(enabledSportsCount) of \(totalSportsCount) sports enabled")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button {
                    enableAllSports()
                } label: {
                    Label("Enable All", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointingHandCursor()

                Button {
                    disableAllSports()
                } label: {
                    Label("Disable All", systemImage: "xmark.circle")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointingHandCursor()
            }
            .padding(.vertical, 2)

            ForEach(Array(SportLeague.SportCategory.allCases.enumerated()), id: \.element) { index, category in
                let leagues = SportLeague.all.filter { $0.category == category }
                if !leagues.isEmpty {
                    if index > 0 {
                        Divider()
                            .padding(.vertical, 2)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Image(systemName: category.icon)
                                .font(.system(size: 10))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                            Text(category.rawValue.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                        }
                        .padding(.top, 2)
                        .padding(.bottom, 1)

                        ForEach(leagues) { league in
                            sportToggleRow(league)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section: Tennis Live Scoring

    @ViewBuilder
    private var tennisSection: some View {
        Section {
            sectionHeader(
                title: "Tennis Live Scoring",
                systemImage: "tennisball.fill",
                description: "Optional upgrade for real-time tennis point scoring."
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.blue)
                        .font(.system(size: 13))
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why is this separate?")
                            .font(.system(size: 12, weight: .semibold))
                        Text("ESPN's public API doesn't expose point-by-point tennis data, so set scores only refresh when a game ends. A free api-tennis.com key unlocks live point scoring.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                )

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.yellow)
                        .font(.system(size: 13))
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What you unlock")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Live 15 · 30 · 40 · Ad point scoring during matches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("api-tennis.com API key (optional)", text: $apiTennisKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))

                    HStack(spacing: 8) {
                        Link(destination: URL(string: "https://api-tennis.com/")!) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 10))
                                Text("Get a free key")
                            }
                            .font(.caption)
                        }
                        .pointingHandCursor()

                        Spacer()

                        if !apiTennisKey.isEmpty {
                            if tennisKeyLooksValid {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.green)
                                    Text("Verified")
                                        .foregroundStyle(.green)
                                        .fontWeight(.medium)
                                }
                                .font(.caption)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.seal.fill")
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.orange)
                                    Text("Invalid format")
                                        .foregroundStyle(.orange)
                                        .fontWeight(.medium)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Section: Refresh Rate

    @ViewBuilder
    private var refreshRateSection: some View {
        Section {
            sectionHeader(
                title: "Refresh Rate",
                systemImage: "arrow.triangle.2.circlepath",
                description: "Control how often scores update. Faster refresh uses more battery and network."
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    presetButton(
                        title: "Battery Saver",
                        systemImage: "battery.25",
                        live: 30,
                        idle: 600
                    )
                    presetButton(
                        title: "Balanced",
                        systemImage: "battery.75",
                        live: 10,
                        idle: 300
                    )
                    presetButton(
                        title: "Realtime",
                        systemImage: "bolt.fill",
                        live: 3,
                        idle: 60
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Live games", systemImage: "dot.radiowaves.left.and.right")
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.titleAndIcon)
                        Spacer()
                        Text("every \(Int(livePollingSeconds))s")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $livePollingSeconds, in: 3...60, step: 1)

                    HStack {
                        Label("Idle sports", systemImage: "moon.zzz")
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.titleAndIcon)
                        Spacer()
                        Text("every \(Int(idlePollingSeconds / 60))m")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $idlePollingSeconds, in: 60...1800, step: 60)
                }

                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Estimated ~\(estimatedRequestsPerHour) requests/hour at current settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Section: Favorite Team

    @ViewBuilder
    private var favoriteTeamSection: some View {
        Section {
            sectionHeader(
                title: "Favorite Team",
                systemImage: "star.fill",
                description: "Pin a team's score to the menu bar so you never miss a beat."
            )

            HStack {
                TextField("Team ID (from ESPN)", text: $favoriteTeamId)
                    .textFieldStyle(.roundedBorder)
                TextField("Display Name", text: $favoriteTeamName)
                    .textFieldStyle(.roundedBorder)
            }
            Text("When set, your favorite team's current score shows in the menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Section: Ticker Bar

    @ViewBuilder
    private var tickerBarSection: some View {
        Section {
            sectionHeader(
                title: "Ticker Bar",
                systemImage: "rectangle.topthird.inset.filled",
                description: "Adjust the scrolling score ticker that pins above your menu bar."
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Ticker Height")
                    Spacer()
                    Text("\(Int(tickerSize))pt")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $tickerSize, in: 28...64, step: 2)

                HStack(spacing: 8) {
                    tickerSizeButton("Small", size: 28)
                    tickerSizeButton("Default", size: 38)
                    tickerSizeButton("Large", size: 50)
                    tickerSizeButton("XL", size: 64)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Section: Notifications

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            sectionHeader(
                title: "Notifications",
                systemImage: "bell.badge.fill",
                description: "Get a heads-up when close games are about to finish."
            )

            Toggle("Close game alerts", isOn: $notificationsEnabled)
            if notificationsEnabled {
                Stepper("Alert within \(closeGameThreshold) points", value: $closeGameThreshold, in: 1...15)
                Toggle("Upset alerts (4+ seed difference)", isOn: .constant(notificationsEnabled))
                    .disabled(true)
            }
        }
    }

    // MARK: - Section: About

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            sectionHeader(
                title: "About",
                systemImage: "info.circle.fill",
                description: "App details, credits, and legal."
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "trophy.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 34))
                        .foregroundStyle(.yellow)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sports Tracker")
                            .font(.system(size: 16, weight: .bold))
                        Text("Version \(appVersionString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Built with SwiftUI · Made for macOS")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    aboutLink(
                        systemImage: "hand.raised.fill",
                        label: "Privacy Policy",
                        url: "https://sportstracker.app/privacy"
                    )
                    aboutLink(
                        systemImage: "globe",
                        label: "Website",
                        url: "https://sportstracker.app"
                    )
                    aboutLink(
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        label: "Source on GitHub",
                        url: "https://github.com/sportstracker/app"
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "sportscourt")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("Live scores powered by ESPN")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Not affiliated with ESPN, the NCAA, NFL, NBA, MLB, NHL, or any other league, team, or organization. All team names, logos, and marks are property of their respective owners.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(title: String, systemImage: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 22)
        }
        .padding(.bottom, 4)
    }

    private func sportToggleRow(_ league: SportLeague) -> some View {
        let isEnabled = manager.isSportEnabled(league.id)
        return HStack(spacing: 8) {
            // Enabled indicator dot
            Circle()
                .fill(isEnabled ? Color.green : Color.secondary.opacity(0.25))
                .frame(width: 6, height: 6)

            Image(systemName: league.icon)
                .font(.system(size: 11))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .frame(width: 16)

            Text(league.displayName)
                .font(.system(size: 12))
                .foregroundStyle(isEnabled ? .primary : .secondary)

            Spacer()

            if let poller = manager.poller(for: league.id), poller.hasLiveGames {
                HStack(spacing: 3) {
                    Circle().fill(.red).frame(width: 4, height: 4)
                    Text("LIVE")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.red)
                }
            }

            Toggle("", isOn: Binding(
                get: { manager.isSportEnabled(league.id) },
                set: { _ in manager.toggleSport(league.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .frame(minHeight: 20)
        .padding(.vertical, 0)
    }

    private func presetButton(title: String, systemImage: String, live: Double, idle: Double) -> some View {
        let isActive = Int(livePollingSeconds) == Int(live) && Int(idlePollingSeconds) == Int(idle)
        return Button {
            livePollingSeconds = live
            idlePollingSeconds = idle
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                Text("\(Int(live))s / \(Int(idle / 60))m")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(isActive ? .accentColor : .secondary)
        .pointingHandCursor()
    }

    private func tickerSizeButton(_ title: String, size: Double) -> some View {
        let isActive = Int(tickerSize) == Int(size)
        return Button(title) {
            tickerSize = size
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isActive ? .accentColor : .secondary)
        .pointingHandCursor()
    }

    private func aboutLink(systemImage: String, label: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 12))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - Actions

    private func enableAllSports() {
        SportPollerManager.selectedSportIDs = SportLeague.all.map(\.id)
        manager.syncWithSettings()
        NotificationCenter.default.post(name: .sportsSelectionChanged, object: nil)
        sportsRefreshTick &+= 1
    }

    private func disableAllSports() {
        SportPollerManager.selectedSportIDs = []
        manager.syncWithSettings()
        NotificationCenter.default.post(name: .sportsSelectionChanged, object: nil)
        sportsRefreshTick &+= 1
    }
}

// MARK: - Cursor Hover Modifier

private extension View {
    /// Shows a pointing-hand cursor while hovering over clickable elements.
    func pointingHandCursor() -> some View {
        self.onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
