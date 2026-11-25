import SwiftUI

/// Все фильтры и сортировка каталога (как на сайте).
struct CatalogFilters: Equatable {
    static let defaultOrder = "popularity"

    var order: String = CatalogFilters.defaultOrder
    var myList: Set<String> = []       // planned, watching ... и "none" (нет в списке)
    var statuses: Set<String> = []
    var kinds: Set<String> = []        // tv, movie ... и tv_13/tv_24/tv_48
    var genreIDs: Set<Int> = []        // жанры, темы и аудитория (версия 2)
    var seasons: Set<String> = []      // winter_2027, 2016, 201x, ancient
    var yearFrom: Int = 0
    var yearTo: Int = 0
    var durations: Set<String> = []    // S, D, F
    var ratings: Set<String> = []      // g, pg, pg_13, r, r_plus, rx
    var origins: Set<String> = []
    var studioIDs: Set<Int> = []
    var publisherIDs: Set<Int> = []
    var minScore: Int = 0

    var isEmpty: Bool { self == CatalogFilters() }

    /// Число включённых пунктов (для значка на кнопке).
    var count: Int {
        var n = 0
        if order != CatalogFilters.defaultOrder { n += 1 }
        if !myList.isEmpty { n += 1 }
        if !statuses.isEmpty { n += 1 }
        if !kinds.isEmpty { n += 1 }
        if !genreIDs.isEmpty { n += 1 }
        if !seasons.isEmpty || yearFrom > 0 || yearTo > 0 { n += 1 }
        if !durations.isEmpty { n += 1 }
        if !ratings.isEmpty { n += 1 }
        if !origins.isEmpty { n += 1 }
        if !studioIDs.isEmpty { n += 1 }
        if !publisherIDs.isEmpty { n += 1 }
        if minScore > 0 { n += 1 }
        return n
    }

    private func csv(_ set: Set<String>) -> String { set.sorted().joined(separator: ",") }

    func queryItems(kind: MediaKind) -> [URLQueryItem] {
        var q: [URLQueryItem] = []
        func add(_ name: String, _ value: String) {
            if !value.isEmpty { q.append(URLQueryItem(name: name, value: value)) }
        }
        if myList.contains("none") {
            add("mylist", ["planned", "watching", "rewatching", "completed", "on_hold", "dropped"]
                .map { "!" + $0 }.joined(separator: ","))
        } else {
            add("mylist", csv(myList))
        }
        add("status", csv(statuses))
        if kind != .ranobe { add("kind", csv(kinds)) }

        var seasonTerms = seasons.sorted()
        if yearFrom > 0 || yearTo > 0 {
            let from = yearFrom > 0 ? yearFrom : yearTo
            let to = yearTo > 0 ? yearTo : yearFrom
            let lo = min(from, to), hi = max(from, to)
            seasonTerms.append(lo == hi ? "\(lo)" : "\(lo)_\(hi)")
        }
        add("season", seasonTerms.joined(separator: ","))

        if minScore > 0 { add("score", String(minScore)) }
        if kind == .anime {
            add("duration", csv(durations))
            add("rating", csv(ratings))
            add("origin", csv(origins))
            add("studio", studioIDs.sorted().map(String.init).joined(separator: ","))
        } else {
            add("publisher", publisherIDs.sorted().map(String.init).joined(separator: ","))
        }
        add("genre_v2", genreIDs.sorted().map(String.init).joined(separator: ","))
        return q
    }
}

/// Списки значений и подписи (как на сайте).
enum CatalogOptions {
    static func orders(for kind: MediaKind) -> [(String, String)] {
        var list = [("ranked", "По рейтингу"), ("popularity", "По популярности"),
                    ("name", "По алфавиту"), ("aired_on", "По дате выхода")]
        list.append(kind == .anime ? ("episodes", "По числу серий") : ("chapters", "По числу глав"))
        if kind != .anime { list.append(("volumes", "По числу томов")) }
        list.append(("random", "Случайно"))
        list.append(("id", "По ID"))
        return list
    }

    static func myList(for kind: MediaKind) -> [(String, String)] {
        let reading = kind != .anime
        return [("planned", "В планах"), ("watching", reading ? "Читаю" : "Смотрю"),
                ("completed", reading ? "Прочитано" : "Просмотрено"), ("on_hold", "Отложено"),
                ("dropped", "Брошено"), ("rewatching", reading ? "Перечитываю" : "Пересматриваю"),
                ("none", "Нет в списке")]
    }

    static func statuses(for kind: MediaKind) -> [(String, String)] {
        if kind == .anime {
            return [("anons", "Анонс"), ("ongoing", "Онгоинг"), ("released", "Вышло"), ("latest", "Недавно вышло")]
        }
        return [("anons", "Анонс"), ("ongoing", "Выходит"), ("released", "Издано"),
                ("paused", "Приостановлено"), ("discontinued", "Прекращено"), ("latest", "Недавно издано")]
    }

    static func kinds(for kind: MediaKind) -> [(String, String)] {
        switch kind {
        case .anime:
            return [("tv", "TV Сериал"), ("movie", "Фильм"), ("ova", "OVA"), ("ona", "ONA"),
                    ("special", "Спецвыпуск"), ("tv_special", "TV Спецвыпуск"), ("music", "Клип"),
                    ("pv", "Проморолик"), ("cm", "Реклама")]
        case .manga:
            return [("manga", "Манга"), ("manhwa", "Манхва"), ("manhua", "Маньхуа"),
                    ("one_shot", "Ваншот"), ("doujin", "Додзинси")]
        case .ranobe:
            return []
        }
    }

    static let episodeCounts: [(String, String)] = [
        ("tv_13", "Короткие — до 16 серий"),
        ("tv_24", "Средние — 17–28 серий"),
        ("tv_48", "Длинные — от 29 серий")
    ]

    static let durations: [(String, String)] = [
        ("S", "Меньше 10 мин"), ("D", "10–30 мин"), ("F", "Больше 30 мин")
    ]

    static let ratings: [(String, String)] = [
        ("g", "G — без ограничений"), ("pg", "PG — детям"), ("pg_13", "PG-13 — 13+"),
        ("r", "R — 17+"), ("r_plus", "R+ — 18+"), ("rx", "Rx — хентай")
    ]

    static let origins: [(String, String)] = [
        "original", "manga", "web_manga", "four_koma_manga", "light_novel", "novel",
        "web_novel", "visual_novel", "game", "card_game", "music", "radio", "book",
        "picture_book", "mixed_media", "other"
    ].map { ($0, SiteLabels.origin($0)) }

    /// Сезоны (годы выбираются отдельным пунктом «Период»).
    static func seasons() -> [(String, String)] {
        let current = Calendar.current.component(.year, from: Date())
        var list: [(String, String)] = []
        let names = [("winter", "зима"), ("spring", "весна"), ("summer", "лето"), ("fall", "осень")]
        for y in stride(from: current + 1, through: current - 5, by: -1) {
            for (key, title) in names { list.append(("\(key)_\(y)", "\(title) \(y)")) }
        }
        return list
    }
}

// MARK: Меню в стиле iOS

/// Данные для меню: жанры, студии, издатели (загружаются один раз и кэшируются).
@MainActor
final class FilterData: ObservableObject {
    @Published var genres: [GQLGenre] = []
    @Published var studios: [ExtraNamed] = []
    @Published var publishers: [ExtraNamed] = []

    func load(kind: MediaKind) async {
        genres = await AuthManager.shared.genresV2(manga: kind != .anime)
        if kind == .anime {
            if studios.isEmpty { studios = await AuthManager.shared.studios() }
        } else if publishers.isEmpty {
            publishers = await AuthManager.shared.publishers()
        }
    }
}

/// Отдельная страница с поиском для длинных списков (студии, издатели).
struct NamedPickerPage: View {
    let title: String
    let items: [ExtraNamed]
    @Binding var selection: Set<Int>
    @State private var search = ""

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = items.filter { query.isEmpty || ($0.name ?? "").lowercased().contains(query) }
        List {
            if items.isEmpty { Text("Загрузка…").foregroundStyle(.secondary) }
            ForEach(list, id: \.id) { item in
                if let id = item.intID {
                    Button {
                        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
                    } label: {
                        HStack {
                            Text(item.name ?? "").foregroundStyle(.primary)
                            Spacer()
                            if selection.contains(id) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Поиск")
    }
}

/// Содержимое выпадающего меню в правом верхнем углу каталога.
struct CatalogMenuContent: View {
    let kind: MediaKind
    @Binding var filters: CatalogFilters
    @ObservedObject var data: FilterData
    var onNamed: () -> Void
    var onRandom: () -> Void

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date()) + 1
        return Array((1960...current).reversed())
    }

    private func title(_ base: String, _ n: Int) -> String { n > 0 ? "\(base) (\(n))" : base }

    private func multi(_ name: String, _ options: [(String, String)], _ keyPath: WritableKeyPath<CatalogFilters, Set<String>>) -> some View {
        let n = options.filter { filters[keyPath: keyPath].contains($0.0) }.count
        return Menu(title(name, n)) {
            ForEach(options, id: \.0) { option in
                Toggle(option.1, isOn: Binding(
                    get: { filters[keyPath: keyPath].contains(option.0) },
                    set: { on in
                        if on { filters[keyPath: keyPath].insert(option.0) }
                        else { filters[keyPath: keyPath].remove(option.0) }
                    }))
            }
        }
        .menuActionDismissBehavior(.disabled)
    }

    private func genreMenu(_ name: String, kindName: String) -> some View {
        let list = data.genres.filter { $0.kind == kindName }.sorted { $0.display < $1.display }
        let n = list.filter { g in g.intID.map { filters.genreIDs.contains($0) } ?? false }.count
        return Menu(title(name, n)) {
            ForEach(list, id: \.id) { g in
                if let id = g.intID {
                    Toggle(g.display, isOn: Binding(
                        get: { filters.genreIDs.contains(id) },
                        set: { on in
                            if on { filters.genreIDs.insert(id) } else { filters.genreIDs.remove(id) }
                        }))
                }
            }
        }
        .menuActionDismissBehavior(.disabled)
    }

    var body: some View {
        let orders = CatalogOptions.orders(for: kind)
        Menu("Сортировка") {
            Picker("Сортировка", selection: $filters.order) {
                ForEach(orders, id: \.0) { Text($0.1).tag($0.0) }
            }
        }
        multi("Мой список", CatalogOptions.myList(for: kind), \.myList)
        multi("Статус", CatalogOptions.statuses(for: kind), \.statuses)
        let kinds = CatalogOptions.kinds(for: kind)
        if !kinds.isEmpty { multi("Тип", kinds, \.kinds) }
        if kind == .anime { multi("Количество серий", CatalogOptions.episodeCounts, \.kinds) }
        genreMenu("Жанры", kindName: "genre")
        genreMenu("Темы", kindName: "theme")
        if data.genres.contains(where: { $0.kind == "demographic" }) {
            genreMenu("Аудитория", kindName: "demographic")
        }
        multi("Сезон", CatalogOptions.seasons(), \.seasons)
        Menu(filters.yearFrom > 0 ? "Год с (\(filters.yearFrom))" : "Год с") {
            Picker("Год с", selection: $filters.yearFrom) {
                Text("Ничего").tag(0)
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
        }
        Menu(filters.yearTo > 0 ? "Год по (\(filters.yearTo))" : "Год по") {
            Picker("Год по", selection: $filters.yearTo) {
                Text("Ничего").tag(0)
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
        }
        if kind == .anime {
            multi("Длительность серии", CatalogOptions.durations, \.durations)
            multi("Возрастной рейтинг", CatalogOptions.ratings, \.ratings)
            multi("Первоисточник", CatalogOptions.origins, \.origins)
            Button(title("Студия…", filters.studioIDs.count), action: onNamed)
        } else {
            Button(title("Издатель…", filters.publisherIDs.count), action: onNamed)
        }
        Menu(filters.minScore > 0 ? "Оценка не ниже (\(filters.minScore))" : "Оценка не ниже") {
            Picker("Оценка", selection: $filters.minScore) {
                Text("Ничего").tag(0)
                ForEach((1...9).reversed(), id: \.self) { Text("\($0)").tag($0) }
            }
        }
        Divider()
        Button("Очистить", role: .destructive) { filters = CatalogFilters() }
            .disabled(filters.isEmpty)
        Button("Случайное", systemImage: "shuffle", action: onRandom)
    }
}
