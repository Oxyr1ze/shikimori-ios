import SwiftUI

/// Блок комментария: текст, цитата, картинка или спойлер.
enum CBlockKind {
    case text(AttributedString)
    case quote(author: String?, blocks: [CBlock])
    case image(URL)
    case spoiler(title: String, blocks: [CBlock])
}

struct CBlock: Identifiable {
    let id = UUID()
    let kind: CBlockKind
}

/// Простой узел разобранного HTML.
final class HNode {
    let tag: String
    var attrs: [String: String]
    var children: [HNode] = []
    var text: String?

    init(tag: String, attrs: [String: String] = [:], text: String? = nil) {
        self.tag = tag
        self.attrs = attrs
        self.text = text
    }

    func hasClass(_ c: String) -> Bool {
        (attrs["class"] ?? "").split(separator: " ").contains { $0 == c }
    }

    var plainText: String {
        if let text { return text }
        return children.map(\.plainText).joined()
    }

    func findFirst(_ test: (HNode) -> Bool) -> HNode? {
        for c in children {
            if test(c) { return c }
            if let f = c.findFirst(test) { return f }
        }
        return nil
    }

    func contains(_ other: HNode) -> Bool {
        for c in children {
            if c === other || c.contains(other) { return true }
        }
        return false
    }
}

enum HTMLMini {
    private static let voidTags: Set<String> = ["br", "img", "hr", "input", "meta", "link", "wbr"]

    static func decode(_ s: String) -> String {
        var t = s
        guard t.contains("&") else { return t }
        let named = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&laquo;": "«", "&raquo;": "»", "&hellip;": "…", "&mdash;": "—", "&ndash;": "–"]
        for (k, v) in named { t = t.replacingOccurrences(of: k, with: v) }
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = t as NSString
            var result = ""
            var last = 0
            for m in regex.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let isHex = ns.substring(with: m.range(at: 1)) == "x"
                let num = ns.substring(with: m.range(at: 2))
                if let code = UInt32(num, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    result += String(Character(scalar))
                }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            t = result
        }
        return t.replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func parseAttrs(_ s: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "([a-zA-Z_:][-\\w:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')") else { return result }
        let ns = s as NSString
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: m.range(at: 1)).lowercased()
            let r = m.range(at: 2).location != NSNotFound ? m.range(at: 2) : m.range(at: 3)
            if r.location != NSNotFound { result[key] = decode(ns.substring(with: r)) }
        }
        return result
    }

    static func parse(_ html: String) -> HNode {
        let root = HNode(tag: "root")
        var stack = [root]
        let chars = Array(html)
        var i = 0
        var buffer = ""

        func flushText() {
            if !buffer.isEmpty {
                stack.last?.children.append(HNode(tag: "#text", text: buffer))
                buffer = ""
            }
        }

        while i < chars.count {
            let ch = chars[i]
            if ch == "<" {
                if i + 3 < chars.count, String(chars[i..<i + 4]) == "<!--" {
                    var j = i + 4
                    while j + 2 < chars.count, String(chars[j..<j + 3]) != "-->" { j += 1 }
                    i = min(chars.count, j + 3)
                    continue
                }
                var j = i + 1
                var quote: Character?
                while j < chars.count {
                    let c = chars[j]
                    if let q = quote { if c == q { quote = nil } }
                    else if c == "\"" || c == "'" { quote = c }
                    else if c == ">" { break }
                    j += 1
                }
                guard j < chars.count else { buffer.append(ch); i += 1; continue }
                let inner = String(chars[i + 1..<j])
                i = j + 1
                flushText()
                if inner.hasPrefix("/") {
                    let name = inner.dropFirst().trimmingCharacters(in: .whitespaces).lowercased()
                    if let idx = stack.lastIndex(where: { $0.tag == name }), idx > 0 {
                        stack.removeSubrange(idx...)
                    }
                } else {
                    let selfClosing = inner.hasSuffix("/")
                    let body = selfClosing ? String(inner.dropLast()) : inner
                    let name = String(body.prefix { !$0.isWhitespace }).lowercased()
                    guard !name.isEmpty else { continue }
                    let attrs = parseAttrs(String(body.dropFirst(name.count)))
                    let node = HNode(tag: name, attrs: attrs)
                    stack.last?.children.append(node)
                    if !selfClosing && !voidTags.contains(name) { stack.append(node) }
                }
            } else {
                buffer.append(ch)
                i += 1
            }
        }
        flushText()
        return root
    }
}

struct CommentStyle {
    var bold = false
    var italic = false
    var underline = false
    var color: Color?
    var link: URL?
    var noImages = false
}

struct CommentRenderer {
    var blocks: [CBlock] = []
    var current = AttributedString()

    static func render(html: String) -> [CBlock] {
        var r = CommentRenderer()
        let root = HTMLMini.parse(html)
        for c in root.children { r.walk(c, CommentStyle(), imageHref: nil) }
        r.flush()
        return r.blocks
    }

    private func absolute(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("//") { return URL(string: "https:" + path) }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: ShikiConfig.host + path)
    }

    mutating func flush() {
        while let f = current.characters.first, f.isNewline || f == " " { current.characters.removeFirst() }
        while let l = current.characters.last, l.isNewline || l == " " { current.characters.removeLast() }
        if !current.characters.isEmpty { blocks.append(CBlock(kind: .text(current))) }
        current = AttributedString()
    }

    private mutating func appendText(_ s: String, _ st: CommentStyle) {
        var a = AttributedString(s)
        var intent: InlinePresentationIntent = []
        if st.bold { intent.insert(.stronglyEmphasized) }
        if st.italic { intent.insert(.emphasized) }
        if !intent.isEmpty { a.inlinePresentationIntent = intent }
        if st.underline { a.underlineStyle = .single }
        if let c = st.color { a.foregroundColor = c }
        if let l = st.link { a.link = l }
        current.append(a)
    }

    private mutating func walkChildren(_ n: HNode, _ st: CommentStyle, imageHref: String? = nil) {
        for c in n.children { walk(c, st, imageHref: imageHref) }
    }

    mutating func walk(_ n: HNode, _ st: CommentStyle, imageHref: String?) {
        if n.tag == "#text" {
            let t = HTMLMini.decode(n.text ?? "").replacingOccurrences(of: "\n", with: " ")
            appendText(t, st)
            return
        }
        switch n.tag {
        case "br":
            appendText("\n", st)
        case "img":
            if st.noImages { return }
            let src = n.attrs["src"] ?? ""
            if n.hasClass("smiley") || src.contains("/smileys/") || n.hasClass("emoji") { return }
            if let url = absolute(imageHref ?? n.attrs["data-src"] ?? src) {
                flush()
                blocks.append(CBlock(kind: .image(url)))
            }
        case "b", "strong":
            var s = st; s.bold = true
            walkChildren(n, s)
        case "i", "em":
            var s = st; s.italic = true
            walkChildren(n, s)
        case "u":
            var s = st; s.underline = true
            walkChildren(n, s)
        case "a":
            if n.hasClass("b-mention") || n.hasClass("b-user16") {
                var s = st
                s.bold = true
                s.color = Theme.accent
                s.noImages = true
                walkChildren(n, s)
            } else if n.hasClass("b-image") || (n.findFirst { $0.tag == "img" } != nil
                        && n.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                walkChildren(n, st, imageHref: n.attrs["href"])
            } else {
                var s = st
                s.color = Theme.accent
                if let href = n.attrs["href"], let url = absolute(href) { s.link = url }
                walkChildren(n, s)
            }
        case "div", "p", "blockquote":
            if n.hasClass("b-quote") || n.tag == "blockquote" {
                var inner = n.children
                var author: String?
                if let user = n.findFirst({ $0.hasClass("b-user16") }) {
                    author = user.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                    inner.removeAll { $0 === user || ($0.hasClass("quoteable") && $0.contains(user)) }
                } else if let q = n.children.first(where: { $0.hasClass("quoteable") }) {
                    author = q.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                    inner.removeAll { $0 === q }
                }
                var sub = CommentRenderer()
                for c in inner { sub.walk(c, CommentStyle(), imageHref: nil) }
                sub.flush()
                flush()
                blocks.append(CBlock(kind: .quote(author: (author?.isEmpty ?? true) ? nil : author, blocks: sub.blocks)))
            } else if n.hasClass("b-spoiler") {
                let title = n.findFirst { $0.tag == "label" }?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? "спойлер"
                let content = n.findFirst { $0.hasClass("inner") } ?? n
                var sub = CommentRenderer()
                for c in content.children where c.tag != "label" { sub.walk(c, CommentStyle(), imageHref: nil) }
                sub.flush()
                flush()
                blocks.append(CBlock(kind: .spoiler(title: title.isEmpty ? "спойлер" : title, blocks: sub.blocks)))
            } else if n.hasClass("b-video") || n.hasClass("b-replies") {
                return
            } else {
                flush()
                walkChildren(n, st)
                flush()
            }
        case "span":
            if n.hasClass("b-spoiler_inline") {
                appendText("[спойлер]", st)
            } else {
                walkChildren(n, st, imageHref: imageHref)
            }
        case "script", "style", "label":
            return
        default:
            walkChildren(n, st, imageHref: imageHref)
        }
    }
}

extension Comment {
    /// Разбор комментария на блоки; если HTML нет, берём простой текст.
    func makeBlocks() -> [CBlock] {
        if let html = htmlBody, !html.isEmpty {
            let r = CommentRenderer.render(html: html)
            if !r.isEmpty { return r }
        }
        let t = plainBody
        return t.isEmpty ? [] : [CBlock(kind: .text(AttributedString(t)))]
    }
}

struct CommentBlocksView: View {
    let blocks: [CBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block.kind {
                case .text(let a):
                    Text(a)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .quote(let author, let inner):
                    AnyView(
                        HStack(alignment: .top, spacing: 10) {
                            Capsule().fill(Theme.accent).frame(width: 3)
                            VStack(alignment: .leading, spacing: 6) {
                                if let author {
                                    Text(author).font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                                }
                                CommentBlocksView(blocks: inner)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    )
                case .image(let url):
                    CommentImage(url: url)
                case .spoiler(let title, let inner):
                    AnyView(
                        DisclosureGroup {
                            CommentBlocksView(blocks: inner).padding(.top, 6)
                        } label: {
                            Text(title).font(.subheadline.weight(.semibold))
                        }
                        .padding(10)
                        .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    )
                }
            }
        }
    }
}

struct CommentImage: View {
    let url: URL
    @State private var open = false

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                Label("Не удалось загрузить фото", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                ProgressView().frame(height: 80)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 320, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { open = true }
        .fullScreenCover(isPresented: $open) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Button { open = false } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .padding(20)
            }
        }
    }
}
