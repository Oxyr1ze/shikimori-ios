import Foundation

enum MediaKind: String, CaseIterable, Identifiable, Hashable {
    case anime, manga, ranobe

    var id: String { rawValue }
    var title: String {
        switch self {
        case .anime: return "Аниме"
        case .manga: return "Манга"
        case .ranobe: return "Ранобэ"
        }
    }
    /// Путь в REST API: /api/animes, /api/mangas, /api/ranobe
    var path: String {
        switch self {
        case .anime: return "animes"
        case .manga: return "mangas"
        case .ranobe: return "ranobe"
        }
    }
}

struct MediaRef: Hashable {
    let id: Int
    let kind: MediaKind
}

struct ImageSet: Codable, Hashable {
    var original: String?
    var preview: String?
    var x96: String?
    var x48: String?
}

private func absoluteURL(_ path: String?) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    if path.hasPrefix("http") { return URL(string: path) }
    return URL(string: ShikiConfig.host + path)
}

/// Адреса постеров из GraphQL (у новых релизов старые адреса из REST дают заглушку).
struct PosterURLs: Codable, Hashable {
    var original: String?
    var main: String?
    var preview: String?
}

private func urlList(_ paths: [String?]) -> [URL] {
    var seen = Set<String>()
    var result: [URL] = []
    for p in paths {
        guard let p, !p.isEmpty, !p.contains("missing_"), seen.insert(p).inserted,
              let u = absoluteURL(p) else { continue }
        result.append(u)
    }
    return result
}

struct Media: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var russian: String?
    var image: ImageSet?
    var kind: String?
    var score: String?
    var status: String?
    var episodes: Int?
    var episodesAired: Int?
    var chapters: Int?
    var volumes: Int?
    var posterURLs: PosterURLs?
    var role: String?

    var title: String {
        if let r = russian, !r.isEmpty { return r }
        return name
    }
    /// Крупный постер: варианты по порядку, пока один не загрузится.
    var posterCandidates: [URL] {
        urlList([posterURLs?.original, posterURLs?.main, image?.original])
    }
    var thumbCandidates: [URL] {
        urlList([posterURLs?.main, posterURLs?.preview, image?.original, image?.preview])
    }
    var scoreText: String? {
        guard let s = score, let v = Double(s), v > 0 else { return nil }
        return String(format: "%.2f", v)
    }
}

struct Genre: Codable, Hashable {
    var id: Int?
    var name: String?
    var russian: String?
    var display: String { (russian?.isEmpty == false ? russian : name) ?? "" }
}

struct UserRate: Codable, Hashable {
    var id: Int
    var status: String?
    var score: Int?
    var episodes: Int?
    var chapters: Int?
    var volumes: Int?
}

struct Studio: Codable, Hashable {
    var name: String?
}

struct Screenshot: Codable, Hashable {
    var original: String?
    var preview: String?
    var originalURL: URL? { absoluteURL(original) }
    var previewURL: URL? { absoluteURL(preview ?? original) }
}

struct CastPerson: Codable, Hashable {
    var id: Int
    var name: String?
    var russian: String?
    var image: ImageSet?
    var title: String {
        if let r = russian, !r.isEmpty { return r }
        return name ?? ""
    }
    var imageURLs: [URL] { urlList([image?.original, image?.preview, image?.x96]) }
}

struct Role: Codable, Identifiable, Hashable {
    var rolesRussian: [String]?
    var character: CastPerson?
    var person: CastPerson?
    var id: String { "\(character?.id ?? 0)-\(person?.id ?? 0)" }
}

struct MediaDetail: Codable, Identifiable {
    let id: Int
    var name: String
    var russian: String?
    var image: ImageSet?
    var kind: String?
    var score: String?
    var status: String?
    var episodes: Int?
    var episodesAired: Int?
    var chapters: Int?
    var volumes: Int?
    var english: [String?]?
    var japanese: [String?]?
    var topicId: Int?
    var rating: String?
    var duration: Int?
    var airedOn: String?
    var releasedOn: String?
    var studios: [Studio]?
    var screenshots: [Screenshot]?
    var description: String?
    var genres: [Genre]?
    var userRate: UserRate?
    var posterURLs: PosterURLs?

    var title: String {
        if let r = russian, !r.isEmpty { return r }
        return name
    }
    var posterCandidates: [URL] {
        urlList([posterURLs?.original, posterURLs?.main, image?.original])
    }
    var scoreText: String? {
        guard let s = score, let v = Double(s), v > 0 else { return nil }
        return String(format: "%.2f", v)
    }
    /// Описание на Shikimori хранится с разметкой вида [character=1]Имя[/character]: убираем теги.
    var infoLines: [(String, String)] {
        var r: [(String, String)] = []
        if let k = kind, !k.isEmpty { r.append(("Тип", kindTitle(k))) }
        if let n = studios?.compactMap(\.name), !n.isEmpty { r.append(("Студия", n.joined(separator: ", "))) }
        if let d = duration, d > 0 { r.append(("Длительность", "\(d) мин.")) }
        if let a = airedOn, !a.isEmpty { r.append(("Выход", ruDate(a))) }
        if let a = releasedOn, !a.isEmpty { r.append(("Завершён", ruDate(a))) }
        if let g = rating, !g.isEmpty, g != "none" { r.append(("Возраст", g.uppercased().replacingOccurrences(of: "_", with: "-"))) }
        return r
    }
    var plainDescription: String? {
        guard let d = description, !d.isEmpty else { return nil }
        let cleaned = d.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct RateEntry: Codable, Identifiable, Hashable {
    var id: Int
    var score: Int?
    var status: String?
    var episodes: Int?
    var chapters: Int?
    var anime: Media?
    var manga: Media?
    /// Произведение из записи списка (аниме или манга/ранобэ).
    var media: Media? { anime ?? manga }
}

struct UserImage: Codable, Hashable {
    var x160: String?
    var x148: String?
}

struct ShikiUser: Codable, Hashable {
    var id: Int
    var nickname: String
    var avatar: String?
    var image: UserImage?
    var avatarURL: URL? { absoluteURL(image?.x160 ?? image?.x148 ?? avatar) }
}

enum RateStatus: String, CaseIterable, Identifiable {
    case watching, planned, completed, onHold = "on_hold", dropped, rewatching
    var id: String { rawValue }
    var title: String {
        switch self {
        case .watching: return "Смотрю"
        case .planned: return "В планах"
        case .completed: return "Просмотрено"
        case .onHold: return "Отложено"
        case .dropped: return "Брошено"
        case .rewatching: return "Пересматриваю"
        }
    }
    static func title(for raw: String?) -> String {
        guard let raw, let s = RateStatus(rawValue: raw) else { return "Не в списке" }
        return s.title
    }
}

func releaseStatusTitle(_ raw: String?) -> String {
    switch raw {
    case "anons": return "Анонс"
    case "ongoing": return "Выходит"
    case "released": return "Вышло"
    default: return "—"
    }
}


func kindTitle(_ k: String) -> String {
    switch k {
    case "tv": return "ТВ-сериал"
    case "movie": return "Фильм"
    case "ova": return "OVA"
    case "ona": return "ONA"
    case "special": return "Спешл"
    case "tv_special": return "ТВ-спешл"
    case "music": return "Клип"
    case "pv": return "Промо"
    case "cm": return "Реклама"
    case "manga": return "Манга"
    case "manhwa": return "Манхва"
    case "manhua": return "Маньхуа"
    case "light_novel": return "Ранобэ"
    case "novel": return "Новелла"
    case "one_shot": return "Ваншот"
    case "doujin": return "Додзинси"
    default: return k
    }
}

extension Media {
    var isRanobe: Bool { kind == "light_novel" || kind == "novel" }
}


struct Comment: Codable, Identifiable, Hashable {
    var id: Int
    var body: String?
    var htmlBody: String?
    var createdAt: String?
    var isOfftopic: Bool?
    var user: ShikiUser?

    /// Текст без разметки Shikimori ([b], [quote], ссылки и т.д.).
    var plainBody: String {
        var t = body ?? ""
        t = t.replacingOccurrences(of: "\\[spoiler[^\\]]*\\][\\s\\S]*?\\[/spoiler\\]", with: "[спойлер]", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[img[^\\]]*\\][\\s\\S]*?\\[/img\\]", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var dateText: String {
        guard let s = createdAt else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter()
        guard let d = f.date(from: s) ?? g.date(from: s) else { return "" }
        let r = RelativeDateTimeFormatter()
        r.locale = Locale(identifier: "ru_RU")
        r.unitsStyle = .short
        return r.localizedString(for: d, relativeTo: Date())
    }
}


struct CalendarItem: Codable, Identifiable, Hashable {
    var nextEpisode: Int?
    var nextEpisodeAt: String?
    var anime: Media
    var id: String { "\(anime.id)-\(nextEpisode ?? 0)" }

    var date: Date? {
        guard let s = nextEpisodeAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter()
        return f.date(from: s) ?? g.date(from: s)
    }
}


/// "2013-04-07" -> "7 апреля 2013"
func ruDate(_ s: String) -> String {
    let inp = DateFormatter()
    inp.locale = Locale(identifier: "en_US_POSIX")
    inp.dateFormat = "yyyy-MM-dd"
    guard let d = inp.date(from: s) else { return s }
    let out = DateFormatter()
    out.locale = Locale(identifier: "ru_RU")
    out.dateFormat = "d MMMM yyyy"
    return out.string(from: d)
}


/// В избранном картинка приходит одной строкой (а не набором размеров, как в каталоге).
struct FavouriteItem: Codable, Hashable {
    var id: Int
    var name: String?
    var russian: String?
    var image: String?
    var url: String?

    var media: Media {
        var m = Media(id: id, name: name ?? "")
        m.russian = russian
        m.image = ImageSet(original: image, preview: image, x96: image, x48: image)
        return m
    }
    var person: CastPerson {
        CastPerson(id: id, name: name, russian: russian, image: ImageSet(original: image, preview: image, x96: image, x48: image))
    }
}

struct Favourites {
    var animes: [Media] = []
    var mangas: [Media] = []
    var ranobe: [Media] = []
    var characters: [CastPerson] = []
}

struct FavouritesResponse: Codable {
    var animes: [FavouriteItem]?
    var mangas: [FavouriteItem]?
    var ranobe: [FavouriteItem]?
    var characters: [FavouriteItem]?
}

struct HistoryTarget: Codable, Hashable {
    var id: Int
    var name: String?
    var russian: String?
    var url: String?
    var title: String {
        if let r = russian, !r.isEmpty { return r }
        return name ?? ""
    }
    var kind: MediaKind {
        let u = url ?? ""
        if u.contains("/ranobe/") { return .ranobe }
        if u.contains("/mangas/") { return .manga }
        return .anime
    }
}

struct HistoryItem: Codable, Identifiable, Hashable {
    var id: Int
    var createdAt: String?
    var description: String?
    var target: HistoryTarget?

    var plainDescription: String {
        let t = (description ?? "")
            .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        return HTMLMini.decode(t).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var dateText: String {
        guard let s = createdAt else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter()
        guard let d = f.date(from: s) ?? g.date(from: s) else { return "" }
        let r = RelativeDateTimeFormatter()
        r.locale = Locale(identifier: "ru_RU")
        r.unitsStyle = .short
        return r.localizedString(for: d, relativeTo: Date())
    }
}


struct CharacterDetail: Codable {
    var id: Int
    var name: String?
    var russian: String?
    var altname: String?
    var japanese: String?
    var image: ImageSet?
    var descriptionHtml: String?
    var seyu: [CastPerson]?
    var animes: [Media]?
    var mangas: [Media]?

    var title: String {
        if let r = russian, !r.isEmpty { return r }
        return name ?? ""
    }
    var posterURLs: [URL] { urlList([image?.original, image?.preview, image?.x96]) }
}

struct PersonRoleGroup: Codable {
    var characters: [CastPerson]?
    var animes: [Media]?
}

struct PersonWork: Codable {
    var anime: Media?
    var manga: Media?
    var role: String?
}

struct PersonDetail: Codable {
    var id: Int
    var name: String?
    var russian: String?
    var japanese: String?
    var jobTitle: String?
    var image: ImageSet?
    var roles: [PersonRoleGroup]?
    var works: [PersonWork]?

    var title: String {
        if let r = russian, !r.isEmpty { return r }
        return name ?? ""
    }
    var posterURLs: [URL] { urlList([image?.original, image?.preview, image?.x96]) }
}
