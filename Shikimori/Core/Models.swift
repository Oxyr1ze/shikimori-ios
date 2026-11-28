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
    var airedOn: String?
    var releasedOn: String?

    var title: String {
        if let r = russian, !r.isEmpty { return r }
        return name
    }
    /// Дата выхода для сортировки (строка вида 2013-04-07).
    var sortDate: String { airedOn ?? releasedOn ?? "" }
    var yearText: String? {
        let d = sortDate
        return d.count >= 4 ? String(d.prefix(4)) : nil
    }
    /// Крупный постер: варианты по порядку, пока один не загрузится.
    var posterCandidates: [URL] {
        urlList([posterURLs?.original, posterURLs?.main, image?.original]) + fallbackURLs
    }
    var thumbCandidates: [URL] {
        urlList([posterURLs?.main, posterURLs?.preview, image?.original, image?.preview]) + fallbackURLs
    }
    /// Запасная картинка с MyAnimeList (номера совпадают).
    var fallbackURLs: [URL] {
        let mangaKinds: Set<String> = ["manga", "manhwa", "manhua", "one_shot", "doujin", "light_novel", "novel"]
        let isManga = (kind.map { mangaKinds.contains($0) } ?? false) || (episodes == nil && (chapters != nil || volumes != nil))
        return ExternalImages.url(isManga ? "manga" : "anime", id).map { [$0] } ?? []
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
    var entryType: String?
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
    /// characters или people: нужен, чтобы искать запасную картинку (не хранится, определяется по месту в ответе).
    var fbKind: String? = nil
    /// true, если картинка взята из GraphQL (та же, что на сайте): тогда запасные картинки не нужны.
    var gqlFixed: Bool? = nil

    enum CodingKeys: String, CodingKey { case id, name, russian, image, gqlFixed }

    init(id: Int, name: String?, russian: String?, image: ImageSet?, fbKind: String? = nil) {
        self.id = id; self.name = name; self.russian = russian; self.image = image; self.fbKind = fbKind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        russian = try? c.decodeIfPresent(String.self, forKey: .russian)
        image = try? c.decodeIfPresent(ImageSet.self, forKey: .image)
        gqlFixed = try? c.decodeIfPresent(Bool.self, forKey: .gqlFixed)
        let path = decoder.codingPath.map(\.stringValue)
        if path.contains("character") || path.contains("characters") { fbKind = "characters" }
        else if path.contains("person") || path.contains("seyu") || path.contains("people") { fbKind = "people" }
    }

    var title: String {
        if let r = russian, !r.isEmpty { return r }
        return name ?? ""
    }
    var imageURLs: [URL] {
        // Картинка с сайта известна: сначала лёгкий размер (быстро), затем оригинал, без других картинок
        if gqlFixed == true { return urlList([image?.preview, image?.original, image?.x96]) }
        return urlList([image?.original, image?.preview, image?.x96]) + (fbKind.flatMap { ExternalImages.url($0, id) }.map { [$0] } ?? [])
    }
}

struct Role: Codable, Identifiable, Hashable {
    var roles: [String]?
    var rolesRussian: [String]?
    var character: CastPerson?
    var person: CastPerson?
    var id: String { "\(character?.id ?? 0)-\(person?.id ?? 0)" }

    /// Главный герой (на сайте «Main»); старый кэш хранит только русские подписи.
    var isMain: Bool {
        (roles ?? []).contains("Main") || (rolesRussian ?? []).contains("Main")
    }
    var isSupporting: Bool {
        (roles ?? []).contains("Supporting") || (rolesRussian ?? []).contains("Supporting")
    }
    /// Подписи для создателя: роли по-русски, самые важные первыми.
    var staffRolesText: String {
        let eng = roles ?? []
        let rus = rolesRussian ?? []
        guard eng.count == rus.count, !eng.isEmpty else { return rus.joined(separator: ", ") }
        return zip(eng, rus).sorted { staffPriority($0.0) < staffPriority($1.0) }.map(\.1).joined(separator: ", ")
    }
    var staffRank: Int { (roles ?? []).map(staffPriority).min() ?? 999 }
}

/// Порядок важности ролей создателей (как принято: автор, режиссёр, сценарий, дизайн, музыка…).
private let staffOrder: [String] = [
    "Original Creator", "Story & Art", "Story", "Art", "Creator",
    "Director", "Co-Director", "Series Composition", "Script", "Screenplay",
    "Original Character Design", "Character Design", "Music",
    "Theme Song Composition", "Theme Song Arrangement", "Theme Song Lyrics", "Theme Song Performance",
    "Inserted Song Performance", "Art Director", "Chief Animation Director", "Animation Director",
    "Assistant Animation Director", "Sound Director", "Director of Photography", "Color Design",
    "Mechanical Design", "Storyboard", "Episode Director", "Assistant Director",
    "Chief Producer", "Executive Producer", "Producer", "Planning Producer", "Associate Producer",
    "Co-Producer", "Assistant Producer", "Planning", "Series Production Director"
]
func staffPriority(_ role: String) -> Int {
    staffOrder.firstIndex(of: role) ?? (staffOrder.count + 1)
}

/// Дата, которую сайт может прислать строкой или объектом {year, month, day}; неполная тоже подходит.
struct LooseDate: Codable, Hashable {
    var year: Int?
    var month: Int?
    var day: Int?

    enum CodingKeys: String, CodingKey { case year, month, day }

    init(from decoder: Decoder) throws {
        if let c = try? decoder.singleValueContainer(), let str = try? c.decode(String.self) {
            let parts = str.prefix(10).split(separator: "-").compactMap { Int($0) }
            if parts.count > 0 { year = parts[0] }
            if parts.count > 1 { month = parts[1] }
            if parts.count > 2 { day = parts[2] }
        } else if let k = try? decoder.container(keyedBy: CodingKeys.self) {
            year = (try? k.decodeIfPresent(Int.self, forKey: .year)) ?? nil
            month = (try? k.decodeIfPresent(Int.self, forKey: .month)) ?? nil
            day = (try? k.decodeIfPresent(Int.self, forKey: .day)) ?? nil
        }
    }

    var text: String? {
        let gen = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа",
                   "сентября", "октября", "ноября", "декабря"]
        let nom = ["январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август",
                   "сентябрь", "октябрь", "ноябрь", "декабрь"]
        var parts: [String] = []
        if let m = month, (1...12).contains(m) {
            if let d = day { parts = ["\(d)", gen[m - 1]] } else { parts = [nom[m - 1]] }
        }
        if let y = year { parts.append("\(y)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// Пара «название роли — сколько раз» из поля grouped_roles.
struct RoleCount: Codable, Hashable {
    var name: String
    var count: Int
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        name = try c.decode(String.self)
        count = try c.decode(Int.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(name)
        try c.encode(count)
    }
}

private struct SkipValue: Decodable { init(from decoder: Decoder) throws {} }

/// Массив, в котором испорченные элементы пропускаются, а не ломают весь ответ.
struct LossyArray<T: Codable & Hashable>: Codable, Hashable {
    var items: [T] = []
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        while !c.isAtEnd {
            if let v = try? c.decode(T.self) { items.append(v) } else { _ = try? c.decode(SkipValue.self) }
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        for i in items { try c.encode(i) }
    }
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
        let mangaKinds: Set<String> = ["manga", "manhwa", "manhua", "one_shot", "doujin", "light_novel", "novel"]
        let isManga = (kind.map { mangaKinds.contains($0) } ?? false) || (episodes == nil && (chapters != nil || volumes != nil))
        return urlList([posterURLs?.original, posterURLs?.main, image?.original])
            + (ExternalImages.url(isManga ? "manga" : "anime", id).map { [$0] } ?? [])
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
    var createdAt: String?
    var updatedAt: String?
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
    // Порядок как на сайте: запланировано, смотрю, просмотрено, пересматриваю, отложено, брошено
    case planned, watching, completed, rewatching, onHold = "on_hold", dropped
    var id: String { rawValue }
    /// Порядок вкладок в «Списках»: смотрю, запланировано, просмотрено, отложено, брошено, пересматриваю
    static let listOrder: [RateStatus] = [.watching, .planned, .completed, .onHold, .dropped, .rewatching]

    /// Названия как на сайте (config/locales/ru.yml): у аниме «Смотрю», у манги и ранобэ «Читаю».
    func title(for kind: MediaKind) -> String {
        let reading = kind != .anime
        switch self {
        case .planned: return "Запланировано"
        case .watching: return reading ? "Читаю" : "Смотрю"
        case .completed: return reading ? "Прочитано" : "Просмотрено"
        case .rewatching: return reading ? "Перечитываю" : "Пересматриваю"
        case .onHold: return "Отложено"
        case .dropped: return "Брошено"
        }
    }
    var title: String { title(for: .anime) }

    static func title(for raw: String?, kind: MediaKind = .anime) -> String {
        guard let raw, let s = RateStatus(rawValue: raw) else { return "Не в списке" }
        return s.title(for: kind)
    }
    var icon: String {
        switch self {
        case .watching: return "play.circle.fill"
        case .planned: return "bookmark.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .onHold: return "pause.circle.fill"
        case .dropped: return "xmark.circle.fill"
        case .rewatching: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }
    static func icon(for raw: String?) -> String {
        guard let raw, let s = RateStatus(rawValue: raw) else { return "plus.circle.fill" }
        return s.icon
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
    case "tv": return "TV Сериал"
    case "movie": return "Фильм"
    case "ova": return "OVA"
    case "ona": return "ONA"
    case "special": return "Спецвыпуск"
    case "tv_special": return "TV Спецвыпуск"
    case "music": return "Клип"
    case "pv": return "Проморолик"
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
        guard let s = createdAt, let d = SharedDates.parse(s) else { return "" }
        return SharedDates.relative.localizedString(for: d, relativeTo: Date())
    }
}


struct CalendarItem: Codable, Identifiable, Hashable {
    var nextEpisode: Int?
    var nextEpisodeAt: String?
    var anime: Media
    var id: String { "\(anime.id)-\(nextEpisode ?? 0)" }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    var date: Date? {
        guard let s = nextEpisodeAt else { return nil }
        return Self.isoFrac.date(from: s) ?? Self.iso.date(from: s)
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
    var person: CastPerson { person(kind: "characters") }
    func person(kind: String) -> CastPerson {
        CastPerson(id: id, name: name, russian: russian, image: ImageSet(original: image, preview: image, x96: image, x48: image), fbKind: kind)
    }
}

struct Favourites: Codable {
    var animes: [Media] = []
    var mangas: [Media] = []
    var ranobe: [Media] = []
    var characters: [CastPerson] = []
    /// Люди: просто люди, мангаки, сэйю, продюсеры (на сайте это отдельные группы).
    var people: [CastPerson] = []
    var mangakas: [CastPerson] = []
    var seyu: [CastPerson] = []
    var producers: [CastPerson] = []

    init() {}

    // Старый сохранённый кэш без новых групп читается без ошибок
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        animes = (try? c.decode([Media].self, forKey: .animes)) ?? []
        mangas = (try? c.decode([Media].self, forKey: .mangas)) ?? []
        ranobe = (try? c.decode([Media].self, forKey: .ranobe)) ?? []
        characters = (try? c.decode([CastPerson].self, forKey: .characters)) ?? []
        people = (try? c.decode([CastPerson].self, forKey: .people)) ?? []
        mangakas = (try? c.decode([CastPerson].self, forKey: .mangakas)) ?? []
        seyu = (try? c.decode([CastPerson].self, forKey: .seyu)) ?? []
        producers = (try? c.decode([CastPerson].self, forKey: .producers)) ?? []
    }

    var isEmpty: Bool {
        animes.isEmpty && mangas.isEmpty && ranobe.isEmpty && characters.isEmpty
            && people.isEmpty && mangakas.isEmpty && seyu.isEmpty && producers.isEmpty
    }
}

struct FavouritesResponse: Codable {
    var animes: [FavouriteItem]?
    var mangas: [FavouriteItem]?
    var ranobe: [FavouriteItem]?
    var characters: [FavouriteItem]?
    var people: [FavouriteItem]?
    var mangakas: [FavouriteItem]?
    var seyu: [FavouriteItem]?
    var producers: [FavouriteItem]?
}

struct HistoryTarget: Codable, Hashable {
    var id: Int
    var name: String?
    var russian: String?
    var url: String?
    var image: ImageSet?
    var score: String?
    var posterURLs: [URL] { urlList([image?.preview, image?.original, image?.x96]) }
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
        guard let s = createdAt, let d = SharedDates.parse(s) else { return "" }
        return SharedDates.relative.localizedString(for: d, relativeTo: Date())
    }
}


struct CharacterDetail: Codable {
    var id: Int
    var name: String?
    var russian: String?
    var altname: String?
    var japanese: String?
    var image: ImageSet?
    var gqlPoster: PosterURLs?
    var descriptionHtml: String?
    var seyu: [CastPerson]?
    var animes: [Media]?
    var mangas: [Media]?
    var topicId: Int?

    var title: String {
        if let r = russian, !r.isEmpty { return r }
        return name ?? ""
    }
    var posterURLs: [URL] {
        if let g = gqlPoster, g.original != nil || g.main != nil { return urlList([g.original, g.main, g.preview]) }
        return urlList([image?.original, image?.preview, image?.x96]) + (ExternalImages.url("characters", id).map { [$0] } ?? [])
    }
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
    /// Картинка из GraphQL (poster): у части людей в обычных данных картинки нет, а здесь есть.
    var gqlPoster: PosterURLs?
    var roles: [PersonRoleGroup]?
    var works: [PersonWork]?
    var topicId: Int?
    var birthOn: LooseDate?
    var deceasedOn: LooseDate?
    var website: String?
    var groupedRoles: LossyArray<RoleCount>?

    var title: String {
        if let r = russian, !r.isEmpty { return r }
        return name ?? ""
    }
    var posterURLs: [URL] {
        if let g = gqlPoster, g.original != nil || g.main != nil { return urlList([g.original, g.main, g.preview]) }
        return urlList([image?.original, image?.preview, image?.x96]) + (ExternalImages.url("people", id).map { [$0] } ?? [])
    }
}


/// Элемент статистики: в оценках имя может быть числом, в типах строкой.
struct StatEntry: Codable {
    var name: String
    var value: Int

    enum CodingKeys: String, CodingKey { case name, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .name) {
            name = s
        } else if let i = try? c.decode(Int.self, forKey: .name) {
            name = String(i)
        } else if let d = try? c.decode(Double.self, forKey: .name) {
            name = String(Int(d))
        } else {
            name = ""
        }
        value = (try? c.decode(Int.self, forKey: .value)) ?? 0
    }
}

struct StatusStat: Codable {
    var name: String
    var size: Int
}

struct UserStats: Codable {
    var fullStatuses: [String: [StatusStat]]?
    var scores: [String: [StatEntry]]?
}

struct UserProfileInfo: Codable {
    var stats: UserStats?
    var aboutHtml: String?
    var fullYears: Int?
    var lastOnlineAt: String?
    var website: String?
    var sex: String?
}


/// Видео тайтла (трейлеры, опенинги, эндинги).
struct VideoItem: Codable, Identifiable, Hashable {
    var id: Int
    var url: String?
    var imageUrl: String?
    var playerUrl: String?
    var name: String?
    var kind: String?
    var hosting: String?

    var thumb: URL? { absoluteURL(imageUrl) }
    var pageURL: URL? { url.flatMap { absoluteURL($0.replacingOccurrences(of: "http://", with: "https://")) } }
    var playerURL: URL? {
        guard let p = playerUrl else { return pageURL }
        return absoluteURL(p.replacingOccurrences(of: "http://", with: "https://")) ?? pageURL
    }
    var kindTitle: String {
        switch kind {
        case "pv": return "Проморолик"
        case "character_trailer": return "Трейлер персонажа"
        case "cm": return "Реклама"
        case "op": return "Опенинг"
        case "ed": return "Эндинг"
        case "op_ed_clip": return "Клип OP/ED"
        case "clip": return "Клип"
        case "episode_preview": return "Анонс серии"
        default: return "Видео"
        }
    }
}

/// Группа видео для вкладок на экране «Видео» (по важности).
enum VideoGroup: Int, CaseIterable, Identifiable {
    case promo, music, episodes, clips, ads, other
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .promo: return "Трейлеры"
        case .music: return "Опенинги и эндинги"
        case .episodes: return "Анонсы серий"
        case .clips: return "Клипы"
        case .ads: return "Реклама"
        case .other: return "Другое"
        }
    }
}

extension VideoItem {
    var group: VideoGroup {
        switch kind {
        case "pv", "character_trailer": return .promo
        case "op", "ed", "op_ed_clip": return .music
        case "episode_preview": return .episodes
        case "clip": return .clips
        case "cm": return .ads
        default: return .other
        }
    }
}

extension Array where Element == VideoItem {
    /// Видео по порядку важности групп (внутри группы порядок сайта).
    var byImportance: [VideoItem] {
        enumerated().sorted { a, b in
            a.element.group.rawValue != b.element.group.rawValue
                ? a.element.group.rawValue < b.element.group.rawValue : a.offset < b.offset
        }.map(\.element)
    }
}

extension AuthManager {
    func videos(_ ref: MediaRef) async -> [VideoItem] {
        guard ref.kind == .anime else { return [] }
        return (try? await get("/api/animes/\(ref.id)/videos")) ?? []
    }
}


/// Узел франшизы: тайтл, связанный цепочкой связей (из /franchise).
struct FranchiseNode: Codable, Identifiable, Hashable {
    var id: Int
    var date: Int?
    var name: String?
    var imageUrl: String?
    var url: String?
    var year: Int?
    var kind: String?

    var imageURL: URL? {
        guard let s = imageUrl, !s.isEmpty else { return nil }
        if s.hasPrefix("//") { return URL(string: "https:" + s) }
        if s.hasPrefix("/") { return URL(string: ShikiConfig.host + s) }
        return URL(string: s)
    }
    var mediaKind: MediaKind {
        let u = url ?? ""
        if u.contains("/ranobe/") { return .ranobe }
        if u.contains("/mangas/") { return .manga }
        return .anime
    }
}

struct FranchiseResponse: Codable {
    var nodes: [FranchiseNode]?
    var currentId: Int?
}

extension AuthManager {
    /// Все кадры тайтла (в профиле тайтла API отдаёт только два).
    func screenshots(_ ref: MediaRef) async -> [Screenshot] {
        guard ref.kind == .anime else { return [] }
        return (try? await get("/api/animes/\(ref.id)/screenshots")) ?? []
    }

    func franchise(_ ref: MediaRef) async -> [FranchiseNode] {
        let r: FranchiseResponse? = try? await get("/api/\(ref.kind.path)/\(ref.id)/franchise")
        return r?.nodes ?? []
    }
}


/// Общие форматтеры дат: создавать их заново для каждой строки списка очень дорого (списки лагали).
enum SharedDates {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()
    static let relative: RelativeDateTimeFormatter = {
        let r = RelativeDateTimeFormatter()
        r.locale = Locale(identifier: "ru_RU")
        r.unitsStyle = .short
        return r
    }()
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f
    }()
    static func parse(_ s: String) -> Date? { withFraction.date(from: s) ?? plain.date(from: s) }
}
