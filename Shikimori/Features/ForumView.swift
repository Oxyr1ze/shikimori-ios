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

/// Тайтл рецензии (поле target у привязанной рецензии).
struct TopicTarget: Codable, Hashable {
    var id: Int?
    var name: String?
    var russian: String?
    var image: ImageSet?
    var url: String?

    enum CodingKeys: String, CodingKey { case id, name, russian, image, url }

    init(from decoder: Decoder) {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        id = try? c.decodeIfPresent(Int.self, forKey: .id)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        russian = try? c.decodeIfPresent(String.self, forKey: .russian)
        image = try? c.decodeIfPresent(ImageSet.self, forKey: .image)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
    }

    /// Аниме, манга или ранобэ: определяется по адресу страницы.
    var kind: MediaKind? {
        guard let url else { return nil }
        if url.contains("/animes/") { return .anime }
        if url.contains("/ranobe/") { return .ranobe }
        if url.contains("/mangas/") { return .manga }
        return nil
    }
    var title: String { (russian?.isEmpty == false ? russian : nil) ?? name ?? "" }
    var subtitle: String? {
        guard let name, !name.isEmpty, name != title else { return nil }
        return name
    }
    var imageURLs: [URL] { CastPerson(id: id ?? 0, name: name, russian: russian, image: image).imageURLs }
}

/// Объект, к которому привязана тема (тайтл, рецензия…). Разбор терпимый: любые поля могут отсутствовать.
struct TopicLinked: Codable, Hashable {
    var id: Int?
    var name: String?
    var russian: String?
    var image: ImageSet?
    // Рецензия
    var target: TopicTarget?
    var overall: Int?
    var storyline: Int?
    var music: Int?
    var characters: Int?
    var animation: Int?
    var votesFor: Int?
    var votesCount: Int?
    var htmlBody: String?
    var body: String?

    enum CodingKeys: String, CodingKey {
        case id, name, russian, image, target, overall, storyline, music, characters, animation, votesFor, votesCount, htmlBody, body
    }

    init(from decoder: Decoder) {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        id = try? c.decodeIfPresent(Int.self, forKey: .id)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        russian = try? c.decodeIfPresent(String.self, forKey: .russian)
        image = try? c.decodeIfPresent(ImageSet.self, forKey: .image)
        target = try? c.decodeIfPresent(TopicTarget.self, forKey: .target)
        overall = try? c.decodeIfPresent(Int.self, forKey: .overall)
        storyline = try? c.decodeIfPresent(Int.self, forKey: .storyline)
        music = try? c.decodeIfPresent(Int.self, forKey: .music)
        characters = try? c.decodeIfPresent(Int.self, forKey: .characters)
        animation = try? c.decodeIfPresent(Int.self, forKey: .animation)
        votesFor = try? c.decodeIfPresent(Int.self, forKey: .votesFor)
        votesCount = try? c.decodeIfPresent(Int.self, forKey: .votesCount)
        htmlBody = try? c.decodeIfPresent(String.self, forKey: .htmlBody)
        body = try? c.decodeIfPresent(String.self, forKey: .body)
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
    var posterURLs: [URL] {
        if let t = linked?.target { return t.imageURLs }
        return linked?.imageURLs ?? []
    }

    var isCritique: Bool { linkedType == "Critique" }
    var isCollection: Bool { linkedType == "Collection" || CollectionParser.looksLikeCollection(htmlBody) }

    /// Текст рецензии: берётся из привязанной рецензии (в html_body темы перед ним лежат звёзды).
    func critiqueBlocks() -> [CBlock] {
        if let h = linked?.htmlBody, !h.isEmpty { return CommentRenderer.render(html: h) }
        return Comment(id: id, body: linked?.body ?? body, htmlBody: nil, createdAt: createdAt, isOfftopic: nil, user: user).makeBlocks()
    }

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
                     "Person": "Человек", "Club": "Клуб", "Critique": "Рецензия", "Collection": "Коллекция"]
        if let t = linkedType, let k = kinds[t] { list.append(k) }
        if isCritique, let o = linked?.overall, o > 0 { list.append("★ \(o)") }
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
    @State private var collection: ParsedCollection?
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

                if t.isCritique { CritiqueHeader(topic: t) }

                if !blocks.isEmpty {
                    CommentBlocksView(blocks: blocks)
                        .environment(\.commentFont, .body)
                        .environment(\.commentLineSpacing, 5)
                }

                if let collection {
                    if collection.total > 0 {
                        Text("В коллекции: \(collection.total)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    CollectionGroupsView(collection: collection)
                } else if t.isCollection && error == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                }

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
            if topic.isCritique {
                blocks = topic.critiqueBlocks()
            } else if !topic.isCollection {
                blocks = topic.makeBlocks()
            }
            do {
                let f = try await AuthManager.shared.topic(id: topic.id)
                full = f
                if f.isCollection {
                    let parsed = CollectionParser.parse(f.htmlBody ?? "")
                    collection = parsed
                    blocks = parsed.descriptionHTML.isEmpty ? [] : CommentRenderer.render(html: parsed.descriptionHTML)
                } else if f.isCritique {
                    let b = f.critiqueBlocks()
                    if !b.isEmpty { blocks = b }
                } else {
                    let b = f.makeBlocks()
                    if !b.isEmpty { blocks = b }
                }
            } catch is CancellationError {
            } catch {
                if blocks.isEmpty { self.error = error.localizedDescription }
            }
        }
    }
}
