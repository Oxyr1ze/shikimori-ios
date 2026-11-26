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
            var answered = false   // хотя бы один источник ответил (пусть и «нет картинки»)
            var found: String?
            for source in sources(kind: kind, id: id) {
                let r = await call(source)
                guard let (code, data) = r else { continue }
                if code == 429 {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    continue
                }
                if code == 200 || code == 404 { answered = true }
                if code == 200, let s = source.parse(data), !s.isEmpty, !s.contains("questionmark"),
                   !s.contains("apple-touch"), !s.contains("logo") {
                    found = s.replacingOccurrences(of: "http://", with: "https://")
                    break
                }
            }
            if found != nil || answered {
                store[key] = ["url": found ?? "", "at": Date().timeIntervalSince1970]
                UserDefaults.standard.set(store, forKey: storeKey)
            }
            return found.flatMap(URL.init(string:))
        }

        private struct Source {
            let request: URLRequest
            let parse: (Data) -> String?
        }

        private func call(_ source: Source) async -> (Int, Data)? {
            // не чаще трёх запросов в секунду
            let wait = 0.35 - Date().timeIntervalSince(lastRequest)
            lastRequest = Date().addingTimeInterval(max(wait, 0))
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard let (data, resp) = try? await URLSession.shared.data(for: source.request),
                  let code = (resp as? HTTPURLResponse)?.statusCode else { return nil }
            return (code, data)
        }

        private nonisolated func json(_ data: Data) -> Any? { try? JSONSerialization.jsonObject(with: data) }

        private func sources(kind: String, id: Int) -> [Source] {
            var list: [Source] = []
            func get(_ url: String, headers: [String: String] = [:]) -> URLRequest? {
                guard let u = URL(string: url) else { return nil }
                var r = URLRequest(url: u, timeoutInterval: 8)
                for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
                return r
            }
            if kind == "anime" || kind == "manga" {
                // 1. AniList (ищет по номеру MyAnimeList)
                let type = kind == "anime" ? "ANIME" : "MANGA"
                if var r = get("https://graphql.anilist.co", headers: ["Content-Type": "application/json", "Accept": "application/json"]) {
                    r.httpMethod = "POST"
                    let q = "{ Media(idMal: \(id), type: \(type)) { coverImage { extraLarge large } } }"
                    r.httpBody = try? JSONSerialization.data(withJSONObject: ["query": q])
                    list.append(Source(request: r) { data in
                        guard let root = self.json(data) as? [String: Any],
                              let d = root["data"] as? [String: Any],
                              let m = d["Media"] as? [String: Any],
                              let c = m["coverImage"] as? [String: Any] else { return nil }
                        return (c["extraLarge"] as? String) ?? (c["large"] as? String)
                    })
                }
                // 2. Kitsu
                let site = kind == "anime" ? "myanimelist/anime" : "myanimelist/manga"
                if let r = get("https://kitsu.io/api/edge/mappings?filter%5BexternalSite%5D=\(site)&filter%5BexternalId%5D=\(id)&include=item", headers: ["Accept": "application/vnd.api+json"]) {
                    list.append(Source(request: r) { data in
                        guard let root = self.json(data) as? [String: Any],
                              let inc = root["included"] as? [[String: Any]],
                              let attrs = inc.first?["attributes"] as? [String: Any],
                              let poster = attrs["posterImage"] as? [String: Any] else { return nil }
                        return (poster["large"] as? String) ?? (poster["original"] as? String)
                    })
                }
            }
            // страница на MyAnimeList: страница на MyAnimeList (картинка в og:image)
            let page = ["anime": "anime", "manga": "manga", "characters": "character", "people": "people"][kind] ?? kind
            if let r = get("https://myanimelist.net/\(page)/\(id)", headers: ["User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"]) {
                list.append(Source(request: r) { data in
                    let html = String(decoding: data, as: UTF8.self)
                    guard let range = html.range(of: "property=\"og:image\" content=\"") ?? html.range(of: "og:image\" content=\"") else { return nil }
                    let rest = html[range.upperBound...]
                    guard let end = rest.firstIndex(of: "\"") else { return nil }
                    let s = String(rest[..<end])
                    return s.contains("cdn.myanimelist.net/images") ? s : nil
                })
            }
            // Jikan последним: у части пользователей он недоступен и съедает время ожидания
            if let r = get("https://api.jikan.moe/v4/\(kind)/\(id)") {
                list.append(Source(request: r) { self.jikanImage($0) })
            }
            return list
        }

        private nonisolated func jikanImage(_ data: Data) -> String? {
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let d = root["data"] as? [String: Any],
                  let images = d["images"] as? [String: Any],
                  let jpg = images["jpg"] as? [String: Any] else { return nil }
            return (jpg["large_image_url"] as? String) ?? (jpg["image_url"] as? String)
        }
    }
}
