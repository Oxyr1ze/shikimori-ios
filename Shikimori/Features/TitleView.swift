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
        }
        do {
            let fresh = try await AuthManager.shared.detail(ref)
            detail = fresh
            DiskCache.save(fresh, key: detailKey)
            let r = await AuthManager.shared.roles(ref)
            if !r.isEmpty { roles = r; DiskCache.save(r, key: "roles-\(base)") }
            let s = await AuthManager.shared.similar(ref)
            if !s.isEmpty { similar = s; DiskCache.save(s, key: "similar-\(base)") }
            if let e = await AuthManager.shared.extras(ref) { extras = e; DiskCache.save(e, key: "extras-\(base)") }
            let rel = await AuthManager.shared.related(ref)
            if !rel.isEmpty { related = rel; DiskCache.save(rel, key: "related-\(base)") }
        } catch is CancellationError {
        } catch {
            self.error = detail == nil ? error.localizedDescription : offlineMessage
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
        }
    }
}

enum TitleTab: CaseIterable, Hashable {
    case info, people, links, ratings
    var title: String {
        switch self {
        case .info: return "Инфо"
        case .people: return "Люди"
        case .links: return "Связи"
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
    @State private var allCharacters = false
    @State private var allStaff = false

    var body: some View {
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
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(ref) }
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
            if let message = model.error {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 100)
        .background(alignment: .top) {
            // размытый постер за шапкой
            Color.clear
                .frame(height: 420)
                .overlay { RemoteImage(urls: d.posterCandidates).blur(radius: 50).opacity(0.5) }
                .clipped()
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(edges: .top)
        }
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
            PosterView(urls: d.posterCandidates, radius: 20)
                .frame(width: 122)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
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
        let fromExtras = (model.extras?.genres ?? []).map(\.display)
        let names = fromExtras.isEmpty ? (d.genres ?? []).map(\.display) : fromExtras
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
                        Button(st.title) { Task { await model.setStatus(st) } }
                    }
                    if d.userRate != nil {
                        Divider()
                        Button("Убрать из списка", role: .destructive) { Task { await model.remove() } }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: d.userRate == nil ? "plus" : "checkmark.circle.fill")
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
                    .accessibilityLabel("Обсуждение")
                }
            }

            if let rate = d.userRate {
                let total = (ref.kind == .anime ? d.episodes : d.chapters) ?? 0
                let done = (ref.kind == .anime ? rate.episodes : rate.chapters) ?? 0
                VStack(spacing: 10) {
                    HStack {
                        Text(ref.kind == .anime ? "Эпизоды" : "Главы").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button { Task { await model.changeEpisodes(by: -1) } } label: { Image(systemName: "minus") }
                            .buttonStyle(.glass)
                            .accessibilityLabel("Меньше")
                        Text(total > 0 ? "\(done) / \(total)" : "\(done)")
                            .font(.headline.weight(.heavy))
                            .frame(minWidth: 70)
                        Button { Task { await model.changeEpisodes(by: 1) } } label: { Image(systemName: "plus") }
                            .buttonStyle(.glassProminent)
                            .accessibilityLabel("Больше")
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
        return r
    }

    private func wideFacts(_ d: MediaDetail) -> [(String, String)] {
        let e = model.extras
        var r: [(String, String)] = []
        if let dates = datesText(d) { r.append(("Даты", dates)) }
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
        if ref.kind == .anime {
            if let f = e?.fansubbers, !f.isEmpty { r.append(("Субтитры", f.joined(separator: ", "))) }
            if let f = e?.fandubbers, !f.isEmpty { r.append(("Озвучка", f.joined(separator: ", "))) }
        }
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
            externalLinks
        }
    }

    @ViewBuilder
    private var externalLinks: some View {
        let links = (model.extras?.externalLinks ?? []).compactMap { l -> (String, URL)? in
            guard let k = l.kind, let u = l.url, let url = URL(string: u) else { return nil }
            return (SiteLabels.linkTitle(k), url)
        }
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Ссылки")
                FlowLayout(spacing: 8) {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                        Link(destination: link.1) {
                            Label(link.0, systemImage: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .glassEffect(.regular, in: .capsule)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func screenshotsRow(_ d: MediaDetail) -> some View {
        let shots = (d.screenshots ?? []).filter { $0.previewURL != nil }
        if !shots.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Кадры")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(shots.enumerated()), id: \.offset) { _, shot in
                            Color(UIColor.tertiarySystemFill)
                                .frame(width: 250, height: 141)
                                .overlay { RemoteImage(urls: [shot.previewURL, shot.originalURL].compactMap { $0 }) }
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)
            }
        }
    }

    // MARK: Вкладка «Люди»

    private func personCell(_ p: CastPerson, subtitle: String?) -> some View {
        HStack(spacing: 10) {
            Color(UIColor.tertiarySystemFill)
                .frame(width: 54, height: 54)
                .overlay { RemoteImage(urls: p.imageURLs) }
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var peopleTab: some View {
        let chars = model.roles.filter { $0.character != nil }
        let staff = model.roles.filter { $0.person != nil }
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        VStack(alignment: .leading, spacing: 18) {
            if chars.isEmpty && staff.isEmpty {
                Text("Данных о персонажах и создателях пока нет").font(.footnote).foregroundStyle(.secondary)
            }
            if !chars.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Персонажи")
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(allCharacters ? chars : Array(chars.prefix(8))) { role in
                            if let c = role.character {
                                NavigationLink { CharacterView(id: c.id) } label: {
                                    personCell(c, subtitle: role.rolesRussian?.joined(separator: ", "))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if chars.count > 8 {
                        Button(allCharacters ? "Свернуть" : "Показать всех (\(chars.count))") {
                            withAnimation { allCharacters.toggle() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            if !staff.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Создатели")
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(allStaff ? staff : Array(staff.prefix(8))) { role in
                            if let p = role.person {
                                NavigationLink { PersonView(id: p.id) } label: {
                                    personCell(p, subtitle: role.rolesRussian?.joined(separator: ", "))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if staff.count > 8 {
                        Button(allStaff ? "Свернуть" : "Показать всех (\(staff.count))") {
                            withAnimation { allStaff.toggle() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: Вкладка «Связи»

    @ViewBuilder
    private var linksTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.related.isEmpty && model.similar.isEmpty {
                Text("Связанных и похожих тайтлов пока нет").font(.footnote).foregroundStyle(.secondary)
            }
            if !model.related.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Связанное")
                    ForEach(model.related.prefix(30)) { item in
                        NavigationLink {
                            TitleView(ref: item.ref)
                        } label: {
                            HStack(spacing: 12) {
                                PosterView(urls: item.media.thumbCandidates, radius: 10)
                                    .frame(width: 46, height: 66)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.relation).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                                    Text(item.media.title).font(.subheadline.weight(.semibold))
                                        .multilineTextAlignment(.leading).lineLimit(2)
                                    if let k = item.media.kind { Text(kindTitle(k)).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            MediaRow(title: "Похожее", items: model.similar, kind: ref.kind)
                .padding(.horizontal, -20)
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
