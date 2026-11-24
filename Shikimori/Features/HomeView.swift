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

    func bump(_ entry: RateEntry) async {
        guard let idx = watching.firstIndex(where: { $0.id == entry.id }) else { return }
        let next = (entry.episodes ?? 0) + 1
        watching[idx].episodes = next
        do {
            try await AuthManager.shared.updateRate(id: entry.id, episodes: next)
        } catch {
            watching[idx].episodes = entry.episodes
            self.error = error.localizedDescription
        }
    }
}

struct HomeView: View {
    @StateObject private var model = HomeModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let entry = model.watching.first, let anime = entry.anime {
                        HeroCard(entry: entry, anime: anime) {
                            Task { await model.bump(entry) }
                        }
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

struct HeroCard: View {
    let entry: RateEntry
    let anime: Media
    let onBump: () -> Void

    private var watched: Int { entry.episodes ?? 0 }
    private var total: Int { anime.episodes ?? 0 }

    var body: some View {
        VStack(spacing: 12) {
            NavigationLink(value: MediaRef(id: anime.id, kind: .anime)) {
                ZStack(alignment: .bottom) {
                    Color.clear
                        .frame(height: 300)
                        .overlay {
                            ZStack {
                                LinearGradient(colors: Theme.posterGradients[abs(anime.id) % Theme.posterGradients.count],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                                if let url = anime.posterURL {
                                    AsyncImage(url: url) { phase in
                                        if let image = phase.image {
                                            image.resizable().scaledToFill()
                                        } else {
                                            Color.clear
                                        }
                                    }
                                }
                            }
                        }
                        .clipped()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("ПРОДОЛЖИТЬ ПРОСМОТР")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(anime.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 10) {
                            if total > 0 {
                                ProgressView(value: Double(min(watched, total)), total: Double(total))
                                    .tint(.white)
                            } else {
                                Spacer()
                            }
                            Text(total > 0 ? "\(watched) / \(total)" : "\(watched) эп.")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onBump) {
                Text("Отметить \(watched + 1)-й эпизод").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
    }
}
