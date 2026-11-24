import SwiftUI

@MainActor
final class HomeModel: ObservableObject {
    @Published var watching: [RateEntry] = []
    @Published var airing: [Media] = []
    @Published var popular: [Media] = []
    @Published var error: String?
    @Published var loading = false

    func load() async {
        let api = AuthManager.shared
        loading = true
        error = nil
        var failures = 0
        do { airing = try await api.media(kind: .anime, order: "popularity", status: "ongoing", limit: 12) }
        catch is CancellationError { loading = false; return }
        catch { failures += 1; self.error = error.localizedDescription }
        do { popular = try await api.media(kind: .anime, order: "popularity", limit: 12) }
        catch is CancellationError { loading = false; return }
        catch { failures += 1; self.error = error.localizedDescription }
        if let rates = try? await api.animeRates(status: "watching") { watching = rates }
        if failures == 0 { error = nil }
        loading = false
    }
}

struct HomeView: View {
    @StateObject private var model = HomeModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if !model.watching.isEmpty {
                        MediaRow(title: "Смотрю", items: model.watching.compactMap(\.anime))
                    }
                    MediaRow(title: "Сейчас выходит", items: model.airing)
                    MediaRow(title: "Популярное", items: model.popular)
                    if let message = model.error {
                        ErrorBanner(message: message) { Task { await model.load() } }
                    }
                    if model.loading && model.airing.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 12)
                .padding(.bottom, 100)
            }
            .background(AppBackground())
            .navigationTitle("Shikimori")
            .navigationDestination(for: MediaRef.self) { TitleView(ref: $0) }
            .task { await model.load() }
            .refreshable { await model.load() }
        }
    }
}
