import Alamofire
import AVFoundation
import Combine
import Defaults
import FactoryKit
import Foundation
import SwiftData
import SwiftUI

#if canImport(PillarboxPlayer)
    import PillarboxPlayer

    struct PillarboxPlayerView: View {
        @Injected(\.getMovieVideoUseCase) private var getMovieVideoUseCase
        @Injected(\.saveWatchingStateUseCase) private var saveWatchingStateUseCase

        @Default(.isLoggedIn) private var isLoggedIn
        @Default(.rate) private var rate
        @Environment(\.dismiss) private var dismiss
        @Environment(\.modelContext) private var modelContext
        @Environment(AppState.self) private var appState

        @Query private var playerPositions: [PlayerPosition]
        @Query private var selectPositions: [SelectPosition]

        private let data: PlayerData
        private let details: MovieDetailed
        private let voiceActing: MovieVoiceActing

        @StateObject private var player: Player
        @State private var seasons: [MovieSeason]?
        @State private var season: MovieSeason?
        @State private var episode: MovieEpisode?
        @State private var movie: MovieVideo
        @State private var quality: String
        @State private var isStarted = false
        @State private var isLoading = false
        @State private var networkError: Error?
        @State private var lastPlaybackTime: Double = .zero
        @State private var manifestRefreshAttempts = 0
        @State private var subscriptions: Set<AnyCancellable> = []
        @State private var resourceLoader: PillarboxResourceLoaderDelegate?

        init(data: PlayerData) {
            self.data = data
            details = data.details
            voiceActing = data.selectedActing

            let initialQuality = data.movie.getAvailableQualities().contains(data.selectedQuality)
                ? data.selectedQuality
                : (data.movie.getAvailableQualities().last ?? data.selectedQuality)

            _player = StateObject(
                wrappedValue: Player(
                    configuration: .init(backwardSkipInterval: 10, forwardSkipInterval: 10),
                ),
            )
            _seasons = State(initialValue: data.seasons)
            _season = State(initialValue: data.selectedSeason)
            _episode = State(initialValue: data.selectedEpisode)
            _movie = State(initialValue: data.movie)
            _quality = State(initialValue: initialQuality)
        }

        var body: some View {
            Group {
                if let activeError, player.items.isEmpty {
                    ErrorStateView(activeError) {
                        startInitialPlayback(force: true)
                    }
                    .padding(36)
                } else {
                    ZStack {
                        SystemVideoView(player: player)
                            .supportsPictureInPicture()
                            .transportBar(content: transportBarContent)
                            .infoViewTabs(content: infoViewTabsContent)
                            .ignoresSafeArea()

                        if shouldShowProgress {
                            ProgressView()
                                .controlSize(.large)
                        }
                    }
                    .background(.black)
                }
            }
            .background(.black)
            .onAppear {
                PlayerDiagnostics.log("view appeared")
                startInitialPlayback()
            }
            .onDisappear {
                PlayerDiagnostics.log("view disappeared")
                teardownPlayer()
            }
            .onReceive(player.periodicTimePublisher(forInterval: .init(value: 1, timescale: 1))) { time in
                let seconds = max(time.seconds, .zero)
                guard seconds.isFinite else { return }

                lastPlaybackTime = seconds
                savePlaybackPosition(seconds, for: season, episode)
            }
            .onReceive(player: player, at: \.playbackState) { playbackState in
                handlePlaybackStateChange(playbackState)
            }
            .onExitCommand {
                dismiss()
            }
        }
    }

    private extension PillarboxPlayerView {
        func handlePlaybackStateChange(_ playbackState: PlaybackState) {
            PlayerDiagnostics.log(
                "playback state changed: state=\(playbackState), shouldPlay=\(player.shouldPlay), items=\(player.items.count), time=\(PlayerDiagnostics.secondsDescription(currentResumeTime())), error=\(PlayerDiagnostics.errorDescription(activeError))",
            )

            guard playbackState == .ended else { return }
            guard nextEpisodeSelection() != nil else { return }

            playNextEpisode()
        }

        var activeError: Error? {
            networkError ?? player.error
        }

        var shouldShowProgress: Bool {
            isLoading || player.items.isEmpty
        }

        var availablePlaybackSpeeds: [Float] {
            [0.5, 1.0, 1.25, 1.5, 2.0].filter { player.playbackSpeedRange.contains($0) }
        }

        var qualityBinding: Binding<String> {
            Binding {
                quality
            } set: { newQuality in
                guard newQuality != quality else { return }

                let autoplay = player.shouldPlay
                let resumeTime = currentResumeTime()
                let subtitleLanguage = currentSubtitleLanguage()

                quality = newQuality
                manifestRefreshAttempts = 0
                loadCurrentItem(
                    startAt: resumeTime,
                    autoplay: autoplay,
                    preferredSubtitleLanguage: subtitleLanguage,
                )
            }
        }

        var subtitlesBinding: Binding<MediaSelectionOption> {
            Binding {
                player.mediaOption(for: .legible).wrappedValue
            } set: { newValue in
                player.mediaOption(for: .legible).wrappedValue = newValue
                saveSelectionState(subtitlesLanguage: subtitleLanguage(from: newValue))
            }
        }

        var playbackSpeedBinding: Binding<Float> {
            Binding {
                player.playbackSpeed
            } set: { newSpeed in
                rate = newSpeed
                player.playbackSpeed = newSpeed
            }
        }

        var canGoToPreviousEpisode: Bool {
            previousEpisodeSelection() != nil
        }

        var canGoToNextEpisode: Bool {
            nextEpisodeSelection() != nil
        }

        @TransportBarContentBuilder
        func transportBarContent() -> TransportBarContent {
            if canGoToPreviousEpisode {
                Button("Previous Episode", systemImage: "backward.end.fill") {
                    playPreviousEpisode()
                }
            }

            if canGoToNextEpisode {
                Button("Next Episode", systemImage: "forward.end.fill") {
                    playNextEpisode()
                }
            }

            if movie.getAvailableQualities().count > 1 {
                Picker("Quality", systemImage: "rectangle.badge.checkmark", selection: qualityBinding) {
                    for value in movie.getAvailableQualities() {
                        Option(value, value: value)
                    }
                }
            }

            if !player.mediaSelectionOptions(for: .legible).isEmpty {
                Picker("Subtitles", systemImage: "captions.bubble", selection: subtitlesBinding) {
                    for option in player.mediaSelectionOptions(for: .legible) {
                        Option(option.displayName, value: option)
                    }
                }
            }

            if !availablePlaybackSpeeds.isEmpty {
                Picker("Playback Speed", systemImage: "speedometer", selection: playbackSpeedBinding) {
                    for speed in availablePlaybackSpeeds {
                        Option("\(speed, specifier: "%g")x", value: speed)
                    }
                }
            }
        }

        @InfoViewTabsContentBuilder
        func infoViewTabsContent() -> InfoViewTabsContent {
            if let seasons, !seasons.isEmpty {
                Tab(title: "Episodes") {
                    EpisodeSelectionTabView(
                        seasons: seasons,
                        selectedSeason: season,
                        selectedEpisode: episode,
                        onSelect: selectEpisode,
                    )
                    .frame(height: 420)
                }
            }
        }
    }

    private extension PillarboxPlayerView {
        func startInitialPlayback(force: Bool = false) {
            guard force || !isStarted else { return }

            PlayerDiagnostics.log(
                "start initial playback: force=\(force), quality=\(quality), storedPosition=\(PlayerDiagnostics.secondsDescription(storedPlaybackPosition(for: season, episode))), subtitle=\(storedSubtitleLanguage() ?? "automatic")",
            )

            isStarted = true
            if force {
                manifestRefreshAttempts = 0
            }
            player.actionAtItemEnd = .pause
            player.playbackSpeed = rate

            loadCurrentItem(
                startAt: storedPlaybackPosition(for: season, episode),
                autoplay: true,
                preferredSubtitleLanguage: storedSubtitleLanguage(),
            )
        }

        func teardownPlayer() {
            PlayerDiagnostics.log(
                "teardown player: time=\(PlayerDiagnostics.secondsDescription(currentResumeTime())), selectedSubtitle=\(currentSubtitleLanguage() ?? "automatic"), playbackSpeed=\(player.playbackSpeed)",
            )

            savePlaybackPosition(currentResumeTime(), for: season, episode)
            saveSelectionState(subtitlesLanguage: currentSubtitleLanguage())

            rate = player.playbackSpeed
            player.pause()
            player.removeAllItems()
            player.resignActive()

            subscriptions.removeAll()
            resourceLoader = nil
        }

        func loadCurrentItem(startAt: Double, autoplay: Bool, preferredSubtitleLanguage: String?) {
            PlayerDiagnostics.log(
                "load item requested: quality=\(quality), startAt=\(PlayerDiagnostics.secondsDescription(startAt)), autoplay=\(autoplay), preferredSubtitle=\(preferredSubtitleLanguage ?? "automatic")",
            )

            guard let item = makePlayerItem(startAt: startAt) else { return }

            isLoading = false
            networkError = nil

            player.items = [item]
            player.becomeActive()
            player.playbackSpeed = rate

            if let preferredSubtitleLanguage, !preferredSubtitleLanguage.isEmpty {
                player.setMediaSelectionPreference(.on(languages: preferredSubtitleLanguage), for: .legible)
            } else {
                player.setMediaSelectionPreference(.automatic, for: .legible)
            }

            saveSelectionState(subtitlesLanguage: preferredSubtitleLanguage)
            saveWatchingStateIfNeeded()

            if autoplay {
                player.play()
            } else {
                player.pause()
            }

            PlayerDiagnostics.log(
                "load item finished: autoplay=\(autoplay), playbackSpeed=\(player.playbackSpeed), items=\(player.items.count)",
            )
        }

        func makePlayerItem(startAt: Double) -> PlayerItem? {
            guard let streamURLs = movie.getFallbackURLs(startingAt: quality)?.compactMap(\.hls), !streamURLs.isEmpty else {
                PlayerDiagnostics.log(
                    "make item failed: no stream URLs for quality=\(quality), availableQualities=\(movie.getAvailableQualities())",
                )

                networkError = PillarboxPlayerError.unavailableStream
                return nil
            }

            PlayerDiagnostics.log(
                "make item: selectedQuality=\(quality), availableQualities=\(movie.getAvailableQualities()), fallbackURLs=\(PlayerDiagnostics.urlListDescription(streamURLs)), browserFallback=\(PlayerDiagnostics.browserFallbackDescription(movie.fallback))",
            )

            let metadata = PillarboxPlaybackMetadata(
                details: details,
                voiceActingName: voiceActing.name,
                posterURL: URL(string: details.poster),
                seasonNumber: displaySeasonNumber(),
                episodeNumber: displayEpisodeNumber(),
                episodeTitle: episode?.name,
            )
            let configuration = PlaybackConfiguration(
                position: startAt > .zero ? at(CMTime(seconds: startAt, preferredTimescale: 600)) : at(.zero),
            )

            guard let loader = PillarboxResourceLoaderDelegate(urls: streamURLs, subtitles: movie.subtitles) else {
                PlayerDiagnostics.log("make item failed: resource loader could not create playback URL")

                networkError = PillarboxPlayerError.unavailableStream
                return nil
            }

            resourceLoader = loader
            loader.onManifestFailure = { failedLoader, error in
                guard resourceLoader === failedLoader else {
                    PlayerDiagnostics.log("manifest failure ignored: stale resource loader")
                    return
                }

                handleManifestFailure(error)
            }
            PlayerDiagnostics.log("make item finished: playbackURL=\(PlayerDiagnostics.urlDescription(loader.playbackURL))")
            return .custom(url: loader.playbackURL, delegate: loader, metadata: metadata, configuration: configuration)
        }

        func handleManifestFailure(_ error: Error?) {
            PlayerDiagnostics.log(
                "manifest failure reported to view: attempts=\(manifestRefreshAttempts), error=\(PlayerDiagnostics.errorDescription(error)), currentTime=\(PlayerDiagnostics.secondsDescription(currentResumeTime()))",
            )

            guard manifestRefreshAttempts == 0 else {
                networkError = error ?? PillarboxPlayerError.unavailableStream
                isLoading = false
                return
            }

            let resumeTime = currentResumeTime()
            let autoplay = player.shouldPlay
            let subtitleLanguage = currentSubtitleLanguage()
            let oldURLs = movie.getFallbackURLs(startingAt: quality)?.compactMap(\.hls) ?? []

            manifestRefreshAttempts += 1
            isLoading = true
            networkError = nil

            PlayerDiagnostics.log(
                "refresh stream URLs after manifest failure: quality=\(quality), oldURLs=\(PlayerDiagnostics.urlListDescription(oldURLs))",
            )

            getMovieVideoUseCase(voiceActing: voiceActing, season: season, episode: episode, favs: details.favs)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    isLoading = false

                    guard case let .failure(error) = completion else { return }
                    PlayerDiagnostics.log("refresh stream URLs failed: error=\(PlayerDiagnostics.errorDescription(error))")
                    networkError = error
                } receiveValue: { refreshedMovie in
                    isLoading = false

                    if refreshedMovie.needPremium {
                        PlayerDiagnostics.log("refresh stream URLs returned premium-only movie")
                        dismiss()
                        appState.isPremiumPresented = true
                        return
                    }

                    movie = refreshedMovie
                    quality = preferredQuality(for: refreshedMovie, preferred: quality)

                    let refreshedURLs = refreshedMovie.getFallbackURLs(startingAt: quality)?.compactMap(\.hls) ?? []
                    PlayerDiagnostics.log(
                        "refresh stream URLs loaded: quality=\(quality), availableQualities=\(refreshedMovie.getAvailableQualities()), newURLs=\(PlayerDiagnostics.urlListDescription(refreshedURLs)), changed=\(oldURLs != refreshedURLs), browserFallback=\(PlayerDiagnostics.browserFallbackDescription(refreshedMovie.fallback))",
                    )

                    loadCurrentItem(
                        startAt: resumeTime,
                        autoplay: autoplay,
                        preferredSubtitleLanguage: subtitleLanguage,
                    )
                }
                .store(in: &subscriptions)
        }
    }

    private extension PillarboxPlayerView {
        func selectEpisode(_ targetSeason: MovieSeason, _ targetEpisode: MovieEpisode) {
            guard targetSeason != season || targetEpisode != episode else { return }

            PlayerDiagnostics.log(
                "select episode: season=\(targetSeason.seasonId), episode=\(targetEpisode.episodeId), currentTime=\(PlayerDiagnostics.secondsDescription(currentResumeTime())), autoplay=\(player.shouldPlay)",
            )

            let autoplay = player.shouldPlay
            let subtitleLanguage = currentSubtitleLanguage()

            savePlaybackPosition(currentResumeTime(), for: season, episode)
            isLoading = true
            networkError = nil

            getMovieVideoUseCase(
                voiceActing: voiceActing,
                season: targetSeason,
                episode: targetEpisode,
                favs: details.favs,
            )
            .receive(on: DispatchQueue.main)
            .sink { completion in
                isLoading = false

                guard case let .failure(error) = completion else { return }
                PlayerDiagnostics.log("select episode failed: error=\(PlayerDiagnostics.errorDescription(error))")
                networkError = error
            } receiveValue: { updatedMovie in
                isLoading = false

                PlayerDiagnostics.log(
                    "select episode loaded movie: availableQualities=\(updatedMovie.getAvailableQualities()), subtitles=\(updatedMovie.subtitles.count), needPremium=\(updatedMovie.needPremium), browserFallback=\(PlayerDiagnostics.browserFallbackDescription(updatedMovie.fallback))",
                )

                if updatedMovie.needPremium {
                    dismiss()
                    appState.isPremiumPresented = true
                    return
                }

                season = targetSeason
                episode = targetEpisode
                movie = updatedMovie
                quality = preferredQuality(for: updatedMovie, preferred: quality)
                manifestRefreshAttempts = 0

                PlayerDiagnostics.log("select episode applying quality=\(quality)")

                loadCurrentItem(
                    startAt: storedPlaybackPosition(for: targetSeason, targetEpisode),
                    autoplay: autoplay,
                    preferredSubtitleLanguage: subtitleLanguage,
                )
            }
            .store(in: &subscriptions)
        }

        func playPreviousEpisode() {
            guard let previous = previousEpisodeSelection() else { return }
            selectEpisode(previous.season, previous.episode)
        }

        func playNextEpisode() {
            guard let next = nextEpisodeSelection() else { return }
            selectEpisode(next.season, next.episode)
        }

        func previousEpisodeSelection() -> (season: MovieSeason, episode: MovieEpisode)? {
            guard let seasons,
                  let season,
                  let episode,
                  let seasonIndex = seasons.firstIndex(of: season),
                  let episodeIndex = seasons[seasonIndex].episodes.firstIndex(of: episode)
            else {
                return nil
            }

            if episodeIndex > 0 {
                return (seasons[seasonIndex], seasons[seasonIndex].episodes[episodeIndex - 1])
            }

            guard seasonIndex > 0,
                  let previousEpisode = seasons[seasonIndex - 1].episodes.last
            else {
                return nil
            }

            return (seasons[seasonIndex - 1], previousEpisode)
        }

        func nextEpisodeSelection() -> (season: MovieSeason, episode: MovieEpisode)? {
            guard let seasons,
                  let season,
                  let episode,
                  let seasonIndex = seasons.firstIndex(of: season),
                  let episodeIndex = seasons[seasonIndex].episodes.firstIndex(of: episode)
            else {
                return nil
            }

            if episodeIndex + 1 < seasons[seasonIndex].episodes.count {
                return (seasons[seasonIndex], seasons[seasonIndex].episodes[episodeIndex + 1])
            }

            guard seasonIndex + 1 < seasons.count,
                  let nextEpisode = seasons[seasonIndex + 1].episodes.first
            else {
                return nil
            }

            return (seasons[seasonIndex + 1], nextEpisode)
        }
    }

    private extension PillarboxPlayerView {
        func storedPlaybackPosition(for season: MovieSeason?, _ episode: MovieEpisode?) -> Double {
            playerPositions.first {
                $0.id == voiceActing.voiceId &&
                    $0.acting == voiceActing.translatorId &&
                    $0.season == season?.seasonId &&
                    $0.episode == episode?.episodeId
            }?.position ?? .zero
        }

        func savePlaybackPosition(_ position: Double, for season: MovieSeason?, _ episode: MovieEpisode?) {
            guard position.isFinite else { return }

            if let existingPosition = playerPositions.first(where: {
                $0.id == voiceActing.voiceId &&
                    $0.acting == voiceActing.translatorId &&
                    $0.season == season?.seasonId &&
                    $0.episode == episode?.episodeId
            }) {
                existingPosition.position = position
            } else {
                modelContext.insert(
                    PlayerPosition(
                        id: voiceActing.voiceId,
                        acting: voiceActing.translatorId,
                        season: season?.seasonId,
                        episode: episode?.episodeId,
                        position: position,
                    ),
                )
            }
        }

        func saveSelectionState(subtitlesLanguage: String?) {
            if let existingSelection = selectPositions.first(where: { $0.id == voiceActing.voiceId }) {
                existingSelection.acting = voiceActing.translatorId
                existingSelection.season = season?.seasonId
                existingSelection.episode = episode?.episodeId
                existingSelection.subtitles = subtitlesLanguage
            } else {
                modelContext.insert(
                    SelectPosition(
                        id: voiceActing.voiceId,
                        acting: voiceActing.translatorId,
                        season: season?.seasonId,
                        episode: episode?.episodeId,
                        subtitles: subtitlesLanguage,
                    ),
                )
            }
        }

        func saveWatchingStateIfNeeded() {
            guard isLoggedIn else { return }

            saveWatchingStateUseCase(voiceActing: voiceActing, season: season, episode: episode)
                .sink { _ in } receiveValue: { _ in }
                .store(in: &subscriptions)
        }

        func storedSubtitleLanguage() -> String? {
            selectPositions.first(where: { $0.id == voiceActing.voiceId })?.subtitles
        }

        func currentSubtitleLanguage() -> String? {
            subtitleLanguage(from: player.selectedMediaOption(for: .legible)) ?? storedSubtitleLanguage()
        }

        func subtitleLanguage(from option: MediaSelectionOption) -> String? {
            switch option {
            case let .on(mediaOption):
                mediaOption.locale?.identifier
            default:
                nil
            }
        }

        func currentResumeTime() -> Double {
            let time = player.time()
            guard time.isValid, time.seconds.isFinite else {
                return lastPlaybackTime
            }
            return max(time.seconds, .zero)
        }
    }

    private extension PillarboxPlayerView {
        func preferredQuality(for movie: MovieVideo, preferred: String) -> String {
            let resolvedQuality = movie.getAvailableQualities().contains(preferred)
                ? preferred
                : (movie.getAvailableQualities().last ?? preferred)

            PlayerDiagnostics.log(
                "resolve preferred quality: preferred=\(preferred), resolved=\(resolvedQuality), available=\(movie.getAvailableQualities())",
            )

            return resolvedQuality
        }

        func displaySeasonNumber() -> Int? {
            guard let seasons,
                  let season,
                  let index = seasons.firstIndex(of: season)
            else {
                return nil
            }
            return index + 1
        }

        func displayEpisodeNumber() -> Int? {
            guard let season,
                  let episode,
                  let index = season.episodes.firstIndex(of: episode)
            else {
                return nil
            }
            return index + 1
        }
    }

    private struct EpisodeSelectionTabView: View {
        let seasons: [MovieSeason]
        let selectedSeason: MovieSeason?
        let selectedEpisode: MovieEpisode?
        let onSelect: (MovieSeason, MovieEpisode) -> Void

        @State private var activeSeasonID: MovieSeason.ID?

        init(seasons: [MovieSeason],
             selectedSeason: MovieSeason?,
             selectedEpisode: MovieEpisode?,
             onSelect: @escaping (MovieSeason, MovieEpisode) -> Void)
        {
            self.seasons = seasons
            self.selectedSeason = selectedSeason
            self.selectedEpisode = selectedEpisode
            self.onSelect = onSelect
            _activeSeasonID = State(initialValue: selectedSeason?.id ?? seasons.first?.id)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose Episode")
                        .font(.title2.weight(.bold))

                    if let activeSeason {
                        Text("\(activeSeason.name) • \(activeSeason.episodes.count) episodes")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(seasons) { season in
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    activeSeasonID = season.id
                                }
                            } label: {
                                SeasonPill(
                                    title: season.name,
                                    subtitle: "\(season.episodes.count)",
                                    isSelected: season.id == activeSeasonID,
                                )
                            }
                            .buttonStyle(OnPressButtonStyle { _ in })
                            .focusEffectDisabled()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)

                ScrollView(.vertical) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 18)],
                        alignment: .leading,
                        spacing: 18,
                    ) {
                        if let activeSeason {
                            ForEach(Array(activeSeason.episodes.enumerated()), id: \.element.id) { index, episode in
                                Button {
                                    onSelect(activeSeason, episode)
                                } label: {
                                    EpisodeCard(
                                        seasonName: activeSeason.name,
                                        episode: episode,
                                        episodeNumber: index + 1,
                                        isCurrent: isCurrentEpisode(activeSeason, episode),
                                    )
                                }
                                .buttonStyle(OnPressButtonStyle { _ in })
                                .focusEffectDisabled()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.visible)
            }
            .padding()
            .infoViewTabPanel()
            .onChange(of: selectedSeason?.id) { _, newValue in
                if let newValue {
                    activeSeasonID = newValue
                }
            }
        }

        private var activeSeason: MovieSeason? {
            seasons.first(where: { $0.id == activeSeasonID }) ?? selectedSeason ?? seasons.first
        }

        private func isCurrentEpisode(_ season: MovieSeason, _ episode: MovieEpisode) -> Bool {
            season == selectedSeason && episode == selectedEpisode
        }
    }

    private struct SeasonPill: View {
        let title: String
        let subtitle: String
        let isSelected: Bool

        @Environment(\.isFocused) private var isFocused

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(backgroundColor, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(borderColor, lineWidth: isFocused ? 2 : 1)
            }
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .shadow(color: shadowColor, radius: isFocused ? 20 : 10, y: isFocused ? 10 : 6)
            .animation(.easeOut(duration: 0.18), value: isFocused)
        }

        private var backgroundColor: Color {
            if isSelected {
                return Color.accentColor.opacity(isFocused ? 0.96 : 0.88)
            }

            return Color.white.opacity(isFocused ? 0.18 : 0.10)
        }

        private var borderColor: Color {
            isFocused ? .white.opacity(0.92) : .white.opacity(isSelected ? 0.16 : 0.10)
        }

        private var shadowColor: Color {
            isSelected ? Color.accentColor.opacity(isFocused ? 0.35 : 0.20) : Color.black.opacity(isFocused ? 0.30 : 0.16)
        }
    }

    private struct EpisodeCard: View {
        let seasonName: String
        let episode: MovieEpisode
        let episodeNumber: Int
        let isCurrent: Bool

        @Environment(\.isFocused) private var isFocused

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text(String(format: "E%02d", episodeNumber))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isCurrent ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(isCurrent ? Color.accentColor : Color.white.opacity(0.08), in: Capsule())

                    Spacer(minLength: 12)

                    if isCurrent {
                        Label("Now Playing", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(episode.name)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(.white)

                    Text(seasonName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Image(systemName: isCurrent ? "play.circle.fill" : "tv")
                        .font(.footnote.weight(.bold))

                    Text(isCurrent ? "Current episode" : "Open episode")
                        .font(.footnote.weight(.medium))
                }
                .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.62))
            }
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .padding(20)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 2 : 1)
            }
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .shadow(color: shadowColor, radius: isFocused ? 20 : 10, y: isFocused ? 10 : 6)
            .animation(.easeOut(duration: 0.18), value: isFocused)
        }

        private var backgroundColor: Color {
            if isCurrent {
                return Color.accentColor.opacity(isFocused ? 0.42 : 0.28)
            }

            return Color.white.opacity(isFocused ? 0.15 : 0.08)
        }

        private var borderColor: Color {
            if isFocused {
                return .white.opacity(0.92)
            }

            return isCurrent ? Color.accentColor.opacity(0.65) : Color.white.opacity(0.08)
        }

        private var shadowColor: Color {
            isCurrent ? Color.accentColor.opacity(isFocused ? 0.34 : 0.18) : Color.black.opacity(isFocused ? 0.28 : 0.14)
        }
    }

    private struct PillarboxPlaybackMetadata: AssetMetadata {
        let details: MovieDetailed
        let voiceActingName: String
        let posterURL: URL?
        let seasonNumber: Int?
        let episodeNumber: Int?
        let episodeTitle: String?

        var playerMetadata: PlayerMetadata {
            PlayerMetadata(
                identifier: details.movieId,
                title: details.nameRussian,
                subtitle: subtitle,
                description: details.description,
                imageSource: imageSource,
                episodeInformation: episodeInformation,
            )
        }

        private var subtitle: String? {
            [voiceActingName, episodeTitle]
                .compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " • ")
        }

        private var imageSource: ImageSource {
            guard let posterURL else { return .none }
            return .url(standardResolution: posterURL)
        }

        private var episodeInformation: EpisodeInformation? {
            guard let episodeNumber else { return nil }

            if let seasonNumber {
                return .long(season: seasonNumber, episode: episodeNumber)
            }

            return .short(episode: episodeNumber)
        }
    }

    private enum PillarboxPlayerError: LocalizedError {
        case unavailableStream

        var errorDescription: String? {
            switch self {
            case .unavailableStream:
                "The selected stream is unavailable."
            }
        }
    }

    private final class PillarboxResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
        @LazyInjected(\.session) private var session

        private let mainScheme = "mainm3u8"
        private let fragmentsScheme = "fragmentsm3u8"
        private let subtitlesScheme = "subtitlesm3u8"
        private let extInfPrefix = "#EXTINF:"

        private let urls: [URL]
        private let subtitles: [MovieSubtitles]
        private let loaderQueue = DispatchQueue(label: "pillarbox.resourceLoader")

        private var m3u8String: String?
        private var playlistDuration = 0.0

        var onManifestFailure: ((PillarboxResourceLoaderDelegate, Error?) -> Void)?

        let playbackURL: URL

        init?(urls: [URL], subtitles: [MovieSubtitles]) {
            guard let playbackURL = urls.first?.replacingScheme(with: mainScheme) else {
                return nil
            }

            self.urls = urls
            self.subtitles = subtitles
            self.playbackURL = playbackURL

            super.init()

            PlayerDiagnostics.log(
                "resource loader created: playbackURL=\(PlayerDiagnostics.urlDescription(playbackURL)), streamURLs=\(PlayerDiagnostics.urlListDescription(urls)), subtitles=\(subtitles.count)",
            )
        }

        func resourceLoader(_: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            guard let scheme = loadingRequest.request.url?.scheme else {
                PlayerDiagnostics.log("resource loader ignored request without scheme")
                return false
            }

            PlayerDiagnostics.log(
                "resource loader request: scheme=\(scheme), url=\(PlayerDiagnostics.urlDescription(loadingRequest.request.url))",
            )

            switch scheme {
            case mainScheme:
                return handleMainRequest(loadingRequest)
            case fragmentsScheme:
                return handleFragmentsRequest(loadingRequest)
            case subtitlesScheme:
                return handleSubtitlesRequest(loadingRequest)
            default:
                PlayerDiagnostics.log("resource loader ignored unsupported scheme=\(scheme)")
                return false
            }
        }

        func resourceLoader(_: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
            PlayerDiagnostics.log(
                "resource loader cancelled: url=\(PlayerDiagnostics.urlDescription(loadingRequest.request.url))",
            )
        }

        private func handleMainRequest(_ loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            PlayerDiagnostics.log("main manifest request started: fallbackURLs=\(PlayerDiagnostics.urlListDescription(urls))")

            let request = session.request(urls.first!, method: .get, headers: [.userAgent(Const.userAgent)])
                .validate(statusCode: 200 ..< 400)
                .interceptor(FallbackInterceptor(urls: urls))
                .responseString { [weak self] response in
                    let statusCode = PlayerDiagnostics.statusCodeDescription(response.response?.statusCode)
                    let responseURL = response.response?.url ?? response.request?.url

                    guard let self else {
                        loadingRequest.finishLoading(with: response.error ?? PillarboxPlayerError.unavailableStream)
                        return
                    }

                    guard let string = response.value,
                          let url = response.request?.url,
                          !string.isEmpty,
                          response.error == nil
                    else {
                        PlayerDiagnostics.log(
                            "main manifest failed: status=\(statusCode), responseURL=\(PlayerDiagnostics.urlDescription(responseURL)), error=\(PlayerDiagnostics.errorDescription(response.error))",
                        )
                        DispatchQueue.main.async {
                            self.onManifestFailure?(self, response.error)
                        }
                        loadingRequest.finishLoading(with: response.error ?? PillarboxPlayerError.unavailableStream)
                        return
                    }

                    PlayerDiagnostics.log(
                        "main manifest loaded: status=\(statusCode), requestURL=\(PlayerDiagnostics.urlDescription(url)), responseURL=\(PlayerDiagnostics.urlDescription(responseURL)), characters=\(string.count)",
                    )

                    processPlaylist(string, url)
                    finishMainRequest(loadingRequest)
                }

            request.resume()
            return true
        }

        private func handleFragmentsRequest(_ loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            guard let m3u8String,
                  let data = m3u8String.data(using: .utf8)
            else {
                PlayerDiagnostics.log("fragments request failed: media playlist is empty")
                return false
            }

            PlayerDiagnostics.log(
                "fragments playlist served: bytes=\(data.count), duration=\(PlayerDiagnostics.secondsDescription(playlistDuration))",
            )

            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()
            return true
        }

        private func handleSubtitlesRequest(_ loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            guard let url = loadingRequest.request.url,
                  let host = url.host,
                  let subtitles = subtitles.first(where: { $0.lang == host }),
                  let data = createSubtitlesPlaylist(withDuration: playlistDuration, subtitles: subtitles).data(using: .utf8)
            else {
                PlayerDiagnostics.log(
                    "subtitles request failed: url=\(PlayerDiagnostics.urlDescription(loadingRequest.request.url)), available=\(subtitles.map(\.lang))",
                )
                return false
            }

            PlayerDiagnostics.log(
                "subtitles playlist served: language=\(subtitles.lang), bytes=\(data.count), duration=\(PlayerDiagnostics.secondsDescription(playlistDuration))",
            )

            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()
            return true
        }

        private func processPlaylist(_ string: String, _ url: URL) {
            let lines = string.components(separatedBy: .newlines).filter { !$0.isEmpty }
            var newLines: [String] = []
            var iterator = lines.makeIterator()
            var segmentURLs: [String] = []

            playlistDuration = .zero

            while let line = iterator.next() {
                newLines.append(line)

                if line.hasPrefix(extInfPrefix), let nextLine = iterator.next() {
                    playlistDuration += duration(from: line)
                    let resolvedURL = URL(
                        string: nextLine,
                        relativeTo: url.pathExtension.isEmpty ? url : url.deletingLastPathComponent(),
                    )?.absoluteString ?? nextLine
                    newLines.append(resolvedURL)
                    segmentURLs.append(resolvedURL)
                }
            }

            m3u8String = newLines.joined(separator: "\n")

            PlayerDiagnostics.log(
                "media playlist processed: sourceURL=\(PlayerDiagnostics.urlDescription(url)), lines=\(lines.count), isMaster=\(string.contains("#EXT-X-STREAM-INF")), segments=\(segmentURLs.count), duration=\(PlayerDiagnostics.secondsDescription(playlistDuration)), firstSegment=\(PlayerDiagnostics.segmentDescription(segmentURLs.first)), lastSegment=\(PlayerDiagnostics.segmentDescription(segmentURLs.last))",
            )
        }

        private func duration(from line: String) -> Double {
            let parts = line.components(separatedBy: ":").filter { !$0.isEmpty }
            guard parts.count > 1 else { return .zero }
            return Double(parts[1].dropLast()) ?? .zero
        }

        private func finishMainRequest(_ loadingRequest: AVAssetResourceLoadingRequest) {
            guard let data = createMainPlaylist().data(using: .utf8) else {
                PlayerDiagnostics.log("main manifest finish failed: generated master playlist is not UTF-8")
                return
            }

            PlayerDiagnostics.log("main manifest served to AVPlayer: bytes=\(data.count)")

            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()
        }

        private func createMainPlaylist() -> String {
            let subtitlesLines = subtitles
                .map(subtitleMediaLine(for:))
                .joined(separator: "\n")
            let streamInfo = subtitles.isEmpty
                ? "#EXT-X-STREAM-INF:BANDWIDTH=1280000,CLOSED-CAPTIONS=NONE\nfragmentsm3u8://foo"
                : "#EXT-X-STREAM-INF:BANDWIDTH=1280000,SUBTITLES=\"subs\",CLOSED-CAPTIONS=NONE\nfragmentsm3u8://foo"

            return """
            #EXTM3U
            \(subtitlesLines)
            \(streamInfo)
            """
        }

        private func createSubtitlesPlaylist(withDuration duration: Double, subtitles: MovieSubtitles) -> String {
            """
            #EXTM3U
            #EXT-X-VERSION:3
            #EXT-X-MEDIA-SEQUENCE:1
            #EXT-X-PLAYLIST-TYPE:VOD
            #EXT-X-ALLOW-CACHE:NO
            #EXT-X-TARGETDURATION:\(Int(duration))
            #EXTINF:\(String(format: "%.3f", duration)), no desc
            \(subtitles.link)
            #EXT-X-ENDLIST
            """
        }

        private func subtitleMediaLine(for subtitles: MovieSubtitles) -> String {
            let language = subtitles.lang.replacingOccurrences(of: "ua", with: "uk")

            return "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"\(subtitles.name)\",DEFAULT=NO,AUTOSELECT=NO,FORCED=NO,URI=\"subtitlesm3u8://\(subtitles.lang)\",LANGUAGE=\"\(language)\""
        }
    }

    private final class FallbackInterceptor: RequestInterceptor, @unchecked Sendable {
        private let urls: [URL]
        private let lock = NSLock()
        private var currentIndex = 0

        init(urls: [URL]) {
            self.urls = urls
        }

        func adapt(_ urlRequest: URLRequest, for _: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
            lock.lock()
            let url = urls[currentIndex]
            lock.unlock()

            var request = urlRequest
            request.url = url

            PlayerDiagnostics.log("fallback adapt: index=\(currentIndex), url=\(PlayerDiagnostics.urlDescription(url))")

            completion(.success(request))
        }

        func retry(_ request: Request, for _: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void) {
            lock.lock()
            defer { lock.unlock() }

            let nextIndex = currentIndex + 1

            guard nextIndex < urls.count else {
                PlayerDiagnostics.log(
                    "fallback exhausted: lastIndex=\(currentIndex), status=\(PlayerDiagnostics.statusCodeDescription(request.response?.statusCode)), error=\(PlayerDiagnostics.errorDescription(error))",
                )
                completion(.doNotRetry)
                return
            }

            PlayerDiagnostics.log(
                "fallback retry: failedIndex=\(currentIndex), nextIndex=\(nextIndex), status=\(PlayerDiagnostics.statusCodeDescription(request.response?.statusCode)), nextURL=\(PlayerDiagnostics.urlDescription(urls[nextIndex])), error=\(PlayerDiagnostics.errorDescription(error))",
            )

            currentIndex = nextIndex
            completion(.retry)
        }
    }

    private enum PlayerDiagnostics {
        static func log(_ message: String) {
            print("[PillarboxDiagnostics] \(message)")
        }

        static func urlListDescription(_ urls: [URL]) -> String {
            urls.enumerated()
                .map { index, url in "#\(index):\(urlDescription(url))" }
                .joined(separator: ", ")
        }

        static func urlDescription(_ url: URL?) -> String {
            guard let url else { return "nil" }

            let host = url.host ?? "no-host"
            let path = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent

            return "\(url.scheme ?? "no-scheme")://\(host)/\(path)"
        }

        static func segmentDescription(_ segment: String?) -> String {
            guard let segment, let url = URL(string: segment) else {
                return segment ?? "nil"
            }

            return urlDescription(url)
        }

        static func secondsDescription(_ seconds: Double) -> String {
            guard seconds.isFinite else { return "invalid" }

            return String(format: "%.3fs", seconds)
        }

        static func statusCodeDescription(_ statusCode: Int?) -> String {
            statusCode.map(String.init) ?? "nil"
        }

        static func errorDescription(_ error: Error?) -> String {
            error.map { String(describing: $0) } ?? "nil"
        }

        static func browserFallbackDescription(_ fallback: MovieVideo.BrowserFallback?) -> String {
            guard let fallback else { return "nil" }

            return "stream=\(urlDescription(fallback.stream)), streamUri=\(fallback.streamUri ?? "nil"), autoswitch=\(fallback.autoswitch), restartHost=\(urlDescription(fallback.restartHost)), geo=\(fallback.geoISO ?? "nil")/\(fallback.geoIP ?? "nil"), tst=\(fallback.tst.map(String.init) ?? "nil")"
        }
    }

    private extension URL {
        func replacingScheme(with scheme: String) -> URL? {
            guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else {
                return nil
            }

            components.scheme = scheme
            return components.url
        }
    }

#else

    struct PillarboxPlayerView: View {
        private let data: PlayerData

        init(data: PlayerData) {
            self.data = data
        }

        var body: some View {
            LegacyPlayerView(data: data)
        }
    }

#endif
