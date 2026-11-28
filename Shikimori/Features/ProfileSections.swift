import SwiftUI

// MARK: - Избранное

/// Одна группа избранного: аниме, манга, ранобэ, персонажи, люди и т.д.
private enum FavGroup: Identifiable {
    case media(String, [Media], MediaKind)
    case people(String, [CastPerson], isCharacter: Bool)

    var id: String { title }
    var title: String {
        switch self {
        case .media(let t, _, _), .people(let t, _, _): return t
        }
    }
    var count: Int {
        switch self {
        case .media(_, let l, _): return l.count
        case .people(_, let l, _): return l.count
        }
    }
}

/// Блок «Избранное» в профиле: у каждой группы заголовок со стрелкой (весь список на отдельном экране) и лента из первых элементов.
struct FavouritesSection: View {
    let fav: Favourites
    private let previewCount = 10

    private var groups: [FavGroup] {
        [
            .media("Аниме", fav.animes, .anime),
            .media("Манга", fav.mangas, .manga),
            .media("Ранобэ", fav.ranobe, .ranobe),
            .people("Персонажи", fav.characters, isCharacter: true),
            .people("Сэйю", fav.seyu, isCharacter: false),
            .people("Мангаки", fav.mangakas, isCharacter: false),
            .people("Режиссёры и авторы", fav.producers, isCharacter: false),
            .people("Другие люди", fav.people, isCharacter: false)
        ].filter { $0.count > 0 }
    }

    var body: some View {
        let list = groups
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                Text("Избранное").font(.title2.weight(.heavy))
                ForEach(list) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink { FavouritePage(group: group) } label: {
                            HStack(spacing: 6) {
                                Text("\(group.title) (\(group.count))").font(.title3.weight(.bold))
                                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        strip(group)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func strip(_ group: FavGroup) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                switch group {
                case .media(_, let items, let kind):
                    ForEach(items.prefix(previewCount)) { item in
                        NavigationLink { TitleView(ref: MediaRef(id: item.id, kind: kind)) } label: {
                            TitleCard(media: item, kind: kind, width: 112)
                        }
                        .buttonStyle(.plain)
                    }
                case .people(_, let items, let isCharacter):
                    ForEach(items.prefix(previewCount), id: \.id) { p in
                        NavigationLink { destination(p, isCharacter) } label: { CastAvatar(person: p) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    fileprivate static func personDestination(_ p: CastPerson, _ isCharacter: Bool) -> some View {
        if isCharacter { CharacterView(id: p.id) } else { PersonView(id: p.id) }
    }
    @ViewBuilder
    private func destination(_ p: CastPerson, _ isCharacter: Bool) -> some View {
        FavouritesSection.personDestination(p, isCharacter)
    }
}

/// Полный список одной группы избранного.
private struct FavouritePage: View {
    let group: FavGroup
    private let mediaColumns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    private let peopleColumns = [GridItem(.adaptive(minimum: 96), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            switch group {
            case .media(_, let items, let kind):
                LazyVGrid(columns: mediaColumns, spacing: 14) {
                    ForEach(items) { item in
                        NavigationLink { TitleView(ref: MediaRef(id: item.id, kind: kind)) } label: {
                            TitleCard(media: item, kind: kind)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            case .people(_, let items, let isCharacter):
                LazyVGrid(columns: peopleColumns, spacing: 16) {
                    ForEach(items, id: \.id) { p in
                        NavigationLink { FavouritesSection.personDestination(p, isCharacter) } label: {
                            CastAvatar(person: p, size: 88)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .background(AppBackground())
        .navigationTitle("\(group.title) (\(group.count))")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Друзья

struct FriendsSection: View {
    let friends: [ShikiUser]

    var body: some View {
        if !friends.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink { FriendsPage(friends: friends) } label: {
                    HStack(spacing: 6) {
                        Text("Друзья (\(friends.count))").font(.title3.weight(.bold))
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(friends.prefix(12), id: \.id) { f in
                            NavigationLink { UserView(user: f) } label: {
                                VStack(spacing: 8) {
                                    avatar(f, 64)
                                    Text(f.nickname).font(.caption.weight(.semibold)).lineLimit(1).frame(width: 80)
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 6)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func avatar(_ u: ShikiUser, _ size: CGFloat) -> some View {
    Color(UIColor.tertiarySystemFill)
        .frame(width: size, height: size)
        .overlay { if let url = u.avatarURL { RemoteImage(urls: [url]) } }
        .clipShape(Circle())
}

private struct FriendsPage: View {
    let friends: [ShikiUser]
    @State private var search = ""

    private var shown: [ShikiUser] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? friends : friends.filter { $0.nickname.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(shown, id: \.id) { f in
                    NavigationLink { UserView(user: f) } label: {
                        HStack(spacing: 14) {
                            avatar(f, 48)
                            Text(f.nickname).font(.body.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if shown.isEmpty {
                    ContentUnavailableView("Никого не найдено", systemImage: "magnifyingglass").padding(.top, 30)
                }
            }
            .padding(20)
        }
        .background(AppBackground())
        .navigationTitle("Друзья (\(friends.count))")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Поиск среди друзей")
    }
}

// MARK: - История

extension HistoryItem {
    var date: Date? { createdAt.flatMap(SharedDates.parse) }
}

/// Готовая к показу запись истории: текст и даты считаются один раз, а не при каждой отрисовке.
struct HistEntry: Identifiable {
    let id: Int
    let title: String
    let text: String
    let dateText: String
    let date: Date?
    let target: HistoryTarget?

    init?(_ item: HistoryItem) {
        let text = item.plainDescription
        guard !text.isEmpty else { return nil }
        id = item.id
        title = item.target?.title ?? ""
        self.text = text
        dateText = item.dateText
        date = item.date
        target = item.target
    }
}

/// Настоящие постеры тайтлов из истории (GraphQL): у новых тайтлов обычные адреса из истории дают заглушку.
@MainActor
final class HistoryPosters: ObservableObject {
    static let shared = HistoryPosters()
    @Published private(set) var urls: [String: [URL]] = [:]

    static func key(_ t: HistoryTarget) -> String { "\(t.kind.rawValue)-\(t.id)" }

    func load(_ targets: [HistoryTarget]) async {
        for kind in MediaKind.allCases {
            let ids = Array(Set(targets.filter { $0.kind == kind }.map(\.id))).filter { urls["\(kind.rawValue)-\($0)"] == nil }
            guard !ids.isEmpty else { continue }
            let found = await AuthManager.shared.fetchPosters(ids: ids, kind: kind)
            var add: [String: [URL]] = [:]
            for (id, p) in found {
                let list = [p.main, p.original, p.preview].compactMap { $0 }
                    .compactMap { URL(string: $0.hasPrefix("http") ? $0 : ShikiConfig.host + $0) }
                if !list.isEmpty { add["\(kind.rawValue)-\(id)"] = list }
            }
            urls.merge(add) { _, new in new }
        }
    }
}

private struct HistoryRow: View {
    let item: HistEntry
    @ObservedObject private var book = HistoryPosters.shared

    var body: some View {
        let kind = item.target?.kind ?? .anime
        let posters = item.target.map { (book.urls[HistoryPosters.key($0)] ?? []) + $0.posterURLs } ?? []
        let content = HStack(alignment: .top, spacing: 12) {
            Color(UIColor.tertiarySystemFill)
                .frame(width: 48, height: 70)
                .overlay { RemoteImage(urls: posters, placeholder: kind == .anime ? "film" : "book.closed", maxPixel: 240) }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                if !item.title.isEmpty {
                    Text(item.title).font(.subheadline.weight(.bold)).multilineTextAlignment(.leading).lineLimit(2)
                }
                Text(item.text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading).lineLimit(3)
                HStack(spacing: 6) {
                    Text(kind.title).font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                    if let score = item.target?.score, let v = Double(score), v > 0 {
                        Label(score, systemImage: "star.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(item.dateText).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

        if let t = item.target {
            NavigationLink { TitleView(ref: MediaRef(id: t.id, kind: t.kind)) } label: { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// Компактная «Недавняя активность» в профиле: несколько записей и кнопка «История».
struct ActivitySection: View {
    let userID: Int
    let nickname: String
    let history: [HistoryItem]

    var body: some View {
        let items = history.prefix(12).compactMap(HistEntry.init).prefix(5)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Недавняя активность").font(.title3.weight(.bold))
                ForEach(Array(items)) { HistoryRow(item: $0) }
                    .task { await HistoryPosters.shared.load(items.compactMap(\.target)) }
                NavigationLink { HistoryScreen(userID: userID, nickname: nickname) } label: {
                    HStack {
                        Label("История", systemImage: "clock.arrow.circlepath").font(.body.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct HistGroup: Identifiable {
    let title: String
    let items: [HistEntry]
    var id: String { title }
}

@MainActor
private final class HistoryModel: ObservableObject {
    let userID: Int
    /// Записи, уже разложенные по периодам (считается один раз при загрузке).
    @Published var groups: [HistGroup] = []
    private var entries: [HistEntry] = []
    @Published var loading = false
    @Published var error: String?
    @Published var finished = false
    var targetType: String?
    private var page = 1
    private var generation = 0
    private var seen = Set<Int>()
    private let limit = 50

    var isEmpty: Bool { entries.isEmpty }

    init(userID: Int) { self.userID = userID }

    static func group(_ list: [HistEntry]) -> [HistGroup] {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        var order: [String] = []
        var map: [String: [HistEntry]] = [:]
        for item in list {
            let title: String
            if let d = item.date {
                let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: startToday).day ?? 0
                if days <= 0 { title = "Сегодня" }
                else if days == 1 { title = "Вчера" }
                else if days < 7 { title = "На этой неделе" }
                else if days < 14 { title = "На прошлой неделе" }
                else if days < 31 { title = "В течение месяца" }
                else { let m = SharedDates.monthYear.string(from: d); title = m.prefix(1).uppercased() + m.dropFirst() }
            } else {
                title = "Раньше"
            }
            if map[title] == nil { order.append(title) }
            map[title, default: []].append(item)
        }
        return order.map { HistGroup(title: $0, items: map[$0] ?? []) }
    }

    func reload() async {
        generation += 1
        page = 1
        finished = false
        entries = []
        groups = []
        seen = []
        error = nil
        loading = false
        await more()
    }

    func more(after current: HistEntry? = nil) async {
        if let current, !entries.suffix(8).contains(where: { $0.id == current.id }) { return }
        guard !finished, !loading else { return }
        loading = true
        error = nil
        let gen = generation
        do {
            let result = try await AuthManager.shared.historyPage(id: userID, page: page, limit: limit, targetType: targetType)
            guard gen == generation else { loading = false; return }
            for item in result where !seen.contains(item.id) {
                seen.insert(item.id)
                if let e = HistEntry(item) { entries.append(e) }
            }
            groups = HistoryModel.group(entries)
            finished = result.count < limit
            page += 1
            await HistoryPosters.shared.load(result.compactMap(\.target))
        } catch is CancellationError {
        } catch {
            if gen == generation { self.error = error.localizedDescription }
        }
        loading = false
    }
}

/// Полная история пользователя: записи по периодам, фильтр аниме/манга, подгрузка при прокрутке.
struct HistoryScreen: View {
    let nickname: String
    @StateObject private var model: HistoryModel
    @State private var filter = 0   // 0 всё, 1 аниме, 2 манга и ранобэ

    init(userID: Int, nickname: String) {
        self.nickname = nickname
        _model = StateObject(wrappedValue: HistoryModel(userID: userID))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Picker("Раздел", selection: $filter) {
                    Text("Всё").tag(0)
                    Text("Аниме").tag(1)
                    Text("Манга").tag(2)
                }
                .pickerStyle(.segmented)

                ForEach(model.groups) { section in
                    LazyVStack(alignment: .leading, spacing: 8) {
                        Text(section.title).font(.headline).foregroundStyle(.secondary).padding(.top, 6)
                        ForEach(section.items) { item in
                            HistoryRow(item: item)
                                .onAppear { Task { await model.more(after: item) } }
                        }
                    }
                }

                if model.loading { ProgressView().frame(maxWidth: .infinity).padding() }
                if let message = model.error {
                    ErrorBanner(message: message) { Task { await model.more() } }
                }
                if !model.loading && model.error == nil && model.isEmpty {
                    ContentUnavailableView("История пуста", systemImage: "clock").padding(.top, 30)
                }
            }
            .padding(20)
            .padding(.bottom, 60)
        }
        .background(AppBackground())
        .navigationTitle("История")
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.isEmpty { await model.reload() } }
        .refreshable { await model.reload() }
        .onChange(of: filter) { _, v in
            model.targetType = v == 1 ? "Anime" : (v == 2 ? "Manga" : nil)
            Task { await model.reload() }
        }
    }
}
