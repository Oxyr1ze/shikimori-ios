import SwiftUI

@MainActor
final class TitleModel: ObservableObject {
    var ref = MediaRef(id: 0, kind: .anime)
    @Published var detail: MediaDetail?
    @Published var error: String?
    @Published var busy = false
    @Published var roles: [Role] = []
    @Published var similar: [Media] = []

    func load(_ ref: MediaRef) async {
        self.ref = ref
        error = nil
        do {
            detail = try await AuthManager.shared.detail(ref)
            roles = await AuthManager.shared.roles(ref)
            similar = await AuthManager.shared.similar(ref)
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
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

            if let genres = d.genres, !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(genres.enumerated()), id: \.offset) { _, g in
                            Text(g.display)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .glassEffect(.regular, in: .capsule)
                        }
                    }
                }
            }

            stats(d)

            listCard(d)

            if let text = d.plainDescription {
                Text(text).font(.body)
            }

            infoCard(d)
            castRow
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

    @ViewBuilder
    private func infoCard(_ d: MediaDetail) -> some View {
        let lines = d.infoLines
        if !lines.isEmpty {
            VStack(spacing: 10) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top) {
                        Text(line.0).foregroundStyle(.secondary)
                        Spacer(minLength: 16)
                        Text(line.1).multilineTextAlignment(.trailing)
                    }
                    .font(.subheadline)
                }
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                                VStack(spacing: 6) {
                                    Color(UIColor.tertiarySystemFill)
                                        .frame(width: 76, height: 76)
                                        .overlay { RemoteImage(urls: c.imageURLs) }
                                        .clipShape(Circle())
                                    Text(c.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 84)
                                }
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
