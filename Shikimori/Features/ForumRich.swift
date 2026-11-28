import SwiftUI

// MARK: Рецензия (тема форума с привязанной рецензией)

/// Название оценки по десятибалльной шкале, как на сайте.
func scoreWord(_ score: Int) -> String {
    switch score {
    case 10: return "Эпик вин"
    case 9: return "Великолепно"
    case 8: return "Отлично"
    case 7: return "Хорошо"
    case 6: return "Нормально"
    case 5: return "Более-менее"
    case 4: return "Плохо"
    case 3: return "Ужасно"
    case 2: return "Отвратительно"
    case 1: return "Хуже некуда"
    default: return ""
    }
}

/// Пять звёзд из десятибалльной оценки (половинки как на сайте).
struct StarsView: View {
    let score: Int
    var size: CGFloat = 17

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: symbol(i))
                    .font(.system(size: size))
                    .foregroundStyle(score > i * 2 ? Theme.accent : Color.secondary.opacity(0.35))
            }
        }
    }

    private func symbol(_ i: Int) -> String {
        if score >= (i + 1) * 2 { return "star.fill" }
        if score == i * 2 + 1 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// Блок с оценками рецензии, голосами и переходом к тайтлу.
struct CritiqueHeader: View {
    let topic: Topic
    @State private var posters: [URL] = []

    private var c: TopicLinked? { topic.linked }
    private var target: TopicTarget? { c?.target }

    private struct Line: Identifiable {
        let id: String
        let title: String
        let score: Int
        var bold = false
    }

    private var lines: [Line] {
        guard let c else { return [] }
        let isAnime = target?.kind == .anime
        var list: [Line] = []
        func add(_ id: String, _ title: String, _ v: Int?, bold: Bool = false) {
            if let v, v > 0 { list.append(Line(id: id, title: title, score: min(v, 10), bold: bold)) }
        }
        add("story", "Сюжет", c.storyline)
        add("chars", "Персонажи", c.characters)
        add("anim", "Рисовка", c.animation)
        if isAnime { add("music", "Звуковой ряд", c.music) }
        add("overall", "Итоговая оценка", c.overall, bold: true)
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let target, let kind = target.kind, let id = target.id {
                NavigationLink {
                    TitleView(ref: MediaRef(id: id, kind: kind))
                } label: {
                    HStack(spacing: 12) {
                        Color(UIColor.tertiarySystemFill)
                            .frame(width: 52, height: 76)
                            .overlay { RemoteImage(urls: posters.isEmpty ? target.imageURLs : posters, placeholder: "film", maxPixel: 300) }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Рецензия на \(kind == .anime ? "аниме" : kind == .manga ? "мангу" : "ранобэ")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                            Text(target.title).font(.headline).multilineTextAlignment(.leading)
                            if let sub = target.subtitle {
                                Text(sub).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .task(id: id) {
                    let found = await AuthManager.shared.fetchPosters(ids: [id], kind: kind)
                    if let p = found[id] {
                        posters = [p.original, p.main, p.preview].compactMap { $0 }.compactMap { URL(string: $0.hasPrefix("http") ? $0 : ShikiConfig.host + $0) }
                    }
                }
            }

            if let up = c?.votesFor, let total = c?.votesCount, total > 0 {
                HStack(spacing: 10) {
                    voteChip("hand.thumbsup.fill", "\(up)", .green)
                    voteChip("hand.thumbsdown.fill", "\(max(total - up, 0))", Theme.accent)
                    Spacer()
                }
            }

            if !lines.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                        if i > 0 { Divider().padding(.leading, 16) }
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(line.title)
                                    .font(line.bold ? .subheadline.weight(.bold) : .subheadline)
                                    .foregroundStyle(line.bold ? Color.primary : Color.secondary)
                                StarsView(score: line.score, size: line.bold ? 20 : 16)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(line.score)")
                                    .font(.system(size: line.bold ? 34 : 26, weight: .bold, design: .rounded))
                                    .foregroundStyle(line.bold ? Theme.accent : Color.primary)
                                Text(scoreWord(line.score).uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func voteChip(_ icon: String, _ text: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: Коллекция (темa форума с коллекцией)

struct CollectionEntry: Identifiable, Hashable {
    enum Kind: String { case anime = "animes", manga = "mangas", ranobe, character = "characters", person = "people" }
    let kind: Kind
    let itemID: Int
    let title: String
    let imageURL: URL?
    var id: String { "\(kind.rawValue)-\(itemID)" }
}

struct CollectionGroup: Identifiable {
    let id: Int
    let title: String?
    let entries: [CollectionEntry]
}

struct ParsedCollection {
    var descriptionHTML = ""
    var groups: [CollectionGroup] = []
    var total: Int { groups.reduce(0) { $0 + $1.entries.count } }
}

/// Разбор HTML коллекции: сайт отдаёт его в поле html_body темы (partial collections/_collection).
enum CollectionParser {
    static func looksLikeCollection(_ html: String?) -> Bool {
        (html ?? "").contains("collection-groups")
    }

    static func parse(_ html: String) -> ParsedCollection {
        var result = ParsedCollection()
        var body = html
        if let r = html.range(of: "collection-groups") {
            let before = html[..<r.lowerBound]
            if let lt = before.range(of: "<", options: .backwards) {
                result.descriptionHTML = String(before[..<lt.lowerBound])
                body = String(html[lt.lowerBound...])
            }
        }
        let pattern = "<div[^>]*class=[\"'][^\"']*subheadline[^\"']*[\"'][^>]*>(.*?)</div>|<article[^>]*b-catalog_entry[^>]*>(.*?)</article>"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return result }
        let ns = body as NSString
        var title: String?
        var current: [CollectionEntry] = []
        func flush() {
            if !current.isEmpty {
                result.groups.append(CollectionGroup(id: result.groups.count, title: title, entries: current))
                current = []
            }
        }
        for m in re.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            if m.range(at: 1).location != NSNotFound {
                flush()
                let t = clean(ns.substring(with: m.range(at: 1)))
                title = t.isEmpty ? nil : t
            } else if m.range(at: 2).location != NSNotFound, let e = entry(ns.substring(with: m.range(at: 2))) {
                current.append(e)
            }
        }
        flush()
        return result
    }

    private static func entry(_ s: String) -> CollectionEntry? {
        guard let link = captures(#"href=["'][^"']*/(animes|mangas|ranobe|characters|people)/[a-zA-Z]*(\d+)[^"']*["']"#, in: s),
              link.count == 3, let kind = CollectionEntry.Kind(rawValue: link[1]), let id = Int(link[2]) else { return nil }

        // Картинка: первый <img> с настоящим адресом (заглушки «missing» пропускаем)
        var image: URL?
        if let imgRe = try? NSRegularExpression(pattern: "<img[^>]*>", options: [.caseInsensitive]) {
            let ns = s as NSString
            for m in imgRe.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                let tag = ns.substring(with: m.range)
                if let c = captures(#"\ssrc=["']([^"']+)["']"#, in: tag), c.count == 2,
                   !c[1].contains("missing"), !c[1].hasPrefix("data:") {
                    image = absolute(c[1])
                    break
                }
            }
        }

        var name = ""
        for cls in ["name-ru", "name-en"] where name.isEmpty {
            if let c = captures("class=[\"'][^\"']*\(cls)[^\"']*[\"'][^>]*>(.*?)</", in: s), c.count == 2 {
                name = clean(c[1])
            }
        }
        if name.isEmpty, let c = captures(#"alt=["']([^"']*)["']"#, in: s), c.count == 2 { name = clean(c[1]) }
        if name.isEmpty, let c = captures(#"class=["'][^"']*title[^"']*["'][^>]*>(.*?)</span>"#, in: s), c.count == 2 { name = clean(c[1]) }
        return CollectionEntry(kind: kind, itemID: id, title: name, imageURL: image)
    }

    private static func absolute(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        if path.hasPrefix("//") { return URL(string: "https:" + path) }
        return URL(string: ShikiConfig.host + path)
    }

    private static func captures(_ pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) else { return nil }
        let ns = s as NSString
        return (0..<m.numberOfRanges).map { i in
            m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i))
        }
    }

    private static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (a, b) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Группы коллекции: заголовок группы и сетка карточек, каждая открывает свою страницу.
struct CollectionGroupsView: View {
    let collection: ParsedCollection
    private let cols = [GridItem(.flexible(), spacing: 12, alignment: .top),
                        GridItem(.flexible(), spacing: 12, alignment: .top),
                        GridItem(.flexible(), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(collection.groups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    if let title = group.title {
                        HStack(alignment: .firstTextBaseline) {
                            Text(title).font(.title3.weight(.bold))
                            Text("\(group.entries.count)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    LazyVGrid(columns: cols, spacing: 16) {
                        ForEach(group.entries) { e in
                            NavigationLink { destination(e) } label: { cell(e) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ e: CollectionEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color(UIColor.tertiarySystemFill)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { RemoteImage(urls: e.imageURL.map { [$0] } ?? [], placeholder: e.kind == .person || e.kind == .character ? "person.fill" : "film", maxPixel: 360) }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(e.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func destination(_ e: CollectionEntry) -> some View {
        switch e.kind {
        case .character: CharacterView(id: e.itemID)
        case .person: PersonView(id: e.itemID)
        case .anime: TitleView(ref: MediaRef(id: e.itemID, kind: .anime))
        case .manga: TitleView(ref: MediaRef(id: e.itemID, kind: .manga))
        case .ranobe: TitleView(ref: MediaRef(id: e.itemID, kind: .ranobe))
        }
    }
}
