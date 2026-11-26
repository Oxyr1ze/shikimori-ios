import Foundation

/// Запасные картинки: если на Shikimori постера нет, ищем его на MyAnimeList (через бесплатный Jikan).
/// Номера на Shikimori и MyAnimeList совпадают, поэтому достаточно номера и вида.
/// Внутри приложения такой запасной адрес выглядит как shikifb://anime/123.
enum ExternalImages {
    static let scheme = "shikifb"

    /// kind: anime, manga, characters, people
    static func url(_ kind: String, _ id: Int) -> URL? { URL(string: "\(scheme)://\(kind)/\(id)") }

    static func isFallback(_ url: URL) -> Bool { url.scheme == scheme }

    static func resolve(_ url: URL) async -> URL? {
        guard let kind = url.host, let id = Int(url.lastPathComponent) else { return nil }
        return await Resolver.shared.resolve(kind: kind, id: id)
    }

    private actor Resolver {
        static let shared = Resolver()
        private let storeKey = "externalImages.v1"
        private var store: [String: [String: Any]]
        private var inflight: [String: Task<URL?, Never>] = [:]
        private var lastRequest = Date.distantPast

        init() {
            store = (UserDefaults.standard.dictionary(forKey: "externalImages.v1") as? [String: [String: Any]]) ?? [:]
        }

        func resolve(kind: String, id: Int) async -> URL? {
            let key = "\(kind)-\(id)"
            if let e = store[key] {
                let at = (e["at"] as? Double) ?? 0
                if let s = e["url"] as? String, !s.isEmpty { return URL(string: s) }
                if Date().timeIntervalSince1970 - at < 3 * 86400 { return nil }
            }
            if let t = inflight[key] { return await t.value }
            let task = Task<URL?, Never> { await self.load(kind: kind, id: id) }
            inflight[key] = task
            let result = await task.value
            inflight[key] = nil
            return result
        }

        private func load(kind: String, id: Int) async -> URL? {
            let key = "\(kind)-\(id)"
            var attempt = 0
            while attempt < 2 {
                attempt += 1
                // не чаще трёх запросов в секунду (правило Jikan)
                let wait = 0.4 - Date().timeIntervalSince(lastRequest)
                lastRequest = Date().addingTimeInterval(max(wait, 0))
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                guard let u = URL(string: "https://api.jikan.moe/v4/\(kind)/\(id)"),
                      let (data, resp) = try? await URLSession.shared.data(from: u),
                      let code = (resp as? HTTPURLResponse)?.statusCode else { return nil }  // нет сети: не запоминаем
                if code == 429 { try? await Task.sleep(nanoseconds: 1_500_000_000); continue }
                var found: String?
                if code == 200,
                   let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let d = root["data"] as? [String: Any],
                   let images = d["images"] as? [String: Any],
                   let jpg = images["jpg"] as? [String: Any] {
                    let s = (jpg["large_image_url"] as? String) ?? (jpg["image_url"] as? String)
                    if let s, !s.contains("questionmark"), !s.isEmpty { found = s.replacingOccurrences(of: "http://", with: "https://") }
                }
                if code == 200 || code == 404 {
                    store[key] = ["url": found ?? "", "at": Date().timeIntervalSince1970]
                    UserDefaults.standard.set(store, forKey: storeKey)
                }
                return found.flatMap(URL.init(string:))
            }
            return nil
        }
    }
}
