//
//  HomeView.swift
//  HDrezka
//
//  Created by Alex Hafros on 19.01.2026.
//

import Kingfisher
import SwiftUI

struct HomeView: View {
    private let title = String(localized: "key.home")

    @State private var viewModel = HomeViewModel()
    @Environment(AppState.self) private var appState

    @FocusState private var headerFocus: HeaderFocus?

    enum HeaderFocus: Hashable {
        case featured
        case seeAll(Category.ID)
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = HomeLayoutMetrics(containerWidth: geometry.size.width)

            ZStack {
                HomeBackgroundView()

                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                        if let featuredMovie,
                           let featuredCategoryTitle
                        {
                            HomeFeaturedView(movie: featuredMovie, categoryTitle: featuredCategoryTitle, metrics: metrics) {
                                openDetails(featuredMovie)
                            }
                            .focused($headerFocus, equals: .featured)
                            .defaultFocus($headerFocus, .featured)
                            .padding(.horizontal, metrics.horizontalPadding)
                        }

                        if !categories.isEmpty {
                            ForEach(categories) { category in
                                HomeCategorySection(category: category, metrics: metrics, openMovie: openDetails)
                                    .id(category.id)

                                if category.id != categories.last?.id {
                                    Divider()
                                        .overlay(.white.opacity(0.12))
                                        .padding(.horizontal, metrics.horizontalPadding)
                                }
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, metrics.verticalPadding)
                }
                .scrollIndicators(.visible, axes: .vertical)
                .scrollClipDisabled()
            }
        }
        .overlay {
            if let error = viewModel.state.error {
                ErrorStateView(error) {
                    viewModel.load()
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 36)
            } else if let categories = viewModel.state.data, categories.isEmpty {
                EmptyStateView(String(localized: "key.home.empty")) {
                    viewModel.load()
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 36)
            } else if viewModel.state == .loading {
                LoadingStateView()
                    .padding(.vertical, 18)
                    .padding(.horizontal, 36)
            }
        }
        .navigationTitle(title)
        .transition(.opacity)
        .task {
            guard viewModel.state.data == nil else { return }

            viewModel.load()
        }
    }

    private var categories: [Category] {
        viewModel.state.data ?? []
    }

    private var featuredMovie: MovieSimple? {
        categories.first?.movies.first
    }

    private var featuredCategoryTitle: String? {
        categories.first?.title
    }

    private func openDetails(_ movie: MovieSimple) {
        appState.presentedDetailsMovie = movie
    }
}

private struct HomeLayoutMetrics {
    let containerWidth: CGFloat

    var horizontalPadding: CGFloat {
        containerWidth >= 1600 ? 56 : 36
    }

    var verticalPadding: CGFloat {
        containerWidth >= 1600 ? 30 : 22
    }

    var sectionSpacing: CGFloat {
        containerWidth >= 1600 ? 32 : 24
    }

    var rowSpacing: CGFloat {
        containerWidth >= 1600 ? 24 : 18
    }

    var cardSize: CGSize {
        let width = min(max(containerWidth * 0.23, 300), 420)
        return CGSize(width: width, height: width * 0.58)
    }

    var heroHeight: CGFloat {
        min(max(containerWidth * 0.28, 300), 420)
    }

    var heroPosterWidth: CGFloat {
        min(max(containerWidth * 0.16, 220), 280)
    }

    var heroContentHeight: CGFloat {
        max(heroHeight - 64, 220)
    }

    var heroPosterSize: CGSize {
        let height = min(heroContentHeight, heroPosterWidth * 1.48)
        return CGSize(width: height / 1.48, height: height)
    }

    var heroArtworkSize: CGSize {
        CGSize(width: max(containerWidth - horizontalPadding * 2, heroPosterWidth), height: heroHeight)
    }
}

private struct HomeBackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.07, green: 0.08, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )

            RadialGradient(
                colors: [Color.accentColor.opacity(0.30), .clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: 700,
            )

            RadialGradient(
                colors: [Color.white.opacity(0.08), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 520,
            )
        }
        .ignoresSafeArea()
    }
}

private struct HomeFeaturedView: View {
    let movie: MovieSimple
    let categoryTitle: String
    let metrics: HomeLayoutMetrics
    let openMovie: () -> Void

    private var movieTitle: String {
        movie.name ?? String(localized: "key.open")
    }

    private var movieSubtitle: String {
        let details = [movie.details, movie.info?.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return details.isEmpty ? categoryTitle : details.joined(separator: " • ")
    }

    var body: some View {
        Button(action: openMovie) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.06))

                if let poster = movie.poster,
                   let url = URL(string: poster)
                {
                    KFImage
                        .url(url)
                        .setProcessor(DownsamplingImageProcessor(size: metrics.heroArtworkSize))
                        .placeholder {
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        }
                        .resizable()
                        .cancelOnDisappear(true)
                        .fade(duration: 0.2)
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blur(radius: 8)
                        .overlay {
                            LinearGradient(
                                colors: [Color.black.opacity(0.88), Color.black.opacity(0.38), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing,
                            )
                        }
                        .clipShape(.rect(cornerRadius: 30))
                }

                HStack(alignment: .center, spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(categoryTitle.uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)

                        Text(movieTitle)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .lineLimit(2)

                        Text(movieSubtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)

                        HomeFeaturedMetaRow(movie: movie)

                        Label("key.open", systemImage: "info.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TVPosterViewRepresentable(movie: movie, size: metrics.heroPosterSize)
                        .frame(width: metrics.heroPosterSize.width, height: metrics.heroPosterSize.height)
                        .allowsHitTesting(false)
                }
                .padding(32)
            }
            .frame(height: metrics.heroHeight)
            .clipShape(.rect(cornerRadius: 30))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12))
            }
            .shadow(color: .black.opacity(0.28), radius: 30, y: 18)
        }
        .buttonStyle(OnPressButtonStyle { _ in })
        .focusEffectDisabled()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(movieTitle))
        .accessibilityHint(Text("key.open"))
    }
}

private struct HomeFeaturedMetaRow: View {
    let movie: MovieSimple

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let cat = movie.cat {
                HomePill(text: cat.title, systemImage: cat.icon, tint: cat.color)
            }

            if let info = movie.info {
                HomePill(text: info.title, systemImage: "sparkles.tv", tint: .white.opacity(0.8))
            }
        }
    }
}

private struct HomeCategorySection: View {
    let category: Category
    let metrics: HomeLayoutMetrics
    let openMovie: (MovieSimple) -> Void

    @FocusState private var headerFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text(verbatim: "\(category.movies.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 20)

                NavigationLink(value: Destinations.category(category.category)) {
                    HStack(alignment: .center, spacing: 8) {
                        Text("key.see_all")
                            .font(.headline)

                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.accentColor.opacity(0.88), in: Capsule())
                }
                .buttonStyle(.plain)
                .focused($headerFocus)
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .focusSection()

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: metrics.rowSpacing) {
                    ForEach(category.movies) { movie in
                        Button {
                            openMovie(movie)
                        } label: {
                            TVPosterViewRepresentable(movie: movie, size: metrics.cardSize)
                                .frame(width: metrics.cardSize.width, height: metrics.cardSize.height)
                                .overlay(alignment: .bottomLeading) {
                                    if let info = movie.info {
                                        HomeInfoBadge(text: info.title)
                                            .padding(14)
                                    }
                                }
                        }
                        .buttonStyle(OnPressButtonStyle { _ in })
                        .focusEffectDisabled()
                        .accessibilityLabel(Text(movie.name ?? category.title))
                        .accessibilityHint(Text("key.open"))
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
            .focusSection()
        }
    }
}

private struct HomeInfoBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(Color.black.opacity(0.68), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.10))
            }
    }
}

private struct HomePill: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.18), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(tint.opacity(0.35))
            }
    }
}
