//
//  TVPosterViewRepresentable.swift
//  HDrezka
//
//  Created by Alex Hafros on 31.01.2026.
//

import Kingfisher
import SwiftUI

struct TVPosterViewRepresentable: View {
    let movie: MovieSimple
    let size: CGSize

    @Environment(\.isFocused) private var isFocused

    private var title: String {
        movie.name ?? ""
    }

    private var subtitle: String {
        if let details = movie.details, !details.isEmpty {
            return details
        }

        return movie.info?.title ?? ""
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            posterArtwork

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.08), Color.black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom,
            )
            .clipShape(.rect(cornerRadius: 28))

            VStack(alignment: .leading, spacing: 6) {
                if !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                }
            }
            .padding(18)
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black.opacity(0.22), in: .rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(isFocused ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
        }
        .shadow(color: .black.opacity(isFocused ? 0.42 : 0.18), radius: isFocused ? 28 : 16, y: isFocused ? 20 : 10)
        .scaleEffect(isFocused ? 1.035 : 1)
        .animation(.easeOut(duration: 0.18), value: isFocused)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private var posterArtwork: some View {
        if let poster = movie.poster,
           let url = URL(string: poster)
        {
            KFImage
                .url(url)
                .setProcessor(DownsamplingImageProcessor(size: size))
                .placeholder {
                    placeholder
                }
                .resizable()
                .cancelOnDisappear(true)
                .fade(duration: 0.2)
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipShape(.rect(cornerRadius: 28))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: 28))
    }
}
