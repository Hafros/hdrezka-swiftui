import Kingfisher
import SwiftUI

struct WatchingLaterCardView: View {
    private let movie: MovieWatchLater
    private let isFocused: Bool

    @Environment(AppState.self) private var appState

    init(movie: MovieWatchLater, isFocused: Bool = false) {
        self.movie = movie
        self.isFocused = isFocused
    }

    var body: some View {
        Button {
            appState.presentedDetailsMovie = MovieSimple(movieId: movie.watchLaterId, name: movie.name, poster: movie.cover)
        } label: {
            cardContent
                .aspectRatio(1.72, contentMode: .fit)
                .contentShape(.rect(cornerRadius: 28))
        }
        .buttonStyle(OnPressButtonStyle { _ in })
        .focusEffectDisabled()
        .opacity(movie.watched ? 0.6 : 1)
        .disabled(movie.watchLaterId.id == nil)
    }

    private var cardContent: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                posterImage(size: geometry.size)
                gradientOverlay
                metadata
            }
            .overlay(alignment: .topLeading) {
                badges
            }
            .background(Color.black.opacity(0.22), in: .rect(cornerRadius: 28))
            .overlay {
                focusBorder
            }
            .shadow(color: .black.opacity(isFocused ? 0.42 : 0.18), radius: isFocused ? 28 : 16, y: isFocused ? 20 : 10)
            .scaleEffect(isFocused ? 1.035 : 1)
            .animation(.easeOut(duration: 0.18), value: isFocused)
        }
    }

    @ViewBuilder
    private func posterImage(size: CGSize) -> some View {
        if let url = URL(string: movie.cover) {
            KFImage
                .url(url)
                .setProcessor(DownsamplingImageProcessor(size: size))
                .placeholder {
                    Color.gray.shimmering()
                }
                .resizable()
                .cancelOnDisappear(true)
                .fade(duration: 0.2)
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipShape(.rect(cornerRadius: 28))
        }
    }

    private var gradientOverlay: some View {
        LinearGradient(
            colors: [.clear, Color.black.opacity(0.16), Color.black.opacity(0.90)],
            startPoint: .top,
            endPoint: .bottom,
        )
        .clipShape(.rect(cornerRadius: 28))
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(movie.name)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(movie.details.trimmingCharacters(in: CharacterSet(charactersIn: "()")))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(2)

            Text(movie.date.replacingOccurrences(of: "-", with: ".").firstLetterUppercased)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
        }
        .padding(18)
    }

    private var badges: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !movie.watchingInfo.isEmpty {
                TVDarkBadge(text: movie.watchingInfo)
            }

            if let buttonText = movie.buttonText, !buttonText.isEmpty, !movie.watched {
                TVAccentBadge(text: buttonText.firstLetterUppercased)
            }
        }
        .padding(14)
    }

    private var focusBorder: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(isFocused ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
    }
}
