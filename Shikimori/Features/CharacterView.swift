import SwiftUI

/// Круглый аватар персонажа или человека с подписью.
struct CastAvatar: View {
    let person: CastPerson
    var size: CGFloat = 76
    var subtitle: String?

    var body: some View {
        VStack(spacing: 6) {
            Color(UIColor.tertiarySystemFill)
                .frame(width: size, height: size)
                .overlay { RemoteImage(urls: person.imageURLs, placeholder: "person.fill") }
                .clipShape(Circle())
            Text(person.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: size + 8)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: size + 8)
            }
        }
        .foregroundStyle(.primary)
    }
}

// MARK: Общие элементы экранов персонажа и человека

/// Кнопка «Комментарии» (открывает комментарии темы персонажа или человека).
struct CommentsLink: View {
    let topicID: Int?
    let title: String

    var body: some View {
        if let id = topicID, id > 0 {
            NavigationLink { CommentsView(topicID: id, title: title) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(Theme.accent)
                    Text("Комментарии").font(.headline)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Названия без повторов: то, что совпадает с главным заголовком или уже показано, пропускается.
func uniqueNames(_ candidates: [String?], excluding title: String) -> [String] {
    var seen: Set<String> = [title.lowercased()]
    var result: [String] = []
    for c in candidates {
        guard let c = c?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { continue }
        if seen.insert(c.lowercased()).inserted { result.append(c) }
    }
    return result
}

/// Описание, которое сворачивается, если оно длинное.
struct CollapsibleBlocks: View {
    let blocks: [CBlock]
    @State private var open = false

    var body: some View {
        let long = blocks.isLongComment
        VStack(alignment: .leading, spacing: 8) {
            let content = CommentBlocksView(blocks: blocks)
                .environment(\.commentFont, .body)
                .environment(\.commentLineSpacing, 4)
            if long && !open {
                content
                    .frame(maxWidth: .infinity, maxHeight: 220, alignment: .topLeading)
                    .clipped()
                    .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
            } else {
                content
            }
            if long {
                Button(open ? "Свернуть" : "Читать полностью") {
                    withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }
}

/// Карточка с подписанными строками («Дата рождения — 29 августа 1986»).
struct InfoRowsCard: View {
    struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var link: URL? = nil
    }
    let rows: [Row]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.label).font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let link = row.link {
                        Link(row.value, destination: link)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text(row.value).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
                    }
                }
                .padding(.vertical, 10)
                if i < rows.count - 1 { Divider() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Шапка: фото слева, названия справа без повторов.
struct PersonHeader: View {
    let posters: [URL]
    let title: String
    let others: [String]
    var badge: String? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            PosterView(urls: posters, radius: 22, placeholder: "person.fill").frame(width: 128)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title2.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                ForEach(others, id: \.self) { n in
                    Text(n).font(.footnote).foregroundStyle(.secondary)
                }
                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.14), in: Capsule())
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: Персонаж

@MainActor
final class CharacterModel: ObservableObject {
    @Published var detail: CharacterDetail?
    @Published var description: [CBlock] = []
    @Published var error: String?

    func load(id: Int) async {
        error = nil
        do {
            async let gT = AuthManager.shared.fetchPersonPosters(ids: [id], field: "characters")
            var d = try await AuthManager.shared.character(id: id)
            d.gqlPoster = await gT[id]
            detail = d
            if let html = d.descriptionHtml, !html.isEmpty {
                description = CommentRenderer.render(html: html)
            }
            async let paT = AuthManager.shared.fetchPosters(ids: (d.animes ?? []).map(\.id), kind: .anime)
            async let pmT = AuthManager.shared.fetchPosters(ids: (d.mangas ?? []).map(\.id), kind: .manga)
            let (pa, pm) = await (paT, pmT)
            d.animes = d.animes?.map { var m = $0; m.posterURLs = pa[m.id]; return m }
            d.mangas = d.mangas?.map { var m = $0; m.posterURLs = pm[m.id]; return m }
            detail = d
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct CharacterView: View {
    let id: Int
    @StateObject private var model = CharacterModel()

    var body: some View {
        ScrollView {
            if let d = model.detail {
                VStack(alignment: .leading, spacing: 20) {
                    PersonHeader(
                        posters: d.posterURLs,
                        title: d.title,
                        others: uniqueNames([d.name, d.japanese, d.altname], excluding: d.title)
                    )

                    if !model.description.isEmpty {
                        CollapsibleBlocks(blocks: model.description)
                    }

                    if let seyu = d.seyu, !seyu.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Сэйю").font(.title3.weight(.bold))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(seyu, id: \.id) { p in
                                        NavigationLink { PersonView(id: p.id) } label: { CastAvatar(person: p) }
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    MediaRow(title: "Аниме", items: d.animes ?? [], kind: .anime)
                        .padding(.horizontal, -20)
                    MediaRow(title: "Манга", items: (d.mangas ?? []).filter { !$0.isRanobe }, kind: .manga)
                        .padding(.horizontal, -20)
                    MediaRow(title: "Ранобэ", items: (d.mangas ?? []).filter { $0.isRanobe }, kind: .ranobe)
                        .padding(.horizontal, -20)

                    CommentsLink(topicID: d.topicId, title: d.title)
                }
                .padding(20)
                .padding(.bottom, 100)
            } else if let message = model.error {
                ErrorBanner(message: message) { Task { await model.load(id: id) } }.padding(.top, 40)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            }
        }
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.detail == nil { await model.load(id: id) } }
    }
}

// MARK: Человек (сэйю, режиссёр, автор)

@MainActor
final class PersonModel: ObservableObject {
    @Published var detail: PersonDetail?
    @Published var error: String?

    func load(id: Int) async {
        error = nil
        do {
            async let gT = AuthManager.shared.fetchPersonPosters(ids: [id], field: "people")
            var d = try await AuthManager.shared.person(id: id)
            d.gqlPoster = await gT[id]
            let animeIDs = (d.works ?? []).compactMap { $0.anime?.id }
            let mangaIDs = (d.works ?? []).compactMap { $0.manga?.id }
            detail = d
            async let paT = AuthManager.shared.fetchPosters(ids: animeIDs, kind: .anime)
            async let pmT = AuthManager.shared.fetchPosters(ids: mangaIDs, kind: .manga)
            let (pa, pm) = await (paT, pmT)
            d.works = d.works?.map { w in
                var w = w
                if let a = w.anime { var m = a; m.posterURLs = pa[a.id]; w.anime = m }
                if let g = w.manga { var m = g; m.posterURLs = pm[g.id]; w.manga = m }
                return w
            }
            detail = d
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Одна работа человека: произведение, его раздел и роль.
struct WorkItem: Identifiable {
    let media: Media
    let kind: MediaKind
    let role: String?
    var id: String { "\(kind.rawValue)-\(media.id)" }
}

enum WorkFilter: Hashable {
    case all, anime, manga, ranobe
    var title: String {
        switch self {
        case .all: return "Все"
        case .anime: return "Аниме"
        case .manga: return "Манга"
        case .ranobe: return "Ранобэ"
        }
    }
}

/// Оценка для сортировки «по рейтингу» (как на сайте: нет оценки или 9.9 и выше уходят в конец).
private func ratingKey(_ m: Media) -> Double {
    guard let s = m.score, let v = Double(s), v > 0, v < 9.9 else { return -999 }
    return v
}

extension PersonDetail {
    var workItems: [WorkItem] {
        (works ?? []).compactMap { w in
            if let a = w.anime { return WorkItem(media: a, kind: .anime, role: w.role) }
            if let m = w.manga { return WorkItem(media: m, kind: m.isRanobe ? .ranobe : .manga, role: w.role) }
            return nil
        }
    }

    /// Группы ролей сэйю (персонажи и аниме), по рейтингу или по дате выхода.
    func sortedRoleGroups(byDate: Bool) -> [PersonRoleGroup] {
        let groups = (roles ?? []).filter { !($0.characters ?? []).isEmpty || !($0.animes ?? []).isEmpty }
        func rating(_ g: PersonRoleGroup) -> Double { (g.animes ?? []).map(ratingKey).max() ?? -999 }
        func date(_ g: PersonRoleGroup) -> String { (g.animes ?? []).map(\.sortDate).max() ?? "" }
        return groups.sorted { a, b in byDate ? date(a) > date(b) : rating(a) > rating(b) }
    }
}

func sortWorks(_ items: [WorkItem], byDate: Bool) -> [WorkItem] {
    items.sorted { a, b in
        if byDate {
            if a.media.sortDate != b.media.sortDate { return a.media.sortDate > b.media.sortDate }
        } else if ratingKey(a.media) != ratingKey(b.media) {
            return ratingKey(a.media) > ratingKey(b.media)
        }
        return a.media.title < b.media.title
    }
}

/// Заголовок раздела со стрелкой: нажатие открывает отдельный экран.
struct SectionLink<Destination: View>: View {
    let title: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 6) {
                Text(title).font(.title3.weight(.bold))
                Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Карточка работы: постер с оценкой справа сверху (как в каталоге), название, роль, тип и год.
struct WorkCard: View {
    let item: WorkItem
    var width: CGFloat? = nil

    var body: some View {
        TitleCard(media: item.media, kind: item.kind, width: width, role: item.role)
    }
}

/// Одна группа ролей сэйю: персонажи слева, аниме справа.
struct RoleGroupCard: View {
    let group: PersonRoleGroup

    var body: some View {
        let chars = group.characters ?? []
        let animes = group.animes ?? []
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(chars.prefix(3), id: \.id) { c in
                    NavigationLink { CharacterView(id: c.id) } label: {
                        HStack(spacing: 10) {
                            Color(UIColor.tertiarySystemFill)
                                .frame(width: 48, height: 48)
                                .overlay { RemoteImage(urls: c.imageURLs, placeholder: "person.fill") }
                                .clipShape(Circle())
                            Text(c.title).font(.subheadline.weight(.semibold))
                                .lineLimit(2).multilineTextAlignment(.leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if chars.count > 3 {
                    Text("и ещё \(chars.count - 3)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                ForEach(animes.prefix(3), id: \.id) { a in
                    NavigationLink { TitleView(ref: MediaRef(id: a.id, kind: .anime)) } label: {
                        HStack(spacing: 10) {
                            PosterView(urls: a.thumbCandidates, radius: 8, rateKey: RateStore.key(.anime, a.id)).frame(width: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.title).font(.footnote.weight(.semibold))
                                    .lineLimit(2).multilineTextAlignment(.leading)
                                Text([a.kind.map(kindTitle), a.yearText].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if animes.count > 3 {
                    Text("и ещё \(animes.count - 3)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct SortPicker: View {
    @Binding var byDate: Bool
    var body: some View {
        Picker("Сортировка", selection: $byDate) {
            Text("По рейтингу").tag(false)
            Text("По дате выхода").tag(true)
        }
        .pickerStyle(.segmented)
    }
}

// MARK: Экран «Участие в проектах»

struct PersonWorksScreen: View {
    @ObservedObject var model: PersonModel
    @State private var byDate = false
    @State private var filter: WorkFilter = .all

    private func count(_ items: [WorkItem], _ f: WorkFilter) -> Int {
        switch f {
        case .all: return items.count
        case .anime: return items.filter { $0.kind == .anime }.count
        case .manga: return items.filter { $0.kind == .manga }.count
        case .ranobe: return items.filter { $0.kind == .ranobe }.count
        }
    }

    private func visible(_ items: [WorkItem]) -> [WorkItem] {
        let list = items.filter { item in
            switch filter {
            case .all: return true
            case .anime: return item.kind == .anime
            case .manga: return item.kind == .manga
            case .ranobe: return item.kind == .ranobe
            }
        }
        return sortWorks(list, byDate: byDate)
    }

    var body: some View {
        let items = model.detail?.workItems ?? []
        let options: [WorkFilter] = [.all, .anime, .manga, .ranobe].filter { $0 == .all || count(items, $0) > 0 }
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SortPicker(byDate: $byDate)
                if options.count > 2 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(options, id: \.self) { f in
                                Button { withAnimation { filter = f } } label: {
                                    Text("\(f.title) \(count(items, f))")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .foregroundStyle(filter == f ? Color.white : Color.primary)
                                        .background(filter == f ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(UIColor.tertiarySystemFill)), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                LazyVGrid(columns: cols, alignment: .leading, spacing: 16) {
                    ForEach(visible(items)) { w in
                        NavigationLink { TitleView(ref: MediaRef(id: w.media.id, kind: w.kind)) } label: {
                            WorkCard(item: w)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(AppBackground())
        .navigationTitle("Участие в проектах")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Экран «Роли» сэйю

struct PersonRolesScreen: View {
    @ObservedObject var model: PersonModel
    @State private var byDate = false

    var body: some View {
        let groups = model.detail?.sortedRoleGroups(byDate: byDate) ?? []
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                SortPicker(byDate: $byDate)
                ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                    RoleGroupCard(group: g)
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(AppBackground())
        .navigationTitle("Роли")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Страница человека

struct PersonView: View {
    let id: Int
    @StateObject private var model = PersonModel()
    @State private var allGrouped = false

    private let previewWorks = 10
    private let previewRoles = 20

    private func infoRows(_ d: PersonDetail) -> [InfoRowsCard.Row] {
        var rows: [InfoRowsCard.Row] = []
        if let b = d.birthOn?.text { rows.append(.init(label: "Дата рождения", value: b)) }
        if let b = d.deceasedOn?.text { rows.append(.init(label: "Дата смерти", value: b)) }
        if let w = d.website, !w.isEmpty {
            let full = w.hasPrefix("http") ? w : "https://" + w
            let host = URL(string: full)?.host ?? w
            rows.append(.init(label: "Сайт", value: host.replacingOccurrences(of: "www.", with: ""), link: URL(string: full)))
        }
        return rows
    }

    /// Персонажи, которых озвучил человек (без повторов), лучшие по оценке — первыми.
    private func voiced(_ d: PersonDetail) -> [CastPerson] {
        var seen = Set<Int>()
        var result: [CastPerson] = []
        let groups = d.sortedRoleGroups(byDate: false)
        for group in groups {
            for c in group.characters ?? [] where seen.insert(c.id).inserted { result.append(c) }
        }
        return result
    }

    var body: some View {
        ScrollView {
            if let d = model.detail {
                content(d)
                    .padding(20)
                    .padding(.bottom, 100)
            } else if let message = model.error {
                ErrorBanner(message: message) { Task { await model.load(id: id) } }.padding(.top, 40)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            }
        }
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.detail == nil { await model.load(id: id) } }
    }

    @ViewBuilder
    private func content(_ d: PersonDetail) -> some View {
        let works = sortWorks(d.workItems, byDate: false)
        let chars = voiced(d)
        let rows = infoRows(d)
        let grouped = d.groupedRoles?.items ?? []
        VStack(alignment: .leading, spacing: 22) {
            PersonHeader(
                posters: d.posterURLs,
                title: d.title,
                others: uniqueNames([d.name, d.japanese], excluding: d.title),
                badge: d.jobTitle
            )
            if !rows.isEmpty { InfoRowsCard(rows: rows) }
            if !grouped.isEmpty { groupedCard(grouped) }

            if !chars.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLink(title: "Роли (\(chars.count))") { PersonRolesScreen(model: model) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(chars.prefix(previewRoles), id: \.id) { c in
                                NavigationLink { CharacterView(id: c.id) } label: { CastAvatar(person: c) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            if !works.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLink(title: "Участие в проектах (\(works.count))") { PersonWorksScreen(model: model) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(works.prefix(previewWorks)) { w in
                                NavigationLink { TitleView(ref: MediaRef(id: w.media.id, kind: w.kind)) } label: {
                                    WorkCard(item: w, width: 124)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            CommentsLink(topicID: d.topicId, title: d.title)
        }
    }

    private func groupedCard(_ grouped: [RoleCount]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Роли в аниме и манге").font(.title3.weight(.bold))
            VStack(spacing: 0) {
                let shown = allGrouped ? grouped : Array(grouped.prefix(6))
                ForEach(Array(shown.enumerated()), id: \.offset) { i, r in
                    HStack {
                        Text(r.name).font(.subheadline)
                        Spacer(minLength: 8)
                        Text("\(r.count)").font(.subheadline.weight(.bold))
                    }
                    .padding(.vertical, 9)
                    if i < shown.count - 1 { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if grouped.count > 6 {
                Button(allGrouped ? "Свернуть" : "Показать все (\(grouped.count))") {
                    withAnimation { allGrouped.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
        }
    }
}
