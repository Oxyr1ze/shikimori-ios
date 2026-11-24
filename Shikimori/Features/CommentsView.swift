import SwiftUI

@MainActor
final class CommentsModel: ObservableObject {
    let topicID: Int
    @Published var comments: [Comment] = []
    @Published var loading = false
    @Published var canLoadMore = true
    @Published var error: String?
    @Published var sending = false
    @Published var blocks: [Int: [CBlock]] = [:]
    private var page = 1
    private let pageSize = 30

    init(topicID: Int) { self.topicID = topicID }

    func reload() async {
        page = 1
        canLoadMore = true
        comments = []
        await loadMore()
    }

    func loadMore() async {
        guard !loading, canLoadMore else { return }
        loading = true
        error = nil
        do {
            // Shikimori отдаёт на один комментарий больше лимита, если есть следующая страница.
            let items = try await AuthManager.shared.comments(topicID: topicID, page: page, limit: pageSize)
            let known = Set(comments.map(\.id))
            let fresh = Array(items.filter { !known.contains($0.id) }.prefix(pageSize))
            for c in fresh { blocks[c.id] = c.makeBlocks() }
            comments += fresh
            canLoadMore = items.count > pageSize
            page += 1
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func send(_ text: String) async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        sending = true
        error = nil
        defer { sending = false }
        do {
            let c = try await AuthManager.shared.postComment(topicID: topicID, body: body)
            blocks[c.id] = c.makeBlocks()
            comments.insert(c, at: 0)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

struct CommentsView: View {
    let title: String
    @StateObject private var model: CommentsModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    init(topicID: Int, title: String) {
        self.title = title
        _model = StateObject(wrappedValue: CommentsModel(topicID: topicID))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                composer
                ForEach(model.comments) { c in
                    commentRow(c)
                }
                if model.loading { ProgressView().frame(maxWidth: .infinity).padding() }
                if model.canLoadMore && !model.loading && !model.comments.isEmpty {
                    Button("Загрузить ещё") { Task { await model.loadMore() } }
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                }
                if !model.loading && model.comments.isEmpty && model.error == nil {
                    Text("Комментариев пока нет").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 30)
                }
                if let message = model.error {
                    ErrorBanner(message: message) { Task { await model.reload() } }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(AppBackground())
        .navigationTitle("Обсуждение")
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.comments.isEmpty { await model.reload() } }
        .refreshable { await model.reload() }
    }

    private var composer: some View {
        VStack(alignment: .trailing, spacing: 10) {
            TextField("Написать комментарий…", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($focused)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button {
                Task {
                    if await model.send(draft) { draft = ""; focused = false }
                }
            } label: {
                Text(model.sending ? "Отправка…" : "Отправить").fontWeight(.semibold)
            }
            .buttonStyle(.glassProminent)
            .disabled(model.sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func commentRow(_ c: Comment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Color(UIColor.tertiarySystemFill)
                .frame(width: 40, height: 40)
                .overlay {
                    if let url = c.user?.avatarURL { RemoteImage(urls: [url]) }
                }
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(c.user?.nickname ?? "—").font(.subheadline.weight(.bold))
                    Text(c.dateText).font(.caption).foregroundStyle(.secondary)
                    if c.isOfftopic == true {
                        Text("оффтоп").font(.caption).foregroundStyle(.secondary)
                    }
                }
                CommentBlocksView(blocks: model.blocks[c.id] ?? [])
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
