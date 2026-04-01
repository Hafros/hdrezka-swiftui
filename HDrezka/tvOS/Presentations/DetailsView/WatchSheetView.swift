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
                            isLoggedIn: isLoggedIn,
                            selectPositions: selectPositions,
                            appState: appState,
                            dismiss: dismiss,
                        )
                    }
                    if (details.series == nil && selectedActing != nil) || selectedEpisode != nil {
                        WatchSheetQualityPicker(
                            movie: movie,
                            selectedQuality: $selectedQuality,
                            selectedActing: selectedActing,
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
        .frame(width: 520)
        .onAppear { subscribeOnAppear() }
        .onChange(of: details) { handleDetailsChange() }
        .onChange(of: selectedActing) { handleActingChange() }
        .onChange(of: selectedSeason) { handleSeasonChange() }
        .onChange(of: selectedEpisode) { handleEpisodeChange() }
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
        let isUserPremium: Bool?
        let isLoggedIn: Bool
        let selectPositions: [SelectPosition]
        let appState: AppState
        let dismiss: DismissAction

        var body: some View {
            VStack(spacing: 2.5) {
                if let acting = details.voiceActing, !acting.filter({ !$0.name.isEmpty }).isEmpty {
                    HStack {
                        Text("key.acting")
                        // ... (повторить логику из главного файла для кнопки рейтинга и меню выбора)
                        Spacer()
                        // ... (menu как в основном файле)
                    }
                    .padding(.vertical, 10)
                    .overlay { if acting.isEmpty != false { ProgressView().scaleEffect(0.6) } }
                }
                // ... аналогично для выбора сезона и эпизода, либо вынести в отдельные View
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 5)
            .background(.quinary, in: .rect(cornerRadius: 6))
            .overlay(.tertiary, in: .rect(cornerRadius: 6).stroke(lineWidth: 1))
        }
    }

    private struct WatchSheetQualityPicker: View {
        let movie: MovieVideo?
        @Binding var selectedQuality: String?
        let selectedActing: MovieVoiceActing?
        let isLoggedIn: Bool
        @Binding var isLoginPresented: Bool

        var body: some View {
            HStack {
                Text("key.quality")
                // ... Логика для ShareLink и Menu с качествами
                Spacer()
                // ... Menu для выбора качества как в основном файле
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 15)
            .background(.quinary, in: .rect(cornerRadius: 6))
            .overlay(.tertiary, in: .rect(cornerRadius: 6).stroke(lineWidth: 1))
            .overlay { if movie?.getAvailableQualities().isEmpty != false { ProgressView().scaleEffect(0.6) } }
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
                        .frame(width: 250, height: 30)
                        .foregroundStyle(.white)
                        .contentShape(.rect(cornerRadius: 6))
                        .background(selectedQuality != nil ? Color.accentColor : Color.secondary, in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(selectedQuality == nil)
            }
        }
    }

    private struct CustomLabelStyle: LabelStyle {
        private let iconVisible: Bool

        init(iconVisible: Bool = true) {
            self.iconVisible = iconVisible
        }

        func makeBody(configuration: Configuration) -> some View {
            HStack(alignment: .center, spacing: 8) {
                configuration.title
                if iconVisible {
                    configuration.icon
                }
            }
        }
    }
}
