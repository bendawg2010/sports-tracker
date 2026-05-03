import Foundation
import Observation
import WidgetKit

@Observable
class ScorePoller {
    let sportLeague: SportLeague

    // MARK: - Published state
    var isLoading = false
    var lastUpdated: Date?
    var errorMessage: String?
    var allGamesLoaded = false

    var recentScoreChanges: Set<String> = []
    var scoringTeamIds: [String: String] = [:]

    /// Callback invoked on the main actor whenever the game list is rebuilt.
    /// Used by SportPollerManager to refresh its cached aggregates.
    var onDataChanged: (() -> Void)?

    // MARK: - Cached game lists
    private(set) var games: [Event] = []
    private(set) var liveGames: [Event] = []
    private(set) var completedGames: [Event] = []
    private(set) var scheduledGames: [Event] = []
    private(set) var hasLiveGames: Bool = false
    private(set) var tickerGames: [Event] = []

    // MARK: - Raw data
    private var todayGames: [Event] = [] { didSet { rebuildGameLists() } }
    private(set) var allTournamentGames: [Event] = [] { didSet { rebuildGameLists() } }

    private var previousScores: [String: (String, String)] = [:]
    private var timer: Timer?
    private let service: ESPNService

    init(sportLeague: SportLeague) {
        self.sportLeague = sportLeague
        self.service = ESPNService(sportLeague: sportLeague)
    }

    // MARK: - Rebuild cached lists

    private func rebuildGameLists() {
        var merged: [String: Event] = [:]
        for game in allTournamentGames { merged[game.id] = game }
        for game in todayGames { merged[game.id] = game }
        let sorted = Array(merged.values).sorted { a, b in
            (a.startDate ?? .distantFuture) < (b.startDate ?? .distantFuture)
        }

        games = sorted
        liveGames = sorted.filter { $0.isLive }
        completedGames = sorted.filter { $0.isFinal }
        scheduledGames = sorted.filter { $0.isScheduled }
        hasLiveGames = !liveGames.isEmpty
        tickerGames = buildTickerGames()
        onDataChanged?()
    }

    private func buildTickerGames() -> [Event] {
        let calendar = Calendar.current
        let now = Date()

        let live = liveGames.filter { hasRealTeams($0) }.sorted { a, b in
            (a.scoreDifference ?? 999) < (b.scoreDifference ?? 999)
        }

        let todayFinals = completedGames.filter { event in
            hasRealTeams(event) && {
                guard let date = event.startDate else { return false }
                return calendar.isDateInToday(date)
            }()
        }.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }

        let todayUpcoming = scheduledGames.filter { event in
            hasRealTeams(event) && {
                guard let date = event.startDate else { return false }
                return calendar.isDateInToday(date) && date > now
            }()
        }.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }

        let yesterdayFinals = completedGames.filter { event in
            hasRealTeams(event) && {
                guard let date = event.startDate else { return false }
                return calendar.isDateInYesterday(date)
            }()
        }.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }

        let result = live + todayFinals + todayUpcoming
        if result.isEmpty {
            let fallback = (yesterdayFinals + completedGames.filter { hasRealTeams($0) }.suffix(8))
            var seen = Set<String>()
            return fallback.filter { seen.insert($0.id).inserted }
        }
        return result
    }

    var currentPollingInterval: TimeInterval {
        // Read user-adjustable polling intervals from settings.
        // Fall back to the sport's defaults if not yet set.
        let live = UserDefaults.standard.double(forKey: "livePollingSeconds")
        let idle = UserDefaults.standard.double(forKey: "idlePollingSeconds")
        let liveInterval = live > 0 ? live : sportLeague.livePollingInterval
        let idleInterval = idle > 0 ? idle : sportLeague.idlePollingInterval
        return hasLiveGames ? liveInterval : idleInterval
    }

    var gamesByRound: [(String, [Event])] {
        let grouped = Dictionary(grouping: games) { event -> String in
            event.roundName ?? "Games"
        }
        if sportLeague.hasBracket {
            let roundOrder = ["First Four", "1st Round", "2nd Round", "Sweet 16", "Elite 8", "Final Four", "National Championship"]
            return grouped.sorted { a, b in
                let idxA = roundOrder.firstIndex(where: { a.key.localizedCaseInsensitiveContains($0) }) ?? 99
                let idxB = roundOrder.firstIndex(where: { b.key.localizedCaseInsensitiveContains($0) }) ?? 99
                return idxA < idxB
            }
        }
        // Non-bracket sports: sort by date
        return grouped.sorted { a, b in
            let dateA = a.value.first?.startDate ?? .distantFuture
            let dateB = b.value.first?.startDate ?? .distantFuture
            return dateA < dateB
        }
    }

    var gamesByDate: [(String, [Event])] {
        let grouped = Dictionary(grouping: games) { event -> String in
            guard let date = event.startDate else { return "TBD" }
            return DateFormatters.dayHeader.string(from: date)
        }
        return grouped.sorted { a, b in
            let dateA = a.value.first?.startDate ?? .distantFuture
            let dateB = b.value.first?.startDate ?? .distantFuture
            return dateA < dateB
        }
    }

    private func hasRealTeams(_ event: Event) -> Bool {
        guard let comp = event.competition else { return false }
        let realTeams = comp.competitors.filter { !$0.team.abbreviation.isEmpty && $0.team.abbreviation != "TBD" }
        return realTeams.count >= 2
    }

    func startPolling() {
        Task {
            await refreshNow()
            if sportLeague.hasBracket {
                await fetchAllTournamentGames()
            }
        }
        scheduleTimer()
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refreshNow() async {
        isLoading = true
        errorMessage = nil

        do {
            // Single request instead of 3 parallel — default scoreboard already
            // returns today's games. Only fetch tomorrow when we have no live
            // games to be aware of upcoming matchups.
            let defaultResponse = try await service.fetchScoreboard(tournamentOnly: false)

            var allEvents: [Event] = []
            var seenIds = Set<String>()

            for event in defaultResponse.events {
                if seenIds.insert(event.id).inserted { allEvents.append(event) }
            }

            // If the default response is empty (off-season / no games today),
            // fall back to tomorrow so the widget can show an upcoming game.
            if allEvents.isEmpty {
                if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                   let tomorrowResponse = try? await service.fetchScoreboard(date: tomorrow, tournamentOnly: false) {
                    for event in tomorrowResponse.events {
                        if seenIds.insert(event.id).inserted { allEvents.append(event) }
                    }
                }
            }

            let finalEvents = allEvents
            await MainActor.run {
                let allEvents = finalEvents
                var changedIds = Set<String>()
                var newScoringTeamIds: [String: String] = [:]
                for event in allEvents {
                    let awayScore = event.awayCompetitor?.safeScore ?? "0"
                    let homeScore = event.homeCompetitor?.safeScore ?? "0"
                    if let prev = self.previousScores[event.id] {
                        let awayChanged = prev.0 != awayScore
                        let homeChanged = prev.1 != homeScore
                        if awayChanged || homeChanged {
                            changedIds.insert(event.id)
                            if awayChanged && !homeChanged {
                                newScoringTeamIds[event.id] = event.awayCompetitor?.team.id ?? ""
                            } else if homeChanged && !awayChanged {
                                newScoringTeamIds[event.id] = event.homeCompetitor?.team.id ?? ""
                            } else {
                                let awayDiff = (Int(awayScore) ?? 0) - (Int(prev.0) ?? 0)
                                let homeDiff = (Int(homeScore) ?? 0) - (Int(prev.1) ?? 0)
                                newScoringTeamIds[event.id] = awayDiff >= homeDiff
                                    ? (event.awayCompetitor?.team.id ?? "")
                                    : (event.homeCompetitor?.team.id ?? "")
                            }
                        }
                    }
                    self.previousScores[event.id] = (awayScore, homeScore)
                }
                self.recentScoreChanges = changedIds
                self.scoringTeamIds = newScoringTeamIds

                if !changedIds.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.recentScoreChanges.subtract(changedIds)
                    }
                }

                self.todayGames = allEvents
                self.lastUpdated = Date()
                self.isLoading = false
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func fetchAllTournamentGames() async {
        guard sportLeague.hasBracket else { return }

        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let startComponents = DateComponents(year: year, month: 3, day: 17)
        let endComponents = DateComponents(year: year, month: 4, day: 8)

        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(from: endComponents) else { return }

        do {
            let events = try await service.fetchGamesInRange(from: startDate, to: endDate)
            await MainActor.run {
                self.allTournamentGames = events
                self.allGamesLoaded = true
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            // Supplementary data; don't show error
        }
    }

    func gameForTeam(teamId: String) -> Event? {
        if let live = liveGames.first(where: { containsTeam($0, teamId: teamId) }) {
            return live
        }
        if let scheduled = scheduledGames.first(where: { containsTeam($0, teamId: teamId) }) {
            return scheduled
        }
        return completedGames.last(where: { containsTeam($0, teamId: teamId) })
    }

    private func containsTeam(_ event: Event, teamId: String) -> Bool {
        event.competition?.competitors.contains { $0.team.id == teamId } ?? false
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = currentPollingInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.refreshNow()
                await MainActor.run {
                    self.scheduleTimer()
                }
            }
        }
    }
}
