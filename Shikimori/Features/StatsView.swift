import SwiftUI

/// Статистика списков пользователя: статусы и распределение оценок.
struct StatsView: View {
    let stats: UserStats
    @State private var kind: MediaKind = .anime

    private var key: String { kind == .anime ? "anime" : "manga" }

    private func title(_ status: String) -> String {
        RateStatus(rawValue: status)?.title(for: kind) ?? status
    }

    private func color(_ status: String) -> Color {
        listStatusColor(status)
    }

    private var statuses: [StatusStat] {
        (stats.fullStatuses?[key] ?? []).filter { $0.size > 0 }
    }

    private var total: Int { statuses.reduce(0) { $0 + $1.size } }

    private var scores: [StatEntry] {
        (stats.scores?[key] ?? []).filter { (Int($0.name) ?? 0) > 0 }
    }

    private var averageScore: Double? {
        let votes = scores.reduce(0) { $0 + $1.value }
        guard votes > 0 else { return nil }
        let sum = scores.reduce(0) { $0 + (Int($1.name) ?? 0) * $1.value }
        return Double(sum) / Double(votes)
    }

    var body: some View {
        let hasAnime = !(stats.fullStatuses?["anime"] ?? []).allSatisfy { $0.size == 0 }
        let hasManga = !(stats.fullStatuses?["manga"] ?? []).allSatisfy { $0.size == 0 }
        if hasAnime || hasManga {
            VStack(alignment: .leading, spacing: 14) {
                Text("Статистика").font(.title3.weight(.bold))

                Picker("Раздел", selection: $kind) {
                    Text("Аниме").tag(MediaKind.anime)
                    Text("Манга и ранобэ").tag(MediaKind.manga)
                }
                .pickerStyle(.segmented)

                if total == 0 {
                    Text("В этом разделе пока пусто").font(.footnote).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            summary("\(total)", "в списках")
                            Divider().frame(height: 32)
                            summary(averageScore.map { String(format: "%.2f", $0) } ?? "—", "средняя оценка")
                        }

                        SegmentedBar(segments: statuses.map { (color: color($0.name), count: $0.size) })

                        VStack(spacing: 8) {
                            ForEach(statuses, id: \.name) { s in
                                HStack {
                                    Circle().fill(color(s.name)).frame(width: 10, height: 10)
                                    Text(title(s.name)).font(.subheadline)
                                    Spacer()
                                    Text("\(s.size)").font(.subheadline.weight(.semibold))
                                }
                            }
                        }

                        if !scores.isEmpty { scoreBars }
                    }
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summary(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.heavy))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var scoreBars: some View {
        let byScore = Dictionary(uniqueKeysWithValues: scores.compactMap { e -> (Int, Int)? in
            guard let n = Int(e.name) else { return nil }
            return (n, e.value)
        })
        let maxValue = max(1, byScore.values.max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Оценки").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            ForEach((1...10).reversed(), id: \.self) { n in
                let v = byScore[n] ?? 0
                HStack(spacing: 8) {
                    Text("\(n)").font(.caption.weight(.semibold)).frame(width: 18, alignment: .trailing)
                    GeometryReader { geo in
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: v == 0 ? 0 : max(4, geo.size.width * CGFloat(v) / CGFloat(maxValue)))
                    }
                    .frame(height: 8)
                    Text("\(v)").font(.caption).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}
