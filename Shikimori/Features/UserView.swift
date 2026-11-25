import SwiftUI

@MainActor
final class UserModel: ObservableObject {
    let user: ShikiUser
    @Published var info: UserProfileInfo?
    @Published var favourites: Favourites?
    @Published var friends: [ShikiUser] = []
    @Published var history: [HistoryItem] = []
    @Published var aboutBlocks: [CBlock] = []
    @Published var comments: [Comment] = []
    @Published var commentBlocks: [Int: [CBlock]] = [:]
    @Published var loaded = false

    init(user: ShikiUser) { self.user = user }

    private func key(_ name: String) -> String { DiskCache.userKey("user-\(user.id)-\(name)") }

    func load() async {
        let api = AuthManager.shared
        if info == nil, let c = DiskCache.load(UserProfileInfo.self, key: key("info")) { apply(c) }
        if favourites == nil { favourites = DiskCache.load(Favourites.self, key: key("fav")) }
        if friends.isEmpty { friends = DiskCache.load([ShikiUser].self, key: key("friends")) ?? [] }
        if history.isEmpty { history = DiskCache.load([HistoryItem].self, key: key("history")) ?? [] }
        if comments.isEmpty, let c = DiskCache.load([Comment].self, key: key("comments")) { setComments(c) }

        if let i = await api.userProfile(id: user.id) {
            apply(i)
            DiskCache.save(i, key: key("info"))
        }
        loaded = true
        if let f = await api.favourites(id: user.id) {
            favourites = f
            DiskCache.save(f, key: key("fav"))
        }
        let fr = await api.friends(id: user.id)
        if !fr.isEmpty { friends = fr; DiskCache.save(fr, key: key("friends")) }
        let h = await api.history(id: user.id)
        if !h.isEmpty { history = h; DiskCache.save(h, key: key("history")) }
        if let c = try? await api.comments(topicID: user.id, type: "User", page: 1, limit: 10) {
            setComments(Array(c.prefix(10)))
            DiskCache.save(comments, key: key("comments"))
        }
    }

    private func setComments(_ list: [Comment]) {
        comments = list
        for c in list { commentBlocks[c.id] = c.makeBlocks() }
    }

    private func apply(_ i: UserProfileInfo) {
        info = i
        if let html = i.aboutHtml, !html.isEmpty {
            aboutBlocks = CommentRenderer.render(html: html)
        } else {
            aboutBlocks = []
        }
    }
}

/// Содержимое профиля. Одинаково для своего профиля и чужих.
struct UserContent: View {
    @ObservedObject var model: UserModel

    private var subtitle: String {
        var parts: [String] = []
        if let y = model.info?.fullYears, y > 0 { parts.append("\(y) \(yearsWord(y))") }
        if let s = model.info?.sex {
            if s == "male" { parts.append("мужской") } else if s == "female" { parts.append("женский") }
        }
        return parts.joined(separator: ", ")
    }

    private func yearsWord(_ n: Int) -> String {
        let m10 = n % 10, m100 = n % 100
        if m10 == 1 && m100 != 11 { return "год" }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return "года" }
        return "лет"
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Color(UIColor.tertiarySystemFill)
                    .frame(width: 96, height: 96)
                    .overlay { if let u = model.user.avatarURL { RemoteImage(urls: [u]) } }
                    .clipShape(Circle())
                Text(model.user.nickname).font(.title2.weight(.heavy))
                if !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                if let last = model.info?.lastOnlineAt, !last.isEmpty {
                    Text("Был на сайте: \(relativeDateText(last))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let site = model.info?.website, !site.isEmpty,
                   let url = URL(string: "https://" + site) {
                    Link(site, destination: url).font(.footnote)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

            if let stats = model.info?.stats { StatsView(stats: stats) }

            if let fav = model.favourites {
                MediaRow(title: "Избранное: аниме", items: fav.animes, kind: .anime).padding(.horizontal, -20)
                MediaRow(title: "Избранное: манга", items: fav.mangas, kind: .manga).padding(.horizontal, -20)
                MediaRow(title: "Избранное: ранобэ", items: fav.ranobe, kind: .ranobe).padding(.horizontal, -20)
                characters(fav.characters)
            }
            friendsRow
            historyList

            // «О себе» внизу и свёрнуто: у некоторых людей там очень много текста и картинок
            if !model.aboutBlocks.isEmpty {
                SpoilerBlockView(title: "О себе", blocks: model.aboutBlocks)
                    .environment(\.commentFont, .body)
                    .environment(\.commentLineSpacing, 4)
            }

            commentsSection

            if model.loaded && model.info == nil {
                Text("Не удалось загрузить профиль. Возможно, он закрыт или нет интернета.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Комментарии").font(.title3.weight(.bold))
            if model.comments.isEmpty {
                if model.loaded {
                    Text("Комментариев пока нет").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.comments) { c in
                    CommentRowView(comment: c, blocks: model.commentBlocks[c.id] ?? [])
                }
                NavigationLink {
                    CommentsView(topicID: model.user.id, title: "Комментарии: \(model.user.nickname)",
                                 type: "User", canPost: false)
                } label: {
                    HStack {
                        Text("Все комментарии").font(.body.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func characters(_ list: [CastPerson]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Избранные персонажи").font(.title3.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(list, id: \.id) { c in
                            NavigationLink { CharacterView(id: c.id) } label: { CastAvatar(person: c) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var friendsRow: some View {
        if !model.friends.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Друзья").font(.title3.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(model.friends, id: \.id) { f in
                            NavigationLink { UserView(user: f) } label: {
                                VStack(spacing: 6) {
                                    Color(UIColor.tertiarySystemFill)
                                        .frame(width: 60, height: 60)
                                        .overlay { if let u = f.avatarURL { RemoteImage(urls: [u]) } }
                                        .clipShape(Circle())
                                    Text(f.nickname)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .frame(width: 72)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var historyList: some View {
        let items = model.history.filter { !$0.plainDescription.isEmpty }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Недавняя активность").font(.title3.weight(.bold))
                ForEach(items) { item in
                    let content = VStack(alignment: .leading, spacing: 4) {
                        if let t = item.target, !t.title.isEmpty {
                            Text(t.title).font(.subheadline.weight(.bold)).multilineTextAlignment(.leading)
                        }
                        Text(item.plainDescription).font(.subheadline).multilineTextAlignment(.leading)
                        Text(item.dateText).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    if let t = item.target {
                        NavigationLink { TitleView(ref: MediaRef(id: t.id, kind: t.kind)) } label: { content }
                            .buttonStyle(.plain)
                    } else {
                        content
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Страница любого пользователя Shikimori.
struct UserView: View {
    @StateObject private var model: UserModel

    init(user: ShikiUser) {
        _model = StateObject(wrappedValue: UserModel(user: user))
    }

    var body: some View {
        ScrollView {
            UserContent(model: model)
                .padding(20)
                .padding(.bottom, 100)
        }
        .background(AppBackground())
        .navigationTitle(model.user.nickname)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}
