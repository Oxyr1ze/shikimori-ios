import Foundation
import SwiftUI

enum ShikiConfig {
    static let host = "https://shikimori.io"
    static let redirect = "urn:ietf:wg:oauth:2.0:oob"
    static let scopes = "user_rates comments topics"
    static let userAgent = "ShikiApp"
}

enum ShikiError: LocalizedError {
    case http(Int, String)
    case unauthorized
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            let short = body.count > 160 ? String(body.prefix(160)) + "…" : body
            return "Ошибка сервера \(code). \(short)"
        case .unauthorized: return "Нужно войти заново."
        case .network(let m): return "Нет соединения: \(m)"
        case .decoding(let m): return "Не удалось разобрать ответ: \(m)"
        }
    }
}

/// Не больше ~4,5 запросов в секунду: лимит Shikimori 5 в секунду.
actor RequestPacer {
    private var next = Date.distantPast
    func wait() async {
        let now = Date()
        let start = max(now, next)
        next = start.addingTimeInterval(0.22)
        let delay = start.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}

/// Вход через OAuth, хранение токенов в Keychain и все запросы к Shikimori.
@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var user: ShikiUser?
    @Published var isReady = false

    private let pacer = RequestPacer()
    private var posterCache: [String: PosterURLs] = [:]
    private var refreshing: Task<Bool, Never>?

    var clientID: String { Keychain.get("client_id") }
    var clientSecret: String { Keychain.get("client_secret") }
    var accessToken: String { Keychain.get("access_token") }
    var refreshToken: String { Keychain.get("refresh_token") }
    var isAuthorized: Bool { user != nil }

    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: Вход

    func restore() async {
        defer { isReady = true }
        guard !accessToken.isEmpty || !refreshToken.isEmpty else { return }
        do {
            let me: ShikiUser = try await get("/api/users/whoami")
            user = me
            DiskCache.save(me, key: "me")
        } catch ShikiError.unauthorized {
            user = nil
        } catch {
            // Нет интернета или сервер недоступен: входить заново не нужно, работаем с сохранёнными данными.
            user = DiskCache.load(ShikiUser.self, key: "me")
        }
    }

    func saveClient(id: String, secret: String) {
        Keychain.set(id.trimmingCharacters(in: .whitespacesAndNewlines), for: "client_id")
        Keychain.set(secret.trimmingCharacters(in: .whitespacesAndNewlines), for: "client_secret")
    }

    func authorizeURL() -> URL? {
        var c = URLComponents(string: ShikiConfig.host + "/oauth/authorize")
        c?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: ShikiConfig.redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: ShikiConfig.scopes)
        ]
        return c?.url
    }

    func login(code: String) async throws {
        let ok = try await tokenRequest([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "redirect_uri": ShikiConfig.redirect
        ])
        guard ok else { throw ShikiError.unauthorized }
        user = try await get("/api/users/whoami")
    }

    func logout() {
        Keychain.set("", for: "access_token")
        Keychain.set("", for: "refresh_token")
        user = nil
        DiskCache.clear()
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> Bool {
        guard let url = URL(string: ShikiConfig.host + "/oauth/token") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.httpMethod = "POST"
        req.setValue(ShikiConfig.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents()
        c.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = Data((c.percentEncodedQuery ?? "").utf8)
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw ShikiError.network(error.localizedDescription)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            if fields["grant_type"] == "authorization_code" {
                throw ShikiError.http(code, String(decoding: data, as: UTF8.self))
            }
            return false
        }
        Keychain.set(access, for: "access_token")
        if let refresh = json["refresh_token"] as? String {
            Keychain.set(refresh, for: "refresh_token")
        }
        return true
    }

    private func refreshTokens() async -> Bool {
        if let running = refreshing { return await running.value }
        let task = Task<Bool, Never> { [self] in
            guard !refreshToken.isEmpty else { return false }
            let result = try? await tokenRequest([
                "grant_type": "refresh_token",
                "client_id": clientID,
                "client_secret": clientSecret,
                "refresh_token": refreshToken
            ])
            return result ?? false
        }
        refreshing = task
        let ok = await task.value
        refreshing = nil
        return ok
    }

    // MARK: Сетевой слой

    func send(_ method: String, _ path: String, query: [URLQueryItem] = [],
              json: Any? = nil, attempt: Int = 0) async throws -> Data {
        guard var comps = URLComponents(string: ShikiConfig.host + path) else {
            throw ShikiError.network("неверный адрес")
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw ShikiError.network("неверный адрес") }

        var req = URLRequest(url: url, timeoutInterval: 25)
        req.httpMethod = method
        req.setValue(ShikiConfig.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let token = accessToken
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        await pacer.wait()
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ShikiError.network(error.localizedDescription)
        }

        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        switch code {
        case 200...299:
            return data
        case 401:
            if attempt == 0, await refreshTokens() {
                return try await send(method, path, query: query, json: json, attempt: 1)
            }
            user = nil
            throw ShikiError.unauthorized
        case 429 where attempt < 2:
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            return try await send(method, path, query: query, json: json, attempt: attempt + 1)
        default:
            throw ShikiError.http(code, String(decoding: data, as: UTF8.self))
        }
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await send("GET", path, query: query)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ShikiError.decoding("\(error)")
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ShikiError.decoding("\(error)")
        }
    }

    // MARK: Методы API

    func media(kind: MediaKind, order: String, status: String? = nil, search: String? = nil,
               filters: [URLQueryItem] = [], page: Int = 1, limit: Int = 24) async throws -> [Media] {
        var q = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "order", value: order)
        ]
        if let status, !status.isEmpty { q.append(URLQueryItem(name: "status", value: status)) }
        if let search, !search.isEmpty { q.append(URLQueryItem(name: "search", value: search)) }
        q += filters
        var items: [Media] = try await get("/api/\(kind.path)", query: q)
        let posters = await fetchPosters(ids: items.map(\.id), kind: kind)
        for i in items.indices { items[i].posterURLs = posters[items[i].id] }
        return items
    }

    /// Все жанры сайта (аниме и манга). Сохраняются на телефоне, список меняется редко.
    func genres() async -> [Genre] {
        if let list: [Genre] = try? await get("/api/genres"), !list.isEmpty {
            DiskCache.save(list, key: "genres")
            return list
        }
        return DiskCache.load([Genre].self, key: "genres") ?? []
    }

    func detail(_ ref: MediaRef) async throws -> MediaDetail {
        var d: MediaDetail = try await get("/api/\(ref.kind.path)/\(ref.id)")
        d.posterURLs = await fetchPosters(ids: [ref.id], kind: ref.kind)[ref.id]
        return d
    }

    /// Расписание выхода серий. Сначала обычный /api/calendar, при сбое запасной путь через GraphQL.
    func calendar() async throws -> [CalendarItem] {
        if let items: [CalendarItem] = try? await get("/api/calendar"), !items.isEmpty {
            var result = items
            let posters = await fetchPosters(ids: result.map { $0.anime.id }, kind: .anime)
            for i in result.indices { result[i].anime.posterURLs = posters[result[i].anime.id] }
            return result
        }
        var result: [CalendarItem] = []
        for page in 1...4 {
            let query = "{ animes(status: \"ongoing\", limit: 50, page: \(page)) { id name russian score episodes episodesAired nextEpisodeAt poster { originalUrl mainUrl previewUrl } } }"
            let data = try await send("POST", "/api/graphql", json: ["query": query])
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ShikiError.decoding("graphql") }
            if let errs = root["errors"] as? [[String: Any]], let m = errs.first?["message"] as? String {
                throw ShikiError.network(m)
            }
            guard let rows = (root["data"] as? [String: Any])?["animes"] as? [[String: Any]] else { break }
            for row in rows {
                guard let at = row["nextEpisodeAt"] as? String else { continue }
                let rawID = row["id"]
                guard let id = (rawID as? Int) ?? Int((rawID as? String) ?? "") else { continue }
                var m = Media(id: id, name: (row["name"] as? String) ?? "")
                m.russian = row["russian"] as? String
                m.score = (row["score"] as? Double).map { String($0) }
                m.episodes = row["episodes"] as? Int
                m.episodesAired = row["episodesAired"] as? Int
                if let p = row["poster"] as? [String: Any] {
                    m.posterURLs = PosterURLs(original: p["originalUrl"] as? String,
                                              main: p["mainUrl"] as? String,
                                              preview: p["previewUrl"] as? String)
                }
                result.append(CalendarItem(nextEpisode: (m.episodesAired ?? 0) + 1, nextEpisodeAt: at, anime: m))
            }
            if rows.count < 50 { break }
        }
        return result
    }

    func character(id: Int) async throws -> CharacterDetail {
        try await get("/api/characters/\(id)")
    }

    func person(id: Int) async throws -> PersonDetail {
        try await get("/api/people/\(id)")
    }

    func userStats() async -> UserStats? {
        await userProfile()?.stats
    }

    /// Профиль пользователя (свой или чужой, если указан id).
    func userProfile(id: Int? = nil) async -> UserProfileInfo? {
        guard let uid = id ?? user?.id else { return nil }
        return try? await get("/api/users/\(uid)")
    }

    func favourites(id: Int? = nil) async -> Favourites? {
        guard let uid = id ?? user?.id, let r: FavouritesResponse = try? await get("/api/users/\(uid)/favourites") else { return nil }
        var fav = Favourites()
        fav.animes = (r.animes ?? []).map(\.media)
        fav.mangas = (r.mangas ?? []).map(\.media)
        fav.ranobe = (r.ranobe ?? []).map(\.media)
        fav.characters = (r.characters ?? []).map(\.person)
        let pa = await fetchPosters(ids: fav.animes.map(\.id), kind: .anime)
        for i in fav.animes.indices { fav.animes[i].posterURLs = pa[fav.animes[i].id] }
        let pm = await fetchPosters(ids: fav.mangas.map(\.id), kind: .manga)
        for i in fav.mangas.indices { fav.mangas[i].posterURLs = pm[fav.mangas[i].id] }
        let pr = await fetchPosters(ids: fav.ranobe.map(\.id), kind: .ranobe)
        for i in fav.ranobe.indices { fav.ranobe[i].posterURLs = pr[fav.ranobe[i].id] }
        return fav
    }

    func friends(id: Int? = nil) async -> [ShikiUser] {
        guard let uid = id ?? user?.id else { return [] }
        return (try? await get("/api/users/\(uid)/friends", query: [URLQueryItem(name: "limit", value: "100")])) ?? []
    }

    func history(id: Int? = nil) async -> [HistoryItem] {
        guard let uid = id ?? user?.id else { return [] }
        return (try? await get("/api/users/\(uid)/history", query: [URLQueryItem(name: "limit", value: "20")])) ?? []
    }

    func comments(topicID: Int, type: String = "Topic", page: Int, limit: Int = 30) async throws -> [Comment] {
        let q = [
            URLQueryItem(name: "commentable_id", value: String(topicID)),
            URLQueryItem(name: "commentable_type", value: type),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "desc", value: "1")
        ]
        return try await get("/api/comments", query: q)
    }

    func postComment(topicID: Int, body: String) async throws -> Comment {
        let payload: [String: Any] = ["comment": [
            "body": body,
            "commentable_id": topicID,
            "commentable_type": "Topic"
        ] as [String: Any]]
        let data = try await send("POST", "/api/comments", json: payload)
        return try decode(data)
    }

    func roles(_ ref: MediaRef) async -> [Role] {
        (try? await get("/api/\(ref.kind.path)/\(ref.id)/roles")) ?? []
    }

    func similar(_ ref: MediaRef) async -> [Media] {
        var items: [Media] = (try? await get("/api/\(ref.kind.path)/\(ref.id)/similar")) ?? []
        let posters = await fetchPosters(ids: items.map(\.id), kind: ref.kind)
        for i in items.indices { items[i].posterURLs = posters[items[i].id] }
        return items
    }

    /// Настоящие постеры через GraphQL. При любой ошибке просто возвращаем пусто: тогда используются адреса из REST.
    func fetchPosters(ids: [Int], kind: MediaKind) async -> [Int: PosterURLs] {
        var result: [Int: PosterURLs] = [:]
        var missing: [Int] = []
        for id in ids {
            if let cached = posterCache["\(kind.rawValue)-\(id)"] { result[id] = cached } else { missing.append(id) }
        }
        let field = kind == .anime ? "animes" : "mangas"
        var start = 0
        while start < missing.count {
            let chunk = Array(missing[start..<min(start + 50, missing.count)])
            start += 50
            let list = chunk.map(String.init).joined(separator: ",")
            let query = "{ \(field)(ids: \"\(list)\", limit: 50) { id poster { originalUrl mainUrl previewUrl } } }"
            guard let data = try? await send("POST", "/api/graphql", json: ["query": query]),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = root["data"] as? [String: Any],
                  let rows = dataObj[field] as? [[String: Any]] else { continue }
            for row in rows {
                let rawID = row["id"]
                let id = (rawID as? Int) ?? Int((rawID as? String) ?? "")
                guard let id, let p = row["poster"] as? [String: Any] else { continue }
                let urls = PosterURLs(original: p["originalUrl"] as? String,
                                      main: p["mainUrl"] as? String,
                                      preview: p["previewUrl"] as? String)
                posterCache["\(kind.rawValue)-\(id)"] = urls
                result[id] = urls
            }
        }
        return result
    }

    /// Список манги (kind == .manga) или ранобэ (kind == .ranobe): оба лежат в manga_rates.
    func mangaRates(kind: MediaKind, status: String) async throws -> [RateEntry] {
        guard let user else { throw ShikiError.unauthorized }
        let q = [
            URLQueryItem(name: "status", value: status),
            URLQueryItem(name: "limit", value: "200")
        ]
        var entries: [RateEntry] = try await get("/api/users/\(user.id)/manga_rates", query: q)
        entries = entries.filter { e in
            guard let m = e.manga else { return false }
            return kind == .ranobe ? m.isRanobe : !m.isRanobe
        }
        let posters = await fetchPosters(ids: entries.compactMap { $0.manga?.id }, kind: kind)
        for i in entries.indices {
            if let id = entries[i].manga?.id { entries[i].manga?.posterURLs = posters[id] }
        }
        return entries
    }

    func animeRates(status: String) async throws -> [RateEntry] {
        guard let user else { throw ShikiError.unauthorized }
        let q = [
            URLQueryItem(name: "status", value: status),
            URLQueryItem(name: "limit", value: "200")
        ]
        var entries: [RateEntry] = try await get("/api/users/\(user.id)/anime_rates", query: q)
        let posters = await fetchPosters(ids: entries.compactMap { $0.anime?.id }, kind: .anime)
        for i in entries.indices {
            if let id = entries[i].anime?.id { entries[i].anime?.posterURLs = posters[id] }
        }
        return entries
    }

    @discardableResult
    func updateRate(id: Int, episodes: Int? = nil, chapters: Int? = nil, status: String? = nil, score: Int? = nil) async throws -> UserRate {
        var fields: [String: Any] = [:]
        if let episodes { fields["episodes"] = episodes }
        if let chapters { fields["chapters"] = chapters }
        if let status { fields["status"] = status }
        if let score { fields["score"] = score }
        let data = try await send("PATCH", "/api/v2/user_rates/\(id)", json: ["user_rate": fields])
        return try decode(data)
    }

    func createRate(animeID: Int, status: String, targetType: String = "Anime") async throws -> UserRate {
        guard let user else { throw ShikiError.unauthorized }
        let body: [String: Any] = ["user_rate": [
            "user_id": user.id,
            "target_id": animeID,
            "target_type": targetType,
            "status": status
        ] as [String: Any]]
        let data = try await send("POST", "/api/v2/user_rates", json: body)
        return try decode(data)
    }

    func deleteRate(id: Int) async throws {
        _ = try await send("DELETE", "/api/v2/user_rates/\(id)")
    }
}
