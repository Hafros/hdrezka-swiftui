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
                startInitialPlayback()
            }
            .onDisappear {
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
            guard playbackState == .ended else { return }
            guard let next = nextEpisodeSelection() else { return }

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

            isStarted = true
            player.actionAtItemEnd = .pause
            player.playbackSpeed = rate

            loadCurrentItem(
                startAt: storedPlaybackPosition(for: season, episode),
                autoplay: true,
                preferredSubtitleLanguage: storedSubtitleLanguage(),
            )
        }

        func teardownPlayer() {
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
        }

        func makePlayerItem(startAt: Double) -> PlayerItem? {
            guard let streamURL = movie.getClosestTo(quality: quality)?.hls else {
                networkError = PillarboxPlayerError.unavailableStream
                return nil
            }

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

            if movie.subtitles.isEmpty {
                resourceLoader = nil
                return .simple(url: streamURL, metadata: metadata, configuration: configuration)
            }

            guard let loader = PillarboxResourceLoaderDelegate(m3u8: streamURL, subtitles: movie.subtitles) else {
                networkError = PillarboxPlayerError.unavailableStream
                return nil
            }

            resourceLoader = loader
            return .custom(url: loader.playbackURL, delegate: loader, metadata: metadata, configuration: configuration)
        }
    }

    private extension PillarboxPlayerView {
        func selectEpisode(_ targetSeason: MovieSeason, _ targetEpisode: MovieEpisode) {
            guard targetSeason != season || targetEpisode != episode else { return }

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
                networkError = error
            } receiveValue: { updatedMovie in
                isLoading = false

                if updatedMovie.needPremium {
                    dismiss()
                    appState.isPremiumPresented = true
                    return
                }

                season = targetSeason
                episode = targetEpisode
                movie = updatedMovie
                quality = preferredQuality(for: updatedMovie, preferred: quality)

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
            movie.getAvailableQualities().contains(preferred)
                ? preferred
                : (movie.getAvailableQualities().last ?? preferred)
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

        var body: some View {
            List {
                ForEach(seasons) { season in
                    Section(season.name) {
                        ForEach(season.episodes) { episode in
                            Button {
                                onSelect(season, episode)
                            } label: {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(episode.name)
                                            .foregroundStyle(.primary)

                                        if isCurrentEpisode(season, episode) {
                                            Text("Now Playing")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if isCurrentEpisode(season, episode) {
                                        Image(systemName: "play.fill")
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .infoViewTabPanel()
        }

        private func isCurrentEpisode(_ season: MovieSeason, _ episode: MovieEpisode) -> Bool {
            season == selectedSeason && episode == selectedEpisode
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

        private let m3u8: URL
        private let subtitles: [MovieSubtitles]
        private let loaderQueue = DispatchQueue(label: "pillarbox.resourceLoader")

        private var m3u8String: String?
        private var playlistDuration = 0.0

        let playbackURL: URL

        init?(m3u8: URL, subtitles: [MovieSubtitles]) {
            guard let playbackURL = m3u8.replacingScheme(with: mainScheme) else {
                return nil
            }

            self.m3u8 = m3u8
            self.subtitles = subtitles
            self.playbackURL = playbackURL

            super.init()
        }

        func resourceLoader(_: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            guard let scheme = loadingRequest.request.url?.scheme else {
                return false
            }

            switch scheme {
            case mainScheme:
                return handleMainRequest(loadingRequest)
            case fragmentsScheme:
                return handleFragmentsRequest(loadingRequest)
            case subtitlesScheme:
                return handleSubtitlesRequest(loadingRequest)
            default:
                return false
            }
        }

        private func handleMainRequest(_ loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            let request = session.request(m3u8, method: .get, headers: [.userAgent(Const.userAgent)])
                .validate(statusCode: 200 ..< 400)
                .responseString { [weak self] response in
                    guard let self,
                          let string = response.value,
                          !string.isEmpty,
                          response.error == nil
                    else {
                        loadingRequest.finishLoading(with: response.error)
                        return
                    }

                    processPlaylist(string)
                    finishMainRequest(loadingRequest)
                }

            request.resume()
            return true
        }

        private func handleFragmentsRequest(_ loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            guard let m3u8String,
                  let data = m3u8String.data(using: .utf8)
            else {
                return false
            }

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
                return false
            }

            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()
            return true
        }

        private func processPlaylist(_ string: String) {
            let lines = string.components(separatedBy: .newlines).filter { !$0.isEmpty }
            var newLines: [String] = []
            var iterator = lines.makeIterator()

            playlistDuration = .zero

            while let line = iterator.next() {
                newLines.append(line)

                if line.hasPrefix(extInfPrefix), let nextLine = iterator.next() {
                    playlistDuration += duration(from: line)
                    let resolvedURL = URL(
                        string: nextLine,
                        relativeTo: m3u8.pathExtension.isEmpty ? m3u8 : m3u8.deletingLastPathComponent(),
                    )?.absoluteString ?? nextLine
                    newLines.append(resolvedURL)
                }
            }

            m3u8String = newLines.joined(separator: "\n")
        }

        private func duration(from line: String) -> Double {
            let parts = line.components(separatedBy: ":").filter { !$0.isEmpty }
            guard parts.count > 1 else { return .zero }
            return Double(parts[1].dropLast()) ?? .zero
        }

        private func finishMainRequest(_ loadingRequest: AVAssetResourceLoadingRequest) {
            guard let data = createMainPlaylist().data(using: .utf8) else {
                return
            }

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
