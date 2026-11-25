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

struct TitleView: View {
    let ref: MediaRef
    @StateObject private var model = TitleModel()

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

    @ViewBuilder
    private func content(_ d: MediaDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 16) {
                PosterView(urls: d.posterCandidates, radius: 22)
                    .frame(width: 128)
                VStack(alignment: .leading, spacing: 6) {
                    Text(d.title)
                        .font(.title2.weight(.heavy))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(d.name)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            stats(d)

            listCard(d)

            if let text = d.plainDescription {
                Text(text).font(.body)
            }

            infoCard(d)
            ratingCard(d)
            linksRow
            relatedSection
            if let topic = d.topicId {
                NavigationLink {
                    CommentsView(topicID: topic, title: d.title)
                } label: {
                    HStack {
                        Label("Обсуждение", systemImage: "bubble.left.and.bubble.right")
                            .font(.body.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            castRow
            staffRow
            screenshotsRow(d)

            if let message = model.error {
                Text(message).font(.footnote).foregroundStyle(.red)
            }

            MediaRow(title: "Похожее", items: model.similar, kind: ref.kind)
                .padding(.horizontal, -20)
        }
        .padding(20)
        .padding(.bottom, 100)
    }

    private func chips(_ items: [String]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                Text(t)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
            }
        }
    }

    private func infoRow(_ label: String, @ViewBuilder _ value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
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

    @ViewBuilder
    private func infoCard(_ d: MediaDetail) -> some View {
        let e = model.extras
        let isAnime = ref.kind == .anime
        let genreList = (e?.genres ?? []).filter { $0.kind == "genre" }.map(\.display)
        let themeList = (e?.genres ?? []).filter { $0.kind == "theme" }.map(\.display)
        let audience = (e?.genres ?? []).filter { $0.kind == "demographic" }.map(\.display)
        let fallbackGenres = (d.genres ?? []).map(\.display)
        VStack(alignment: .leading, spacing: 12) {
            if let k = d.kind, !k.isEmpty { textRow("Тип", kindTitle(k)) }
            if isAnime {
                let total = d.episodes ?? 0
                let aired = d.episodesAired ?? 0
                if total > 0 || aired > 0 {
                    textRow("Эпизоды", total > 0 && d.status == "ongoing" && aired > 0
                            ? "\(aired) из \(total)" : (total > 0 ? "\(total)" : "\(aired)"))
                }
                if let dur = d.duration, dur > 0 { textRow("Длительность эпизода", "\(dur) мин.") }
            } else {
                if let v = d.volumes, v > 0 { textRow("Тома", "\(v)") }
                if let c = d.chapters, c > 0 { textRow("Главы", "\(c)") }
            }
            textRow("Статус", releaseStatusTitle(d.status))
            if let dates = datesText(d) { textRow("Даты", dates) }
            if isAnime, let next = e?.nextEpisodeAt, d.status == "ongoing", let text = nextEpisodeText(next) {
                textRow("Следующий эпизод", text)
            }
            if !genreList.isEmpty {
                infoRow("Жанры") { chips(genreList) }
            } else if e == nil && !fallbackGenres.isEmpty {
                infoRow("Жанры") { chips(fallbackGenres) }
            }
            if !themeList.isEmpty { infoRow("Темы") { chips(themeList) } }
            if !audience.isEmpty { infoRow("Аудитория") { chips(audience) } }
            if isAnime {
                if let r = e?.rating ?? d.rating, let label = SiteLabels.ageRating(r) { textRow("Возрастной рейтинг", label) }
                if let o = e?.origin { textRow("Первоисточник", SiteLabels.origin(o)) }
                let studioNames = (e?.studios ?? []).compactMap(\.name)
                let names = studioNames.isEmpty ? (d.studios ?? []).compactMap(\.name) : studioNames
                if !names.isEmpty { textRow("Студия", names.joined(separator: ", ")) }
            } else if let p = e?.publishers?.compactMap(\.name), !p.isEmpty {
                textRow("Издатель", p.joined(separator: ", "))
            }
            if let l = e?.licensors, !l.isEmpty { textRow("Лицензировано", l.joined(separator: ", ")) }
            if isAnime {
                if let f = e?.fansubbers, !f.isEmpty { textRow("Субтитры", f.joined(separator: ", ")) }
                if let f = e?.fandubbers, !f.isEmpty { textRow("Озвучка", f.joined(separator: ", ")) }
            }
            alternativeNames(d)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
    private func alternativeNames(_ d: MediaDetail) -> some View {
        let unique = alternativeList(d)
        if !unique.isEmpty {
            DisclosureGroup("Альтернативные названия") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(unique, id: \.self) { Text($0).font(.subheadline).textSelection(.enabled) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
            .font(.subheadline)
            .tint(.secondary)
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

    @ViewBuilder
    private func ratingCard(_ d: MediaDetail) -> some View {
        let scores = (model.extras?.scoresStats ?? []).sorted { $0.score > $1.score }
        let statuses = model.extras?.statusesStats ?? []
        if !scores.isEmpty || !statuses.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Оценки и списки").font(.title3.weight(.bold))
                if !scores.isEmpty {
                    let maxCount = max(scores.map(\.count).max() ?? 1, 1)
                    let total = scores.reduce(0) { $0 + $1.count }
                    ForEach(scores, id: \.score) { s in
                        HStack(spacing: 10) {
                            Text("\(s.score)").font(.footnote.weight(.bold)).frame(width: 20, alignment: .trailing)
                            GeometryReader { geo in
                                Capsule().fill(Theme.accent)
                                    .frame(width: max(4, geo.size.width * CGFloat(s.count) / CGFloat(maxCount)))
                            }
                            .frame(height: 8)
                            Text("\(s.count)").font(.caption).foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                    Text("Всего оценок: \(total)").font(.footnote).foregroundStyle(.secondary)
                }
                if !statuses.isEmpty {
                    Divider()
                    ForEach(statuses, id: \.status) { s in
                        textRow(SiteLabels.listStatus(s.status, kind: ref.kind), "\(s.count)")
                    }
                }
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    @ViewBuilder
    private var linksRow: some View {
        let links = (model.extras?.externalLinks ?? []).compactMap { l -> (String, URL)? in
            guard let k = l.kind, let u = l.url, let url = URL(string: u) else { return nil }
            return (SiteLabels.linkTitle(k), url)
        }
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ссылки").font(.title3.weight(.bold))
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
    private var relatedSection: some View {
        if !model.related.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Связанное").font(.title3.weight(.bold))
                ForEach(model.related.prefix(30)) { item in
                    NavigationLink {
                        TitleView(ref: item.ref)
                    } label: {
                        HStack(spacing: 12) {
                            PosterView(urls: item.media.thumbCandidates, radius: 10)
                                .frame(width: 44, height: 64)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.relation).font(.caption).foregroundStyle(Theme.accent)
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
    }

    @ViewBuilder
    private var castRow: some View {
        let list = model.roles.filter { $0.character != nil }.prefix(20)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Персонажи").font(.title3.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(list)) { role in
                            if let c = role.character {
                                NavigationLink { CharacterView(id: c.id) } label: { CastAvatar(person: c) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var staffRow: some View {
        let list = model.roles.filter { $0.person != nil }.prefix(15)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Создатели").font(.title3.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(list)) { role in
                            if let p = role.person {
                                NavigationLink { PersonView(id: p.id) } label: {
                                    CastAvatar(person: p, size: 64, subtitle: role.rolesRussian?.joined(separator: ", "))
                                }
                                .buttonStyle(.plain)
                            }
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
            VStack(alignment: .leading, spacing: 12) {
                Text("Кадры").font(.title3.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(shots.enumerated()), id: \.offset) { _, shot in
                            Color(UIColor.tertiarySystemFill)
                                .frame(width: 240, height: 135)
                                .overlay { RemoteImage(urls: [shot.previewURL, shot.originalURL].compactMap { $0 }) }
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.heavy))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func stats(_ d: MediaDetail) -> some View {
        HStack {
            stat(d.scoreText ?? "—", "Оценка")
            Divider().frame(height: 32)
            if ref.kind == .anime {
                stat((d.episodes ?? 0) > 0 ? "\(d.episodes ?? 0)" : "?", "Эпизодов")
            } else {
                stat((d.chapters ?? 0) > 0 ? "\(d.chapters ?? 0)" : "?", "Глав")
            }
            Divider().frame(height: 32)
            stat(releaseStatusTitle(d.status), "Статус")
        }
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func listCard(_ d: MediaDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Мой список").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(RateStatus.allCases) { s in
                        Button(s.title) { Task { await model.setStatus(s) } }
                    }
                    if d.userRate != nil {
                        Divider()
                        Button("Убрать из списка", role: .destructive) { Task { await model.remove() } }
                    }
                } label: {
                    Text(RateStatus.title(for: d.userRate?.status))
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.glass)
            }

            if let rate = d.userRate {
                HStack {
                    Text(ref.kind == .anime ? "Эпизоды" : "Главы").font(.body.weight(.semibold))
                    Spacer()
                    Button { Task { await model.changeEpisodes(by: -1) } } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Меньше")
                    let total = (ref.kind == .anime ? d.episodes : d.chapters) ?? 0
                    let done = (ref.kind == .anime ? rate.episodes : rate.chapters) ?? 0
                    Text(total > 0 ? "\(done) / \(total)" : "\(done)")
                        .font(.headline.weight(.heavy))
                        .frame(minWidth: 64)
                    Button { Task { await model.changeEpisodes(by: 1) } } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel("Больше")
                }
                HStack {
                    Text("Оценка").font(.body.weight(.semibold))
                    Spacer()
                    Menu {
                        ForEach((1...10).reversed(), id: \.self) { n in
                            Button("\(n)") { Task { await model.setScore(n) } }
                        }
                    } label: {
                        Text((rate.score ?? 0) > 0 ? "\(rate.score ?? 0) / 10" : "Не оценено")
                            .font(.subheadline.weight(.bold))
                    }
                    .buttonStyle(.glass)
                }
            } else {
                Text("Выберите статус, чтобы добавить в список.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .disabled(model.busy)
    }
}
