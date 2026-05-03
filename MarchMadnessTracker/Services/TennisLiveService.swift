import Foundation
import Observation

/// Fetches live point-by-point tennis scoring from api-tennis.com.
/// ESPN's free API only exposes set scores and current set games.
/// When the user provides an api-tennis.com key in Settings, this service
/// polls their livescore endpoint and caches per-match point data keyed by
/// player name pairs, which GameRowView looks up at render time.
@Observable
final class TennisLiveService {
    static let shared = TennisLiveService()

    /// Cached point data keyed by a normalized player-pair string like
    /// "alcaraz::etcheverry" (sorted + lowercased last names).
    private(set) var pointScores: [String: TennisPointData] = [:]
    private(set) var lastFetch: Date?

    private var fetchTask: Task<Void, Never>?
    private let session = URLSession.shared

    private init() {}

    struct TennisPointData {
        let player1Score: String       // "0" "15" "30" "40" "Ad"
        let player2Score: String
        let player1IsServing: Bool
        let isBreakPoint: Bool
        let isSetPoint: Bool
        let isMatchPoint: Bool
        let fetchedAt: Date
    }

    var isEnabled: Bool {
        !apiKey.isEmpty
    }

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "apiTennisKey") ?? ""
    }

    /// Normalize player names into a stable lookup key.
    /// "Carlos Alcaraz" and "Tomas Martin Etcheverry" -> "alcaraz::etcheverry"
    static func matchKey(player1: String, player2: String) -> String {
        let norm: (String) -> String = { name in
            (name.components(separatedBy: " ").last ?? name)
                .lowercased()
                .trimmingCharacters(in: .whitespaces)
        }
        let pair = [norm(player1), norm(player2)].sorted()
        return pair.joined(separator: "::")
    }

    /// Look up live game score for a pair of players.
    func pointScore(player1: String, player2: String) -> TennisPointData? {
        let key = Self.matchKey(player1: player1, player2: player2)
        return pointScores[key]
    }

    /// Start periodic polling. Call on app launch.
    func startPolling() {
        stopPolling()
        fetchTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchOnce()
                // Stay well under 100 req/day: 30-second cadence = ~2880/day
                // but we only fetch when a user actually has tennis sports on.
                // Use 30s to be safe; the GameRowView will read cached values.
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func stopPolling() {
        fetchTask?.cancel()
        fetchTask = nil
    }

    /// Manually trigger one fetch. Respects a 10-second floor so rapid calls
    /// don't hammer the API.
    func fetchOnce() async {
        guard isEnabled else { return }
        if let last = lastFetch, Date().timeIntervalSince(last) < 10 { return }

        let urlString = "https://api.api-tennis.com/tennis/?method=get_livescore&APIkey=\(apiKey)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            // The API returns either {"success":1,"result":[...]} or {"error":"1","result":[...]}
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if let err = json["error"] as? String, err != "0" { return }
            guard let matches = json["result"] as? [[String: Any]] else { return }

            var next: [String: TennisPointData] = [:]

            for match in matches {
                let player1Name = match["event_first_player"] as? String ?? ""
                let player2Name = match["event_second_player"] as? String ?? ""
                guard !player1Name.isEmpty, !player2Name.isEmpty else { continue }

                // event_game_result like "15 - 30" or "40 - Ad"
                var p1Score = "0"
                var p2Score = "0"
                if let gameResult = match["event_game_result"] as? String {
                    let parts = gameResult.components(separatedBy: " - ")
                    if parts.count == 2 {
                        p1Score = parts[0].trimmingCharacters(in: .whitespaces)
                        p2Score = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }

                // serve: "First Player" | "Second Player" | nil
                let serveField = (match["event_serve"] as? String ?? "").lowercased()
                let p1Serving = serveField.contains("first")

                // Point situation markers
                let eventType = (match["event_type_type"] as? String ?? "").lowercased()
                let status = (match["event_status"] as? String ?? "").lowercased()
                let isBP = status.contains("break") || eventType.contains("break")
                let isSP = status.contains("set point")
                let isMP = status.contains("match point")

                let key = Self.matchKey(player1: player1Name, player2: player2Name)
                next[key] = TennisPointData(
                    player1Score: p1Score,
                    player2Score: p2Score,
                    player1IsServing: p1Serving,
                    isBreakPoint: isBP,
                    isSetPoint: isSP,
                    isMatchPoint: isMP,
                    fetchedAt: Date()
                )
            }

            let finalNext = next
            await MainActor.run {
                self.pointScores = finalNext
                self.lastFetch = Date()
            }
        } catch {
            // Silent fail — tennis point scoring is a nice-to-have
        }
    }
}
