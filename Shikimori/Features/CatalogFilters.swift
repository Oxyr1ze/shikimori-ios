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

// MARK: Элементы интерфейса

/// Строка «название — выбранное значение» с выпадающим меню iOS.
private struct MenuRow<Content: View>: View {
    let title: String
    let summary: String
    var multi = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if multi {
                Menu { content() } label: { label }
                    .menuActionDismissBehavior(.disabled)
            } else {
                Menu { content() } label: { label }
            }
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            Text(summary.isEmpty ? "Не важно" : summary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.footnote)
        }
        .foregroundStyle(summary.isEmpty ? Color.secondary : Theme.accent)
    }
}

/// Отдельная страница с поиском для длинных списков (студии, издатели).
private struct NamedPickerPage: View {
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

struct CatalogFiltersView: View {
    let kind: MediaKind
    @Binding var filters: CatalogFilters
    @Environment(\.dismiss) private var dismiss
    @State private var genres: [GQLGenre] = []
    @State private var studios: [ExtraNamed] = []
    @State private var publishers: [ExtraNamed] = []

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date()) + 1
        return Array((1960...current).reversed())
    }

    private func summary(_ set: Set<String>, _ options: [(String, String)]) -> String {
        let mine = options.filter { set.contains($0.0) }
        if mine.isEmpty { return "" }
        if mine.count == 1 { return mine[0].1 }
        return "Выбрано: \(mine.count)"
    }

    private func multi(_ title: String, _ options: [(String, String)], _ keyPath: WritableKeyPath<CatalogFilters, Set<String>>) -> some View {
        MenuRow(title: title, summary: summary(filters[keyPath: keyPath], options)) {
            ForEach(options, id: \.0) { option in
                Toggle(option.1, isOn: Binding(
                    get: { filters[keyPath: keyPath].contains(option.0) },
                    set: { on in
                        if on { filters[keyPath: keyPath].insert(option.0) }
                        else { filters[keyPath: keyPath].remove(option.0) }
                    }))
            }
        }
    }

    private func genreRow(_ title: String, kindName: String) -> some View {
        let list = genres.filter { $0.kind == kindName }.sorted { $0.display < $1.display }
        let chosen = list.filter { g in g.intID.map { filters.genreIDs.contains($0) } ?? false }
        let text = chosen.count == 1 ? chosen[0].display : (chosen.isEmpty ? "" : "Выбрано: \(chosen.count)")
        return MenuRow(title: title, summary: text) {
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
    }

    private func namedRow(_ title: String, items: [ExtraNamed], selection: Binding<Set<Int>>) -> some View {
        let chosen = items.filter { $0.intID.map { selection.wrappedValue.contains($0) } ?? false }
        let text = chosen.count == 1 ? (chosen[0].name ?? "") : (selection.wrappedValue.isEmpty ? "" : "Выбрано: \(selection.wrappedValue.count)")
        return NavigationLink {
            NamedPickerPage(title: title, items: items, selection: selection)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(text.isEmpty ? "Не важно" : text)
                    .lineLimit(1)
                    .foregroundStyle(text.isEmpty ? Color.secondary : Theme.accent)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                let orders = CatalogOptions.orders(for: kind)
                MenuRow(title: "Сортировка", summary: orders.first { $0.0 == filters.order }?.1 ?? "", multi: false) {
                    Picker("Сортировка", selection: $filters.order) {
                        ForEach(orders, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }

                multi("Мой список", CatalogOptions.myList(for: kind), \.myList)
                multi("Статус", CatalogOptions.statuses(for: kind), \.statuses)

                let kinds = CatalogOptions.kinds(for: kind)
                if !kinds.isEmpty { multi("Тип", kinds, \.kinds) }
                if kind == .anime { multi("Количество серий", CatalogOptions.episodeCounts, \.kinds) }

                genreRow("Жанры", kindName: "genre")
                genreRow("Темы", kindName: "theme")
                if genres.contains(where: { $0.kind == "demographic" }) {
                    genreRow("Аудитория", kindName: "demographic")
                }

                multi("Сезон", CatalogOptions.seasons(), \.seasons)

                MenuRow(title: "Год с",
                        summary: filters.yearFrom > 0 ? String(filters.yearFrom) : "", multi: false) {
                    Picker("С", selection: $filters.yearFrom) {
                        Text("Не важно").tag(0)
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                }
                MenuRow(title: "Год по",
                        summary: filters.yearTo > 0 ? String(filters.yearTo) : "", multi: false) {
                    Picker("По", selection: $filters.yearTo) {
                        Text("Не важно").tag(0)
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                }

                if kind == .anime {
                    multi("Длительность серии", CatalogOptions.durations, \.durations)
                    multi("Возрастной рейтинг", CatalogOptions.ratings, \.ratings)
                    multi("Первоисточник", CatalogOptions.origins, \.origins)
                    namedRow("Студия", items: studios, selection: $filters.studioIDs)
                } else {
                    namedRow("Издатель", items: publishers, selection: $filters.publisherIDs)
                }

                MenuRow(title: "Оценка не ниже",
                        summary: filters.minScore > 0 ? "\(filters.minScore)" : "", multi: false) {
                    Picker("Оценка", selection: $filters.minScore) {
                        Text("Не важно").tag(0)
                        ForEach((1...9).reversed(), id: \.self) { Text("\($0)").tag($0) }
                    }
                }
            }
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Сбросить") { filters = CatalogFilters() }
                        .disabled(filters.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }.fontWeight(.semibold)
                }
            }
            .task {
                genres = await AuthManager.shared.genresV2(manga: kind != .anime)
                if kind == .anime {
                    studios = await AuthManager.shared.studios()
                } else {
                    publishers = await AuthManager.shared.publishers()
                }
            }
        }
    }
}
