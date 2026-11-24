import SwiftUI

@MainActor
final class TitleModel: ObservableObject {
    @Published var detail: MediaDetail?
    @Published var error: String?
    @Published var busy = false

    func load(_ ref: MediaRef) async {
        error = nil
        do {
            detail = try await AuthManager.shared.detail(ref)
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
                detail?.userRate = try await AuthManager.shared.createRate(animeID: d.id, status: status.rawValue)
            }
        }
    }

    func changeEpisodes(by delta: Int) async {
        guard let rate = detail?.userRate else { return }
        var next = max(0, (rate.episodes ?? 0) + delta)
        if let total = detail?.episodes, total > 0 { next = min(next, total) }
        await run { detail?.userRate = try await AuthManager.shared.updateRate(id: rate.id, episodes: next) }
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
                PosterView(url: d.posterURL, seed: d.id, radius: 22)
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

            if ref.kind == .anime {
                listCard(d)
            } else {
                Text("Редактирование списков манги и ранобэ добавим следующим шагом.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let text = d.plainDescription {
                Text(text).font(.body)
            }

            if let message = model.error {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(20)
        .padding(.bottom, 100)
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
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
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
                    Text("Эпизоды").font(.body.weight(.semibold))
                    Spacer()
                    Button { Task { await model.changeEpisodes(by: -1) } } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Меньше")
                    let total = d.episodes ?? 0
                    Text(total > 0 ? "\(rate.episodes ?? 0) / \(total)" : "\(rate.episodes ?? 0)")
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
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .disabled(model.busy)
    }
}
