import SwiftUI

enum CatalogOrder: String, CaseIterable, Identifiable {
    case popularity, ranked, aired_on, name
    var id: String { rawValue }
    var title: String {
        switch self {
        case .popularity: return "Популярность"
        case .ranked: return "Рейтинг"
        case .aired_on: return "Новизна"
        case .name: return "Название"
        }
    }
}

enum CatalogStatus: String, CaseIterable, Identifiable {
    case all = "", ongoing, released, anons
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Любой статус"
        case .ongoing: return "Выходит"
        case .released: return "Вышло"
        case .anons: return "Анонс"
        }
    }
}

@MainActor
final class CatalogModel: ObservableObject {
    @Published var kind: MediaKind = .anime
    @Published var order: CatalogOrder = .popularity
    @Published var status: CatalogStatus = .all
    @Published var filters = CatalogFilters()
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
                kind: kind, order: order.rawValue, status: status.rawValue,
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

struct CatalogView: View {
    @StateObject private var model = CatalogModel()
    @State private var showFilters = false
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Тип", selection: $model.kind) {
                        ForEach(MediaKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 10) {
                        Menu {
                            Picker("Сортировка", selection: $model.order) {
                                ForEach(CatalogOrder.allCases) { Text($0.title).tag($0) }
                            }
                        } label: {
                            Label(model.order.title, systemImage: "arrow.up.arrow.down")
                        }
                        Menu {
                            Picker("Статус", selection: $model.status) {
                                ForEach(CatalogStatus.allCases) { Text($0.title).tag($0) }
                            }
                        } label: {
                            Label(model.status.title, systemImage: "line.3.horizontal.decrease")
                        }
                        Button { showFilters = true } label: {
                            Label(model.filters.count > 0 ? "Фильтры (\(model.filters.count))" : "Фильтры",
                                  systemImage: "slider.horizontal.3")
                        }
                        Spacer()
                    }
                    .buttonStyle(.glass)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(model.items) { item in
                            NavigationLink(value: MediaRef(id: item.id, kind: model.kind)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    PosterView(urls: item.thumbCandidates, radius: 22)
                                        .overlay(alignment: .topTrailing) {
                                            if let s = item.scoreText { ScoreBadge(text: s).padding(8) }
                                        }
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
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
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(AppBackground())
            .navigationTitle("Каталог")
            .navigationDestination(for: MediaRef.self) { TitleView(ref: $0) }
            .task { if model.items.isEmpty { await model.reload() } }
            .sheet(isPresented: $showFilters) {
                CatalogFiltersView(kind: model.kind, filters: $model.filters)
                    .presentationDetents([.large])
            }
            .onChange(of: model.filters) { _, _ in Task { await model.reload() } }
            .onChange(of: model.kind) { _, _ in
                model.filters = CatalogFilters()
                Task { await model.reload() }
            }
            .onChange(of: model.order) { _, _ in Task { await model.reload() } }
            .onChange(of: model.status) { _, _ in Task { await model.reload() } }
        }
    }
}
