import Foundation

/// Жанр/тема/аудитория из GraphQL (версия 2, как на сайте). id приходит строкой.
struct GQLGenre: Codable, Hashable {
    var id: String?
    var name: String?
    var russian: String?
    var kind: String?   // genre, theme, demographic
    var display: String { (russian?.isEmpty == false ? russian : name) ?? "" }
    var intID: Int? { id.flatMap { Int($0) } }
}

struct ExtraNamed: Codable, Hashable {
    var id: String?
    var name: String?
    var intID: Int? { id.flatMap { Int($0) } }
}

struct ExtraLink: Codable, Hashable {
    var kind: String?
    var url: String?
}

struct ExtraScore: Codable, Hashable {
    var score: Int
    var count: Int
}

struct ExtraStatus: Codable, Hashable {
    var status: String
    var count: Int
}

/// Дополнительные сведения о тайтле, которых нет в обычном ответе API.
struct MediaExtras: Codable {
    var origin: String?
    var rating: String?
    var english: String?
    var japanese: String?
    var synonyms: [String]?
    var licensors: [String]?
    var nextEpisodeAt: String?
    var fansubbers: [String]?
    var fandubbers: [String]?
    var genres: [GQLGenre]?
    var studios: [ExtraNamed]?
    var publishers: [ExtraNamed]?
    var externalLinks: [ExtraLink]?
    var scoresStats: [ExtraScore]?
    var statusesStats: [ExtraStatus]?
}

struct RelatedItem: Codable, Hashable, Identifiable {
    var relation: String
    var media: Media
    var kindRaw: String
    var year: Int? = nil
    var id: String { "\(kindRaw)-\(media.id)" }
    var ref: MediaRef { MediaRef(id: media.id, kind: MediaKind(rawValue: kindRaw) ?? .anime) }
}

// MARK: Подписи как на сайте

enum SiteLabels {
    static func origin(_ k: String) -> String {
        let map = [
            "original": "Оригинал", "manga": "Манга", "web_manga": "Веб-манга",
            "four_koma_manga": "Ёнкома", "novel": "Роман", "web_novel": "Веб-новелла",
            "visual_novel": "Визуальная новелла", "light_novel": "Ранобэ", "game": "Игра",
            "card_game": "Карточная игра", "music": "Музыка", "radio": "Радио",
            "book": "Книга", "picture_book": "Книга с картинками",
            "mixed_media": "Более одного", "other": "Другое", "unknown": "Неизвестен"
        ]
        return map[k] ?? k
    }

    static func ageRating(_ k: String) -> String? {
        switch k {
        case "g": return "G"
        case "pg": return "PG"
        case "pg_13": return "PG-13"
        case "r": return "R-17+"
        case "r_plus": return "R+"
        case "rx": return "Rx"
        default: return nil
        }
    }

    static func relation(_ text: String) -> String { text }

    static func linkTitle(_ k: String) -> String {
        let map = [
            "official_site": "Официальный сайт", "wikipedia": "Википедия",
            "anime_news_network": "Anime News Network", "anime_db": "AniDB",
            "kinopoisk": "КиноПоиск", "kinopoisk_hd": "КиноПоиск HD",
            "world_art": "World Art", "myanimelist": "MyAnimeList",
            "readmanga": "ReadManga", "novelupdates": "Novel Updates",
            "mangaupdates": "Baka-Updates", "smotret_anime": "Anime 365",
            "ruranobe": "РуРанобэ", "novel_tl": "Novel.tl"
        ]
        return map[k] ?? k.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func listStatus(_ k: String, kind: MediaKind) -> String {
        let reading = kind != .anime
        switch k {
        case "planned": return "В планах"
        case "watching": return reading ? "Читаю" : "Смотрю"
        case "rewatching": return reading ? "Перечитываю" : "Пересматриваю"
        case "completed": return reading ? "Прочитано" : "Просмотрено"
        case "on_hold": return "Отложено"
        case "dropped": return "Брошено"
        default: return k
        }
    }
}

extension AuthManager {
    private func graphQLRows(_ query: String, field: String) async -> [[String: Any]]? {
        guard let data = try? await send("POST", "/api/graphql", json: ["query": query]),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let rows = dataObj[field] as? [[String: Any]] else { return nil }
        return rows
    }

    /// Темы, первоисточник, альтернативные названия, статистика, ссылки.
    func extras(_ ref: MediaRef) async -> MediaExtras? {
        let field = ref.kind == .anime ? "animes" : "mangas"
        let common = "english japanese synonyms licensors genres { id name russian kind } externalLinks { kind url } scoresStats { score count } statusesStats { status count }"
        let specific = ref.kind == .anime
            ? "origin rating nextEpisodeAt fansubbers fandubbers studios { id name }"
            : "publishers { id name }"
        let query = "{ \(field)(ids: \"\(ref.id)\", limit: 1) { \(common) \(specific) } }"
        guard let rows = await graphQLRows(query, field: field), let row = rows.first,
              let json = try? JSONSerialization.data(withJSONObject: row),
              let result = try? JSONDecoder().decode(MediaExtras.self, from: json) else { return nil }
        return result
    }

    /// Связанное: продолжения, предыстории, адаптации.
    func related(_ ref: MediaRef) async -> [RelatedItem] {
        let field = ref.kind == .anime ? "animes" : "mangas"
        let sub = "id name russian kind score airedOn { year } poster { originalUrl mainUrl previewUrl }"
        let query = "{ \(field)(ids: \"\(ref.id)\", limit: 1) { related { relationText anime { \(sub) } manga { \(sub) } } } }"
        guard let rows = await graphQLRows(query, field: field),
              let list = rows.first?["related"] as? [[String: Any]] else { return [] }
        var result: [RelatedItem] = []
        for item in list {
            let relation = (item["relationText"] as? String) ?? ""
            let isAnime = item["anime"] is [String: Any]
            guard let obj = (item["anime"] as? [String: Any]) ?? (item["manga"] as? [String: Any]),
                  let id = Int((obj["id"] as? String) ?? "") ?? (obj["id"] as? Int) else { continue }
            var m = Media(id: id, name: (obj["name"] as? String) ?? "")
            m.russian = obj["russian"] as? String
            m.kind = obj["kind"] as? String
            if let s = obj["score"] as? Double { m.score = String(s) }
            if let p = obj["poster"] as? [String: Any] {
                m.posterURLs = PosterURLs(original: p["originalUrl"] as? String,
                                          main: p["mainUrl"] as? String,
                                          preview: p["previewUrl"] as? String)
            }
            var kindRaw = "anime"
            if !isAnime { kindRaw = (m.kind == "light_novel" || m.kind == "novel") ? "ranobe" : "manga" }
            let year = ((obj["airedOn"] as? [String: Any])?["year"] as? Int)
            result.append(RelatedItem(relation: relation, media: m, kindRaw: kindRaw, year: year))
        }
        return result
    }

    /// Жанры, темы и аудитория (версия 2). Кэшируются на телефоне.
    func genresV2(manga: Bool) async -> [GQLGenre] {
        let type = manga ? "Manga" : "Anime"
        let key = "genres2-\(type)"
        let query = "{ genres(entryType: \(type)) { id name russian kind } }"
        if let rows = await graphQLRows(query, field: "genres"),
           let json = try? JSONSerialization.data(withJSONObject: rows),
           let list = try? JSONDecoder().decode([GQLGenre].self, from: json), !list.isEmpty {
            DiskCache.save(list, key: key)
            return list
        }
        return DiskCache.load([GQLGenre].self, key: key) ?? []
    }

    func studios() async -> [ExtraNamed] {
        struct S: Decodable { var id: Int; var name: String?; var filteredName: String?; var real: Bool? }
        if let list: [S] = try? await get("/api/studios"), !list.isEmpty {
            let out = list.filter { $0.real != false }.map { ExtraNamed(id: String($0.id), name: $0.filteredName ?? $0.name) }
            DiskCache.save(out, key: "studios")
            return out
        }
        return DiskCache.load([ExtraNamed].self, key: "studios") ?? []
    }

    func publishers() async -> [ExtraNamed] {
        struct P: Decodable { var id: Int; var name: String? }
        if let list: [P] = try? await get("/api/publishers"), !list.isEmpty {
            let out = list.map { ExtraNamed(id: String($0.id), name: $0.name) }
            DiskCache.save(out, key: "publishers")
            return out
        }
        return DiskCache.load([ExtraNamed].self, key: "publishers") ?? []
    }

    /// Постеры пачкой по номерам (в данных франшизы у новых тайтлов вместо постера заглушка).
    func posters(kind: MediaKind, ids: [Int]) async -> [Int: PosterURLs] {
        let field = kind == .anime ? "animes" : "mangas"
        var result: [Int: PosterURLs] = [:]
        var index = 0
        while index < ids.count {
            let chunk = Array(ids[index..<min(index + 40, ids.count)])
            index += 40
            let list = chunk.map(String.init).joined(separator: ",")
            let query = "{ \(field)(ids: \"\(list)\", limit: 50) { id poster { originalUrl mainUrl previewUrl } } }"
            guard let rows = await graphQLRows(query, field: field) else { continue }
            for row in rows {
                guard let id = Int((row["id"] as? String) ?? ""),
                      let p = row["poster"] as? [String: Any] else { continue }
                result[id] = PosterURLs(original: p["originalUrl"] as? String,
                                        main: p["mainUrl"] as? String,
                                        preview: p["previewUrl"] as? String)
            }
        }
        return result
    }
}
