import SwiftUI
import ImageIO

/// Блок комментария: текст, цитата, картинка или спойлер.
enum CRun {
    case text(AttributedString)
    case smiley(URL)
}

enum CBlockKind {
    case text([CRun])
    case quote(author: String?, blocks: [CBlock])
    case image(URL)
    case spoiler(title: String, blocks: [CBlock])
    case video(thumb: URL?, link: URL, player: URL?, hosting: String)
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
    var pill = false
}

struct CommentRenderer {
    var blocks: [CBlock] = []
    var current = AttributedString()
    var pending: [CRun] = []
    var spoilerCount = 0

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

    private mutating func commitCurrent() {
        if !current.characters.isEmpty { pending.append(.text(current)) }
        current = AttributedString()
    }

    mutating func flush() {
        commitCurrent()
        guard !pending.isEmpty else { return }
        var runs = pending
        pending = []
        if case .text(var first) = runs[0] {
            while let f = first.characters.first, f.isNewline || f == " " { first.characters.removeFirst() }
            runs[0] = .text(first)
        }
        if case .text(var last) = runs[runs.count - 1] {
            while let l = last.characters.last, l.isNewline || l == " " { last.characters.removeLast() }
            runs[runs.count - 1] = .text(last)
        }
        runs = runs.filter { if case .text(let t) = $0 { return !t.characters.isEmpty } else { return true } }
        if !runs.isEmpty { blocks.append(CBlock(kind: .text(runs))) }
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
        if st.pill { a.backgroundColor = Color(UIColor.tertiarySystemFill) }
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
        // подпись с размером картинки («1224x827») не нужна
        if n.hasClass("marker") || n.hasClass("image-sizes") { return }
        if n.hasClass("b-mention") {
            var s = st
            s.bold = true
            s.color = Theme.accent
            s.noImages = true
            walkChildren(n, s)
            return
        }
        if n.hasClass("b-user16") {
            var s = st
            s.bold = true
            s.noImages = true
            s.pill = true
            appendText(" ", st)
            walkChildren(n, s)
            appendText(" ", st)
            return
        }
        switch n.tag {
        case "br":
            appendText("\n", st)
        case "img":
            if st.noImages { return }
            let src = n.attrs["src"] ?? ""
            if n.hasClass("smiley") || src.contains("/smileys/") || n.hasClass("emoji") {
                if let url = absolute(src) {
                    commitCurrent()
                    pending.append(.smiley(url))
                }
                return
            }
            if src.contains("/system/users/") { return }
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
            } else if n.hasClass("b-spoiler_block") {
                let titleNode = n.children.first { $0.tag == "span" }
                let title = titleNode?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let content = n.children.first { $0.tag == "div" }
                var sub = CommentRenderer()
                for c in (content?.children ?? []) { sub.walk(c, CommentStyle(), imageHref: nil) }
                sub.flush()
                flush()
                blocks.append(CBlock(kind: .spoiler(title: title.isEmpty ? "спойлер" : title, blocks: sub.blocks)))
            } else if n.hasClass("b-spoiler") {
                let title = n.findFirst { $0.tag == "label" }?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? "спойлер"
                let content = n.findFirst { $0.hasClass("inner") } ?? n
                var sub = CommentRenderer()
                for c in content.children where c.tag != "label" { sub.walk(c, CommentStyle(), imageHref: nil) }
                sub.flush()
                flush()
                blocks.append(CBlock(kind: .spoiler(title: title.isEmpty ? "спойлер" : title, blocks: sub.blocks)))
            } else if n.hasClass("b-replies") {
                return
            } else if n.hasClass("b-video") {
                let linkNode = n.findFirst { $0.tag == "a" && $0.hasClass("video-link") }
                    ?? n.findFirst { $0.tag == "a" }
                guard let linkNode, let link = absolute(linkNode.attrs["href"]) else { return }
                let thumb = absolute(linkNode.findFirst { $0.tag == "img" }?.attrs["src"])
                let player = absolute(linkNode.attrs["data-href"])
                let hosting = n.findFirst { $0.hasClass("marker") }?.plainText
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                flush()
                blocks.append(CBlock(kind: .video(thumb: thumb, link: link, player: player, hosting: hosting)))
            } else {
                flush()
                walkChildren(n, st)
                flush()
            }
        case "h1", "h2", "h3", "h4", "h5":
            flush()
            var s = st; s.bold = true
            walkChildren(n, s)
            flush()
        case "ul", "ol":
            flush()
            walkChildren(n, st)
            flush()
        case "li":
            flush()
            appendText("•  ", st)
            walkChildren(n, st)
            flush()
        case "span":
            if n.hasClass("b-spoiler_inline") {
                spoilerCount += 1
                var s = st
                s.link = URL(string: "shikispoiler://\(spoilerCount)")
                s.noImages = true
                walkChildren(n, s)
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
        return t.isEmpty ? [] : [CBlock(kind: .text([.text(AttributedString(t))]))]
    }
}

struct CommentBlocksView: View {
    let blocks: [CBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block.kind {
                case .text(let runs):
                    CommentRichText(runs: runs)
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
                case .video(let thumb, let link, let player, let hosting):
                    CommentVideo(thumb: thumb, link: link, player: player, hosting: hosting)
                case .spoiler(let title, let inner):
                    SpoilerBlockView(title: title, blocks: inner)
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
            ImageViewer(images: [[url]], index: 0)
        }
    }
}


/// Смайлик Shikimori: GIF, разобранный на кадры (уменьшены до высоты строки текста).
struct SmileyAnim: @unchecked Sendable {
    let frames: [CGImage]
    let starts: [Double]
    let total: Double
    let still: UIImage        // первый кадр
    let placeholder: UIImage  // прозрачная картинка того же размера: занимает место в тексте

    var isAnimated: Bool { frames.count > 1 && total > 0 }

    func frame(at t: Double) -> CGImage {
        guard isAnimated else { return frames[0] }
        let m = t.truncatingRemainder(dividingBy: total)
        var i = 0
        for (k, st) in starts.enumerated() where st <= m { i = k }
        return frames[i]
    }

    static func decode(_ data: Data) -> SmileyAnim? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return nil }
        let height: CGFloat = 28
        let scale: CGFloat = 3
        var frames: [CGImage] = []
        var starts: [Double] = []
        var total = 0.0
        for i in 0..<count {
            guard let probe = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any],
                  let w = probe[kCGImagePropertyPixelWidth] as? CGFloat,
                  let h = probe[kCGImagePropertyPixelHeight] as? CGFloat, h > 0 else { continue }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: height * scale * max(1, w / h)
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, i, opts as CFDictionary) else { continue }
            var delay = 0.1
            if let gif = probe[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                let d = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                    ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
                delay = d < 0.02 ? 0.1 : d
            }
            frames.append(cg)
            starts.append(total)
            total += delay
        }
        guard let first = frames.first else { return nil }
        let size = CGSize(width: CGFloat(first.width) / scale, height: CGFloat(first.height) / scale)
        let still = UIImage(cgImage: first, scale: scale, orientation: .up)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale
        let placeholder = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in }
        return SmileyAnim(frames: frames, starts: starts, total: total, still: still, placeholder: placeholder)
    }
}

/// Загрузка и хранение смайликов (GIF разбираются на кадры один раз).
@MainActor
final class SmileyStore: ObservableObject {
    static let shared = SmileyStore()
    @Published private(set) var anims: [URL: SmileyAnim] = [:]
    private var loading: Set<URL> = []

    static func url(for code: String) -> URL? {
        guard let enc = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: ShikiConfig.host + "/images/smileys/" + enc + ".gif")
    }

    func load(_ url: URL) async {
        if anims[url] != nil || loading.contains(url) { return }
        loading.insert(url)
        defer { loading.remove(url) }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        let anim = await Task.detached(priority: .utility) { SmileyAnim.decode(data) }.value
        if let anim { anims[url] = anim }
    }
}

/// Метка в тексте: на этом месте рисуется кадр анимированного смайлика.
struct SmileyKey: TextAttribute { let url: URL }

/// Рисует текст как обычно, а вместо прозрачных заглушек подставляет текущий кадр GIF.
struct SmileyRenderer: TextRenderer {
    var anims: [URL: SmileyAnim]
    var time: Double

    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if let key = run[SmileyKey.self], let a = anims[key.url] {
                    ctx.draw(Image(decorative: a.frame(at: time), scale: 3), in: run.typographicBounds.rect)
                } else {
                    ctx.draw(run)
                }
            }
        }
    }
}

private struct CommentFontKey: EnvironmentKey { static let defaultValue: Font = .subheadline }
private struct CommentLineSpacingKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var commentFont: Font {
        get { self[CommentFontKey.self] }
        set { self[CommentFontKey.self] = newValue }
    }
    var commentLineSpacing: CGFloat {
        get { self[CommentLineSpacingKey.self] }
        set { self[CommentLineSpacingKey.self] = newValue }
    }
}

struct CommentRichText: View {
    let runs: [CRun]
    @Environment(\.commentFont) private var commentFont
    @Environment(\.commentLineSpacing) private var lineSpacing
    @ObservedObject private var store = SmileyStore.shared
    @State private var revealed: Set<String> = []

    /// Скрытый спойлер показывается плашкой «спойлер», после нажатия — настоящим текстом.
    private func applySpoilers(_ a: AttributedString) -> AttributedString {
        var out = AttributedString()
        var lastHidden: String?
        for run in a.runs {
            let piece = AttributedString(a[run.range])
            if let link = run.link, link.scheme == "shikispoiler" {
                let id = link.absoluteString
                var p: AttributedString
                if revealed.contains(id) {
                    lastHidden = nil
                    p = piece
                    p.link = nil
                } else {
                    // один спойлер может состоять из нескольких кусков — плашка нужна одна
                    if lastHidden == id { continue }
                    lastHidden = id
                    p = AttributedString(" спойлер ")
                    p.link = link
                    p.inlinePresentationIntent = .stronglyEmphasized
                }
                p.backgroundColor = Color(UIColor.tertiarySystemFill)
                out.append(p)
            } else {
                lastHidden = nil
                out.append(piece)
            }
        }
        return out
    }

    private var smileyURLs: [URL] {
        runs.compactMap { if case .smiley(let u) = $0 { return u } else { return nil } }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasAnimated: Bool {
        smileyURLs.contains { store.anims[$0]?.isAnimated == true }
    }

    var body: some View {
        let animate = hasAnimated && !reduceMotion
        var result = Text("")
        for run in runs {
            switch run {
            case .text(let a):
                result = result + Text(applySpoilers(a))
            case .smiley(let url):
                if let a = store.anims[url] {
                    if animate && a.isAnimated {
                        result = result + Text(Image(uiImage: a.placeholder)).customAttribute(SmileyKey(url: url))
                    } else {
                        result = result + Text(Image(uiImage: a.still))
                    }
                }
            }
        }
        let styled = result
            .font(commentFont)
            .lineSpacing(lineSpacing)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "shikispoiler" {
                    withAnimation { _ = revealed.insert(url.absoluteString) }
                    return .handled
                }
                return .systemAction
            })
            .task(id: smileyURLs) {
                for u in smileyURLs { await store.load(u) }
            }
        return Group {
            if animate {
                TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { tl in
                    styled.textRenderer(SmileyRenderer(anims: store.anims, time: tl.date.timeIntervalSinceReferenceDate))
                }
            } else {
                styled
            }
        }
    }
}


/// Видео из комментария или темы: превью с кнопкой, по нажатию открывается плеер.
struct CommentVideo: View {
    let thumb: URL?
    let link: URL
    let player: URL?
    let hosting: String
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            ZStack {
                Color.black
                if let thumb {
                    AsyncImage(url: thumb) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                    }
                }
                Image(systemName: "play.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(.black.opacity(0.55), in: Circle())
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Label(hosting.isEmpty ? "видео" : hosting, systemImage: "play.rectangle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.65), in: Capsule())
                    }
                }
                .padding(10)
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $open) {
            VideoPlayerScreen(player: player ?? link, link: link)
        }
    }
}

struct VideoPlayerScreen: View {
    let player: URL
    let link: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            EmbeddedVideoView(url: player)
                .padding(.top, 56)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(12)
                }
                .buttonStyle(.glass)
                Spacer()
                Link(destination: link) {
                    Label("Открыть в браузере", systemImage: "safari")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}

import WebKit

/// Встроенный плеер: страница видео открывается в веб-окне прямо в приложении.
struct EmbeddedVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        let host = url.host ?? ""
        if host.contains("youtube.com") || host.contains("youtube-nocookie.com") {
            // Встроенный плеер YouTube требует, чтобы его открывали со страницы сайта
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var items = comps?.queryItems ?? []
            items.append(URLQueryItem(name: "playsinline", value: "1"))
            items.append(URLQueryItem(name: "autoplay", value: "1"))
            comps?.queryItems = items
            let src = comps?.url?.absoluteString ?? url.absoluteString
            let html = """
            <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
            <style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style>
            </head><body><iframe src="\(src)" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe></body></html>
            """
            web.loadHTMLString(html, baseURL: URL(string: ShikiConfig.host))
        } else {
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}


/// Раскрывающийся блок, как на сайте: плашка с названием и кнопкой «показать» / «скрыть».
struct SpoilerBlockView: View {
    let title: String
    let blocks: [CBlock]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(open ? "скрыть" : "показать")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(open ? Color(UIColor.label) : Color(UIColor.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(open ? Color(UIColor.systemBackground) : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                CommentBlocksView(blocks: blocks)
                    .transition(.opacity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
