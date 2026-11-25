import SwiftUI

/// Раздел форума (permalink из API Shikimori).
struct ForumSection: Identifiable, Hashable {
    let id: String
    let title: String

    static let all: [ForumSection] = [
        ForumSection(id: "news", title: "Новости"),
        ForumSection(id: "animanga", title: "Аниме и манга"),
        ForumSection(id: "site", title: "Сайт"),
        ForumSection(id: "offtopic", title: "Оффтоп"),
        ForumSection(id: "games", title: "Игры"),
        ForumSection(id: "vn", title: "Визуальные новеллы"),
        ForumSection(id: "contests", title: "Турниры"),
        ForumSection(id: "critiques", title: "Рецензии"),
        ForumSection(id: "collections", title: "Коллекции"),
        ForumSection(id: "articles", title: "Статьи")
    ]
}

struct ForumRef: Codable, Hashable {
    var id: Int?
    var name: String?
}

struct Topic: Codable, Identifiable, Hashable {
    var id: Int
    var topicTitle: String?
    var body: String?
    var htmlBody: String?
    var createdAt: String?
    var commentsCount: Int?
    var forum: ForumRef?
    var user: ShikiUser?

    var title: String { (topicTitle?.isEmpty == false ? topicTitle : nil) ?? "Без названия" }

    var dateText: String { relativeDateText(createdAt) }

    /// Тема как «комментарий»: так её разбирает общий разборщик разметки.
    func makeBlocks() -> [CBlock] {
        Comment(id: id, body: body, htmlBody: htmlBody, createdAt: createdAt, isOfftopic: nil, user: user).makeBlocks()
    }
}

func relativeDateText(_ s: String?) -> String {
    guard let s else { return "" }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let g = ISO8601DateFormatter()
    guard let d = f.date(from: s) ?? g.date(from: s) else { return "" }
    let r = RelativeDateTimeFormatter()
    r.locale = Locale(identifier: "ru_RU")
    r.unitsStyle = .short
    return r.localizedString(for: d, relativeTo: Date())
}

extension AuthManager {
    /// Темы форума раздела. Сайт отдаёт на одну тему больше лимита, если есть следующая страница.
    func topics(forum: String, page: Int, limit: Int) async throws -> [Topic] {
        let q = [
            URLQueryItem(name: "forum", value: forum),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return try await get("/api/topics", query: q)
    }

    func topic(id: Int) async throws -> Topic {
        try await get("/api/topics/\(id)")
    }
}

@MainActor
final class ForumModel: ObservableObject {
    @Published var section = ForumSection.all[0]
    @Published var topics: [Topic] = []
    @Published var loading = false
    @Published var canLoadMore = true
    @Published var error: String?
    private var page = 1
    private let pageSize = 20
    private var generation = 0

    func reload() async {
        generation += 1
        page = 1
        canLoadMore = true
        let key = "topics-\(section.id)"
        topics = DiskCache.load([Topic].self, key: key) ?? []
        await loadMore(replacing: true)
    }

    func loadMore(replacing: Bool = false) async {
        guard !loading, canLoadMore else { return }
        loading = true
        error = nil
        let gen = generation
        let current = section
        do {
            let items = try await AuthManager.shared.topics(forum: current.id, page: page, limit: pageSize)
            guard gen == generation else { loading = false; return }
            let fresh = Array(items.prefix(pageSize))
            if replacing {
                topics = fresh
                DiskCache.save(fresh, key: "topics-\(current.id)")
            } else {
                let known = Set(topics.map(\.id))
                topics += fresh.filter { !known.contains($0.id) }
            }
            canLoadMore = items.count > pageSize
            page += 1
        } catch is CancellationError {
        } catch {
            if gen == generation { self.error = topics.isEmpty ? error.localizedDescription : offlineMessage }
        }
        loading = false
    }
}

struct ForumView: View {
    @StateObject private var model = ForumModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ForumSection.all) { s in
                            Button { model.section = s } label: {
                                Text(s.title)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(model.section == s ? .regular.tint(Theme.accent.opacity(0.6)) : .regular, in: .capsule)
                        }
                    }
                }

                ForEach(model.topics) { topic in
                    NavigationLink {
                        TopicView(topic: topic)
                    } label: {
                        row(topic)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if topic.id == model.topics.last?.id { Task { await model.loadMore() } }
                    }
                }
                if model.loading { ProgressView().frame(maxWidth: .infinity).padding() }
                if let message = model.error {
                    ErrorBanner(message: message) { Task { await model.reload() } }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(AppBackground())
        .navigationTitle("Форум")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.section) { await model.reload() }
        .refreshable { await model.reload() }
    }

    private func row(_ t: Topic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t.title).font(.headline).multilineTextAlignment(.leading)
            HStack(spacing: 10) {
                if let n = t.user?.nickname { Text(n).font(.caption.weight(.semibold)) }
                Text(t.dateText).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Label("\(t.commentsCount ?? 0)", systemImage: "bubble.left")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct TopicView: View {
    let topic: Topic
    @State private var full: Topic?
    @State private var blocks: [CBlock] = []
    @State private var error: String?

    var body: some View {
        let t = full ?? topic
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(t.title).font(.title2.weight(.heavy))
                HStack(spacing: 10) {
                    if let n = t.user?.nickname { Text(n).font(.subheadline.weight(.semibold)) }
                    Text(t.dateText).font(.subheadline).foregroundStyle(.secondary)
                    if let f = t.forum?.name { Text(f).font(.subheadline).foregroundStyle(.secondary) }
                }
                CommentBlocksView(blocks: blocks)
                NavigationLink {
                    CommentsView(topicID: t.id, title: t.title)
                } label: {
                    HStack {
                        Label("Комментарии (\(t.commentsCount ?? 0))", systemImage: "bubble.left.and.bubble.right")
                            .font(.body.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            blocks = topic.makeBlocks()
            do {
                let f = try await AuthManager.shared.topic(id: topic.id)
                full = f
                let b = f.makeBlocks()
                if !b.isEmpty { blocks = b }
            } catch is CancellationError {
            } catch {
                if blocks.isEmpty { self.error = error.localizedDescription }
            }
        }
    }
}
