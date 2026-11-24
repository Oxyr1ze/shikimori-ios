import SwiftUI

@MainActor
final class ListsModel: ObservableObject {
    @Published var kind: MediaKind = .anime
    @Published var status: RateStatus = .watching
    @Published var entries: [RateEntry] = []
    @Published var loading = false
    @Published var error: String?

    func load() async {
        loading = true
        error = nil
        do {
            if kind == .anime {
                entries = try await AuthManager.shared.animeRates(status: status.rawValue)
            } else {
                entries = try await AuthManager.shared.mangaRates(kind: kind, status: status.rawValue)
            }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func bump(_ entry: RateEntry) async {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        if kind == .anime {
            var next = (entry.episodes ?? 0) + 1
            if let total = entry.anime?.episodes, total > 0 { next = min(next, total) }
            entries[idx].episodes = next
            do {
                try await AuthManager.shared.updateRate(id: entry.id, episodes: next)
            } catch {
                entries[idx].episodes = entry.episodes
                self.error = error.localizedDescription
            }
        } else {
            var next = (entry.chapters ?? 0) + 1
            if let total = entry.manga?.chapters, total > 0 { next = min(next, total) }
            entries[idx].chapters = next
            do {
                try await AuthManager.shared.updateRate(id: entry.id, chapters: next)
            } catch {
                entries[idx].chapters = entry.chapters
                self.error = error.localizedDescription
            }
        }
    }
}

struct ListsView: View {
    @StateObject private var model = ListsModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Раздел", selection: $model.kind) {
                        ForEach(MediaKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RateStatus.allCases) { s in
                                Button(s.title) { model.status = s }
                                    .buttonStyle(.glass)
                                    .tint(s == model.status ? Theme.accent : .gray)
                                    .fontWeight(s == model.status ? .bold : .regular)
                            }
                        }
                    }

                    ForEach(model.entries) { entry in
                        if let media = entry.media {
                            row(entry, media)
                        }
                    }

                    if model.loading { ProgressView().padding() }
                    if !model.loading && model.entries.isEmpty && model.error == nil {
                        Text("Здесь пока пусто")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                    if let message = model.error {
                        ErrorBanner(message: message) { Task { await model.load() } }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(AppBackground())
            .navigationTitle("Мои списки")
            .navigationDestination(for: MediaRef.self) { TitleView(ref: $0) }
            .task(id: "\(model.kind.rawValue)-\(model.status.rawValue)") {
                model.entries = []
                await model.load()
            }
            .refreshable { await model.load() }
        }
    }

    @ViewBuilder
    private func row(_ entry: RateEntry, _ anime: Media) -> some View {
        let isAnime = model.kind == .anime
        HStack(spacing: 12) {
            NavigationLink(value: MediaRef(id: anime.id, kind: model.kind)) {
                HStack(spacing: 14) {
                    PosterView(urls: anime.thumbCandidates, radius: 14)
                        .frame(width: 58)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(anime.title)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        let total = (isAnime ? anime.episodes : anime.chapters) ?? 0
                        let watched = (isAnime ? entry.episodes : entry.chapters) ?? 0
                        if total > 0 {
                            ProgressView(value: Double(min(watched, total)), total: Double(total))
                        }
                        Text(total > 0 ? "\(watched) / \(total)" : "\(watched) \(isAnime ? "эп." : "гл.")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Button { Task { await model.bump(entry) } } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Отметить прогресс")
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
