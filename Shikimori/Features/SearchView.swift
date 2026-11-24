import SwiftUI

struct SearchView: View {
    @State private var text = ""
    @State private var kind: MediaKind = .anime
    @State private var results: [Media] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { item in
                    NavigationLink(value: MediaRef(id: item.id, kind: kind)) {
                        HStack(spacing: 14) {
                            PosterView(urls: item.thumbCandidates, radius: 10)
                                .frame(width: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text(item.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                if loading { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red).listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Поиск")
            .navigationDestination(for: MediaRef.self) { TitleView(ref: $0) }
            .searchable(text: $text, prompt: "Аниме, манга, ранобэ")
            .searchScopes($kind) {
                ForEach(MediaKind.allCases) { Text($0.title).tag($0) }
            }
            .task(id: "\(text)|\(kind.rawValue)") { await search() }
        }
    }

    private func search() async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { results = []; error = nil; return }
        try? await Task.sleep(nanoseconds: 450_000_000)
        if Task.isCancelled { return }
        loading = true
        error = nil
        do {
            results = try await AuthManager.shared.media(kind: kind, order: "popularity", search: query, limit: 20)
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
