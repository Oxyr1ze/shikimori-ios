import SwiftUI

/// Картинка с запасными адресами: если первый не загрузился, пробуем следующий.
struct RemoteImage: View {
    let urls: [URL]
    @State private var index = 0

    var body: some View {
        if index < urls.count {
            AsyncImage(url: urls[index]) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else if phase.error != nil {
                    Color.clear.onAppear { index += 1 }
                } else {
                    Color.clear
                }
            }
            .id(index)
        } else {
            Color.clear
        }
    }
}

/// Постер: серая подложка, поверх загружается настоящая картинка.
struct PosterView: View {
    let urls: [URL]
    var radius: CGFloat = 20

    var body: some View {
        Color(UIColor.tertiarySystemFill)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay { RemoteImage(urls: urls) }
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
                .frame(width: width)
            Text(media.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)
        }
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
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            NavigationLink(value: MediaRef(id: item.id, kind: kind)) {
                                MediaCard(media: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
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
