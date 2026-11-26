import SwiftUI

@MainActor
final class CommentsModel: ObservableObject {
    let topicID: Int
    let type: String
    @Published var comments: [Comment] = []
    @Published var loading = false
    @Published var canLoadMore = true
    @Published var error: String?
    @Published var sending = false
    @Published var blocks: [Int: [CBlock]] = [:]
    private var page = 1
    private let pageSize = 30

    init(topicID: Int, type: String = "Topic") { self.topicID = topicID; self.type = type }

    /// Обновление: старые комментарии остаются на экране, пока не придут новые
    /// (иначе при «потянуть для обновления» список очищался и показывалось «пока нет»).
    func reload() async {
        error = nil
        do {
            let items = try await AuthManager.shared.comments(topicID: topicID, type: type, page: 1, limit: pageSize)
            let fresh = Array(items.prefix(pageSize))
            var map: [Int: [CBlock]] = [:]
            for c in fresh { map[c.id] = c.makeBlocks() }
            blocks = map
            comments = fresh
            canLoadMore = items.count > pageSize
            page = 2
        } catch is CancellationError {
        } catch {
            self.error = comments.isEmpty ? error.localizedDescription : offlineMessage
        }
    }

    func loadMore() async {
        guard !loading, canLoadMore else { return }
        loading = true
        error = nil
        do {
            // Shikimori отдаёт на один комментарий больше лимита, если есть следующая страница.
            let items = try await AuthManager.shared.comments(topicID: topicID, type: type, page: page, limit: pageSize)
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
    let canPost: Bool
    @StateObject private var model: CommentsModel
    @State private var draft = ""
    @State private var replyTo: Comment?
    @State private var showSmileys = false
    @FocusState private var focused: Bool

    init(topicID: Int, title: String, type: String = "Topic", canPost: Bool = true) {
        self.title = title
        self.canPost = canPost
        _model = StateObject(wrappedValue: CommentsModel(topicID: topicID, type: type))
    }

    private var canSend: Bool {
        !model.sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if canPost { composer }
                ForEach(model.comments) { c in
                    CommentRowView(comment: c, blocks: model.blocks[c.id] ?? [],
                                   onReply: canPost ? { startReply(to: $0) } : nil)
                }
                if model.loading { ProgressView().frame(maxWidth: .infinity).padding() }
                if model.canLoadMore && !model.loading && !model.comments.isEmpty {
                    Button("Загрузить ещё") { Task { await model.loadMore() } }
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                }
                if !model.loading && model.comments.isEmpty && model.error == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.largeTitle).foregroundStyle(.tertiary)
                        Text("Комментариев пока нет").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 40)
                }
                if let message = model.error {
                    ErrorBanner(message: message) { Task { await model.reload() } }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle("Комментарии")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSmileys) {
            SmileyPicker { code in
                draft += (draft.isEmpty || draft.hasSuffix(" ") || draft.hasSuffix("\n") ? "" : " ") + code + " "
            }
            .presentationDetents([.medium, .large])
        }
        .simultaneousGesture(TapGesture().onEnded { focused = false })
        .task {
            if model.comments.isEmpty {
                model.loading = true
                await model.reload()
                model.loading = false
            }
        }
        .refreshable { await model.reload() }
    }

    private func startReply(to c: Comment) {
        replyTo = c
        let nick = c.user?.nickname ?? ""
        let tag = "[comment=\(c.id)]\(nick)[/comment], "
        if !draft.hasPrefix(tag) { draft = tag + draft }
        focused = true
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let r = replyTo {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left.fill").font(.caption).foregroundStyle(Theme.accent)
                    Text("Ответ для \(r.user?.nickname ?? "—")")
                        .font(.footnote.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Button { replyTo = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button { focused = false; showSmileys = true } label: {
                    Image(systemName: "face.smiling").font(.title3).frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                TextField("Комментарий", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Button {
                    Task {
                        if await model.send(draft) { draft = ""; replyTo = nil; focused = false }
                    }
                } label: {
                    Image(systemName: model.sending ? "ellipsis" : "arrow.up")
                        .font(.title3.weight(.bold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(!canSend)
            }
        }
    }
}

/// Выбор смайликов (картинки с сайта).
struct SmileyPicker: View {
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SmileyStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                    ForEach(SmileyList.all, id: \.self) { code in
                        if let url = SmileyStore.url(for: code) {
                            Button { onPick(code) } label: {
                                ZStack {
                                    Theme.card
                                    if let a = store.anims[url] {
                                        Image(uiImage: a.still)
                                    } else {
                                        ProgressView().controlSize(.small)
                                    }
                                }
                                .frame(height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .task { await store.load(url) }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Смайлики")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

extension Array where Element == CBlock {
    /// Длинный ли комментарий (его стоит свернуть).
    var isLongComment: Bool {
        var chars = 0
        var media = 0
        for b in self {
            switch b.kind {
            case .text(let runs):
                for r in runs { if case .text(let a) = r { chars += a.characters.count } }
            case .quote(_, let inner):
                chars += inner.count * 200
            default:
                media += 1
            }
        }
        return chars > 500 || media > 1 || count > 6
    }
}

/// Один комментарий: шапка (аватар, ник, время, меню) и текст на всю ширину карточки.
struct CommentRowView: View {
    let comment: Comment
    let blocks: [CBlock]
    var onReply: ((Comment) -> Void)? = nil
    @State private var open = false

    @ViewBuilder
    private func userLink<L: View>(_ user: ShikiUser?, @ViewBuilder label: () -> L) -> some View {
        if let user {
            NavigationLink { UserView(user: user) } label: { label() }.buttonStyle(.plain)
        } else {
            label()
        }
    }

    private var link: URL? { URL(string: ShikiConfig.host + "/comments/\(comment.id)") }

    var body: some View {
        let c = comment
        let long = blocks.isLongComment
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                userLink(c.user) {
                    HStack(spacing: 10) {
                        Color(UIColor.tertiarySystemFill)
                            .frame(width: 36, height: 36)
                            .overlay {
                                if let url = c.user?.avatarURL { RemoteImage(urls: [url]) }
                            }
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.user?.nickname ?? "—").font(.subheadline.weight(.bold)).lineLimit(1)
                            Text(c.dateText).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 8)
                if c.isOfftopic == true {
                    Text("оффтоп")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(UIColor.tertiarySystemFill), in: Capsule())
                }
                Menu {
                    if let onReply {
                        Button { onReply(c) } label: { Label("Ответить", systemImage: "arrowshape.turn.up.left") }
                    }
                    Button { UIPasteboard.general.string = c.plainBody } label: {
                        Label("Копировать текст", systemImage: "doc.on.doc")
                    }
                    if let link {
                        ShareLink(item: link) { Label("Поделиться ссылкой", systemImage: "square.and.arrow.up") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }
            let content = CommentBlocksView(blocks: blocks)
            if long && !open {
                content
                    .frame(maxWidth: .infinity, maxHeight: 230, alignment: .topLeading)
                    .clipped()
                    .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
            } else {
                content
            }
            if long {
                Button(open ? "Свернуть" : "Читать далее") {
                    withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
