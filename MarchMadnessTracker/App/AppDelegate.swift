import AppKit
import SwiftUI
import WidgetKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var toolbarWindow: ToolbarWindow?
    private var widgetWindows: [String: ScoreWidgetWindow] = [:]
    private var settingsWindow: NSWindow?
    private var gameDetailWindows: [String: NSWindow] = [:]
    private var watchWindows: [String: NSWindow] = [:]
    private var multiviewWindow: NSWindow?
    let manager = SportPollerManager()
    let notificationService = NotificationService()
    private var wasAutoHidden = false
    private var tickerSizeObserver: NSKeyValueObservation?

    /// Convenience: the first active poller (for legacy single-poller views)
    var primaryPoller: ScorePoller? {
        manager.pollers.values.first
    }

    var isToolbarVisible: Bool {
        toolbarWindow?.isVisible ?? false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupNotifications()
        setupViewNotifications()

        manager.syncWithSettings()

        // Start live tennis point scoring service (noop when no API key set)
        TennisLiveService.shared.startPolling()

        // DO NOT force reloadAllTimelines() on every launch — it starves the
        // widget extension budget when 13 widgets all fetch from ESPN at once.
        // ScorePoller already calls reloadAllTimelines() after each data
        // refresh, which is the right moment for widgets to update.

        observeScoreUpdates()
        observeTickerSizeChanges()
        observeSportsChanges()

        if UserDefaults.standard.bool(forKey: "toolbarEnabled") {
            showToolbar()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stopAll()
        toolbarWindow?.close()
        widgetWindows.values.forEach { $0.close() }
        settingsWindow?.close()
        gameDetailWindows.values.forEach { $0.close() }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "trophy.fill", accessibilityDescription: "Sports Tracker")
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: Constants.popoverWidth, height: Constants.popoverHeight)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(
                manager: manager,
                onToggleToolbar: { [weak self] in self?.toggleToolbar() },
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        )
    }

    private func rebuildPopover() {
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(
                manager: manager,
                onToggleToolbar: { [weak self] in self?.toggleToolbar() },
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        )
    }

    // MARK: - Sports Changes

    private func observeSportsChanges() {
        NotificationCenter.default.addObserver(
            forName: .sportsSelectionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildToolbarIfNeeded()
        }
    }

    private func rebuildToolbarIfNeeded() {
        guard isToolbarVisible else { return }
        toolbarWindow?.close()
        toolbarWindow = nil
        showToolbar()
    }

    // MARK: - Toolbar Window

    func showToolbar() {
        if toolbarWindow == nil {
            toolbarWindow = ToolbarWindow(manager: manager, onClose: { [weak self] in
                self?.hideToolbar()
            }, onDetachGame: { [weak self] event in
                self?.createWidget(for: event)
            })
        }
        toolbarWindow?.orderFront(nil)
        UserDefaults.standard.set(true, forKey: "toolbarEnabled")
        wasAutoHidden = false
    }

    func hideToolbar() {
        toolbarWindow?.orderOut(nil)
        UserDefaults.standard.set(false, forKey: "toolbarEnabled")
    }

    func toggleToolbar() {
        if isToolbarVisible {
            hideToolbar()
        } else {
            showToolbar()
        }
        rebuildPopover()
    }

    // MARK: - Score Widgets

    func createWidget(for event: Event) {
        guard widgetWindows[event.id] == nil else {
            widgetWindows[event.id]?.orderFront(nil)
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let widgetCount = CGFloat(widgetWindows.count)
        let x = screen.frame.width - 300 - (widgetCount * 20)
        let y = screen.frame.height - 200 - (widgetCount * 30)

        // Find the poller that owns this event
        let poller = manager.pollers.values.first { p in
            p.games.contains { $0.id == event.id }
        } ?? primaryPoller

        guard let poller else { return }

        let widget = ScoreWidgetWindow(
            eventId: event.id,
            poller: poller,
            manager: manager,
            position: NSPoint(x: x, y: y),
            onClose: { [weak self] in
                self?.widgetWindows.removeValue(forKey: event.id)
            }
        )
        widget.orderFront(nil)
        widgetWindows[event.id] = widget
    }

    // MARK: - Settings Window

    func openSettings() {
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sports Tracker Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView(manager: manager))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Game Detail Window

    func openGameDetail(for event: Event) {
        if let existing = gameDetailWindows[event.id], existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "\(event.awayCompetitor?.team.abbreviation ?? "Away") vs \(event.homeCompetitor?.team.abbreviation ?? "Home")"
        window.isFloatingPanel = true
        window.level = .floating
        window.contentViewController = NSHostingController(
            rootView: GameDetailView(event: event, onCreateWidget: { [weak self] in
                self?.createWidget(for: event)
            })
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        gameDetailWindows[event.id] = window
    }

    // MARK: - View Notifications

    private func setupViewNotifications() {
        NotificationCenter.default.addObserver(
            forName: .openGameDetail,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let eventId = notification.userInfo?["eventId"] as? String else { return }
            let event = self?.findEvent(id: eventId)
            if let event { self?.openGameDetail(for: event) }
        }

        NotificationCenter.default.addObserver(
            forName: .createGameWidget,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let eventId = notification.userInfo?["eventId"] as? String else { return }
            let event = self?.findEvent(id: eventId)
            if let event { self?.createWidget(for: event) }
        }

        NotificationCenter.default.addObserver(
            forName: .openWatchPortal,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openWatchPortal()
        }

        NotificationCenter.default.addObserver(
            forName: .openWatchGame,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let eventId = notification.userInfo?["eventId"] as? String,
                  let sportId = notification.userInfo?["sportId"] as? String else { return }
            let event = self?.findEvent(id: eventId)
            let sport = SportLeague.find(sportId)
            if let event { self?.openWatchGame(event, sport: sport) }
        }

        NotificationCenter.default.addObserver(
            forName: .openMultiview,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openMultiview()
        }
    }

    /// Find an event across all pollers
    private func findEvent(id: String) -> Event? {
        for poller in manager.pollers.values {
            if let event = poller.games.first(where: { $0.id == id }) {
                return event
            }
        }
        return nil
    }

    // MARK: - Watch

    private func openWatchPortal() {
        let url = URL(string: "https://www.espn.com/watch/")!
        let window = WatchGameWindow(url: url, title: "ESPN Watch")
        watchWindows["portal"] = window
    }

    private func openWatchGame(_ event: Event, sport: SportLeague? = nil) {
        if let existing = watchWindows[event.id], existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let away = event.awayCompetitor?.team.abbreviation ?? "Away"
        let home = event.homeCompetitor?.team.abbreviation ?? "Home"
        let segment = sport?.espnWebSegment ?? "sports"
        let url = URL(string: "https://www.espn.com/\(segment)/game/_/gameId/\(event.id)")!
        let window = WatchGameWindow(url: url, title: "\(away) vs \(home)")
        watchWindows[event.id] = window
    }

    private func openMultiview() {
        if let existing = multiviewWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Get all live games across all sports
        let allLive = manager.pollers.values.flatMap(\.liveGames)
        if allLive.isEmpty { return }

        let ranked = allLive.sorted { a, b in
            gameExcitementScore(a) > gameExcitementScore(b)
        }
        let gamesToShow = Array(ranked.prefix(4))

        let streams: [(url: URL, title: String)] = gamesToShow.compactMap { game in
            let away = game.awayCompetitor?.team.abbreviation ?? "Away"
            let home = game.homeCompetitor?.team.abbreviation ?? "Home"
            // Find sport for this game
            let sport = manager.pollers.values.first { p in
                p.games.contains { $0.id == game.id }
            }?.sportLeague
            let segment = sport?.espnWebSegment ?? "sports"
            let url = URL(string: "https://www.espn.com/\(segment)/game/_/gameId/\(game.id)")!
            return (url: url, title: "\(away) vs \(home)")
        }

        let window = MultiviewWindow(urls: streams)
        multiviewWindow = window
    }

    private func gameExcitementScore(_ game: Event) -> Int {
        var score = 0
        if let diff = game.scoreDifference {
            score += max(0, 20 - diff) * 3
        }
        if let awaySeed = game.awayCompetitor?.seed,
           let homeSeed = game.homeCompetitor?.seed,
           let awayScore = game.awayCompetitor?.scoreInt,
           let homeScore = game.homeCompetitor?.scoreInt {
            let seedDiff = abs(awaySeed - homeSeed)
            if (awaySeed > homeSeed && awayScore > homeScore) ||
               (homeSeed > awaySeed && homeScore > awayScore) {
                score += seedDiff * 4
            }
        }
        if game.status.period >= 3 { score += 25 }
        else if game.status.period == 2 { score += 10 }
        return score
    }

    // MARK: - Ticker Size

    private func observeTickerSizeChanges() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateToolbarSize()
        }
    }

    private func updateToolbarSize() {
        guard let toolbarWindow else { return }
        let size = UserDefaults.standard.double(forKey: "tickerSize")
        let height = size > 0 ? size : 38

        if let screen = NSScreen.main {
            let menuBarHeight = screen.frame.height - screen.visibleFrame.height - screen.visibleFrame.origin.y
            let yPos = screen.frame.height - menuBarHeight - height
            toolbarWindow.setFrame(
                NSRect(x: 0, y: yPos, width: screen.frame.width, height: height),
                display: true,
                animate: true
            )
        }
    }

    // MARK: - Auto-hide ticker when no games

    private func updateToolbarAutoHide() {
        let toolbarEnabled = UserDefaults.standard.bool(forKey: "toolbarEnabled")
        let hasActiveGames = !manager.allTickerGames.isEmpty

        if toolbarEnabled || wasAutoHidden {
            if hasActiveGames && !isToolbarVisible {
                showToolbar()
                wasAutoHidden = false
            } else if !hasActiveGames && isToolbarVisible {
                toolbarWindow?.orderOut(nil)
                wasAutoHidden = true
            }
        }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        notificationService.requestPermission()

        if UserDefaults.standard.object(forKey: "notificationsEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "notificationsEnabled")
        }
        if UserDefaults.standard.integer(forKey: "closeGameThreshold") == 0 {
            UserDefaults.standard.set(Constants.closeGamePointThreshold, forKey: "closeGameThreshold")
        }
    }

    // MARK: - Updates

    private func observeScoreUpdates() {
        // 15s is enough for notifications; score flashes still fire per-poll.
        // With 22 sports a 3s timer was iterating hundreds of events every tick.
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateMenuBarTitle()
            let allGames = self.manager.pollers.values.flatMap(\.games)
            self.notificationService.checkForCloseGames(events: allGames)
            self.notificationService.checkForUpsets(events: allGames)
            self.notificationService.checkForHalftimeUpsets(events: allGames)
            self.updateToolbarAutoHide()
            self.updateMenuBarIcon()
        }
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem.button else { return }
        // Show sport-specific icon if there's a live game
        if let livePoller = manager.pollers.values.first(where: { $0.hasLiveGames }) {
            let iconName = livePoller.sportLeague.icon
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: livePoller.sportLeague.shortName)
            button.image?.size = NSSize(width: 18, height: 18)
        } else {
            button.image = NSImage(systemSymbolName: "trophy.fill", accessibilityDescription: "Sports Tracker")
            button.image?.size = NSSize(width: 18, height: 18)
        }
    }

    private func updateMenuBarTitle() {
        guard let favoriteTeamId = UserDefaults.standard.string(forKey: "favoriteTeamId"),
              !favoriteTeamId.isEmpty,
              let button = statusItem.button else {
            statusItem.button?.title = ""
            return
        }

        // Search across all pollers for the favorite team
        for poller in manager.pollers.values {
            if let game = poller.gameForTeam(teamId: favoriteTeamId) {
                if game.isLive {
                    let away = game.awayCompetitor
                    let home = game.homeCompetitor
                    button.title = " \(away?.team.abbreviation ?? "") \(away?.safeScore ?? "0")-\(home?.safeScore ?? "0") \(home?.team.abbreviation ?? "")"
                } else if game.isScheduled, let date = game.startDate {
                    button.title = " \(DateFormatters.timeOnly.string(from: date))"
                } else {
                    button.title = ""
                }
                return
            }
        }
        button.title = ""
    }

    // MARK: - Actions

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
