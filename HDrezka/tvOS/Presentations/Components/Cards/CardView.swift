//
//  CardView.swift
//  HDrezka
//
//  Created by Alex Hafros on 20.01.2026.
//

import SwiftUI

struct CardView: View {
    private let movie: MovieSimple
    @Environment(AppState.self) private var appState

    init(movie: MovieSimple) {
        self.movie = movie
    }

    var body: some View {
        Button {
            appState.presentedDetailsMovie = movie
        } label: {
            GeometryReader { geometry in
                TVPosterViewRepresentable(movie: movie, size: geometry.size)
                    .overlay(alignment: .topLeading) {
                        if let info = movie.info {
                            TVDarkBadge(text: info.title)
                                .padding(14)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let cat = movie.cat {
                            TVCategoryBadge(category: cat)
                                .padding(14)
                        }
                    }
            }
            .aspectRatio(1.72, contentMode: .fit)
            .contentShape(.rect(cornerRadius: 28))
        }
        .buttonStyle(OnPressButtonStyle { _ in })
        .focusEffectDisabled()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(movie.name ?? String(localized: "key.open")))
        .accessibilityHint(Text("key.open"))
    }
}

struct TVDarkBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(Color.black.opacity(0.70), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.10))
            }
    }
}

struct TVAccentBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.12))
            }
    }
}

struct TVCategoryBadge: View {
    let category: MovieSimple.Cat

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: category.icon)
                .font(.caption.weight(.bold))

            Text(category.title)
                .font(.caption.weight(.semibold))

            if let rating = category.rating {
                Text(verbatim: String(format: "%.1f", rating))
                    .font(.caption.weight(.bold))
            }
        }
        .lineLimit(1)
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(category.color.opacity(0.94), in: Capsule())
    }
}
