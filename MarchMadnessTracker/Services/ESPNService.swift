import Foundation

actor ESPNService {
    let sportLeague: SportLeague
    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    init(sportLeague: SportLeague) {
        self.sportLeague = sportLeague
    }

    func fetchScoreboard(date: Date? = nil, tournamentOnly: Bool = false) async throws -> ScoreboardResponse {
        var components = URLComponents(string: sportLeague.scoreboardURL)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "100")
        ]

        if tournamentOnly, let groupID = sportLeague.groupID {
            queryItems.append(URLQueryItem(name: "groups", value: groupID))
        }

        if let date {
            queryItems.append(URLQueryItem(name: "dates", value: DateFormatters.espnDateParam.string(from: date)))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw ESPNError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ESPNError.requestFailed
        }

        return try decoder.decode(ScoreboardResponse.self, from: data)
    }

    /// Fetch games using ESPN's date range format (YYYYMMDD-YYYYMMDD)
    func fetchGamesInRange(from startDate: Date, to endDate: Date) async throws -> [Event] {
        let fmt = DateFormatters.espnDateParam
        let startStr = fmt.string(from: startDate)
        let endStr = fmt.string(from: endDate)

        var components = URLComponents(string: sportLeague.scoreboardURL)!
        var queryItems = [
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "dates", value: "\(startStr)-\(endStr)")
        ]
        if let groupID = sportLeague.groupID {
            queryItems.append(URLQueryItem(name: "groups", value: groupID))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw ESPNError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return try await fetchGamesParallel(from: startDate, to: endDate)
        }

        let scoreboardResponse = try decoder.decode(ScoreboardResponse.self, from: data)
        if !scoreboardResponse.events.isEmpty {
            var seen = Set<String>()
            return scoreboardResponse.events.filter { seen.insert($0.id).inserted }
        }

        return try await fetchGamesParallel(from: startDate, to: endDate)
    }

    /// Parallel fallback — fetch multiple days concurrently
    private func fetchGamesParallel(from startDate: Date, to endDate: Date) async throws -> [Event] {
        let calendar = Calendar.current
        var dates: [Date] = []
        var current = startDate
        while current <= endDate {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        let allEvents = try await withThrowingTaskGroup(of: [Event].self) { group in
            for date in dates {
                group.addTask {
                    do {
                        let response = try await self.fetchScoreboard(date: date, tournamentOnly: self.sportLeague.groupID != nil)
                        return response.events
                    } catch {
                        return []
                    }
                }
            }

            var results: [Event] = []
            for try await events in group {
                results.append(contentsOf: events)
            }
            return results
        }

        var seen = Set<String>()
        return allEvents.filter { seen.insert($0.id).inserted }
    }
}

enum ESPNError: LocalizedError {
    case invalidURL
    case requestFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .requestFailed: return "Failed to fetch data from ESPN"
        case .decodingFailed: return "Failed to parse ESPN response"
        }
    }
}
