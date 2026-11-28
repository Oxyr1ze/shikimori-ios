import SwiftUI

/// Количество комментариев для кнопок «Комментарии» (запоминается на время работы приложения).
@MainActor
final class CommentCounts {
    static let shared = CommentCounts()
    private var topics: [Int: String] = [:]
    private var users: [Int: String] = [:]

    /// У темы счётчик есть в самой теме.
    func text(topicID: Int) async -> String? {
        if let c = topics[topicID] { return c }
        guard let t = try? await AuthManager.shared.topic(id: topicID), let n = t.commentsCount else { return nil }
        topics[topicID] = String(n)
        return String(n)
    }

    /// У профиля готового счётчика нет: считаем по первой странице комментариев (до 50, дальше «50+»).
    func text(userID: Int) async -> String? {
        if let c = users[userID] { return c }
        let limit = 50
        let list: [Comment]
        do {
            list = try await AuthManager.shared.comments(topicID: userID, type: "User", page: 1, limit: limit)
        } catch ShikiError.http(404, _) {
            users[userID] = "0"
            return "0"
        } catch {
            return nil
        }
        let text = list.count > limit ? "\(limit)+" : String(list.count)
        users[userID] = text
        return text
    }
}

/// Единый вид кнопки «Комментарии»: значок, подпись, число и стрелка.
struct CommentsCardLabel: View {
    var count: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(Theme.accent)
            Text(count.map { "Комментарии (\($0))" } ?? "Комментарии")
                .font(.body.weight(.semibold))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Кнопка «Комментарии» с числом, которое подгружается само (по теме или по профилю).
struct CountedCommentsLabel: View {
    var topicID: Int? = nil
    var userID: Int? = nil
    @State private var count: String?

    var body: some View {
        CommentsCardLabel(count: count)
            .task(id: "\(topicID ?? 0)-\(userID ?? 0)") {
                if let t = topicID { count = await CommentCounts.shared.text(topicID: t) }
                else if let u = userID { count = await CommentCounts.shared.text(userID: u) }
            }
    }
}

/// Только число (для маленькой кнопки со значком на странице тайтла).
struct CommentsCountText: View {
    let topicID: Int
    @State private var count: String?

    var body: some View {
        Group {
            if let count { Text(count).font(.subheadline.weight(.semibold)) }
        }
        .task(id: topicID) { count = await CommentCounts.shared.text(topicID: topicID) }
    }
}

/// Названия коллекций: у темы-коллекции сайт в API отдаёт только «Обсуждение коллекции», настоящее имя берём со страницы коллекции.
final class CollectionNames: ObservableObject, @unchecked Sendable {
    static let shared = CollectionNames()
    @Published var version = 0
    private var names: [Int: String]
    private var inflight = Set<Int>()
    private let lock = NSLock()
    private let key = "collection-names-v1"

    init() { names = DiskCache.load([Int: String].self, key: "collection-names-v1") ?? [:] }

    func cached(_ id: Int?) -> String? {
        guard let id else { return nil }
        lock.lock(); defer { lock.unlock() }
        return names[id]
    }

    func ensure(_ id: Int) async {
        lock.lock()
        let known = names[id] != nil || inflight.contains(id)
        if !known { inflight.insert(id) }
        lock.unlock()
        if known { return }
        let name = await Self.fetchName(id)
        lock.lock()
        inflight.remove(id)
        if let name { names[id] = name }
        let snapshot = names
        lock.unlock()
        if name != nil {
            DiskCache.save(snapshot, key: key)
            await MainActor.run { self.version += 1 }
        }
    }

    private static func fetchName(_ id: Int) async -> String? {
        guard let url = URL(string: ShikiConfig.host + "/collections/\(id)") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(ShikiConfig.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { return nil }
        func first(_ pattern: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
                  let m = re.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
                  m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
            return (html as NSString).substring(with: m.range(at: 1))
        }
        func clean(_ s: String) -> String {
            var t = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            for (a, b) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
                t = t.replacingOccurrences(of: a, with: b)
            }
            return t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Заголовок страницы коллекции: <h1> внутри шапки, запасной вариант — og:title
        let candidates: [String?] = [
            first("<header[^>]*class=[\"'][^\"']*head[^\"']*[\"'][^>]*>.*?<h1[^>]*>(.*?)</h1>"),
            first("property=[\"']og:title[\"'][^>]*content=[\"']([^\"']+)[\"']"),
            first("content=[\"']([^\"']+)[\"'][^>]*property=[\"']og:title[\"']")
        ]
        for c in candidates {
            if let c {
                let t = clean(c)
                if !t.isEmpty, t != "Shikimori", !t.lowercased().hasPrefix("коллекции") { return t }
            }
        }
        return nil
    }
}
