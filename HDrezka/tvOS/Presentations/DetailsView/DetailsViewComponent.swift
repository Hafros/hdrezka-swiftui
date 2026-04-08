//
//  DetailsViewComponent.swift
//  HDrezka
//
//  Created by Alex Hafros on 21.01.2026.
//

import AVFoundation
import AVKit
import Kingfisher
import SwiftUI

struct DetailsViewComponent: View {
    private let details: MovieDetailed
    private let trailerId: String?
    private let topSafeAreaInset: CGFloat
    @Binding private var isSchedulePresented: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @Binding private var countryDestination: MovieCountry?
    @Binding private var genreDestination: MovieGenre?
    @Binding private var personDestination: PersonSimple?
    @Binding private var listDestination: MovieList?
    @Binding private var collectionDestination: MoviesCollection?

    @State private var trailerViewModel: DetailsViewTrailerViewModel
    @State private var player: AVPlayer?
    @State private var playerData: PlayerData?

    @State private var isPlayPresented = false
    @State private var franchiseExpanded = false
    @State private var heroHeight: CGFloat = .zero
    @State private var containerWidth: CGFloat = 1920

    init(details: MovieDetailed,
         trailerId: String?,
         topSafeAreaInset: CGFloat,
         isSchedulePresented: Binding<Bool>,
         countryDestination: Binding<MovieCountry?>,
         genreDestination: Binding<MovieGenre?>,
         personDestination: Binding<PersonSimple?>,
         listDestination: Binding<MovieList?>,
         collectionDestination: Binding<MoviesCollection?>)
    {
        self.details = details
        self.trailerId = trailerId
        self.topSafeAreaInset = topSafeAreaInset
        _isSchedulePresented = isSchedulePresented
        _countryDestination = countryDestination
        _genreDestination = genreDestination
        _personDestination = personDestination
        _listDestination = listDestination
        _collectionDestination = collectionDestination
        _trailerViewModel = State(initialValue: .init(trailerId: trailerId))
    }

    private var hasMetadata: Bool {
        details.slogan?.isEmpty == false
            || details.releaseDate?.isEmpty == false
            || details.year?.isEmpty == false
            || details.countries?.isEmpty == false
            || details.genres?.isEmpty == false
            || details.producer?.isEmpty == false
            || details.actors?.isEmpty == false
            || details.lists?.isEmpty == false
            || details.collections?.isEmpty == false
            || details.rating != nil
    }

    private var hasStats: Bool {
        details.imdbRating != nil
            || details.kpRating != nil
            || details.waRating != nil
            || details.duration != nil
            || details.ageRestriction?.isEmpty == false
    }

    private var heroSubtitle: String {
        var parts: [String] = []

        if let year = details.year, !year.isEmpty {
            parts.append(year)
        }

        if let releaseDate = details.releaseDate, !releaseDate.isEmpty {
            parts.append(releaseDate)
        }

        if let type = details.type, !type.isEmpty {
            parts.append(type)
        }

        if let countries = details.countries, !countries.isEmpty {
            parts.append(countries.prefix(2).map(\.name).joined(separator: ", "))
        }

        return parts.joined(separator: "  •  ")
    }

    private var genreLine: String? {
        guard let genres = details.genres, !genres.isEmpty else { return nil }

        return genres.prefix(4).map(\.name).joined(separator: " • ")
    }

    var body: some View {
        let layout = DetailsLayout(width: containerWidth)

        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            heroSection(layout: layout)
                .onGeometryChange(for: CGFloat.self) { heroGeometry in
                    heroGeometry.size.height
                } action: { height in
                    heroHeight = height
                }

            if hasMetadata {
                metadataSection
            }

            if hasStats {
                ratingsSection(layout: layout)
            }

            overviewSection(layout: layout)

            if details.franchise?.isEmpty == false || details.schedule?.isEmpty == false {
                supportingSections(layout: layout)
            }

            relatedSection
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, topSafeAreaInset + 28)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            containerWidth = width
        }
        .background(alignment: .top) {
            backgroundHero
        }
        .task {
            await trailerViewModel.start()
        }
        .onChange(of: trailerViewModel.state) { _, state in
            if case let .url(url) = state {
                player = AVPlayer(url: url)
            }
        }
    }

    private func heroSection(layout: DetailsLayout) -> some View {
        let contentLayout = layout.prefersHorizontalHero
            ? AnyLayout(HStackLayout(alignment: .top, spacing: layout.sectionSpacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))

        return contentLayout {
            posterView(width: layout.posterWidth)

            VStack(alignment: .leading, spacing: 20) {
                heroBadgeRow

                VStack(alignment: .leading, spacing: 10) {
                    Text(details.nameRussian)
                        .font(.system(size: layout.titleSize, weight: .bold, design: .rounded))
                        .lineLimit(3)

                    if let nameOriginal = details.nameOriginal, !nameOriginal.isEmpty {
                        Text(nameOriginal)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if !heroSubtitle.isEmpty {
                        Text(heroSubtitle)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if let genreLine {
                        Text(genreLine)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                actionRow

                if let slogan = details.slogan, !slogan.isEmpty {
                    Text(verbatim: "\"\(slogan)\"")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                }

                Text(details.description)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(layout.prefersHorizontalHero ? 6 : 8)

                quickFactsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(layout.cardPadding)
        .background(sectionSurface(opacity: colorScheme == .dark ? 0.38 : 0.18))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18))
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private func posterView(width: CGFloat) -> some View {
        KFImage
            .url(URL(string: details.hposter))
            .placeholder {
                KFImage
                    .url(URL(string: details.poster))
                    .placeholder {
                        Color.gray.shimmering()
                    }
                    .resizable()
                    .loadTransition(.blurReplace, animation: .easeInOut)
                    .cancelOnDisappear(true)
                    .retry(NetworkRetryStrategy())
            }
            .resizable()
            .loadTransition(.blurReplace, animation: .easeInOut)
            .cancelOnDisappear(true)
            .retry(NetworkRetryStrategy())
            .scaledToFill()
            .frame(width: width, height: width * 1.48)
            .background(Color.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    if details.available {
                        TVAccentBadge(text: String(localized: "key.watch"))
                    } else if details.comingSoon {
                        TVDarkBadge(text: String(localized: "key.soon"))
                    } else {
                        TVDarkBadge(text: String(localized: "key.unavailable"))
                    }
                }
                .padding(18)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10))
            }
            .shadow(color: .black.opacity(0.28), radius: 34, y: 18)
    }

    private var heroBadgeRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                statusBadge

                if let ageRestriction = details.ageRestriction, !ageRestriction.isEmpty {
                    TVDarkBadge(text: ageRestriction)
                }

                if let duration = details.duration, duration > 0 {
                    TVDarkBadge(text: "\(duration) мин")
                }

                if details.commentsCount > 0 {
                    TVDarkBadge(text: "\(details.commentsCount) comments")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                statusBadge

                HStack(spacing: 10) {
                    if let ageRestriction = details.ageRestriction, !ageRestriction.isEmpty {
                        TVDarkBadge(text: ageRestriction)
                    }

                    if let duration = details.duration, duration > 0 {
                        TVDarkBadge(text: "\(duration) мин")
                    }

                    if details.commentsCount > 0 {
                        TVDarkBadge(text: "\(details.commentsCount) comments")
                    }
                }
            }
        }
    }

    private var statusBadge: some View {
        Group {
            if details.available {
                TVAccentBadge(text: String(localized: "key.watch"))
            } else if details.comingSoon {
                TVDarkBadge(text: String(localized: "key.soon"))
            } else {
                TVDarkBadge(text: String(localized: "key.unavailable"))
            }
        }
    }

    private var actionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                primaryActionButton

                if let rating = details.rating {
                    ratingBadge(rating: rating)
                }

                if !details.favs.isEmpty {
                    TVDarkBadge(text: details.favs)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                primaryActionButton

                HStack(spacing: 14) {
                    if let rating = details.rating {
                        ratingBadge(rating: rating)
                    }

                    if !details.favs.isEmpty {
                        TVDarkBadge(text: details.favs)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if details.available {
            Button {
                isPlayPresented = true
            } label: {
                DetailsActionLabel(
                    title: String(localized: "key.watch"),
                    systemImage: "play.fill",
                    accent: true,
                )
            }
            .buttonStyle(OnPressButtonStyle { _ in })
            .focusEffectDisabled()
            .sheet(isPresented: $isPlayPresented) {
                WatchSheetView(id: details.movieId, playerData: $playerData)
                    .presentationSizing(.fitted)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(item: $playerData) { data in
                PlayerView(data: data)
                    .analyticsScreen(name: "player", class: "PlayerView")
            }
        } else if details.comingSoon {
            DetailsActionLabel(
                title: String(localized: "key.soon"),
                systemImage: "clock",
                accent: false,
            )
        } else {
            DetailsActionLabel(
                title: String(localized: "key.unavailable"),
                systemImage: "network.slash",
                accent: false,
            )
        }
    }

    private func ratingBadge(rating: Float) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundStyle(Color.yellow)

            Text(verbatim: String(format: "%.1f", rating))
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.58), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.10))
        }
    }

    private var quickFactsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                if let imdbRating = details.imdbRating {
                    quickFact(title: "IMDb", value: String(format: "%.1f", imdbRating.value))
                }

                if let kpRating = details.kpRating {
                    quickFact(title: "KP", value: String(format: "%.1f", kpRating.value))
                }

                if let waRating = details.waRating {
                    quickFact(title: "WA", value: String(format: "%.1f", waRating.value))
                }

                if let ageRestriction = details.ageRestriction, !ageRestriction.isEmpty {
                    quickFact(title: String(localized: "key.info.age"), value: ageRestriction)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    if let imdbRating = details.imdbRating {
                        quickFact(title: "IMDb", value: String(format: "%.1f", imdbRating.value))
                    }

                    if let kpRating = details.kpRating {
                        quickFact(title: "KP", value: String(format: "%.1f", kpRating.value))
                    }
                }

                HStack(spacing: 16) {
                    if let waRating = details.waRating {
                        quickFact(title: "WA", value: String(format: "%.1f", waRating.value))
                    }

                    if let ageRestriction = details.ageRestriction, !ageRestriction.isEmpty {
                        quickFact(title: String(localized: "key.info.age"), value: ageRestriction)
                    }
                }
            }
        }
    }

    private func quickFact(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private var metadataSection: some View {
        sectionCard(title: "Details") {
            VStack(alignment: .leading, spacing: 0) {
                if let slogan = details.slogan, !slogan.isEmpty {
                    InfoRow(String(localized: "key.info.slogan"), slogan)
                }

                if let releaseDate = details.releaseDate, !releaseDate.isEmpty {
                    metadataDivider(hasPrevious: details.slogan?.isEmpty == false)
                    InfoRow(String(localized: "key.info.date"), releaseDate)
                }

                if let year = details.year, !year.isEmpty {
                    metadataDivider(hasPrevious: details.slogan?.isEmpty == false || details.releaseDate?.isEmpty == false)
                    InfoRow(String(localized: "key.info.year"), year)
                }

                if let countries = details.countries, !countries.isEmpty {
                    metadataDivider(hasPrevious: details.slogan?.isEmpty == false || details.releaseDate?.isEmpty == false || details.year?.isEmpty == false)
                    InfoRowWithButtons(
                        String(localized: "key.info.country"),
                        String(localized: "key.info.country.description"),
                        countries,
                        countryDestination: $countryDestination,
                        genreDestination: $genreDestination,
                        personDestination: $personDestination,
                        listDestination: $listDestination,
                        collectionDestination: $collectionDestination,
                    )
                }

                if let genres = details.genres, !genres.isEmpty {
                    metadataDivider(hasPrevious: details.slogan?.isEmpty == false || details.releaseDate?.isEmpty == false || details.year?.isEmpty == false || details.countries?.isEmpty == false)
                    InfoRowWithButtons(
                        String(localized: "key.info.genres"),
                        String(localized: "key.info.genres.description"),
                        genres,
                        countryDestination: $countryDestination,
                        genreDestination: $genreDestination,
                        personDestination: $personDestination,
                        listDestination: $listDestination,
                        collectionDestination: $collectionDestination,
                    )
                }

                if let producer = details.producer, !producer.isEmpty {
                    metadataDivider(hasPrevious: details.slogan?.isEmpty == false || details.releaseDate?.isEmpty == false || details.year?.isEmpty == false || details.countries?.isEmpty == false || details.genres?.isEmpty == false)
                    InfoRowWithButtons(
                        String(localized: "key.info.producer"),
                        String(localized: "key.info.producer.description"),
                        producer,
                        countryDestination: $countryDestination,
                        genreDestination: $genreDestination,
                        personDestination: $personDestination,
                        listDestination: $listDestination,
                        collectionDestination: $collectionDestination,
                    )
                }

                if let actors = details.actors, !actors.isEmpty {
                    metadataDivider(hasPrevious: details.slogan?.isEmpty == false || details.releaseDate?.isEmpty == false || details.year?.isEmpty == false || details.countries?.isEmpty == false || details.genres?.isEmpty == false || details.producer?.isEmpty == false)
                    InfoRowWithButtons(
                        String(localized: "key.info.actors"),
                        String(localized: "key.info.actors.description"),
                        actors,
                        countryDestination: $countryDestination,
                        genreDestination: $genreDestination,
                        personDestination: $personDestination,
                        listDestination: $listDestination,
                        collectionDestination: $collectionDestination,
                    )
                }

                if let lists = details.lists, !lists.isEmpty {
                    metadataDivider(hasPrevious: details.slogan?.isEmpty == false || details.releaseDate?.isEmpty == false || details.year?.isEmpty == false || details.countries?.isEmpty == false || details.genres?.isEmpty == false || details.producer?.isEmpty == false || details.actors?.isEmpty == false)
                    InfoRowWithButtons(
                        String(localized: "key.info.lists"),
                        String(localized: "key.info.lists.description"),
                        lists,
                        countryDestination: $countryDestination,
                        genreDestination: $genreDestination,
                        personDestination: $personDestination,
                        listDestination: $listDestination,
                        collectionDestination: $collectionDestination,
                    )
                }

                if let collections = details.collections, !collections.isEmpty {
                    metadataDivider(hasPrevious: details.slogan?.isEmpty == false || details.releaseDate?.isEmpty == false || details.year?.isEmpty == false || details.countries?.isEmpty == false || details.genres?.isEmpty == false || details.producer?.isEmpty == false || details.actors?.isEmpty == false || details.lists?.isEmpty == false)
                    InfoRowWithButtons(
                        String(localized: "key.info.collections"),
                        String(localized: "key.info.collections.description"),
                        collections,
                        countryDestination: $countryDestination,
                        genreDestination: $genreDestination,
                        personDestination: $personDestination,
                        listDestination: $listDestination,
                        collectionDestination: $collectionDestination,
                    )
                }

                if let rating = details.rating {
                    metadataDivider(hasPrevious: details.slogan?.isEmpty == false || details.releaseDate?.isEmpty == false || details.year?.isEmpty == false || details.countries?.isEmpty == false || details.genres?.isEmpty == false || details.producer?.isEmpty == false || details.actors?.isEmpty == false || details.lists?.isEmpty == false || details.collections?.isEmpty == false)
                    InfoRowRating(String(localized: "key.info.rating"), rating, details.rated, details.votes)
                }
            }
        }
    }

    @ViewBuilder
    private func metadataDivider(hasPrevious: Bool) -> some View {
        if hasPrevious {
            Divider()
        }
    }

    private func ratingsSection(layout: DetailsLayout) -> some View {
        sectionCard(title: "Ratings") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: layout.metricMinimumWidth, maximum: 260), spacing: 18)],
                alignment: .leading,
                spacing: 18,
            ) {
                if let imdbRating = details.imdbRating {
                    let color = Color.red.mix(with: .green, by: Double(imdbRating.value / 10.0))
                    detailsMetricCard(
                        title: "IMDb",
                        value: imdbRating.value.description,
                        subtitle: StarsView(rating: imdbRating.value * 0.5, color: color),
                        valueColor: color,
                        caption: imdbRating.votesCount,
                        url: URL(string: imdbRating.link),
                    )
                }

                if let kpRating = details.kpRating {
                    let color = Color.red.mix(with: .green, by: Double(kpRating.value / 10.0))
                    detailsMetricCard(
                        title: "КиноПоиск",
                        value: kpRating.value.description,
                        subtitle: StarsView(rating: kpRating.value * 0.5, color: color),
                        valueColor: color,
                        caption: kpRating.votesCount,
                        url: URL(string: kpRating.link),
                    )
                }

                if let waRating = details.waRating {
                    let color = Color.red.mix(with: .green, by: Double(waRating.value / 10.0))
                    detailsMetricCard(
                        title: "World Art",
                        value: waRating.value.description,
                        subtitle: StarsView(rating: waRating.value * 0.5, color: color),
                        valueColor: color,
                        caption: waRating.votesCount,
                        url: URL(string: waRating.link),
                    )
                }

                if let duration = details.duration, duration > 0 {
                    detailsMetricCard(
                        title: String(localized: "key.info.duration"),
                        value: duration.description,
                        subtitle: Text(String(localized: "key.info.minutes-\(duration)").trimmingCharacters(in: .letters.inverted).lowercased())
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary),
                    )
                }

                if let ageRestriction = details.ageRestriction, !ageRestriction.isEmpty {
                    detailsMetricCard(
                        title: String(localized: "key.info.age"),
                        value: ageRestriction,
                        subtitle: Text(String(localized: "key.info.years_old").lowercased())
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary),
                    )
                }
            }
        }
    }

    private func overviewSection(layout: DetailsLayout) -> some View {
        let contentLayout = trailerId != nil && layout.prefersSideBySideOverview
            ? AnyLayout(HStackLayout(alignment: .top, spacing: layout.sectionSpacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))

        return sectionCard(title: "Synopsis") {
            contentLayout {
                VStack(alignment: .leading, spacing: 14) {
                    Text(details.description)
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let voiceActing = details.voiceActing, !voiceActing.isEmpty {
                        Text(voiceActing.prefix(4).map(\.name).joined(separator: " • "))
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if trailerId != nil {
                    trailerCard
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var trailerCard: some View {
        Group {
            switch trailerViewModel.state {
            case .idle:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 260)
            case .error:
                VStack(alignment: .center, spacing: 12) {
                    Image(systemName: "play.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text("Trailer unavailable")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            case .url:
                VideoPlayer(player: player)
                    .onDisappear {
                        player?.pause()
                    }
                    .onScrollVisibilityChange { isVisible in
                        if !isVisible {
                            player?.pause()
                        }
                    }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func supportingSections(layout: DetailsLayout) -> some View {
        let contentLayout = layout.prefersSideBySideOverview
            ? AnyLayout(HStackLayout(alignment: .top, spacing: layout.sectionSpacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: layout.sectionSpacing))

        return contentLayout {
            if let franchise = details.franchise, !franchise.isEmpty {
                franchiseSection(franchise)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let schedule = details.schedule, let first = schedule.first {
                scheduleSection(schedule: schedule, first: first)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func franchiseSection(_ franchise: [MovieFranchisePart]) -> some View {
        sectionCard(title: String(localized: "key.franchise")) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(franchise.prefix(franchiseExpanded ? franchise.count : 5)) { part in
                    if !part.current, let movieId = part.franchiseId {
                        Button {
                            appState.presentedDetailsMovie = MovieSimple(movieId: movieId, name: part.name)
                        } label: {
                            franchiseRow(part: part, accent: false)
                        }
                        .buttonStyle(OnPressButtonStyle { _ in })
                        .focusEffectDisabled()
                    } else {
                        franchiseRow(part: part, accent: true)
                    }

                    if part != franchise.last || franchise.count > 5 {
                        Divider()
                    }
                }

                if franchise.count > 5 {
                    HStack {
                        Spacer()

                        Button {
                            withAnimation(.easeInOut) {
                                franchiseExpanded.toggle()
                            }
                        } label: {
                            Text(franchiseExpanded ? String(localized: "key.hide").lowercased() : String(localized: "key.view_more").lowercased())
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(OnPressButtonStyle { _ in })
                        .focusEffectDisabled()

                        Spacer()
                    }
                }
            }
        }
    }

    private func franchiseRow(part: MovieFranchisePart, accent: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent ? Color.accentColor : Color.black.opacity(0.42))

                Text(verbatim: "\(part.position)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(part.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                Text(franchiseSubtitle(part))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !accent {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
    }

    private func franchiseSubtitle(_ part: MovieFranchisePart) -> String {
        if let rating = part.rating {
            return "\(part.year) • \(rating)"
        }

        return String(part.year)
    }

    private func scheduleSection(schedule: [SeriesScheduleGroup], first: SeriesScheduleGroup) -> some View {
        sectionCard(title: String(localized: "key.schedule")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(first.name)
                    .font(.title3.weight(.bold))

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(first.items.prefix(5)) { item in
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.russianEpisodeName)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(1)

                                if let originalEpisodeName = item.originalEpisodeName {
                                    Text(originalEpisodeName)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text(item.releaseDate)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.secondary)

                                Text(item.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 12)

                        if item != first.items.prefix(5).last || schedule.count > 1 || first.items.count > 5 {
                            Divider()
                        }
                    }

                    if schedule.count > 1 || first.items.count > 5 {
                        HStack {
                            Spacer()

                            Button {
                                isSchedulePresented = true
                            } label: {
                                Text(String(localized: "key.view_more").lowercased())
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(OnPressButtonStyle { _ in })
                            .focusEffectDisabled()

                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("key.watch_also")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(details.watchAlsoMovies) { movie in
                        CardView(movie: movie)
                            .frame(width: 320)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private func sectionCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))

            content()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionSurface())
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.14))
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func sectionSurface(opacity: Double? = nil) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.black.opacity(opacity ?? (colorScheme == .dark ? 0.34 : 0.12)))
    }

    private func detailsMetricCard(title: String,
                                   value: String,
                                   subtitle: some View,
                                   valueColor: Color? = nil,
                                   caption: String? = nil,
                                   url: URL? = nil) -> some View
    {
        DetailsMetricCard(
            title: title,
            value: value,
            caption: caption,
            valueColor: valueColor,
            url: url,
            subtitle: subtitle,
        )
    }

    private var backgroundHero: some View {
        ZStack(alignment: .top) {
            KFImage
                .url(URL(string: details.poster))
                .placeholder {
                    Color.gray
                }
                .resizable()
                .loadTransition(.opacity, animation: .easeInOut)
                .cancelOnDisappear(true)
                .retry(NetworkRetryStrategy())
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: max(heroHeight + 180, 760))
                .clipped()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.70),
                    Color.black,
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
            .frame(height: max(heroHeight + 220, 860))
        }
        .viewModifier { view in
            if #available(tvOS 26, *) {
                view.backgroundExtensionEffect()
            } else {
                view
            }
        }
    }
}

private struct DetailsLayout {
    let width: CGFloat

    var horizontalPadding: CGFloat {
        width > 1500 ? 52 : 36
    }

    var sectionSpacing: CGFloat {
        width > 1500 ? 30 : 24
    }

    var cardPadding: CGFloat {
        width > 1500 ? 34 : 28
    }

    var posterWidth: CGFloat {
        min(max(width * 0.22, 250), 340)
    }

    var titleSize: CGFloat {
        width > 1500 ? 54 : 44
    }

    var metricMinimumWidth: CGFloat {
        width > 1500 ? 220 : 190
    }

    var prefersHorizontalHero: Bool {
        width >= 1220
    }

    var prefersSideBySideOverview: Bool {
        width >= 1380
    }
}

private struct DetailsActionLabel: View {
    let title: String
    let systemImage: String
    let accent: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))

            Text(title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(backgroundColor, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(borderColor, lineWidth: isFocused ? 2 : 1)
        }
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .shadow(color: shadowColor, radius: isFocused ? 22 : 12, y: isFocused ? 12 : 6)
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }

    private var backgroundColor: Color {
        accent ? Color.accentColor : Color.black.opacity(0.60)
    }

    private var borderColor: Color {
        isFocused ? .white.opacity(0.9) : .white.opacity(accent ? 0.14 : 0.10)
    }

    private var shadowColor: Color {
        accent ? Color.accentColor.opacity(isFocused ? 0.35 : 0.18) : Color.black.opacity(isFocused ? 0.32 : 0.18)
    }
}

private struct DetailsMetricCard<Subtitle: View>: View {
    let title: String
    let value: String
    let caption: String?
    let valueColor: Color?
    let url: URL?
    let subtitle: Subtitle

    @Environment(\.isFocused) private var isFocused
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let url {
                Button {
                    openURL(url)
                } label: {
                    content
                }
                .buttonStyle(OnPressButtonStyle { _ in })
                .focusEffectDisabled()
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor ?? .primary)

            subtitle

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
        .padding(20)
        .background(Color.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isFocused ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.08), lineWidth: isFocused ? 2 : 1)
        }
        .scaleEffect(isFocused && url != nil ? 1.03 : 1.0)
        .shadow(color: isFocused ? Color.accentColor.opacity(0.22) : Color.black.opacity(0.16), radius: isFocused ? 18 : 10, y: isFocused ? 10 : 6)
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}
