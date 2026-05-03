import Foundation
import Observation

@Observable
class SportPollerManager {
    private(set) var pollers: [String: ScorePoller] = [:]

    // Cached aggregates — updated via refreshAggregates() when any poller
    // changes. Recomputing on every access was catastrophic with 22 sports.
    private(set) var activeSportLeagues: [SportLeague] = []
    private(set) var allTickerGames: [Event] = []
    private(set) var hasAnyLiveGames: Bool = false
    private(set) var anyLoading: Bool = false

    private var refreshWorkItem: DispatchWorkItem?

    /// Rebuild cached aggregates. Called after any poller updates its data.
    /// Debounced to avoid thrashing when many pollers update in quick succession.
    func refreshAggregates() {
        refreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.activeSportLeagues = self.pollers.values.map(\.sportLeague)
                .sorted { $0.displayName < $1.displayName }
            self.allTickerGames = self.pollers.values.flatMap(\.tickerGames)
                .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            self.hasAnyLiveGames = self.pollers.values.contains { $0.hasLiveGames }
            self.anyLoading = self.pollers.values.contains { $0.isLoading }
        }
        refreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Get poller for a specific sport
    func poller(for sportId: String) -> ScorePoller? {
        pollers[sportId]
    }

    /// Read selected sport IDs from UserDefaults
    static var selectedSportIDs: [String] {
        get {
            UserDefaults.standard.array(forKey: Constants.selectedSportIDsKey) as? [String]
                ?? Constants.defaultSelectedSportIDs
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.selectedSportIDsKey)
        }
    }

    /// Sync pollers with current settings — starts new pollers, stops removed ones
    func syncWithSettings() {
        let selectedIDs = Set(Self.selectedSportIDs)
        let currentIDs = Set(pollers.keys)

        // Stop removed sports
        for id in currentIDs.subtracting(selectedIDs) {
            pollers[id]?.stopPolling()
            pollers.removeValue(forKey: id)
        }

        // Start new sports
        for id in selectedIDs.subtracting(currentIDs) {
            guard let league = SportLeague.find(id) else { continue }
            let poller = ScorePoller(sportLeague: league)
            poller.onDataChanged = { [weak self] in
                self?.refreshAggregates()
            }
            pollers[id] = poller
            poller.startPolling()
        }
        refreshAggregates()
    }

    /// Toggle a sport on/off
    func toggleSport(_ sportId: String) {
        var ids = Self.selectedSportIDs
        if let idx = ids.firstIndex(of: sportId) {
            ids.remove(at: idx)
        } else {
            ids.append(sportId)
        }
        Self.selectedSportIDs = ids
        syncWithSettings()
        NotificationCenter.default.post(name: .sportsSelectionChanged, object: nil)
    }

    func isSportEnabled(_ sportId: String) -> Bool {
        Self.selectedSportIDs.contains(sportId)
    }

    /// Stop all pollers
    func stopAll() {
        for poller in pollers.values {
            poller.stopPolling()
        }
        pollers.removeAll()
    }

    /// Refresh all active pollers
    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for poller in pollers.values {
                group.addTask {
                    await poller.refreshNow()
                }
            }
        }
    }
}
