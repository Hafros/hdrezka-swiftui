//
//  WatchSheetView.swift
//  HDrezka
//
//  Created by Alex Hafros on 30.01.2026.
//

import Combine
import Defaults
import FactoryKit
import FirebaseAnalytics
import SwiftData
import SwiftUI

struct WatchSheetView: View {
    private enum FocusTarget: Hashable {
        case acting(UUID)
        case season(UUID)
        case episode(UUID)
        case quality(String)
        case play
    }

    @Injected(\.getMovieDetailsUseCase) private var getMovieDetailsUseCase
    @Injected(\.getMovieVideoUseCase) private var getMovieVideoUseCase
    @Injected(\.getSeriesSeasonsUseCase) private var getSeriesSeasonsUseCase

    @State private var subscriptions: Set<AnyCancellable> = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Environment(AppState.self) private var appState

    @Query private var selectPositions: [SelectPosition]

    @Default(.isUserPremium) private var isUserPremium
    @Default(.isLoggedIn) private var isLoggedIn
    @Default(.defaultQuality) private var defaultQuality

    private let id: String
    @Binding private var playerData: PlayerData?

    @State private var details: MovieDetailed?
    @State private var seasons: [MovieSeason]?
    @State private var selectedActing: MovieVoiceActing?
    @State private var selectedSeason: MovieSeason?
    @State private var selectedEpisode: MovieEpisode?
    @State private var selectedQuality: String?
    @State private var movie: MovieVideo?

    @State private var error: Error?

    @State private var isErrorPresented: Bool = false
    @State private var isLoginPresented: Bool = false

    @State private var showRating: Bool = false

    @FocusState private var focusedField: FocusTarget?

    init(id: String, playerData: Binding<PlayerData?>) {
        self.id = id
        _playerData = playerData
    }

    var body: some View {
        VStack(alignment: .center, spacing: 25) {
            WatchSheetHeaderView()

            if let details {
                VStack(spacing: 18) {
                    if details.series != nil || !(details.voiceActing ?? []).filter({ !$0.name.isEmpty }).isEmpty {
                        WatchSheetActingPicker(
                            details: details,
                            seasons: $seasons,
                            selectedActing: $selectedActing,
                            selectedSeason: $selectedSeason,
                            selectedEpisode: $selectedEpisode,
                            showRating: $showRating,
                            isUserPremium: isUserPremium != nil,
                            focusedField: $focusedField,
                            appState: appState,
                            dismiss: dismiss,
                        )
                    }
                    if (details.series == nil && selectedActing != nil) || selectedEpisode != nil {
                        WatchSheetQualityPicker(
                            movie: movie,
                            selectedQuality: $selectedQuality,
                            focusedField: $focusedField,
                            isLoggedIn: isLoggedIn,
                            isLoginPresented: $isLoginPresented,
                        )
                    }
                }
            } else {
                ProgressView()
            }

            WatchSheetPlayButton(
                details: details,
                selectedActing: selectedActing,
                selectedQuality: selectedQuality,
                seasons: seasons,
                selectedSeason: selectedSeason,
                selectedEpisode: selectedEpisode,
                movie: movie,
                playerData: $playerData,
                focusedField: $focusedField,
                dismiss: dismiss,
            )
        }
        .alert("key.ops", isPresented: $isErrorPresented) {
            if let hdrezkaError = error as? HDrezkaError, case .loginRequired = hdrezkaError {
                Button(role: .destructive) {
                    dismiss()
                    appState.isSignInPresented = true
                } label: {
                    Text("key.sign_in")
                }
            }
            Button(role: .cancel) {
                dismiss()
            } label: {
                Text("key.ok")
            }
        } message: {
            if let error {
                Text(error.localizedDescription)
            }
        }
        .confirmationDialog("key.sign_in.label", isPresented: $isLoginPresented) {
            Button {
                dismiss()
                appState.isSignInPresented = true
            } label: {
                Text("key.sign_in")
            }
        } message: {
            Text("key.sign_in.access")
        }
        .padding(.horizontal, 35)
        .padding(.top, 35)
        .padding(.bottom, 25)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 760)
        .onAppear { subscribeOnAppear() }
        .onChange(of: details) { handleDetailsChange() }
        .onChange(of: selectedActing) { handleActingChange() }
        .onChange(of: selectedSeason) { handleSeasonChange() }
        .onChange(of: selectedEpisode) { handleEpisodeChange() }
        .onChange(of: selectedQuality) { _, selectedQuality in
            if let selectedQuality {
                focusedField = .quality(selectedQuality)
            }
        }
        .analyticsScreen(name: "watch_sheet", class: "WatchSheetView")
    }

    // MARK: - Side Effect Handlers

    private func subscribeOnAppear() {
        getMovieDetailsUseCase(movieId: id)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                guard case let .failure(error) = completion else { return }
                self.error = error
                isErrorPresented = true
            } receiveValue: { details in
                withAnimation(.easeInOut) { self.details = details }
            }
            .store(in: &subscriptions)
    }

    private func handleDetailsChange() {
        guard let details, let acting = details.voiceActing else { return }
        withAnimation(.easeInOut) {
            selectedActing = pickActing(details: details, acting: acting)
        }

        if let selectedActing {
            focusedField = .acting(selectedActing.id)
        }
    }

    private func pickActing(details: MovieDetailed, acting: [MovieVoiceActing]) -> MovieVoiceActing? {
        if !isLoggedIn,
           let position = selectPositions.first(where: { $0.id == details.movieId.id }),
           let first = acting.filter({ isUserPremium != nil || !$0.isPremium }).first(where: { $0.translatorId == position.acting })
        {
            first
        } else if let series = details.series,
                  let first = acting.filter({ isUserPremium != nil || !$0.isPremium }).first(where: { $0.translatorId == series.acting })
        {
            first
        } else if let first = acting.filter({ isUserPremium != nil || !$0.isPremium }).first(where: { $0.isSelected }) {
            first
        } else if let first = acting.filter({ isUserPremium != nil || !$0.isPremium }).first {
            first
        } else {
            acting.first
        }
    }

    private func handleActingChange() {
        withAnimation(.easeInOut) {
            selectedSeason = nil
            selectedEpisode = nil
            selectedQuality = nil
            seasons = nil
            movie = nil
        }
        guard let details, let selectedActing else { return }
        if details.series != nil {
            if let movieId = details.movieId.id {
                getSeriesSeasonsUseCase(movieId: movieId, voiceActing: selectedActing, favs: details.favs)
                    .receive(on: DispatchQueue.main)
                    .sink { completion in
                        guard case let .failure(error) = completion else { return }
                        self.error = error
                        isErrorPresented = true
                    } receiveValue: { seasons in
                        withAnimation(.easeInOut) {
                            self.seasons = seasons
                            selectedSeason = pickSeason(details: details, selectedActing: selectedActing, seasons: seasons)
                        }

                        if let selectedSeason {
                            focusedField = .season(selectedSeason.id)
                        }
                    }
                    .store(in: &subscriptions)
            } else {
                if !isErrorPresented { isErrorPresented = true }
            }
        } else {
            getMovieVideoUseCase(voiceActing: selectedActing, season: nil, episode: nil, favs: details.favs)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    guard case let .failure(error) = completion else { return }
                    self.error = error
                    isErrorPresented = true
                } receiveValue: { movie in
                    if movie.needPremium {
                        dismiss()
                        appState.isPremiumPresented = true
                    } else {
                        withAnimation(.easeInOut) {
                            self.movie = movie
                            selectedQuality = pickQuality(movie: movie)
                        }

                        if let selectedQuality {
                            focusedField = .quality(selectedQuality)
                        }
                    }
                }
                .store(in: &subscriptions)
        }
    }

    private func pickSeason(details: MovieDetailed, selectedActing: MovieVoiceActing, seasons: [MovieSeason]) -> MovieSeason? {
        if !isLoggedIn,
           let position = selectPositions.first(where: { $0.id == selectedActing.voiceId }),
           let first = seasons.first(where: { $0.seasonId == position.season })
        {
            first
        } else if let series = details.series,
                  let first = seasons.first(where: { $0.seasonId == series.season })
        {
            first
        } else if let first = seasons.first(where: { $0.isSelected }) {
            first
        } else {
            seasons.first
        }
    }

    private func handleSeasonChange() {
        withAnimation(.easeInOut) {
            selectedQuality = nil
            movie = nil
            selectedEpisode = pickEpisode()
        }

        if let selectedEpisode {
            focusedField = .episode(selectedEpisode.id)
        }
    }

    private func pickEpisode() -> MovieEpisode? {
        if !isLoggedIn,
           let position = selectPositions.first(where: { $0.id == selectedActing?.voiceId }),
           let first = selectedSeason?.episodes.first(where: { $0.episodeId == position.episode })
        {
            first
        } else if let series = details?.series,
                  let first = selectedSeason?.episodes.first(where: { $0.episodeId == series.episode })
        {
            first
        } else if let first = selectedSeason?.episodes.first(where: { $0.isSelected }) {
            first
        } else {
            selectedSeason?.episodes.first
        }
    }

    private func handleEpisodeChange() {
        withAnimation(.easeInOut) {
            selectedQuality = nil
            movie = nil
        }
        guard let details, let selectedSeason, let selectedEpisode, let selectedActing else { return }
        getMovieVideoUseCase(voiceActing: selectedActing, season: selectedSeason, episode: selectedEpisode, favs: details.favs)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                guard case let .failure(error) = completion else { return }
                self.error = error
                isErrorPresented = true
            } receiveValue: { movie in
                if movie.needPremium {
                    dismiss()
                    appState.isPremiumPresented = true
                } else {
                    withAnimation(.easeInOut) {
                        self.movie = movie
                        selectedQuality = pickQuality(movie: movie)
                    }

                    if let selectedQuality {
                        focusedField = .quality(selectedQuality)
                    }
                }
            }
            .store(in: &subscriptions)
    }

    private func pickQuality(movie: MovieVideo) -> String? {
        if defaultQuality != .ask,
           defaultQuality != .highest,
           movie.getAvailableQualities().contains(defaultQuality.rawValue)
        {
            defaultQuality.rawValue
        } else if defaultQuality == .highest,
                  let highest = movie.getAvailableQualities().last
        {
            highest
        } else {
            nil
        }
    }

    // MARK: - Components

    private struct WatchSheetHeaderView: View {
        var body: some View {
            VStack(alignment: .center, spacing: 5) {
                Image(systemName: "videoprojector")
                    .font(.largeTitle)
                    .foregroundStyle(Color.accentColor)

                Text("key.before_starting")
                    .font(.largeTitle.weight(.semibold))

                Text("key.watch.description")
                    .font(.title3)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private struct WatchSheetActingPicker: View {
        let details: MovieDetailed
        @Binding var seasons: [MovieSeason]?
        @Binding var selectedActing: MovieVoiceActing?
        @Binding var selectedSeason: MovieSeason?
        @Binding var selectedEpisode: MovieEpisode?
        @Binding var showRating: Bool
        let isUserPremium: Bool
        @FocusState.Binding var focusedField: FocusTarget?
        let appState: AppState
        let dismiss: DismissAction

        var body: some View {
            let actingOptions = details.voiceActing?.filter { !$0.name.isEmpty } ?? []

            VStack(alignment: .leading, spacing: 16) {
                if !actingOptions.isEmpty {
                    WatchSheetSectionHeader(
                        title: String(localized: "key.acting"),
                        value: selectedActingTitle,
                    ) {
                        if let rating = details.voiceActingRating?.sorted(by: { $0.percent > $1.percent }), !rating.isEmpty {
                            Button {
                                withAnimation(.easeInOut) {
                                    showRating.toggle()
                                }
                            } label: {
                                Label(showRating ? String(localized: "key.hide") : String(localized: "key.info.rating"), systemImage: showRating ? "chevron.up" : "chart.bar.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    WatchSheetOptionsRow(actingOptions) { acting in
                        Button {
                            if acting.isPremium, !isUserPremium {
                                dismiss()
                                appState.isPremiumPresented = true
                            } else {
                                withAnimation(.easeInOut) {
                                    selectedActing = acting
                                }
                            }
                        } label: {
                            WatchSheetOptionChip(
                                title: actingTitle(acting),
                                subtitle: actingSubtitle(acting),
                                isSelected: selectedActing == acting,
                                isDisabled: acting.isPremium && !isUserPremium,
                                systemImage: acting.isPremium ? "star.fill" : nil,
                            )
                        }
                        .buttonStyle(.plain)
                        .focused($focusedField, equals: .acting(acting.id))
                    }
                    .viewModifier { view in
                        view.focusSection()
                    }

                    if showRating,
                       let rating = details.voiceActingRating?.sorted(by: { $0.percent > $1.percent }),
                       !rating.isEmpty
                    {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(rating) { rate in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .center) {
                                        Text(rate.name)
                                            .font(.subheadline.weight(.medium))

                                        Spacer()

                                        Text(verbatim: "\(Int(rate.percent))%")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    ProgressView(value: Double(rate.percent), total: 100)
                                        .tint(.accentColor)
                                }
                            }
                        }
                        .padding(14)
                        .background(.background.opacity(0.6), in: .rect(cornerRadius: 8))
                    }
                }

                if details.series != nil, selectedActing != nil {
                    WatchSheetSelectionBlock(
                        title: String(localized: "key.season"),
                        value: selectedSeasonTitle,
                        isLoading: seasons?.isEmpty != false,
                    ) {
                        WatchSheetOptionsRow(seasons ?? []) { season in
                            Button {
                                withAnimation(.easeInOut) {
                                    selectedSeason = season
                                }
                            } label: {
                                WatchSheetOptionChip(
                                    title: seasonTitle(season),
                                    isSelected: selectedSeason == season,
                                )
                            }
                            .buttonStyle(.plain)
                            .focused($focusedField, equals: .season(season.id))
                        }
                    }

                    WatchSheetSelectionBlock(
                        title: String(localized: "key.episode"),
                        value: selectedEpisodeTitle,
                        isLoading: selectedSeason?.episodes.isEmpty != false,
                    ) {
                        WatchSheetOptionsRow(selectedSeason?.episodes ?? []) { episode in
                            Button {
                                withAnimation(.easeInOut) {
                                    selectedEpisode = episode
                                }
                            } label: {
                                WatchSheetOptionChip(
                                    title: episodeTitle(episode),
                                    isSelected: selectedEpisode == episode,
                                )
                            }
                            .buttonStyle(.plain)
                            .focused($focusedField, equals: .episode(episode.id))
                        }
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 15)
            .background(.quinary, in: .rect(cornerRadius: 6))
            .overlay(.tertiary, in: .rect(cornerRadius: 6).stroke(lineWidth: 1))
        }

        private var selectedActingTitle: String {
            if let selectedActing {
                actingTitle(selectedActing)
            } else {
                String(localized: "key.acting.select")
            }
        }

        private var selectedSeasonTitle: String {
            if let selectedSeason {
                seasonTitle(selectedSeason)
            } else {
                String(localized: "key.season.select")
            }
        }

        private var selectedEpisodeTitle: String {
            if let selectedEpisode {
                episodeTitle(selectedEpisode)
            } else {
                String(localized: "key.episode.select")
            }
        }

        private func actingTitle(_ acting: MovieVoiceActing) -> String {
            acting.name.isEmpty ? String(localized: "key.default") : acting.name
        }

        private func actingSubtitle(_ acting: MovieVoiceActing) -> String? {
            var badges: [String] = []

            if acting.isPremium {
                badges.append(String(localized: "key.premium"))
            }

            if acting.isDirector == "1" {
                badges.append("Director")
            }

            if acting.isAds == "1" {
                badges.append("Ads")
            }

            if acting.isCamrip == "1" {
                badges.append("CamRip")
            }

            return badges.isEmpty ? nil : badges.joined(separator: " • ")
        }

        private func seasonTitle(_ season: MovieSeason) -> String {
            localizedOrdinalName(season.name, key: "key.season")
        }

        private func episodeTitle(_ episode: MovieEpisode) -> String {
            localizedOrdinalName(episode.name, key: "key.episode")
        }

        private func localizedOrdinalName(_ name: String, key: String) -> String {
            if name.isEmpty {
                String(localized: "\(key)-\(1)")
            } else if name.first?.isNumber == true {
                String(localized: "\(key)-\(name)")
            } else {
                name
            }
        }
    }

    private struct WatchSheetQualityPicker: View {
        let movie: MovieVideo?
        @Binding var selectedQuality: String?
        @FocusState.Binding var focusedField: FocusTarget?
        let isLoggedIn: Bool
        @Binding var isLoginPresented: Bool

        var body: some View {
            let availableQualities = movie?.getAvailableQualities() ?? []
            let lockedQualities = movie?.getLockedQualities() ?? []

            VStack(alignment: .leading, spacing: 14) {
                WatchSheetSectionHeader(
                    title: String(localized: "key.quality"),
                    value: selectedQuality ?? String(localized: "key.quality.select"),
                )

                if !availableQualities.isEmpty {
                    WatchSheetOptionsRow(availableQualities, id: \.self) { quality in
                        Button {
                            withAnimation(.easeInOut) {
                                selectedQuality = quality
                            }
                        } label: {
                            WatchSheetOptionChip(
                                title: quality,
                                isSelected: selectedQuality == quality,
                            )
                        }
                        .buttonStyle(.plain)
                        .focused($focusedField, equals: .quality(quality))
                    }
                    .viewModifier { view in
                        view.focusSection()
                    }
                }

                if !lockedQualities.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("key.sign_in.access")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        WatchSheetOptionsRow(lockedQualities, id: \.self) { quality in
                            Button {
                                if isLoggedIn {
                                    withAnimation(.easeInOut) {
                                        selectedQuality = quality
                                    }
                                } else {
                                    isLoginPresented = true
                                }
                            } label: {
                                WatchSheetOptionChip(
                                    title: quality,
                                    subtitle: isLoggedIn ? nil : String(localized: "key.sign_in"),
                                    isSelected: selectedQuality == quality,
                                    isDisabled: !isLoggedIn,
                                    systemImage: isLoggedIn ? nil : "lock.fill",
                                )
                            }
                            .buttonStyle(.plain)
                            .focused($focusedField, equals: .quality(quality))
                        }
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 15)
            .background(.quinary, in: .rect(cornerRadius: 6))
            .overlay(.tertiary, in: .rect(cornerRadius: 6).stroke(lineWidth: 1))
            .overlay {
                if movie?.getAvailableQualities().isEmpty != false {
                    ProgressView().scaleEffect(0.6)
                }
            }
        }
    }

    private struct WatchSheetPlayButton: View {
        let details: MovieDetailed?
        let selectedActing: MovieVoiceActing?
        let selectedQuality: String?
        let seasons: [MovieSeason]?
        let selectedSeason: MovieSeason?
        let selectedEpisode: MovieEpisode?
        let movie: MovieVideo?
        @Binding var playerData: PlayerData?
        @FocusState.Binding var focusedField: FocusTarget?
        let dismiss: DismissAction

        var body: some View {
            VStack(alignment: .center, spacing: 10) {
                Button {
                    if let details, let selectedActing, let selectedQuality, let movie {
                        dismiss()
                        playerData = PlayerData(
                            details: details,
                            selectedActing: selectedActing,
                            seasons: seasons,
                            selectedSeason: selectedSeason,
                            selectedEpisode: selectedEpisode,
                            selectedQuality: selectedQuality,
                            movie: movie,
                        )
                    }
                } label: {
                    Text("key.watch")
                        .font(.headline.weight(.semibold))
                        .frame(width: 280, height: 56)
                        .foregroundStyle(.white)
                        .contentShape(.rect(cornerRadius: 6))
                        .background(selectedQuality != nil ? Color.accentColor : Color.secondary, in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(selectedQuality == nil)
                .focused($focusedField, equals: .play)
            }
        }
    }

    private struct WatchSheetSelectionBlock<Content: View>: View {
        let title: String
        let value: String
        let isLoading: Bool
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                WatchSheetSectionHeader(title: title, value: value)

                ZStack {
                    content
                        .opacity(isLoading ? 0 : 1)

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 84)
                    }
                }
            }
        }
    }

    private struct WatchSheetSectionHeader<TrailingContent: View>: View {
        let title: String
        let value: String
        @ViewBuilder let trailingContent: TrailingContent

        init(title: String, value: String, @ViewBuilder trailingContent: () -> TrailingContent = { EmptyView() }) {
            self.title = title
            self.value = value
            self.trailingContent = trailingContent()
        }

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.headline)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 10)

                trailingContent
            }
        }
    }

    private struct WatchSheetOptionsRow<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
        private let data: Data
        private let id: KeyPath<Data.Element, ID>
        private let content: (Data.Element) -> Content

        init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
            self.data = data
            self.id = id
            self.content = content
        }

        init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) where Data.Element: Identifiable, ID == Data.Element.ID {
            self.init(data, id: \.id, content: content)
        }

        var body: some View {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(data, id: id) { element in
                        content(element)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
        }
    }

    private struct WatchSheetOptionChip: View {
        let title: String
        var subtitle: String?
        var isSelected: Bool = false
        var isDisabled: Bool = false
        var systemImage: String?

        var body: some View {
            HStack(alignment: .center, spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.bold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(backgroundStyle, in: .rect(cornerRadius: 10))
            .overlay(borderStyle, in: .rect(cornerRadius: 10).stroke(lineWidth: 1))
            .opacity(isDisabled ? 0.7 : 1)
        }

        private var foregroundStyle: AnyShapeStyle {
            if isSelected {
                AnyShapeStyle(.white)
            } else if isDisabled {
                AnyShapeStyle(.tertiary)
            } else {
                AnyShapeStyle(.primary)
            }
        }

        private var backgroundStyle: AnyShapeStyle {
            if isSelected {
                AnyShapeStyle(Color.accentColor)
            } else if isDisabled {
                AnyShapeStyle(Color.secondary.opacity(0.18))
            } else {
                AnyShapeStyle(.background.opacity(0.85))
            }
        }

        private var borderStyle: AnyShapeStyle {
            if isSelected {
                AnyShapeStyle(Color.accentColor)
            } else {
                AnyShapeStyle(.tertiary)
            }
        }
    }
}
