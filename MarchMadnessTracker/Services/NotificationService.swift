import Foundation
import UserNotifications

class NotificationService {
    private var notifiedCloseGameIds = Set<String>()
    private var notifiedUpsetIds = Set<String>()
    private var notifiedHalftimeUpsetIds = Set<String>()

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
        }
    }

    func checkForCloseGames(events: [Event]) {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }

        let threshold = UserDefaults.standard.integer(forKey: "closeGameThreshold")
        let pointThreshold = threshold > 0 ? threshold : Constants.closeGamePointThreshold

        for event in events {
            guard event.isLive,
                  event.status.period >= 2,
                  let clock = event.status.clock,
                  clock <= Constants.closeGameTimeThreshold,
                  let diff = event.scoreDifference,
                  diff <= pointThreshold,
                  !notifiedCloseGameIds.contains(event.id)
            else { continue }

            notifiedCloseGameIds.insert(event.id)
            sendCloseGameNotification(event: event)
        }
    }

    func checkForUpsets(events: [Event]) {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }

        for event in events {
            guard event.isLive,
                  event.isUpset,
                  let magnitude = event.upsetMagnitude,
                  magnitude >= 4, // Only alert for significant upsets (4+ seed difference)
                  event.status.period >= 2,
                  !notifiedUpsetIds.contains(event.id)
            else { continue }

            notifiedUpsetIds.insert(event.id)
            sendUpsetNotification(event: event)
        }
    }

    /// Feature #11: Alert when a 12+ seed is winning at halftime
    func checkForHalftimeUpsets(events: [Event]) {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }

        for event in events {
            guard event.isLive,
                  // At or just past halftime (period 2, clock > 19:00 means just started 2nd half)
                  event.status.period == 2,
                  let clock = event.status.clock,
                  clock >= 1140, // Within first minute of 2nd half (20:00 - 19:00 = ~halftime)
                  let underdog = event.underdog,
                  let favorite = event.favorite,
                  let underdogSeed = underdog.seed,
                  underdogSeed >= 12, // Only for 12+ seeds
                  let underdogScore = underdog.scoreInt,
                  let favoriteScore = favorite.scoreInt,
                  underdogScore > favoriteScore, // Underdog is winning
                  !notifiedHalftimeUpsetIds.contains(event.id)
            else { continue }

            notifiedHalftimeUpsetIds.insert(event.id)
            sendHalftimeUpsetNotification(event: event, underdog: underdog, favorite: favorite)
        }
    }

    func resetForNewDay() {
        notifiedCloseGameIds.removeAll()
        notifiedUpsetIds.removeAll()
        notifiedHalftimeUpsetIds.removeAll()
    }

    private func sendCloseGameNotification(event: Event) {
        let content = UNMutableNotificationContent()
        content.title = "Close Game!"

        let away = event.awayCompetitor
        let home = event.homeCompetitor
        let awayName = away?.team.abbreviation ?? "Away"
        let homeName = home?.team.abbreviation ?? "Home"
        let awayScore = away?.safeScore ?? "0"
        let homeScore = home?.safeScore ?? "0"
        let clock = event.status.displayClock ?? ""
        let period = event.status.period == 2 ? "2nd Half" : "OT"

        content.body = "\(awayName) \(awayScore) - \(homeName) \(homeScore) | \(period) \(clock)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "close-game-\(event.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func sendUpsetNotification(event: Event) {
        let content = UNMutableNotificationContent()

        guard let underdog = event.underdog, let favorite = event.favorite else { return }

        let underdogSeed = underdog.seed ?? 0
        let favoriteSeed = favorite.seed ?? 0
        let underdogScore = underdog.scoreInt ?? 0
        let favoriteScore = favorite.scoreInt ?? 0

        content.title = "Upset Alert!"
        content.body = "#\(underdogSeed) \(underdog.team.abbreviation) \(underdogScore) leads #\(favoriteSeed) \(favorite.team.abbreviation) \(favoriteScore)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "upset-\(event.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func sendHalftimeUpsetNotification(event: Event, underdog: Competitor, favorite: Competitor) {
        let content = UNMutableNotificationContent()

        let underdogSeed = underdog.seed ?? 0
        let favoriteSeed = favorite.seed ?? 0
        let underdogScore = underdog.scoreInt ?? 0
        let favoriteScore = favorite.scoreInt ?? 0
        let lead = underdogScore - favoriteScore

        content.title = "🚨 Cinderella Alert!"
        content.body = "#\(underdogSeed) \(underdog.team.displayName) leads #\(favoriteSeed) \(favorite.team.displayName) \(underdogScore)-\(favoriteScore) at the half! (+\(lead) lead)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "halftime-upset-\(event.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
