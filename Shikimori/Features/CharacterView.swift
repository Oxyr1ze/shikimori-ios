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
                .overlay { RemoteImage(urls: person.imageURLs) }
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

// MARK: Персонаж

@MainActor
final class CharacterModel: ObservableObject {
    @Published var detail: CharacterDetail?
    @Published var description: [CBlock] = []
    @Published var error: String?

    func load(id: Int) async {
        error = nil
        do {
            var d = try await AuthManager.shared.character(id: id)
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
                    HStack(alignment: .bottom, spacing: 16) {
                        PosterView(urls: d.posterURLs, radius: 22).frame(width: 128)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(d.title).font(.title2.weight(.heavy))
                                .fixedSize(horizontal: false, vertical: true)
                            if let n = d.name, n != d.title {
                                Text(n).font(.footnote).foregroundStyle(.secondary)
                            }
                            if let j = d.japanese, !j.isEmpty {
                                Text(j).font(.footnote).foregroundStyle(.secondary)
                            }
                            if let a = d.altname, !a.isEmpty {
                                Text(a).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    if !model.description.isEmpty {
                        CommentBlocksView(blocks: model.description)
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
            var d = try await AuthManager.shared.person(id: id)
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

struct PersonView: View {
    let id: Int
    @StateObject private var model = PersonModel()

    private func voiced(_ d: PersonDetail) -> [CastPerson] {
        var seen = Set<Int>()
        var result: [CastPerson] = []
        for group in d.roles ?? [] {
            for c in group.characters ?? [] where seen.insert(c.id).inserted { result.append(c) }
        }
        return result
    }

    var body: some View {
        ScrollView {
            if let d = model.detail {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .bottom, spacing: 16) {
                        PosterView(urls: d.posterURLs, radius: 22).frame(width: 128)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(d.title).font(.title2.weight(.heavy))
                                .fixedSize(horizontal: false, vertical: true)
                            if let n = d.name, n != d.title {
                                Text(n).font(.footnote).foregroundStyle(.secondary)
                            }
                            if let j = d.japanese, !j.isEmpty {
                                Text(j).font(.footnote).foregroundStyle(.secondary)
                            }
                            if let t = d.jobTitle, !t.isEmpty {
                                Text(t).font(.footnote.weight(.semibold))
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    let chars = voiced(d)
                    if !chars.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Роли (персонажи)").font(.title3.weight(.bold))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(chars.prefix(40), id: \.id) { c in
                                        NavigationLink { CharacterView(id: c.id) } label: { CastAvatar(person: c) }
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    let works = d.works ?? []
                    if !works.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Работы").font(.title3.weight(.bold))
                            ForEach(Array(works.prefix(60).enumerated()), id: \.offset) { _, w in
                                if let m = w.anime ?? w.manga {
                                    NavigationLink {
                                        TitleView(ref: MediaRef(id: m.id, kind: w.anime != nil ? .anime : (m.isRanobe ? .ranobe : .manga)))
                                    } label: {
                                        workRow(m, role: w.role)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
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

    private func workRow(_ m: Media, role: String?) -> some View {
        HStack(spacing: 12) {
            PosterView(urls: m.thumbCandidates, radius: 10).frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.title).font(.subheadline.weight(.bold)).multilineTextAlignment(.leading)
                if let role, !role.isEmpty {
                    Text(role).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
