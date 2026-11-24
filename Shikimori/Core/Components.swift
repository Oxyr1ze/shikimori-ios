import SwiftUI

/// Постер: сначала красивый градиент, поверх загружается настоящая картинка.
struct PosterView: View {
    let url: URL?
    let seed: Int
    var radius: CGFloat = 20

    var body: some View {
        let colors = Theme.posterGradients[abs(seed) % Theme.posterGradients.count]
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                ZStack {
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let url {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
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
            PosterView(url: media.thumbURL, seed: media.id)
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
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 20)
    }
}
