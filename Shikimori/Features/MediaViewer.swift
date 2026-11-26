import SwiftUI

/// Что открыть в полноэкранном просмотрщике картинок.
struct ViewerState: Identifiable {
    let id = UUID()
    let images: [[URL]]
    var index: Int
}

/// Кнопка закрытия в том же стиле, что и системная кнопка «назад».
struct ViewerCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .tint(.white)
        .accessibilityLabel("Закрыть")
    }
}

final class LayoutScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// Прокрутка и увеличение картинки как в «Фото»: щипок, перемещение в любую сторону, двойное касание.
struct ZoomScrollView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = LayoutScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.bouncesZoom = true
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never

        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true
        scroll.addSubview(iv)
        context.coordinator.imageView = iv
        context.coordinator.scroll = scroll
        scroll.onLayout = { [weak coordinator = context.coordinator] in coordinator?.layoutImage() }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(tap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        context.coordinator.layoutImage()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scroll: UIScrollView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { center() }

        func layoutImage() {
            guard let scroll, let iv = imageView, scroll.bounds.width > 0 else { return }
            if scroll.zoomScale == 1 {
                iv.frame = scroll.bounds
                scroll.contentSize = scroll.bounds.size
            }
            center()
        }

        private func center() {
            guard let scroll, let iv = imageView else { return }
            let bw = scroll.bounds.width, bh = scroll.bounds.height
            var f = iv.frame
            f.origin.x = f.width < bw ? (bw - f.width) / 2 : 0
            f.origin.y = f.height < bh ? (bh - f.height) / 2 : 0
            iv.frame = f
        }

        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let scroll, let iv = imageView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = g.location(in: iv)
                let scale: CGFloat = 3
                let w = scroll.bounds.width / scale
                let h = scroll.bounds.height / scale
                let rect = CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h)
                scroll.zoom(to: rect, animated: true)
            }
        }
    }
}

/// Одна картинка в просмотрщике.
struct ZoomableImage: View {
    let urls: [URL]
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ZoomScrollView(image: image)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: urls) {
            for u in urls {
                if let img = await ImageCache.fetch(u) { image = img; return }
            }
        }
    }
}

/// Полноэкранный просмотр картинок: листание влево-вправо, увеличение, закрытие крестиком.
struct ImageViewer: View {
    let images: [[URL]]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(images.indices, id: \.self) { i in
                    ZoomableImage(urls: images[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            HStack {
                if images.count > 1 {
                    Text("\(index + 1) / \(images.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .glassEffect(.regular, in: .capsule)
                }
                Spacer()
                ViewerCloseButton { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}

/// Все кадры тайтла сеткой.
struct ScreenshotsPage: View {
    let title: String
    let shots: [Screenshot]
    @State private var viewer: ViewerState?
    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var allImages: [[URL]] {
        shots.map { [$0.originalURL, $0.previewURL].compactMap { $0 } }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(Array(shots.enumerated()), id: \.offset) { i, shot in
                    Button {
                        viewer = ViewerState(images: allImages, index: i)
                    } label: {
                        Color(UIColor.tertiarySystemFill)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .overlay { RemoteImage(urls: [shot.previewURL, shot.originalURL].compactMap { $0 }) }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(AppBackground())
        .navigationTitle("Кадры: \(title)")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewer) { ImageViewer(images: $0.images, index: $0.index) }
    }
}

/// Карточка видео: превью, кнопка play, название.
struct VideoCard: View {
    let video: VideoItem
    var width: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.black
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay { if let t = video.thumb { RemoteImage(urls: [t]) } }
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.body)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(video.kindTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(video.name ?? "")
                .font(.footnote)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width)
    }
}

/// Все видео тайтла: вкладки по группам (трейлеры, опенинги и эндинги, анонсы серий, …).
struct VideosPage: View {
    let title: String
    let videos: [VideoItem]
    @State private var playing: VideoItem?
    @State private var selected: VideoGroup?
    private let cols = [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]

    private var groups: [VideoGroup] {
        VideoGroup.allCases.filter { g in videos.contains { $0.group == g } }
    }
    private var shown: [VideoItem] {
        let list = videos.byImportance
        guard let g = selected else { return list }
        return list.filter { $0.group == g }
    }
    private func count(_ g: VideoGroup?) -> Int {
        g == nil ? videos.count : videos.filter { $0.group == g }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if groups.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("Все", nil)
                            ForEach(groups) { g in chip(g.title, g) }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, -20)
                }
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(shown) { v in
                        Button { playing = v } label: { VideoCard(video: v) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(AppBackground())
        .navigationTitle("Видео: \(title)")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playing) { v in
            if let player = v.playerURL, let link = v.pageURL ?? v.playerURL {
                VideoPlayerScreen(player: player, link: link)
            }
        }
    }

    private func chip(_ text: String, _ g: VideoGroup?) -> some View {
        let on = selected == g
        return Button { selected = g } label: {
            Text("\(text) \(count(g))")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? Theme.accent : Color.clear, in: Capsule())
                .glassEffect(on ? .regular.tint(Theme.accent) : .regular, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
