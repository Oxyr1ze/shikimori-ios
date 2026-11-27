import SwiftUI

/// Раздел форума (permalink из API Shikimori).
struct ForumSection: Identifiable, Hashable {
    let id: String
    let title: String
    var icon: String {
        switch id {
        case "news": return "newspaper"
        case "animanga": return "play.rectangle"
        case "site": return "gearshape"
        case "offtopic": return "bubble.left.and.bubble.right"
        case "games": return "gamecontroller"
        case "vn": return "book"
        case "contests": return "trophy"
        case "critiques": return "text.quote"
        case "collections": return "square.stack"
        default: return "doc.text"
        }
    }

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

/// Тайтл, к которому привязана тема (если есть): его постер показывается в ленте. Разбор терпимый: любые поля могут отсутствовать.
struct TopicLinked: Codable, Hashable {
    var id: Int?
    var name: String?
    var russian: String?
    var image: ImageSet?

    enum CodingKeys: String, CodingKey { case id, name, russian, image }

    init(from decoder: Decoder) {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        id = try? c.decodeIfPresent(Int.self, forKey: .id)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        russian = try? c.decodeIfPresent(String.self, forKey: .russian)
        image = try? c.decodeIfPresent(ImageSet.self, forKey: .image)
    }

    var imageURLs: [URL] { CastPerson(id: id ?? 0, name: name, russian: russian, image: image).imageURLs }
}

struct Topic: Codable, Identifiable, Hashable {
    var id: Int
    var topicTitle: String?
    var body: String?
    var htmlBody: String?
    var htmlFooter: String?
    var createdAt: String?
    var commentsCount: Int?
    var linkedType: String?
    var event: String?
    var episode: Int?
    var forum: ForumRef?
    var user: ShikiUser?
    var linked: TopicLinked?

    var title: String { (topicTitle?.isEmpty == false ? topicTitle : nil) ?? "Без названия" }

    var dateText: String { relativeDateText(createdAt) }

    /// Адрес темы на сайте (для «Поделиться» и «Открыть на сайте»).
    var siteURL: URL? { URL(string: "https://shikimori.io/topics/\(id)") }

    /// Ссылка на постер из привязанного тайтла.
    var posterURLs: [URL] { linked?.imageURLs ?? [] }

    /// Тема как «комментарий»: так её разбирает общий разборщик разметки.
    func makeBlocks() -> [CBlock] {
        var all = Comment(id: id, body: body, htmlBody: htmlBody, createdAt: createdAt, isOfftopic: nil, user: user).makeBlocks()
        // Картинки и видео темы лежат в отдельном поле (html_footer)
        if let footer = htmlFooter, !footer.isEmpty { all += CommentRenderer.render(html: footer) }
        return all
    }

    /// Плашки над текстом: раздел, о чём новость, событие. Теги и источник сайт в API не отдаёт.
    var chips: [String] {
        var list: [String] = []
        let kinds = ["Anime": "Аниме", "Manga": "Манга", "Ranobe": "Ранобэ", "Character": "Персонаж",
                     "Person": "Человек", "Club": "Клуб", "Critique": "Рецензия"]
        if let t = linkedType, let k = kinds[t] { list.append(k) }
        let events = ["anons": "Анонс", "ongoing": "Онгоинг", "released": "Релиз", "episode": "Эпизод"]
        if let e = event, let name = events[e] {
            list.append(e == "episode" && (episode ?? 0) > 0 ? "Эпизод \(episode ?? 0)" : name)
        }
        return list
    }
}

private let topicDateISOFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let topicDateISO = ISO8601DateFormatter()
private let topicDateRelative: RelativeDateTimeFormatter = {
    let r = RelativeDateTimeFormatter()
    r.locale = Locale(identifier: "ru_RU")
    r.unitsStyle = .short
    return r
}()

func relativeDateText(_ s: String?) -> String {
    guard let s, let d = topicDateISOFrac.date(from: s) ?? topicDateISO.date(from: s) else { return "" }
    return topicDateRelative.localizedString(for: d, relativeTo: Date())
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
                sectionTabs

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
                if model.loading && model.topics.isEmpty {
                    ForEach(0..<6, id: \.self) { _ in skeleton }
                } else if model.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }
                if !model.loading && model.topics.isEmpty && model.error == nil {
                    ContentUnavailableView("Пока ничего нет", systemImage: "text.bubble")
                }
                if let message = model.error {
                    ErrorBanner(message: message) { Task { await model.reload() } }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(AppBackground())
        .navigationTitle(model.section.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.section) { await model.reload() }
        .refreshable { await model.reload() }
    }

    /// Разделы: лёгкие плашки со значками (без стекла на каждой, чтобы не тормозила прокрутка).
    private var sectionTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ForumSection.all) { s in
                        let on = model.section == s
                        Button {
                            withAnimation(.snappy) { model.section = s }
                        } label: {
                            Label(s.title, systemImage: s.icon)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .background(on ? Theme.accent : Theme.card, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(s.id)
                    }
                }
            }
            .onChange(of: model.section) { _, new in
                withAnimation { proxy.scrollTo(new.id, anchor: .center) }
            }
        }
    }

    private var skeleton: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Theme.card)
            .frame(height: 96)
            .redacted(reason: .placeholder)
    }

    private func row(_ t: Topic) -> some View {
        HStack(alignment: .top, spacing: 12) {
            let posters = t.posterURLs
            if !posters.isEmpty {
                PosterView(urls: posters, radius: 10)
                    .frame(width: 58)
            }
            VStack(alignment: .leading, spacing: 8) {
                let chips = t.chips
                if !chips.isEmpty {
                    Text(chips.joined(separator: " · "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text(t.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    if let n = t.user?.nickname {
                        Text(n).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    Text(t.dateText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    Label("\(t.commentsCount ?? 0)", systemImage: "bubble.left")
                        .font(.caption).foregroundStyle(.secondary)
                }
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

    @ViewBuilder
    private func authorLink<L: View>(_ user: ShikiUser?, @ViewBuilder label: () -> L) -> some View {
        if let user {
            NavigationLink { UserView(user: user) } label: { label() }.buttonStyle(.plain)
        } else {
            label()
        }
    }

    var body: some View {
        let t = full ?? topic
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    let posters = t.posterURLs
                    if !posters.isEmpty {
                        PosterView(urls: posters, radius: 14).frame(width: 86)
                    }
                    Text(t.title).font(.title2.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }

                authorLink(t.user) {
                HStack(spacing: 10) {
                    Color(UIColor.tertiarySystemFill)
                        .frame(width: 36, height: 36)
                        .overlay { if let url = t.user?.avatarURL { RemoteImage(urls: [url]) } }
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.user?.nickname ?? "—").font(.subheadline.weight(.bold))
                        Text([t.dateText, t.forum?.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                }

                let chips = t.chips
                if !chips.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(chips, id: \.self) { c in
                            Text(c)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .foregroundStyle(Theme.accent)
                                .background(Theme.accent.opacity(0.14), in: Capsule())
                        }
                    }
                }

                CommentBlocksView(blocks: blocks)
                    .environment(\.commentFont, .body)
                    .environment(\.commentLineSpacing, 5)

                NavigationLink {
                    CommentsView(topicID: t.id, title: t.title)
                } label: {
                    HStack {
                        Label("Комментарии (\(t.commentsCount ?? 0))", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
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
        .toolbar {
            if let url = t.siteURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
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
