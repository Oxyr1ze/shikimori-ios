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

        if let i = await api.userProfile(id: user.id) {
            apply(i)
            DiskCache.save(i, key: key("info"))
        }
        loaded = true
        // Всё остальное грузится одновременно, комментарии появляются сразу
        let uid = user.id
        async let favTask = api.favourites(id: uid)
        async let friendsTask = api.friends(id: uid)
        async let historyTask = api.history(id: uid)
        if let f = await favTask {
            favourites = f
            DiskCache.save(f, key: key("fav"))
        }
        let fr = await friendsTask
        if !fr.isEmpty { friends = fr; DiskCache.save(fr, key: key("friends")) }
        let h = await historyTask
        if !h.isEmpty { history = h; DiskCache.save(h, key: key("history")) }
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
            hero
            counters

            if let stats = model.info?.stats { StatsView(stats: stats) }

            if let fav = model.favourites { FavouritesSection(fav: fav) }
            FriendsSection(friends: model.friends)
            ActivitySection(userID: model.user.id, nickname: model.user.nickname, history: model.history)

            // «О себе» внизу: короткий текст виден сразу, длинный сворачивается
            if !model.aboutBlocks.isEmpty {
                AboutCard(blocks: model.aboutBlocks)
            }

            commentsSection

            if model.loaded && model.info == nil {
                Text("Не удалось загрузить профиль. Возможно, он закрыт или нет интернета.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Шапка

    private var hero: some View {
        VStack(spacing: 10) {
            Color(UIColor.tertiarySystemFill)
                .frame(width: 108, height: 108)
                .overlay { if let u = model.user.avatarURL { RemoteImage(urls: [u]) } }
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            Text(model.user.nickname)
                .font(.title.weight(.heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let y = model.info?.fullYears, y > 0 { chip("\(y) \(yearsWord(y))", "birthday.cake.fill") }
                if let s = model.info?.sex {
                    if s == "male" { chip("Мужской", "figure.stand") }
                    else if s == "female" { chip("Женский", "figure.stand.dress") }
                }
            }
            if let last = model.info?.lastOnlineAt, !last.isEmpty {
                chip("Был на сайте: \(relativeDateText(last))", "clock.fill")
            }
            if let site = model.info?.website, !site.isEmpty, let url = URL(string: "https://" + site) {
                Link(destination: url) {
                    Label(site, systemImage: "link").font(.footnote.weight(.semibold)).lineLimit(1)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background {
            // Размытый аватар как фон шапки
            Color(UIColor.tertiarySystemFill)
                .overlay { if let u = model.user.avatarURL { RemoteImage(urls: [u]) } }
                .blur(radius: 36)
                .scaleEffect(1.4)
                .overlay(LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)],
                                        startPoint: .top, endPoint: .bottom))
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func chip(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: Capsule())
    }

    // MARK: Счётчики

    private func total(_ key: String) -> Int {
        (model.info?.stats?.fullStatuses?[key] ?? []).reduce(0) { $0 + $1.size }
    }

    private var averageText: String? {
        let all = (model.info?.stats?.scores?["anime"] ?? []).filter { (Int($0.name) ?? 0) > 0 }
        let votes = all.reduce(0) { $0 + $1.value }
        guard votes > 0 else { return nil }
        let sum = all.reduce(0) { $0 + (Int($1.name) ?? 0) * $1.value }
        return String(format: "%.2f", Double(sum) / Double(votes))
    }

    @ViewBuilder
    private var counters: some View {
        if model.info?.stats != nil {
            HStack(spacing: 10) {
                tile("\(total("anime"))", "Аниме", "play.rectangle.fill")
                tile("\(total("manga"))", "Манга", "book.fill")
                tile(averageText ?? "—", "Ср. оценка", "star.fill")
                if !model.friends.isEmpty { tile("\(model.friends.count)", "Друзей", "person.2.fill") }
            }
        }
    }

    private func tile(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.footnote).foregroundStyle(Theme.accent)
            Text(value).font(.title3.weight(.heavy)).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var commentsSection: some View {
        NavigationLink {
            CommentsView(topicID: model.user.id, title: "Комментарии: \(model.user.nickname)",
                         type: "User", canPost: false)
        } label: {
            HStack {
                Label("Комментарии", systemImage: "text.bubble").font(.body.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
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


/// Блок «О себе»: короткий показывается целиком, длинный обрезается с кнопкой «Показать полностью».
struct AboutCard: View {
    let blocks: [CBlock]
    @State private var open = false

    private var isLong: Bool {
        var chars = 0
        var media = 0
        for b in blocks {
            switch b.kind {
            case .text(let runs):
                for r in runs { if case .text(let a) = r { chars += a.characters.count } }
            case .quote(_, let inner):
                chars += inner.count * 200
            default:
                media += 1
            }
        }
        return chars > 450 || media > 1 || blocks.count > 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("О себе").font(.title3.weight(.bold))
            let content = CommentBlocksView(blocks: blocks)
                .environment(\.commentFont, .body)
                .environment(\.commentLineSpacing, 4)
            if isLong && !open {
                content
                    .frame(maxWidth: .infinity, maxHeight: 190, alignment: .topLeading)
                    .clipped()
                    .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
            } else {
                content
            }
            if isLong {
                Button(open ? "Свернуть" : "Показать полностью") {
                    withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
