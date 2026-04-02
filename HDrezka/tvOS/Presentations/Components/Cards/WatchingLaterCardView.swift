import Kingfisher
import SwiftUI

struct WatchingLaterCardView: View {
    private let movie: MovieWatchLater

    init(movie: MovieWatchLater) {
        self.movie = movie
    }

    var body: some View {
        NavigationLink(value: Destinations.details(MovieSimple(movieId: movie.watchLaterId, name: movie.name, poster: movie.cover))) {
            VStack(alignment: .leading, spacing: 10) {
                KFImage
                    .url(URL(string: movie.cover))
                    .placeholder {
                        Color.gray.shimmering()
                    }
                    .resizable()
                    .loadTransition(.blurReplace, animation: .easeInOut)
                    .cancelOnDisappear(true)
                    .retry(NetworkRetryStrategy())
                    .imageFill(2 / 3)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            if !movie.watchingInfo.isEmpty {
                                Text(movie.watchingInfo)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(.ultraThickMaterial, in: .rect(cornerRadius: 8))
                            }

                            if let buttonText = movie.buttonText, !buttonText.isEmpty, !movie.watched {
                                Text(buttonText.firstLetterUppercased())
                                    .font(.caption.weight(.medium))
                                    .lineLimit(2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor, in: .rect(cornerRadius: 8))
                            }
                        }
                        .padding(10)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(movie.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)

                    Text(movie.details.trimmingCharacters(in: CharacterSet(charactersIn: "()")))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(movie.date.replacingOccurrences(of: "-", with: ".").firstLetterUppercased())
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.borderless)
        .opacity(movie.watched ? 0.6 : 1)
        .disabled(movie.watchLaterId.id == nil)
    }
}
