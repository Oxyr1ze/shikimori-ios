import SwiftUI

enum ListSort: String, CaseIterable, Identifiable {
    case site, added, updated, name, myScore, siteScore, progress
    var id: String { rawValue }
    var title: String {
        switch self {
        case .site: return "Как на сайте"
        case .added: return "По дате добавления"
        case .updated: return "По дате обновления"
        case .name: return "По названию"
        case .myScore: return "По моей оценке"
        case .siteScore: return "По оценке на сайте"
        case .progress: return "По прогрессу"
        }
    }
}

@MainActor
final class ListsModel: ObservableObject {
    @Published var kind: MediaKind = .anime
    @Published var status: RateStatus = .watching
    /// Загруженные списки по ключу «раздел-статус»: переключение между статусами мгновенное.
    @Published private(set) var lists: [String: [RateEntry]] = [:]
    @Published var loading = false
    @Published var error: String?
    private var prefetched = Set<MediaKind>()

    private func key(_ k: MediaKind, _ s: RateStatus) -> String { "\(k.rawValue)-\(s.rawValue)" }

    var entries: [RateEntry] { lists[key(kind, status)] ?? [] }
    func count(_ s: RateStatus) -> Int? { lists[key(kind, s)]?.count }
    var total: Int? {
        let counts = RateStatus.allCases.compactMap { count($0) }
        return counts.count == RateStatus.allCases.count ? counts.reduce(0, +) : nil
    }

    private func fetch(_ k: MediaKind, _ s: RateStatus) async throws -> [RateEntry] {
        k == .anime
            ? try await AuthManager.shared.animeRates(status: s.rawValue)
            : try await AuthManager.shared.mangaRates(kind: k, status: s.rawValue)
    }

    private func restore(_ k: MediaKind, _ s: RateStatus) {
        let id = key(k, s)
        if lists[id] == nil, let cached = DiskCache.load([RateEntry].self, key: DiskCache.userKey("lists-\(id)")) {
            lists[id] = cached
        }
    }

    func load() async {
        let k = kind, s = status
        RateStatus.allCases.forEach { restore(k, $0) }
        loading = true
        error = nil
        do {
            let result = try await fetch(k, s)
            lists[key(k, s)] = result
            DiskCache.save(result, key: DiskCache.userKey("lists-\(key(k, s))"))
        } catch is CancellationError {
            loading = false
            return
        } catch {
            self.error = entries.isEmpty ? error.localizedDescription : offlineMessage
        }
        loading = false
        await prefetchOthers(k, except: s)
    }

    /// Остальные статусы того же раздела подгружаются тихо: появляются числа на вкладках, переключение мгновенное.
    private func prefetchOthers(_ k: MediaKind, except loaded: RateStatus) async {
        guard !prefetched.contains(k) else { return }
        prefetched.insert(k)
        for s in RateStatus.allCases where s != loaded {
            if Task.isCancelled { prefetched.remove(k); return }
            do {
                let result = try await fetch(k, s)
                lists[key(k, s)] = result
                DiskCache.save(result, key: DiskCache.userKey("lists-\(key(k, s))"))
            } catch {
                prefetched.remove(k)
                return
            }
        }
    }

    func forceReload() async {
        prefetched.remove(kind)
        await load()
    }

    func bump(_ entry: RateEntry) async {
        let id = key(kind, status)
        guard var list = lists[id], let idx = list.firstIndex(where: { $0.id == entry.id }) else { return }
        if kind == .anime {
            var next = (entry.episodes ?? 0) + 1
            if let total = entry.anime?.episodes, total > 0 { next = min(next, total) }
            list[idx].episodes = next
            lists[id] = list
            do {
                _ = try await AuthManager.shared.updateRate(id: entry.id, episodes: next)
            } catch {
                list[idx].episodes = entry.episodes
                lists[id] = list
                self.error = error.localizedDescription
            }
        } else {
            var next = (entry.chapters ?? 0) + 1
            if let total = entry.manga?.chapters, total > 0 { next = min(next, total) }
            list[idx].chapters = next
            lists[id] = list
            do {
                _ = try await AuthManager.shared.updateRate(id: entry.id, chapters: next)
            } catch {
                list[idx].chapters = entry.chapters
                lists[id] = list
                self.error = error.localizedDescription
            }
        }
    }
}

struct ListsView: View {
    @StateObject private var model = ListsModel()
    @State private var search = ""
    // Выбор сортировки сохраняется и после закрытия приложения
    @AppStorage("lists.sort") private var sortRaw = ListSort.added.rawValue
    @AppStorage("lists.descending") private var descending = true
    private var sort: ListSort { ListSort(rawValue: sortRaw) ?? .added }

    private var shown: [RateEntry] {
        var list = model.entries.filter { $0.media != nil }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter {
                guard let m = $0.media else { return false }
                return m.title.localizedCaseInsensitiveContains(q) || m.name.localizedCaseInsensitiveContains(q)
            }
        }
        // сначала считаем «по убыванию» (новые, высокие, Я→А), для «по возрастанию» переворачиваем
        switch sort {
        case .site: break
        case .added, .updated:
            // сначала новые; даты разбираем один раз, а не при каждом сравнении
            let pick: (RateEntry) -> String? = { sort == .added ? $0.createdAt : $0.updatedAt }
            let keyed = list.map { ($0, pick($0).flatMap(SharedDates.parse) ?? .distantPast) }
            list = keyed.sorted { $0.1 > $1.1 }.map(\.0)
        case .name: list.sort { ($0.media?.title ?? "").localizedCompare($1.media?.title ?? "") == .orderedDescending }
        case .myScore: list.sort { ($0.score ?? 0) > ($1.score ?? 0) }
        case .siteScore: list.sort { (Double($0.media?.score ?? "") ?? 0) > (Double($1.media?.score ?? "") ?? 0) }
        case .progress:
            let isAnime = model.kind == .anime
            list.sort { (isAnime ? $0.episodes : $0.chapters) ?? 0 > (isAnime ? $1.episodes : $1.chapters) ?? 0 }
        }
        if sort != .site && !descending { list.reverse() }
        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    Picker("Раздел", selection: $model.kind) {
                        ForEach(MediaKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    statusTabs

                    if let total = model.total, search.isEmpty {
                        HStack {
                            Text("Всего в разделе: \(total)").font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                        }
                    }

                    ForEach(shown) { entry in
                        if let media = entry.media { row(entry, media) }
                    }

                    if model.loading && model.entries.isEmpty { ProgressView().padding() }
                    if !model.loading && model.error == nil && shown.isEmpty {
                        ContentUnavailableView(
                            search.isEmpty ? "Здесь пока пусто" : "Ничего не найдено",
                            systemImage: search.isEmpty ? RateStatus.icon(for: model.status.rawValue) : "magnifyingglass",
                            description: Text(search.isEmpty ? "В списке «\(model.status.title(for: model.kind))» нет записей" : "Попробуйте изменить запрос")
                        )
                        .padding(.top, 30)
                    }
                    if let message = model.error {
                        ErrorBanner(message: message) { Task { await model.forceReload() } }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(AppBackground())
            .navigationTitle("Мои списки")
            .searchable(text: $search, prompt: "Поиск по списку")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Сортировка", selection: $sortRaw) {
                            ForEach(ListSort.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        Divider()
                        Picker("Порядок", selection: $descending) {
                            Text("По возрастанию").tag(false)
                            Text("По убыванию").tag(true)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Сортировка")
                }
            }
            .navigationDestination(for: MediaRef.self) { TitleView(ref: $0) }
            .task(id: "\(model.kind.rawValue)-\(model.status.rawValue)") { await model.load() }
            .refreshable { await model.forceReload() }
        }
    }

    // MARK: Вкладки статусов (названия как на сайте, у манги свои)

    private var statusTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RateStatus.allCases) { s in
                    let selected = s == model.status
                    Button { model.status = s } label: {
                        HStack(spacing: 6) {
                            Image(systemName: rateGlyph(s.rawValue)).font(.caption.weight(.bold))
                            Text(s.title(for: model.kind)).font(.subheadline.weight(selected ? .bold : .medium))
                            if let n = model.count(s) {
                                Text("\(n)")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(selected ? Color.white.opacity(0.28) : Color.secondary.opacity(0.2), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .glassEffect(selected ? .regular.tint(listStatusColor(s.rawValue).opacity(0.85)) : .regular, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }

    // MARK: Строка списка

    @ViewBuilder
    private func row(_ entry: RateEntry, _ media: Media) -> some View {
        let isAnime = model.kind == .anime
        let total = (isAnime ? media.episodes : media.chapters) ?? 0
        let done = (isAnime ? entry.episodes : entry.chapters) ?? 0
        let unit = isAnime ? "эп." : "гл."
        let color = listStatusColor(model.status.rawValue)
        let canBump = model.status == .watching || model.status == .rewatching

        HStack(spacing: 12) {
            NavigationLink(value: MediaRef(id: media.id, kind: model.kind)) {
                HStack(alignment: .top, spacing: 14) {
                    PosterView(urls: media.thumbCandidates, radius: 14)
                        .frame(width: 70)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(media.title)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let sub = media.subtitleText {
                            Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 2)
                        if total > 0 {
                            ProgressView(value: Double(min(done, total)), total: Double(total)).tint(color)
                        }
                        HStack(spacing: 8) {
                            Text(total > 0 ? "\(done) / \(total) \(unit)" : "\(done) \(unit)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if let sc = entry.score, sc > 0 {
                                Label("\(sc)", systemImage: "star.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.yellow)
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            if canBump {
                Button { Task { await model.bump(entry) } } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Отметить прогресс")
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
