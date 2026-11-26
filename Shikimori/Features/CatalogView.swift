import SwiftUI

@MainActor
final class CatalogModel: ObservableObject {
    @Published var kind: MediaKind = .anime
    @Published var filters = CatalogFilters()
    @Published var query = ""
    @Published var items: [Media] = []
    @Published var loading = false
    @Published var error: String?
    private var page = 1
    private var hasMore = true
    private var generation = 0

    func reload() async {
        generation += 1
        page = 1
        hasMore = true
        items = []
        await loadMore()
    }

    func loadMore(after current: Media? = nil) async {
        if let current, let last = items.suffix(6).first, current.id != last.id,
           !items.suffix(6).contains(where: { $0.id == current.id }) { return }
        guard hasMore, !loading else { return }
        loading = true
        error = nil
        let gen = generation
        do {
            let result = try await AuthManager.shared.media(
                kind: kind, order: filters.order, search: query.trimmingCharacters(in: .whitespaces),
                filters: filters.queryItems(kind: kind), page: page, limit: 24)
            guard gen == generation else { loading = false; return }
            let known = Set(items.map(\.id))
            items += result.filter { !known.contains($0.id) }
            hasMore = result.count >= 24
            page += 1
        } catch is CancellationError {
        } catch {
            if gen == generation { self.error = error.localizedDescription }
        }
        loading = false
    }
}

private struct SearchKey: Equatable {
    let filters: CatalogFilters
    let query: String
}

struct CatalogView: View {
    @StateObject private var model = CatalogModel()
    @StateObject private var data = FilterData()
    @State private var showFilters = false
    @State private var randomRef: MediaRef?
    @State private var randomBusy = false
    @State private var applied = CatalogFilters()
    @State private var appliedQuery = ""
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private func openRandom() async {
        guard !randomBusy else { return }
        randomBusy = true
        defer { randomBusy = false }
        let kind = model.kind
        if let list = try? await AuthManager.shared.media(
            kind: kind, order: "random", search: model.query.trimmingCharacters(in: .whitespaces), filters: model.filters.queryItems(kind: kind), page: 1, limit: 1),
           let first = list.first {
            randomRef = MediaRef(id: first.id, kind: kind)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Тип", selection: $model.kind) {
                        ForEach(MediaKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    FilterChipsBar(
                        chips: model.filters.chips(kind: model.kind, genres: data.genres,
                                                   studios: data.studios, publishers: data.publishers),
                        filters: $model.filters, horizontalInset: 20)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(model.items) { item in
                            NavigationLink(value: MediaRef(id: item.id, kind: model.kind)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    PosterView(urls: item.thumbCandidates, radius: 22, rateKey: RateStore.key(model.kind, item.id))
                                        .overlay(alignment: .topTrailing) {
                                            if let s = item.scoreText { ScoreBadge(text: s).padding(8) }
                                        }
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    if let sub = item.subtitleText {
                                        Text(sub)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .padding(.top, -4)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .onAppear { Task { await model.loadMore(after: item) } }
                        }
                    }

                    if model.loading { ProgressView().padding() }
                    if let message = model.error {
                        ErrorBanner(message: message) { Task { await model.loadMore() } }
                    }
                    if !model.loading && model.error == nil && model.items.isEmpty && !applied.isEmpty || (!model.loading && model.items.isEmpty && !model.query.isEmpty && model.error == nil) {
                        ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass",
                                               description: Text("Измените запрос или уберите часть фильтров"))
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(AppBackground())
            .navigationTitle("Каталог")
            .searchable(text: $model.query, prompt: "Поиск в каталоге")
            .navigationDestination(for: MediaRef.self) { TitleView(ref: $0) }
            .task { if model.items.isEmpty { await model.reload() } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if randomBusy {
                        ProgressView()
                    } else {
                        Button { Task { await openRandom() } } label: { Image(systemName: "shuffle") }
                            .accessibilityLabel("Случайное")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        Image(systemName: model.filters.count > 0
                              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                    }
                    .accessibilityLabel("Фильтры и сортировка")
                }
            }
            .navigationDestination(item: $randomRef) { TitleView(ref: $0) }
            .sheet(isPresented: $showFilters) {
                CatalogFiltersView(kind: model.kind, filters: $model.filters, data: data)
                    .presentationDetents([.large])
            }
            .task(id: model.kind) { await data.load(kind: model.kind) }
            .task(id: SearchKey(filters: model.filters, query: model.query)) {
                // Небольшая пауза: пока человек отмечает пункты в меню или печатает, список не перестраивается
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                if applied != model.filters || appliedQuery != model.query {
                    applied = model.filters
                    appliedQuery = model.query
                    await model.reload()
                }
            }
            .onChange(of: model.kind) { _, _ in
                model.filters = CatalogFilters()
                applied = CatalogFilters()
                Task { await model.reload() }
            }
        }
    }
}
