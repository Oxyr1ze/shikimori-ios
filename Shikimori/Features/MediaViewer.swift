import SwiftUI

/// Что открыть в полноэкранном просмотрщике картинок.
struct ViewerState: Identifiable {
    let id = UUID()
    let images: [[URL]]
    var index: Int
}

/// Одна картинка с увеличением щипком и двойным касанием.
struct ZoomableImage: View {
    let urls: [URL]
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { scale = max(1, base * $0.magnification) }
                            .onEnded { _ in
                                base = scale
                                if scale <= 1 { offset = .zero; lastOffset = .zero }
                            }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                offset = CGSize(width: lastOffset.width + v.translation.width,
                                                height: lastOffset.height + v.translation.height)
                            }
                            .onEnded { _ in lastOffset = offset },
                        including: scale > 1 ? .all : .subviews
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scale = scale > 1 ? 1 : 2.5
                            base = scale
                            offset = .zero
                            lastOffset = .zero
                        }
                    }
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
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).padding(12)
                }
                .buttonStyle(.glass)
                Spacer()
                if images.count > 1 {
                    Text("\(index + 1) / \(images.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                }
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

/// Все видео тайтла сеткой.
struct VideosPage: View {
    let title: String
    let videos: [VideoItem]
    @State private var playing: VideoItem?
    private let cols = [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 14) {
                ForEach(videos) { v in
                    Button { playing = v } label: { VideoCard(video: v) }
                        .buttonStyle(.plain)
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
}
