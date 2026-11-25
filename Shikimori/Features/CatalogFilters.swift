import SwiftUI

/// Выбранные фильтры каталога.
struct CatalogFilters: Equatable {
    var type: String = ""          // tv, movie, manga ...
    var yearFrom: Int = 0          // 0 = не задан
    var yearTo: Int = 0
    var minScore: Int = 0          // 0 = любая
    var rating: String = ""        // g, pg_13 ... только аниме
    var genreIDs: Set<Int> = []

    var isEmpty: Bool { self == CatalogFilters() }

    /// Число включённых фильтров (для значка на кнопке).
    var count: Int {
        var n = 0
        if !type.isEmpty { n += 1 }
        if yearFrom > 0 || yearTo > 0 { n += 1 }
        if minScore > 0 { n += 1 }
        if !rating.isEmpty { n += 1 }
        if !genreIDs.isEmpty { n += 1 }
        return n
    }

    func queryItems(kind: MediaKind) -> [URLQueryItem] {
        var q: [URLQueryItem] = []
        if !type.isEmpty && kind != .ranobe { q.append(URLQueryItem(name: "kind", value: type)) }
        if yearFrom > 0 || yearTo > 0 {
            let from = yearFrom > 0 ? yearFrom : yearTo
            let to = yearTo > 0 ? yearTo : yearFrom
            let lo = min(from, to), hi = max(from, to)
            q.append(URLQueryItem(name: "season", value: lo == hi ? "\(lo)" : "\(lo)_\(hi)"))
        }
        if minScore > 0 { q.append(URLQueryItem(name: "score", value: String(minScore))) }
        if !rating.isEmpty && kind == .anime { q.append(URLQueryItem(name: "rating", value: rating)) }
        if !genreIDs.isEmpty {
            q.append(URLQueryItem(name: "genre", value: genreIDs.sorted().map(String.init).joined(separator: ",")))
        }
        return q
    }
}

enum CatalogTypes {
    static func options(for kind: MediaKind) -> [(String, String)] {
        switch kind {
        case .anime:
            return [("tv", "ТВ-сериал"), ("movie", "Фильм"), ("ova", "OVA"), ("ona", "ONA"),
                    ("special", "Спешл"), ("tv_special", "ТВ-спешл"), ("music", "Клип")]
        case .manga:
            return [("manga", "Манга"), ("manhwa", "Манхва"), ("manhua", "Маньхуа"),
                    ("one_shot", "Ваншот"), ("doujin", "Додзинси")]
        case .ranobe:
            return []
        }
    }

    static let ratings: [(String, String)] = [
        ("g", "G: для всех"), ("pg", "PG: детям"), ("pg_13", "PG-13: от 13 лет"),
        ("r", "R-17: от 17 лет"), ("r_plus", "R+: мягкая эротика")
    ]
}

struct CatalogFiltersView: View {
    let kind: MediaKind
    @Binding var filters: CatalogFilters
    @Environment(\.dismiss) private var dismiss
    @State private var genres: [Genre] = []

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date()) + 1
        return Array((1960...current).reversed())
    }

    private var kindGenres: [Genre] {
        let type = kind == .anime ? "Anime" : "Manga"
        return genres.filter { $0.entryType == type }.sorted { $0.display < $1.display }
    }

    var body: some View {
        NavigationStack {
            Form {
                let types = CatalogTypes.options(for: kind)
                if !types.isEmpty {
                    Picker("Тип", selection: $filters.type) {
                        Text("Любой").tag("")
                        ForEach(types, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }

                Section("Год выхода") {
                    Picker("С", selection: $filters.yearFrom) {
                        Text("Не важно").tag(0)
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                    Picker("По", selection: $filters.yearTo) {
                        Text("Не важно").tag(0)
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                }

                Picker("Оценка не ниже", selection: $filters.minScore) {
                    Text("Любая").tag(0)
                    ForEach((1...9).reversed(), id: \.self) { Text("\($0)").tag($0) }
                }

                if kind == .anime {
                    Picker("Возрастной рейтинг", selection: $filters.rating) {
                        Text("Любой").tag("")
                        ForEach(CatalogTypes.ratings, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }

                Section("Жанры") {
                    if kindGenres.isEmpty {
                        Text("Загрузка жанров…").foregroundStyle(.secondary)
                    }
                    ForEach(kindGenres, id: \.id) { g in
                        if let id = g.id {
                            Button {
                                if filters.genreIDs.contains(id) { filters.genreIDs.remove(id) }
                                else { filters.genreIDs.insert(id) }
                            } label: {
                                HStack {
                                    Text(g.display).foregroundStyle(.primary)
                                    Spacer()
                                    if filters.genreIDs.contains(id) {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                        }
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
            .task { genres = await AuthManager.shared.genres() }
        }
    }
}
