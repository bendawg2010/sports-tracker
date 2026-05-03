import Foundation

enum Constants {
    static let popoverWidth: CGFloat = 420
    static let popoverHeight: CGFloat = 580

    static let closeGamePointThreshold = 5
    static let closeGameTimeThreshold: Double = 300 // 5 minutes in seconds

    static let toolbarHeight: CGFloat = 38

    /// Default selected sports for new users
    static let defaultSelectedSportIDs = ["nba", "nfl", "mlb", "f1"]

    /// UserDefaults key for selected sport IDs
    static let selectedSportIDsKey = "selectedSportIDs"
}

// MARK: - Notification Names

extension Notification.Name {
    static let openGameDetail = Notification.Name("openGameDetail")
    static let createGameWidget = Notification.Name("createGameWidget")
    static let openWatchPortal = Notification.Name("openWatchPortal")
    static let openWatchGame = Notification.Name("openWatchGame")
    static let openMultiview = Notification.Name("openMultiview")
    static let sportsSelectionChanged = Notification.Name("sportsSelectionChanged")
}
