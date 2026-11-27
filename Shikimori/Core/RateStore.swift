import SwiftUI

/// Статусы тайтлов в списках пользователя: нужны, чтобы везде показывать отметку «в моём списке».
@MainActor
final class RateStore: ObservableObject {
    static let shared = RateStore()

    /// Ключ: «a-123» для аниме, «m-456» для манги и ранобэ. Значение: watching, planned, completed…
    @Published private(set) var statuses: [String: String] = [:]
    private var loading = false

    static func key(_ kind: MediaKind, _ id: Int) -> String { (kind == .anime ? "a-" : "m-") + String(id) }

    func status(_ key: String?) -> String? { key.flatMap { statuses[$0] } }

    func set(_ key: String, status: String?) {
        statuses[key] = status
        persist()
    }

    private var cacheKey: String { DiskCache.userKey("rate-statuses") }

    private func persist() { DiskCache.save(statuses, key: cacheKey) }

    func restore() {
        if let saved = DiskCache.load([String: String].self, key: cacheKey) { statuses = saved }
    }

    /// Загружает все списки пользователя (аниме, манга, ранобэ) постранично.
    func refresh() async {
        guard !loading, let user = AuthManager.shared.user else { return }
        loading = true
        defer { loading = false }
        async let a = fetchAll("/api/users/\(user.id)/anime_rates", prefix: "a-")
        async let m = fetchAll("/api/users/\(user.id)/manga_rates", prefix: "m-")
        let (anime, manga) = await (a, m)
        guard anime != nil || manga != nil else { return }   // нет сети: оставляем сохранённое
        var result: [String: String] = [:]
        if let anime { result.merge(anime) { $1 } } else { result.merge(statuses.filter { $0.key.hasPrefix("a-") }) { $1 } }
        if let manga { result.merge(manga) { $1 } } else { result.merge(statuses.filter { $0.key.hasPrefix("m-") }) { $1 } }
        statuses = result
        persist()
    }

    private func fetchAll(_ path: String, prefix: String) async -> [String: String]? {
        var result: [String: String] = [:]
        var seen = Set<Int>()
        for page in 1...40 {
            let q = [URLQueryItem(name: "limit", value: "500"), URLQueryItem(name: "page", value: String(page))]
            guard let list: [RateEntry] = try? await AuthManager.shared.get(path, query: q) else {
                return page == 1 ? nil : result
            }
            let fresh = list.filter { seen.insert($0.id).inserted }
            if fresh.isEmpty { break }
            for e in fresh {
                if let m = e.media, let s = e.status { result[prefix + String(m.id)] = s }
            }
        }
        return result
    }
}

/// Значок статуса списка: простые белые иконки на стекле, без цвета.
func rateGlyph(_ raw: String) -> String {
    switch raw {
    case "watching": return "play.fill"
    case "planned": return "bookmark.fill"
    case "completed": return "checkmark"
    case "on_hold": return "pause.fill"
    case "dropped": return "xmark"
    case "rewatching": return "arrow.triangle.2.circlepath"
    default: return "circle.fill"
    }
}

/// Маленькая отметка статуса в правом нижнем углу постера (Liquid Glass).
struct RateBadge: View {
    let key: String?
    @ObservedObject private var store = RateStore.shared

    var body: some View {
        if let raw = store.status(key) {
            GeometryReader { g in
                let d = max(20, min(30, g.size.width * 0.22))
                Image(systemName: rateGlyph(raw))
                    .font(.system(size: d * 0.46, weight: .bold))
                    .foregroundStyle(raw == "planned" ? Color(red: 0.09, green: 0.38, blue: 0.58) : .white)
                    .frame(width: d, height: d)
                    .background(Circle().fill(raw == "planned" ? Color.white.opacity(0.92) : listStatusColor(raw).opacity(0.95)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                    .padding(max(5, d * 0.28))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .allowsHitTesting(false)
        }
    }
}

extension Media {
    /// Ключ для RateStore: тип угадывается по виду тайтла.
    var rateKey: String {
        let mangaKinds: Set<String> = ["manga", "manhwa", "manhua", "one_shot", "doujin", "light_novel", "novel"]
        let isManga = (kind.map { mangaKinds.contains($0) } ?? false) || (episodes == nil && (chapters != nil || volumes != nil))
        return (isManga ? "m-" : "a-") + String(id)
    }

    /// «TV Сериал · 2024»
    var subtitleText: String? {
        let parts = [kind.map(kindTitle), yearText].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
