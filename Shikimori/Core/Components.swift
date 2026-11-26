import SwiftUI
import CryptoKit

/// Хранение картинок на телефоне: однажды загруженный постер потом открывается и без интернета.
enum ImageCache {
    private static let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        return c
    }()

    private static let folder: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func file(_ url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(hash)
    }

    static func cached(_ url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        if let m = memory.object(forKey: key) { return m }
        guard let data = try? Data(contentsOf: file(url)), let img = UIImage(data: data) else { return nil }
        memory.setObject(img, forKey: key)
        return img
    }

    static func fetch(_ url: URL) async -> UIImage? {
        if let c = cached(url) { return c }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let img = UIImage(data: data) else { return nil }
        try? data.write(to: file(url), options: .atomic)
        memory.setObject(img, forKey: url.absoluteString as NSString)
        return img
    }
}

/// Картинка с запасными адресами: если первый не загрузился, пробуем следующий.
struct RemoteImage: View {
    let urls: [URL]
    /// Значок, если картинки нет нигде (постер, человек).
    var placeholder: String? = nil
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed, let placeholder {
                ImagePlaceholder(symbol: placeholder)
            } else {
                Color.clear
            }
        }
        .task(id: urls) {
            failed = false
            for u in urls {
                let real: URL?
                if ExternalImages.isFallback(u) { real = await ExternalImages.resolve(u) } else { real = u }
                guard let real else { continue }
                if let img = await ImageCache.fetch(real) {
                    image = img
                    return
                }
            }
            failed = true
        }
    }
}

/// Красивая заглушка, когда постера нет ни на Shikimori, ни на MyAnimeList.
struct ImagePlaceholder: View {
    let symbol: String
    var body: some View {
        GeometryReader { g in
            ZStack {
                LinearGradient(colors: [Theme.accent.opacity(0.35), Color(UIColor.tertiarySystemFill)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: symbol)
                    .font(.system(size: min(g.size.width, g.size.height) * 0.34, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

/// Постер: серая подложка, поверх загружается настоящая картинка.
struct PosterView: View {
    let urls: [URL]
    var radius: CGFloat = 20
    var placeholder: String = "film"

    var body: some View {
        Color(UIColor.tertiarySystemFill)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay { RemoteImage(urls: urls, placeholder: placeholder) }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Маленькая плашка с оценкой поверх постера.
struct ScoreBadge: View {
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow)
            Text(text).font(.caption.weight(.bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Карточка произведения для горизонтальных лент.
struct MediaCard: View {
    let media: Media
    var width: CGFloat = 118

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterView(urls: media.thumbCandidates)
                .frame(width: width, height: width * 1.5)
                .clipped()
            Text(media.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)
        }
        .frame(width: width, alignment: .topLeading)
    }
}

struct MediaRow: View {
    let title: String
    let items: [Media]
    var kind: MediaKind = .anime

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            NavigationLink {
                                TitleView(ref: MediaRef(id: item.id, kind: kind))
                            } label: {
                                MediaCard(media: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let retry {
                Button("Повторить", action: retry).buttonStyle(.glass)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
    }
}


/// Раскладка «в строку с переносом»: плашки жанров, ссылки.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing; x = 0; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing; x = bounds.minX; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}


/// Цвет статуса в списке (одинаковый в профиле и на странице тайтла).
func listStatusColor(_ status: String) -> Color {
    switch status {
    case "watching": return .green
    case "planned": return .blue
    case "completed": return .purple
    case "on_hold": return .orange
    case "dropped": return .red
    default: return .gray
    }
}

/// «1 234» → «1,2 тыс.»
func shortCount(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1f млн", Double(n) / 1_000_000).replacingOccurrences(of: ".", with: ",") }
    if n >= 10_000 { return "\(n / 1000) тыс." }
    if n >= 1000 { return String(format: "%.1f тыс.", Double(n) / 1000).replacingOccurrences(of: ".", with: ",") }
    return "\(n)"
}

/// Цветная полоса из частей. Ширины считаются с учётом промежутков, поэтому полоса не вылезает за края.
struct SegmentedBar: View {
    let segments: [(color: Color, count: Int)]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let items = segments.filter { $0.count > 0 }
            let total = max(1, items.reduce(0) { $0 + $1.count })
            let spacing: CGFloat = 2
            let avail = max(0, geo.size.width - spacing * CGFloat(max(0, items.count - 1)))
            let raw = items.map { max(3, avail * CGFloat($0.count) / CGFloat(total)) }
            let sum = max(1, raw.reduce(0, +))
            let scale = sum > avail ? avail / sum : 1
            HStack(spacing: spacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    item.color.frame(width: raw[i] * scale)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}
