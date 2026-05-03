import Foundation

/// Wraps an async URLSession fetch with a hard deadline so the completion
/// closure is ALWAYS called exactly once, even when WidgetKit preempts the
/// extension or ESPN's CDN drops the connection.
///
/// WidgetKit gives a TimelineProvider a very short runtime budget (often
/// ~2–5 seconds for `getTimeline`). If the completion isn't called in time,
/// the widget stays stuck in its placeholder/redacted state. Every widget in
/// this bundle routes its network fetches through this helper so that failure
/// modes degrade gracefully to fallback data.
enum WidgetFetch {
    /// Fetch JSON from a URL with a hard deadline. Calls `completion` exactly
    /// once with either the parsed JSON root or `nil` on any failure/timeout.
    static func fetchJSON(
        url: String,
        deadline: TimeInterval = 3.5,
        completion: @escaping ([String: Any]?) -> Void
    ) {
        guard let u = URL(string: url) else { completion(nil); return }
        fetchJSON(url: u, deadline: deadline, completion: completion)
    }

    static func fetchJSON(
        url: URL,
        deadline: TimeInterval = 3.5,
        completion: @escaping ([String: Any]?) -> Void
    ) {
        // Thread-safe one-shot completion
        let lock = NSLock()
        var fired = false
        func fire(_ value: [String: Any]?) {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            lock.unlock()
            completion(value)
        }

        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: deadline
        )

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { fire(nil); return }
            fire(json)
        }
        task.resume()

        // Hard deadline: if the fetch hasn't fired completion in N+0.5s, give up.
        DispatchQueue.global().asyncAfter(deadline: .now() + deadline + 0.5) {
            task.cancel()
            fire(nil)
        }
    }
}
