import SwiftUI

@MainActor
final class TitleModel: ObservableObject {
    var ref = MediaRef(id: 0, kind: .anime)
    @Published var detail: MediaDetail?
    @Published var error: String?
    @Published var busy = false
    @Published var roles: [Role] = []
    @Published var similar: [Media] = []
    @Published var extras: MediaExtras?
    @Published var related: [RelatedItem] = []
    @Published var videos: [VideoItem] = []
    @Published var screenshots: [Screenshot] = []
    @Published var franchise: [FranchiseNode] = []
    @Published var nodePosters: [Int: PosterURLs] = [:]

    func load(_ ref: MediaRef) async {
        self.ref = ref
        error = nil
        let base = "\(ref.kind.rawValue)-\(ref.id)"
        let detailKey = DiskCache.userKey("detail-\(base)")
        if detail == nil {
            detail = DiskCache.load(MediaDetail.self, key: detailKey)
            roles = DiskCache.load([Role].self, key: "roles-\(base)") ?? []
            similar = DiskCache.load([Media].self, key: "similar-\(base)") ?? []
            extras = DiskCache.load(MediaExtras.self, key: "extras-\(base)")
            related = DiskCache.load([RelatedItem].self, key: "related-\(base)") ?? []
            videos = DiskCache.load([VideoItem].self, key: "videos-\(base)") ?? []
            screenshots = DiskCache.load([Screenshot].self, key: "shots-\(base)") ?? []
            franchise = DiskCache.load([FranchiseNode].self, key: "franchise-\(base)") ?? []
            nodePosters = DiskCache.load([Int: PosterURLs].self, key: "franchise-posters-\(base)") ?? [:]
        }
        // Все блоки грузятся одновременно и появляются по мере готовности.
        // Сначала самые заметные, потом остальные. Свежие данные из кэша не перезапрашиваем.
        let fresh: TimeInterval = 3600
        func stale(_ key: String) -> Bool { DiskCache.age(key: key).map { $0 > fresh } ?? true }
        let ref = ref
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                do {
                    let d = try await AuthManager.shared.detail(ref)
                    self.detail = d
                    DiskCache.save(d, key: detailKey)
                } catch is CancellationError {
                } catch {
                    self.error = self.detail == nil ? error.localizedDescription : offlineMessage
                }
            }
            if stale("extras-\(base)") || extras == nil {
                group.addTask { @MainActor in
                    if let e = await AuthManager.shared.extras(ref) { self.extras = e; DiskCache.save(e, key: "extras-\(base)") }
                }
            }
            if stale("shots-\(base)") || screenshots.isEmpty {
                group.addTask { @MainActor in
                    let v = await AuthManager.shared.screenshots(ref)
                    if !v.isEmpty { self.screenshots = v; DiskCache.save(v, key: "shots-\(base)") }
                }
            }
            if stale("videos-\(base)") || videos.isEmpty {
                group.addTask { @MainActor in
                    let v = await AuthManager.shared.videos(ref)
                    if !v.isEmpty { self.videos = v; DiskCache.save(v, key: "videos-\(base)") }
                }
            }
            if stale("roles-\(base)") || roles.isEmpty {
                group.addTask { @MainActor in
                    let v = await AuthManager.shared.roles(ref)
                    if !v.isEmpty { self.roles = v; DiskCache.save(v, key: "roles-\(base)") }
                }
            }
            if stale("related-\(base)") || related.isEmpty {
                group.addTask { @MainActor in
                    let v = await AuthManager.shared.related(ref)
                    if !v.isEmpty { self.related = v; DiskCache.save(v, key: "related-\(base)") }
                }
            }
            if stale("franchise-\(base)") || franchise.isEmpty {
                group.addTask { @MainActor in
                    let fr = await AuthManager.shared.franchise(ref)
                    guard !fr.isEmpty else { return }
                    self.franchise = fr
                    DiskCache.save(fr, key: "franchise-\(base)")
                    let posters = await AuthManager.shared.posters(kind: ref.kind, ids: fr.map(\.id))
                    if !posters.isEmpty {
                        self.nodePosters = posters
                        DiskCache.save(posters, key: "franchise-posters-\(base)")
                    }
                }
            }
            if stale("similar-\(base)") || similar.isEmpty {
                group.addTask { @MainActor in
                    let v = await AuthManager.shared.similar(ref)
                    if !v.isEmpty { self.similar = v; DiskCache.save(v, key: "similar-\(base)") }
                }
            }
        }
    }

    private func run(_ block: () async throws -> Void) async {
        busy = true
        error = nil
        do { try await block() } catch is CancellationError {} catch { self.error = error.localizedDescription }
        busy = false
    }

    func setStatus(_ status: RateStatus) async {
        guard let d = detail else { return }
        await run {
            if let rate = d.userRate {
                detail?.userRate = try await AuthManager.shared.updateRate(id: rate.id, status: status.rawValue)
            } else {
                detail?.userRate = try await AuthManager.shared.createRate(
                    animeID: d.id, status: status.rawValue,
                    targetType: ref.kind == .anime ? "Anime" : "Manga")
            }
            RateStore.shared.set(RateStore.key(ref.kind, d.id), status: detail?.userRate?.status ?? status.rawValue)
        }
    }

    func changeEpisodes(by delta: Int) async {
        guard let rate = detail?.userRate else { return }
        if ref.kind == .anime {
            var next = max(0, (rate.episodes ?? 0) + delta)
            if let total = detail?.episodes, total > 0 { next = min(next, total) }
            await run { detail?.userRate = try await AuthManager.shared.updateRate(id: rate.id, episodes: next) }
        } else {
            var next = max(0, (rate.chapters ?? 0) + delta)
            if let total = detail?.chapters, total > 0 { next = min(next, total) }
            await run { detail?.userRate = try await AuthManager.shared.updateRate(id: rate.id, chapters: next) }
        }
    }

    func setScore(_ score: Int) async {
        guard let rate = detail?.userRate else { return }
        await run { detail?.userRate = try await AuthManager.shared.updateRate(id: rate.id, score: score) }
    }

    func remove() async {
        guard let rate = detail?.userRate else { return }
        await run {
            try await AuthManager.shared.deleteRate(id: rate.id)
            detail?.userRate = nil
            RateStore.shared.set(RateStore.key(ref.kind, ref.id), status: nil)
        }
    }
}

enum TitleTab: CaseIterable, Hashable {
    case info, people, links, ratings
    var title: String {
        switch self {
        case .info: return "Инфо"
        case .people: return "Люди"
        case .links: return "Связанное"
        case .ratings: return "Оценки"
        }
    }
    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .people: return "person.2"
        case .links: return "link"
        case .ratings: return "chart.bar"
        }
    }
}

struct TitleView: View {
    let ref: MediaRef
    @StateObject private var model = TitleModel()
    @State private var tab: TitleTab = .info
    @State private var descOpen = false
    @State private var allRelated = false
    @State private var relatedMode = 0
    @State private var allLinks = false
    @State private var viewer: ViewerState?
    @State private var playing: VideoItem?
    @State private var scrollY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            if let d = model.detail { backdrop(d) }
            ScrollView {
                if let d = model.detail {
                    content(d)
                } else if let message = model.error {
                    ErrorBanner(message: message) { Task { await model.load(ref) } }
                        .padding(.top, 40)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, new in
                scrollY = max(0, new)
            }
        }
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await model.load(ref) }
        .fullScreenCover(item: $viewer) { ImageViewer(images: $0.images, index: $0.index) }
        .fullScreenCover(item: $playing) { v in
            if let player = v.playerURL, let link = v.pageURL ?? v.playerURL {
                VideoPlayerScreen(player: player, link: link)
            }
        }
    }

    /// Размытый постер: часть страницы, уходит вместе с прокруткой.
    private func backdrop(_ d: MediaDetail) -> some View {
        Color.clear
            .frame(height: 480)
            .overlay { RemoteImage(urls: d.posterCandidates).blur(radius: 50).opacity(0.5) }
            .clipped()
            .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea(edges: .top)
            .offset(y: -scrollY)
            .allowsHitTesting(false)
    }

    // MARK: Каркас страницы

    @ViewBuilder
    private func content(_ d: MediaDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(d)
            genreStrip(d)
            actions(d)
            descriptionBlock(d)
            tabBar
            switch tab {
            case .info: infoTab(d)
            case .people: peopleTab
            case .links: linksTab
            case .ratings: ratingsTab(d)
            }
            if tab != .ratings {
                similarBlock
            }
            if let message = model.error {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 100)
    }

    // MARK: Шапка

    private func statusTint(_ raw: String?) -> Color {
        switch raw {
        case "ongoing": return .green
        case "anons": return .orange
        default: return .blue
        }
    }

    private func factsLine(_ d: MediaDetail) -> String {
        var parts: [String] = []
        if let k = d.kind, !k.isEmpty { parts.append(kindTitle(k)) }
        if let y = d.airedOn?.prefix(4), y.count == 4 { parts.append(String(y)) }
        if ref.kind == .anime {
            if let e = d.episodes, e > 0 { parts.append("\(e) эп.") }
            else if let a = d.episodesAired, a > 0 { parts.append("\(a) эп.") }
            if let dur = d.duration, dur > 0 { parts.append("\(dur) мин.") }
        } else {
            if let c = d.chapters, c > 0 { parts.append("\(c) гл.") }
            else if let v = d.volumes, v > 0 { parts.append("\(v) т.") }
        }
        return parts.joined(separator: " · ")
    }

    private func header(_ d: MediaDetail) -> some View {
        let votes = (model.extras?.scoresStats ?? []).reduce(0) { $0 + $1.count }
        return HStack(alignment: .bottom, spacing: 16) {
            Button {
                viewer = ViewerState(images: [d.posterCandidates], index: 0)
            } label: {
                PosterView(urls: d.posterCandidates, radius: 20)
                    .frame(width: 122)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 8) {
                Text(d.title)
                    .font(.title2.weight(.heavy))
                    .fixedSize(horizontal: false, vertical: true)
                if d.name != d.title {
                    Text(d.name).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(factsLine(d)).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(releaseStatusTitle(d.status))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusTint(d.status))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(statusTint(d.status).opacity(0.15), in: Capsule())
                    if let score = d.scoreText {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                            Text(score).fontWeight(.heavy)
                            if votes > 0 {
                                Text("(\(shortCount(votes)))").foregroundStyle(.secondary).font(.caption)
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func genreStrip(_ d: MediaDetail) -> some View {
        let fromExtras = (model.extras?.genres ?? []).filter { $0.kind == "genre" }.map(\.display)
        let names = model.extras == nil ? (d.genres ?? []).map(\.display) : fromExtras
        if !names.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(names.enumerated()), id: \.offset) { _, t in
                        Text(t)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .glassEffect(.regular, in: .capsule)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
        }
    }

    // MARK: Мой список и обсуждение

    private func actions(_ d: MediaDetail) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(RateStatus.allCases) { st in
                        Button { Task { await model.setStatus(st) } } label: {
                            Label(st.title, systemImage: st.icon)
                        }
                    }
                    if d.userRate != nil {
                        Divider()
                        Button("Убрать из списка", role: .destructive) { Task { await model.remove() } }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: RateStatus.icon(for: d.userRate?.status))
                        Text(d.userRate == nil ? "Добавить в список" : RateStatus.title(for: d.userRate?.status))
                            .fontWeight(.bold)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)

                if let topic = d.topicId {
                    NavigationLink {
                        CommentsView(topicID: topic, title: d.title)
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.headline)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Комментарии")
                }
            }

            if let rate = d.userRate {
                let total = (ref.kind == .anime ? d.episodes : d.chapters) ?? 0
                let done = (ref.kind == .anime ? rate.episodes : rate.chapters) ?? 0
                VStack(spacing: 10) {
                    HStack {
                        Text(ref.kind == .anime ? "Эпизоды" : "Главы").font(.subheadline.weight(.semibold))
                        Spacer()
                        stepButton("minus", label: "Меньше") { await model.changeEpisodes(by: -1) }
                        Text(total > 0 ? "\(done) / \(total)" : "\(done)")
                            .font(.headline.weight(.heavy))
                            .frame(minWidth: 64)
                        stepButton("plus", label: "Больше") { await model.changeEpisodes(by: 1) }
                    }
                    if total > 0 {
                        ProgressView(value: Double(min(done, total)), total: Double(total))
                            .tint(Theme.accent)
                    }
                    HStack {
                        Text("Моя оценка").font(.subheadline.weight(.semibold))
                        Spacer()
                        Menu {
                            ForEach((1...10).reversed(), id: \.self) { n in
                                Button("\(n)") { Task { await model.setScore(n) } }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                                Text((rate.score ?? 0) > 0 ? "\(rate.score ?? 0) / 10" : "Не оценено")
                                    .font(.subheadline.weight(.bold))
                            }
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .disabled(model.busy)
    }

    private func stepButton(_ icon: String, label: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    // MARK: Описание

    @ViewBuilder
    private func descriptionBlock(_ d: MediaDetail) -> some View {
        if let text = d.plainDescription, !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.subheadline)
                    .lineSpacing(3)
                    .lineLimit(descOpen ? nil : 5)
                if text.count > 260 {
                    Button(descOpen ? "Свернуть" : "Показать больше") {
                        withAnimation(.easeInOut(duration: 0.2)) { descOpen.toggle() }
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        }
    }

    // MARK: Вкладки

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(TitleTab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { tab = t }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 17, weight: .semibold))
                        Text(t.title).font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(tab == t ? Theme.accent : Color.secondary)
                    .background(tab == t ? Theme.accent.opacity(0.14) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.card, in: Capsule())
    }

    @ViewBuilder
    private var similarBlock: some View {
        if !model.similar.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionLink(title: "Похожее (\(model.similar.count))") {
                    SimilarScreen(items: model.similar, kind: ref.kind)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(model.similar.prefix(12)) { item in
                            NavigationLink { TitleView(ref: MediaRef(id: item.id, kind: ref.kind)) } label: {
                                MediaCard(media: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)
            }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.title3.weight(.bold))
    }

    // MARK: Вкладка «Инфо»

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func chipsCard(_ label: String, _ names: [String]) -> some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(Array(names.enumerated()), id: \.offset) { _, n in
                        Text(n)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Color(UIColor.tertiarySystemFill), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func datesText(_ d: MediaDetail) -> String? {
        let from = (d.airedOn ?? "").isEmpty ? nil : ruDate(d.airedOn ?? "")
        let to = (d.releasedOn ?? "").isEmpty ? nil : ruDate(d.releasedOn ?? "")
        switch (from, to) {
        case let (f?, t?): return f == t ? f : "с \(f) по \(t)"
        case let (f?, nil): return "с \(f)"
        case let (nil, t?): return "по \(t)"
        default: return nil
        }
    }

    private func nextEpisodeText(_ iso: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter()
        guard let date = f.date(from: iso) ?? g.date(from: iso) else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "ru_RU")
        out.dateFormat = "d MMMM yyyy, HH:mm"
        return out.string(from: date)
    }

    private func shortFacts(_ d: MediaDetail) -> [(String, String)] {
        let e = model.extras
        var r: [(String, String)] = []
        if let k = d.kind, !k.isEmpty { r.append(("Тип", kindTitle(k))) }
        if ref.kind == .anime {
            let total = d.episodes ?? 0
            let aired = d.episodesAired ?? 0
            if total > 0 || aired > 0 {
                r.append(("Эпизоды", total > 0 && d.status == "ongoing" && aired > 0
                          ? "\(aired) из \(total)" : (total > 0 ? "\(total)" : "\(aired)")))
            }
            if let dur = d.duration, dur > 0 { r.append(("Длительность", "\(dur) мин.")) }
            if let rt = e?.rating ?? d.rating, let label = SiteLabels.ageRating(rt) { r.append(("Возраст", label)) }
            if let o = e?.origin { r.append(("Первоисточник", SiteLabels.origin(o))) }
        } else {
            if let v = d.volumes, v > 0 { r.append(("Тома", "\(v)")) }
            if let c = d.chapters, c > 0 { r.append(("Главы", "\(c)")) }
        }
        r.append(("Статус", releaseStatusTitle(d.status)))
        r.append(("Дата начала", (d.airedOn ?? "").isEmpty ? "—" : ruDate(d.airedOn ?? "")))
        r.append(("Дата завершения", (d.releasedOn ?? "").isEmpty ? "—" : ruDate(d.releasedOn ?? "")))
        return r
    }

    private func wideFacts(_ d: MediaDetail) -> [(String, String)] {
        let e = model.extras
        var r: [(String, String)] = []
        if ref.kind == .anime, let next = e?.nextEpisodeAt, d.status == "ongoing", let t = nextEpisodeText(next) {
            r.append(("Следующий эпизод", t))
        }
        if ref.kind == .anime {
            let fromExtras = (e?.studios ?? []).compactMap(\.name)
            let names = fromExtras.isEmpty ? (d.studios ?? []).compactMap(\.name) : fromExtras
            if !names.isEmpty { r.append(("Студия", names.joined(separator: ", "))) }
        } else if let p = e?.publishers?.compactMap(\.name), !p.isEmpty {
            r.append(("Издатель", p.joined(separator: ", ")))
        }
        if let l = e?.licensors, !l.isEmpty { r.append(("Лицензировано", l.joined(separator: ", "))) }
        return r
    }

    private func alternativeList(_ d: MediaDetail) -> [String] {
        let e = model.extras
        var names: [String] = [d.name]
        names += [e?.english].compactMap { $0 }
        names += (d.english ?? []).compactMap { $0 }
        names += [e?.japanese].compactMap { $0 }
        names += (d.japanese ?? []).compactMap { $0 }
        names += e?.synonyms ?? []
        var unique: [String] = []
        for n in names where !n.isEmpty && !unique.contains(n) { unique.append(n) }
        return unique
    }

    @ViewBuilder
    private func infoTab(_ d: MediaDetail) -> some View {
        let short = shortFacts(d)
        let wide = wideFacts(d)
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(short.enumerated()), id: \.offset) { _, f in tile(f.0, f.1) }
            }
            ForEach(Array(wide.enumerated()), id: \.offset) { _, f in tile(f.0, f.1) }
            chipsCard("Темы", (model.extras?.genres ?? []).filter { $0.kind == "theme" }.map(\.display))
            chipsCard("Аудитория", (model.extras?.genres ?? []).filter { $0.kind == "demographic" }.map(\.display))
            if ref.kind == .anime {
                ExpandableChipsCard(label: "Субтитры", names: model.extras?.fansubbers ?? [])
                ExpandableChipsCard(label: "Озвучка", names: model.extras?.fandubbers ?? [])
            }

            let alts = alternativeList(d)
            if !alts.isEmpty {
                DisclosureGroup("Альтернативные названия") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(alts, id: \.self) { Text($0).font(.subheadline).textSelection(.enabled) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
                .font(.subheadline.weight(.semibold))
                .tint(.secondary)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            screenshotsRow(d)
            videosRow(d)
            externalLinks
        }
    }

    private func linkIcon(_ kind: String) -> String {
        switch kind {
        case "official_site": return "globe"
        case "wikipedia": return "text.book.closed"
        case "anime_news_network": return "newspaper"
        case "twitter": return "bubble.left"
        case "kinopoisk", "kinopoisk_hd": return "film"
        case "myanimelist", "anime_db", "world_art", "mangaupdates", "novelupdates": return "list.bullet.rectangle"
        case "smotret_anime": return "play.rectangle"
        default: return "link"
        }
    }

    @ViewBuilder
    private var externalLinks: some View {
        let links = (model.extras?.externalLinks ?? []).compactMap { l -> (kind: String, url: URL)? in
            guard let k = l.kind, let u = l.url, let url = URL(string: u) else { return nil }
            return (k, url)
        }
        if !links.isEmpty {
            let shown = allLinks ? links : Array(links.prefix(5))
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Ссылки")
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, link in
                        Link(destination: link.url) {
                            HStack(spacing: 12) {
                                Image(systemName: linkIcon(link.kind))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 34, height: 34)
                                    .background(Theme.accent.opacity(0.14), in: Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(SiteLabels.linkTitle(link.kind))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text((link.url.host ?? "").replacingOccurrences(of: "www.", with: ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < shown.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                if links.count > 5 {
                    Button(allLinks ? "Свернуть" : "Показать все (\(links.count))") {
                        withAnimation { allLinks.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func screenshotsRow(_ d: MediaDetail) -> some View {
        let shots = (model.screenshots.isEmpty ? (d.screenshots ?? []) : model.screenshots).filter { $0.previewURL != nil }
        if !shots.isEmpty {
            let all = shots.map { [$0.originalURL, $0.previewURL].compactMap { $0 } }
            VStack(alignment: .leading, spacing: 10) {
                SectionLink(title: "Кадры (\(shots.count))") {
                    ScreenshotsPage(title: d.title, shots: shots)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(shots.prefix(10).enumerated()), id: \.offset) { i, shot in
                            Button {
                                viewer = ViewerState(images: all, index: i)
                            } label: {
                                Color(UIColor.tertiarySystemFill)
                                    .frame(width: 170, height: 96)
                                    .overlay { RemoteImage(urls: [shot.previewURL, shot.originalURL].compactMap { $0 }) }
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)
            }
        }
    }

    @ViewBuilder
    private func videosRow(_ d: MediaDetail) -> some View {
        let list = model.videos.filter { $0.playerURL != nil }.byImportance
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLink(title: "Видео (\(list.count))") {
                    VideosPage(title: d.title, videos: list)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        ForEach(list.prefix(5)) { v in
                            Button { playing = v } label: { VideoCard(video: v, width: 190) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)
            }
        }
    }

    // MARK: Вкладка «Люди»

    @ViewBuilder
    private var peopleTab: some View {
        let chars = model.roles.allCharactersSorted
        let staff = model.roles.staffSorted
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        VStack(alignment: .leading, spacing: 18) {
            if chars.isEmpty && staff.isEmpty {
                Text("Данных о персонажах и создателях пока нет").font(.footnote).foregroundStyle(.secondary)
            }
            if !chars.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLink(title: "Персонажи (\(chars.count))") { TitleCharactersScreen(roles: model.roles) }
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(chars.prefix(6)) { role in
                            if let c = role.character {
                                NavigationLink { CharacterView(id: c.id) } label: { PersonCellView(person: c) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            if !staff.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLink(title: "Создатели (\(staff.count))") { TitleStaffScreen(roles: model.roles) }
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(staff.prefix(6)) { role in
                            if let p = role.person {
                                NavigationLink { PersonView(id: p.id) } label: {
                                    PersonCellView(person: p, subtitle: role.staffRolesText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Вкладка «Связи»

    private func nodePoster(_ node: FranchiseNode) -> [URL] {
        var urls: [URL] = []
        if let p = model.nodePosters[node.id] {
            var m = Media(id: node.id, name: node.name ?? "")
            m.posterURLs = p
            urls = m.thumbCandidates
        }
        if let u = node.imageURL { urls.append(u) }
        return urls
    }

    private var chronology: [FranchiseNode] {
        model.franchise.sorted { ($0.date ?? 0, $0.id) < ($1.date ?? 0, $1.id) }
    }

    private func relatedRow(poster: [URL], badge: String?, title: String, subtitle: String?, current: Bool = false, rateKey: String? = nil) -> some View {
        HStack(spacing: 12) {
            PosterView(urls: poster, radius: 10, rateKey: rateKey)
                .frame(width: 46, height: 66)
            VStack(alignment: .leading, spacing: 3) {
                if let badge { Text(badge).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent) }
                Text(title).font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading).lineLimit(2)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if !current { Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if current {
                RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.accent, lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder
    private var linksTab: some View {
        let hasChronology = model.franchise.count > 1
        VStack(alignment: .leading, spacing: 14) {
            if hasChronology {
                Picker("Порядок", selection: $relatedMode) {
                    Text("Напрямую").tag(0)
                    Text("Хронология").tag(1)
                }
                .pickerStyle(.segmented)
                .onChange(of: relatedMode) { _, _ in allRelated = false }
            }
            if relatedMode == 1 && hasChronology {
                let nodes = chronology
                let shown = allRelated ? nodes : Array(nodes.prefix(8))
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Хронология")
                    ForEach(shown) { node in
                        let current = node.id == ref.id
                        let sub = [node.kind, node.year.map { String($0) }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                        if current {
                            relatedRow(poster: nodePoster(node), badge: "Вы здесь",
                                       title: node.name ?? "", subtitle: sub, current: true)
                        } else {
                            NavigationLink {
                                TitleView(ref: MediaRef(id: node.id, kind: node.mediaKind))
                            } label: {
                                relatedRow(poster: nodePoster(node), badge: nil,
                                           title: node.name ?? "", subtitle: sub,
                                           rateKey: RateStore.key(node.mediaKind, node.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if nodes.count > 8 {
                        Button(allRelated ? "Свернуть" : "Показать все (\(nodes.count))") {
                            withAnimation { allRelated.toggle() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                if model.related.isEmpty {
                    Text("Связанных тайтлов пока нет").font(.footnote).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Связанное")
                        ForEach(allRelated ? Array(model.related) : Array(model.related.prefix(5))) { item in
                            NavigationLink {
                                TitleView(ref: item.ref)
                            } label: {
                                relatedRow(poster: item.media.thumbCandidates, badge: item.relation,
                                           title: item.media.title,
                                           subtitle: [item.media.kind.map { kindTitle($0) }, item.year.map { String($0) }]
                                               .compactMap { $0 }.joined(separator: " · "),
                                           rateKey: RateStore.key(item.ref.kind, item.media.id))
                            }
                            .buttonStyle(.plain)
                        }
                        if model.related.count > 5 {
                            Button(allRelated ? "Свернуть" : "Показать все (\(model.related.count))") {
                                withAnimation { allRelated.toggle() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    // MARK: Вкладка «Оценки»

    @ViewBuilder
    private func ratingsTab(_ d: MediaDetail) -> some View {
        let scores = model.extras?.scoresStats ?? []
        let statuses = (model.extras?.statusesStats ?? []).filter { $0.count > 0 }
        let votes = scores.reduce(0) { $0 + $1.count }
        VStack(alignment: .leading, spacing: 16) {
            if scores.isEmpty && statuses.isEmpty {
                Text("Статистики пока нет").font(.footnote).foregroundStyle(.secondary)
            }
            if !scores.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(d.scoreText ?? "—").font(.system(size: 40, weight: .heavy))
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Spacer()
                        Text("\(votes) оценок").font(.subheadline).foregroundStyle(.secondary)
                    }
                    scoreHistogram(scores)
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            if !statuses.isEmpty {
                let total = statuses.reduce(0) { $0 + $1.count }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        sectionTitle("В списках")
                        Spacer()
                        Text("\(total)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    SegmentedBar(segments: statuses.map { (color: listStatusColor($0.status), count: $0.count) })
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                              alignment: .leading, spacing: 10) {
                        ForEach(statuses, id: \.status) { s in
                            HStack(spacing: 8) {
                                Circle().fill(listStatusColor(s.status)).frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(SiteLabels.listStatus(s.status, kind: ref.kind)).font(.caption).foregroundStyle(.secondary)
                                    Text("\(s.count)").font(.subheadline.weight(.bold))
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private func scoreHistogram(_ scores: [ExtraScore]) -> some View {
        let byScore = Dictionary(scores.map { ($0.score, $0.count) }, uniquingKeysWith: +)
        let maxCount = max(1, byScore.values.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(1...10, id: \.self) { n in
                let v = byScore[n] ?? 0
                VStack(spacing: 4) {
                    Text(v > 0 ? shortCount(v) : "").font(.system(size: 9)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.accent.opacity(0.35 + 0.65 * Double(v) / Double(maxCount)))
                        .frame(height: max(3, 90 * CGFloat(v) / CGFloat(maxCount)))
                    Text("\(n)").font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
        .frame(height: 130, alignment: .bottom)
    }
}


/// Блок с названиями-«таблетками»: показывается несколько, остальные по кнопке «Ещё».
struct ExpandableChipsCard: View {
    let label: String
    let names: [String]
    var limit = 6
    @State private var open = false

    var body: some View {
        if !names.isEmpty {
            let shown = open ? names : Array(names.prefix(limit))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(names.count)").font(.caption).foregroundStyle(.secondary)
                }
                FlowLayout(spacing: 6) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, n in
                        Text(n)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Color(UIColor.tertiarySystemFill), in: Capsule())
                    }
                    if names.count > limit {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
                        } label: {
                            Text(open ? "Свернуть" : "Ещё \(names.count - limit)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Theme.accent.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
