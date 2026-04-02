import AVKit
import Combine
import Defaults
import FactoryKit
import Kingfisher
import MediaPlayer
import SwiftData
import SwiftUI

struct PlayerView: View {
    @Default(.usePillarboxPlayerOnTvOS) private var usePillarboxPlayerOnTvOS

    private let data: PlayerData

    init(data: PlayerData) {
        self.data = data
    }

    var body: some View {
        Group {
            if usePillarboxPlayerOnTvOS {
                PillarboxPlayerView(data: data)
            } else {
                LegacyPlayerView(data: data)
            }
        }
    }
}

struct LegacyPlayerView: View {
    @Injected(\.saveWatchingStateUseCase) private var saveWatchingStateUseCase
    @Injected(\.getMovieThumbnailsUseCase) private var getMovieThumbnailsUseCase
    @Injected(\.getMovieVideoUseCase) private var getMovieVideoUseCase

    @Default(.isLoggedIn) private var isLoggedIn
    @Default(.spatialAudio) private var spatialAudio
    @Default(.rate) private var rate
    @Default(.volume) private var volume
    @Default(.isMuted) private var isMuted
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Environment(AppState.self) private var appState

    @Query private var playerPositions: [PlayerPosition]
    @Query private var selectPositions: [SelectPosition]

    @State private var playerSubscriptions: Set<AnyCancellable> = []
    @State private var layerSubscriptions: Set<AnyCancellable> = []

    private let poster: String
    private let name: String
    private let favs: String
    private let voiceActing: MovieVoiceActing

    private let times: [Int]

    @State private var seasons: [MovieSeason]?
    @State private var season: MovieSeason?
    @State private var episode: MovieEpisode?
    @State private var movie: MovieVideo
    @State private var quality: String

    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()

    @State private var player: AVPlayer?
    @State private var playerLayer: AVPlayerLayer?
    @State private var pipController: AVPictureInPictureController?
    @State private var isPictureInPictureActive: Bool = false
    @State private var isPictureInPicturePossible: Bool = false
    @State private var videoGravity: AVLayerVideoGravity = .resizeAspect
    @State private var loadedTimeRanges: [CMTimeRange] = []
    @State private var timeObserverToken: Any?
    private let rates: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]
    @State private var timer: Int?
    @State private var timerWork: DispatchWorkItem?
    @State private var nextTimer: CGFloat?
    @State private var currentTime: Double = .zero
    @State private var duration: Double = .greatestFiniteMagnitude
    @State private var error: Error?
    @State private var subtitles: String?
    @State private var isPlaying: Bool = true
    @State private var isLoading: Bool = true
    @State private var isMaskShow: Bool = true
    @State private var delayHide: DispatchWorkItem?
    @State private var subtitlesOptions: [AVMediaSelectionOption] = []
    @State private var thumbnails: WebVTT?
    @State private var initialVolume: Float = .zero
    @State private var topInset: CGFloat = .zero

    init(data: PlayerData) {
        poster = data.details.poster
        name = data.details.nameRussian
        favs = data.details.favs
        voiceActing = data.selectedActing

        seasons = data.seasons
        season = data.selectedSeason
        episode = data.selectedEpisode
        movie = data.movie
        quality = data.selectedQuality

        times = data.details.series != nil ? [900, 1800, 2700, 3600, -1] : [900, 1800, 2700, 3600]

        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    var body: some View {
        Group {
            if let error {
                ErrorStateView(error) {
                    resetPlayer {
                        setupPlayer(subtitles: subtitles)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(36)
            } else if let player {
                SystemVideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaPadding(.top)
        .ignoresSafeArea(edges: .top)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onAppear {
            initialVolume = volume

            setupPlayer(subtitles: selectPositions.first(where: { position in position.id == voiceActing.voiceId })?.subtitles)
        }
        .onDisappear {
            resetPlayer()
        }
        .onChange(of: scenePhase) {
            guard let player,
                  player.status == .readyToPlay
            else {
                return
            }

            switch scenePhase {
            case .active:
                break
            default:
                if !isPictureInPictureActive, isPlaying {
                    player.pause()
                }
            }
        }
        .onChange(of: spatialAudio) {
            guard let player,
                  player.status == .readyToPlay,
                  let currentItem = player.currentItem
            else {
                return
            }

            currentItem.allowedAudioSpatializationFormats = spatialAudio.format
        }
        .onExitCommand {
            dismiss()
        }
    }

    private func setupPlayer(seek: CMTime? = nil, isPlaying playing: Bool = true, subtitles: String? = nil) {
        guard let url = movie.getClosestTo(quality: quality)?.hls else { return }

        let player = CustomAVPlayer(m3u8: url, subtitles: movie.subtitles)

        if let player, let currentItem = player.currentItem {
            nowPlayingInfoCenter.nowPlayingInfo = [:]

            if let thumbnails = movie.thumbnails {
                getMovieThumbnailsUseCase(path: thumbnails)
                    .receive(on: DispatchQueue.main)
                    .sink { _ in } receiveValue: { thumbnails in
                        self.thumbnails = thumbnails
                    }
                    .store(in: &playerSubscriptions)
            }

            timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: .main) { time in
                let currentTime = time.seconds

                self.currentTime = currentTime

                nowPlayingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
                nowPlayingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = rate
                nowPlayingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyCurrentPlaybackDate] = currentItem.currentDate()
                nowPlayingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyDefaultPlaybackRate] = player.defaultRate

                if let position = playerPositions.first(where: { position in
                    position.id == voiceActing.voiceId &&
                        position.acting == voiceActing.translatorId &&
                        position.season == season?.seasonId &&
                        position.episode == episode?.episodeId
                }) {
                    position.position = currentTime
                } else {
                    let position = PlayerPosition(
                        id: voiceActing.voiceId,
                        acting: voiceActing.translatorId,
                        season: season?.seasonId,
                        episode: episode?.episodeId,
                        position: currentTime,
                    )

                    modelContext.insert(position)
                }

                updateNextTimer()
            }

            player.publisher(for: \.status)
                .receive(on: DispatchQueue.main)
                .sink { status in
                    switch status {
                    case .readyToPlay:
                        if isLoggedIn {
                            saveWatchingStateUseCase(voiceActing: voiceActing, season: season, episode: episode)
                                .sink { _ in } receiveValue: { _ in }
                                .store(in: &playerSubscriptions)
                        }

                        if let position = selectPositions.first(where: { position in
                            position.id == voiceActing.voiceId
                        }) {
                            position.acting = voiceActing.translatorId
                            position.season = season?.seasonId
                            position.episode = episode?.episodeId
                        } else {
                            let position = SelectPosition(
                                id: voiceActing.voiceId,
                                acting: voiceActing.translatorId,
                                season: season?.seasonId,
                                episode: episode?.episodeId,
                            )

                            modelContext.insert(position)
                        }

                        currentItem.asset.loadMediaSelectionGroup(for: .legible) { mediaSelectionGroup, _ in
                            if let mediaSelectionGroup {
                                currentItem.select(mediaSelectionGroup.options.filter { $0.extendedLanguageTag != nil }.first(where: { $0.extendedLanguageTag == subtitles }), in: mediaSelectionGroup)

                                withAnimation(.easeInOut(duration: 0.15)) {
                                    subtitlesOptions = mediaSelectionGroup.options.filter { $0.extendedLanguageTag != nil }
                                } completion: {
                                    self.subtitles = subtitles
                                }
                            }
                        }

                        if let seasons, let season, let episode {
                            remoteCommandCenter.previousTrackCommand.addTarget { _ in
                                prevTrack(seasons, season, episode)

                                return .success
                            }

                            remoteCommandCenter.nextTrackCommand.addTarget { _ in
                                nextTrack(seasons, season, episode)

                                return .success
                            }

                            remoteCommandCenter.previousTrackCommand.isEnabled = seasons.element(before: season) != nil || season.episodes.element(before: episode) != nil
                            remoteCommandCenter.nextTrackCommand.isEnabled = seasons.element(after: season) != nil || season.episodes.element(after: episode) != nil
                        }

                        updateNextTimer()

                        if let seek {
                            player.seek(to: seek, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                                if playing {
                                    player.playImmediately(atRate: rate)
                                }
                            }
                        } else {
                            if let position = playerPositions.first(where: { position in
                                position.id == voiceActing.voiceId &&
                                    position.acting == voiceActing.translatorId &&
                                    position.season == season?.seasonId &&
                                    position.episode == episode?.episodeId
                            }) {
                                player.seek(to: CMTime(seconds: position.position, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                                    if playing {
                                        player.playImmediately(atRate: rate)
                                    }
                                }
                            } else if playing {
                                player.playImmediately(atRate: rate)
                            }
                        }
                    default:
                        break
                    }
                }
                .store(in: &playerSubscriptions)

            player.publisher(for: \.timeControlStatus)
                .receive(on: DispatchQueue.main)
                .sink { status in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        switch status {
                        case .playing:
                            isPlaying = true
                            isLoading = false

                            nowPlayingInfoCenter.playbackState = .playing
                        case .paused:
                            isPlaying = false
                            isLoading = false

                            nowPlayingInfoCenter.playbackState = .paused
                        case .waitingToPlayAtSpecifiedRate:
                            isPlaying = false
                            isLoading = true

                            nowPlayingInfoCenter.playbackState = .paused
                        default:
                            isPlaying = false
                            isLoading = true

                            nowPlayingInfoCenter.playbackState = .paused
                        }
                    }

                    setMask(!isPictureInPictureActive)

                    updateNextTimer()
                }
                .store(in: &playerSubscriptions)

            player.publisher(for: \.isMuted)
                .receive(on: DispatchQueue.main)
                .sink { isMuted in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.isMuted = isMuted
                    }

                    setMask(!isPictureInPictureActive)

                    updateNextTimer()
                }
                .store(in: &playerSubscriptions)

            player.publisher(for: \.volume)
                .receive(on: DispatchQueue.main)
                .sink { volume in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.volume = volume
                    }

                    if isMuted {
                        player.isMuted.toggle()
                    }

                    setMask(!isPictureInPictureActive)

                    updateNextTimer()
                }
                .store(in: &playerSubscriptions)

            player.publisher(for: \.error)
                .compactMap(\.self)
                .handleError()
                .receive(on: DispatchQueue.main)
                .sink { error in
                    resetPlayer {
                        withAnimation(.easeInOut) {
                            self.error = error
                        }
                    }
                }
                .store(in: &playerSubscriptions)

            currentItem.publisher(for: \.duration)
                .compactMap(\.self)
                .filter { $0.isValid && !$0.isIndefinite && !$0.isNegativeInfinity && !$0.isPositiveInfinity && $0.seconds > 0 }
                .receive(on: DispatchQueue.main)
                .sink { duration in
                    self.duration = duration.seconds

                    nowPlayingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = duration.seconds

                    updateNextTimer()
                }
                .store(in: &playerSubscriptions)

            currentItem.publisher(for: \.loadedTimeRanges)
                .compactMap { $0 as? [CMTimeRange] }
                .receive(on: DispatchQueue.main)
                .sink { loadedTimeRanges in
                    self.loadedTimeRanges = loadedTimeRanges
                }
                .store(in: &playerSubscriptions)

            currentItem.publisher(for: \.error)
                .compactMap(\.self)
                .handleError()
                .receive(on: DispatchQueue.main)
                .sink { error in
                    resetPlayer {
                        withAnimation(.easeInOut) {
                            self.error = error
                        }
                    }
                }
                .store(in: &playerSubscriptions)

            NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: currentItem)
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    player.seek(to: CMTime(seconds: 0, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        if isPictureInPictureActive, let pipController {
                            pipController.stopPictureInPicture()
                        } else if timer != -1, let seasons, let season, let episode {
                            nextTrack(seasons, season, episode)
                        }

                        updateNextTimer()
                    }
                }
                .store(in: &playerSubscriptions)

            NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: currentItem)
                .compactMap { $0.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error }
                .handleError()
                .receive(on: DispatchQueue.main)
                .sink { error in
                    resetPlayer {
                        withAnimation(.easeInOut) {
                            self.error = error
                        }
                    }
                }
                .store(in: &playerSubscriptions)

            nowPlayingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyAssetURL] = url
            nowPlayingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
            nowPlayingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyIsLiveStream] = false
            nowPlayingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] = name
            nowPlayingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyAlbumTitle] = voiceActing.name

            if let season, let episode {
                nowPlayingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyArtist] = "Season \(season.name) Episode \(episode.name)"
            }

            if let url = URL(string: poster) {
                KingfisherManager.shared.retrieveImage(with: url) { result in
                    if case let .success(value) = result {
                        nowPlayingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: value.image.size) { _ in value.image }
                    }
                }
            }

            remoteCommandCenter.playCommand.addTarget { _ in
                player.playImmediately(atRate: rate)

                return .success
            }

            remoteCommandCenter.pauseCommand.addTarget { _ in
                player.pause()

                return .success
            }

            remoteCommandCenter.togglePlayPauseCommand.addTarget { _ in
                if isPlaying {
                    player.pause()
                } else {
                    player.playImmediately(atRate: rate)
                }

                return .success
            }

            remoteCommandCenter.changePlaybackPositionCommand.addTarget { event in
                guard let effectiveEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }

                player.seek(to: CMTime(seconds: effectiveEvent.positionTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), toleranceBefore: .zero, toleranceAfter: .zero) { success in
                    if success {
                        updateNextTimer()
                    }
                }

                return .success
            }

            remoteCommandCenter.changePlaybackRateCommand.addTarget { event in
                guard let effectiveEvent = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }

                rate = effectiveEvent.playbackRate
                nowPlayingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = effectiveEvent.playbackRate

                if isPlaying {
                    player.playImmediately(atRate: effectiveEvent.playbackRate)
                }

                return .success
            }

            remoteCommandCenter.pauseCommand.isEnabled = true
            remoteCommandCenter.playCommand.isEnabled = true
            remoteCommandCenter.togglePlayPauseCommand.isEnabled = true
            remoteCommandCenter.changePlaybackPositionCommand.isEnabled = true
            remoteCommandCenter.changePlaybackRateCommand.isEnabled = true
            remoteCommandCenter.changePlaybackRateCommand.supportedPlaybackRates = rates.map { NSNumber(value: $0) }

            remoteCommandCenter.previousTrackCommand.isEnabled = false
            remoteCommandCenter.nextTrackCommand.isEnabled = false
            remoteCommandCenter.stopCommand.isEnabled = false
            remoteCommandCenter.changeRepeatModeCommand.isEnabled = false
            remoteCommandCenter.enableLanguageOptionCommand.isEnabled = false
            remoteCommandCenter.changeShuffleModeCommand.isEnabled = false
            remoteCommandCenter.skipForwardCommand.isEnabled = false
            remoteCommandCenter.skipBackwardCommand.isEnabled = false
            remoteCommandCenter.ratingCommand.isEnabled = false
            remoteCommandCenter.likeCommand.isEnabled = false
            remoteCommandCenter.dislikeCommand.isEnabled = false
            remoteCommandCenter.seekForwardCommand.isEnabled = false
            remoteCommandCenter.seekBackwardCommand.isEnabled = false
            remoteCommandCenter.bookmarkCommand.isEnabled = false
            remoteCommandCenter.disableLanguageOptionCommand.isEnabled = false

            player.volume = volume
            player.isMuted = isMuted

            withAnimation(.easeInOut) {
                self.player = player
            }
        }
    }

    private func resetPlayer(completion: (() -> Void)? = nil) {
        if let timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }

        layerSubscriptions.flush()
        playerSubscriptions.flush()

        nowPlayingInfoCenter.playbackState = .stopped
        nowPlayingInfoCenter.nowPlayingInfo = nil

        remoteCommandCenter.playCommand.removeTarget(nil)
        remoteCommandCenter.pauseCommand.removeTarget(nil)
        remoteCommandCenter.togglePlayPauseCommand.removeTarget(nil)
        remoteCommandCenter.changePlaybackPositionCommand.removeTarget(nil)
        remoteCommandCenter.changePlaybackRateCommand.removeTarget(nil)
        remoteCommandCenter.stopCommand.removeTarget(nil)
        remoteCommandCenter.previousTrackCommand.removeTarget(nil)
        remoteCommandCenter.nextTrackCommand.removeTarget(nil)

        timerWork?.cancel()
        delayHide?.cancel()

        thumbnails = nil

        player?.pause()
        player?.replaceCurrentItem(with: nil)

        withAnimation(.easeInOut) {
            player = nil
            pipController = nil
            error = nil
            nextTimer = nil
            subtitlesOptions = []
            isLoading = true
        } completion: {
            completion?()
        }

        duration = .greatestFiniteMagnitude
        currentTime = 0.0
    }

    private func selectSubtitles(_ language: String?) {
        guard let player,
              let currentItem = player.currentItem
        else {
            return
        }

        currentItem.asset.loadMediaSelectionGroup(for: .legible) { mediaSelectionGroup, _ in
            if let mediaSelectionGroup {
                currentItem.select(mediaSelectionGroup.options.filter { $0.extendedLanguageTag != nil }.first(where: { $0.extendedLanguageTag == language }), in: mediaSelectionGroup)

                if let position = selectPositions.first(where: { position in
                    position.id == voiceActing.voiceId
                }) {
                    position.subtitles = language
                } else {
                    let position = SelectPosition(
                        id: voiceActing.voiceId,
                        acting: voiceActing.translatorId,
                        season: season?.seasonId,
                        episode: episode?.episodeId,
                        subtitles: language,
                    )

                    modelContext.insert(position)
                }
            }
        }
    }

    private func resetTimer() {
        timerWork?.cancel()

        updateNextTimer()

        guard let timer,
              timer > 0,
              isPlaying
        else {
            return
        }

        timerWork = DispatchWorkItem {
            guard let player,
                  player.status == .readyToPlay
            else {
                return
            }

            player.pause()
        }

        if let timerWork {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(timer), execute: timerWork)
        }
    }

    private func setMask(_ newValue: Bool, force: Bool = false) {
        withAnimation(.easeInOut) {
            isMaskShow = newValue
        }

        delayHide?.cancel()

        if newValue, !isLoading, isPlaying, !force {
            delayHide = DispatchWorkItem {
                setMask(false)
            }

            if let delayHide {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: delayHide)
            }
        }
    }

    private func updateNextTimer() {
        if (duration - currentTime) / 60 > 0, (duration - currentTime) / 60 <= 1, let seasons, let season, let episode, seasons.element(after: season) != nil || season.episodes.element(after: episode) != nil, timer != -1, !isPictureInPictureActive {
            withAnimation(.easeInOut) {
                nextTimer = min((duration - currentTime) / 60, 1.0)
            }
        } else if nextTimer != nil {
            withAnimation(.easeInOut) {
                nextTimer = nil
            }
        }
    }

    private func prevTrack(_ seasons: [MovieSeason], _ season: MovieSeason, _ episode: MovieEpisode) {
        if let prevEpisode = season.episodes.element(before: episode) {
            withAnimation(.easeInOut(duration: 0.15)) {
                isLoading = true
            }

            resetPlayer {
                getMovieVideoUseCase(voiceActing: voiceActing, season: season, episode: prevEpisode, favs: favs)
                    .receive(on: DispatchQueue.main)
                    .sink { completion in
                        guard case let .failure(error) = completion else { return }

                        withAnimation(.easeInOut) {
                            self.error = error
                        }
                    } receiveValue: { movie in
                        if movie.needPremium {
                            dismiss()

                            appState.isPremiumPresented = true
                        } else {
                            self.movie = movie
                            self.episode = prevEpisode

                            setupPlayer(subtitles: subtitles)
                        }
                    }
                    .store(in: &playerSubscriptions)
            }
        } else if let prevSeason = seasons.element(before: season), let prevEpisode = prevSeason.episodes.last {
            withAnimation(.easeInOut(duration: 0.15)) {
                isLoading = true
            }

            resetPlayer {
                getMovieVideoUseCase(voiceActing: voiceActing, season: prevSeason, episode: prevEpisode, favs: favs)
                    .receive(on: DispatchQueue.main)
                    .sink { completion in
                        guard case let .failure(error) = completion else { return }

                        withAnimation(.easeInOut) {
                            self.error = error
                        }
                    } receiveValue: { movie in
                        if movie.needPremium {
                            dismiss()

                            appState.isPremiumPresented = true
                        } else {
                            self.movie = movie
                            self.season = prevSeason
                            self.episode = prevEpisode

                            setupPlayer(subtitles: subtitles)
                        }
                    }
                    .store(in: &playerSubscriptions)
            }
        }
    }

    private func nextTrack(_ seasons: [MovieSeason], _ season: MovieSeason, _ episode: MovieEpisode) {
        if let nextEpisode = season.episodes.element(after: episode) {
            withAnimation(.easeInOut(duration: 0.15)) {
                isLoading = true
            }

            resetPlayer {
                getMovieVideoUseCase(voiceActing: voiceActing, season: season, episode: nextEpisode, favs: favs)
                    .receive(on: DispatchQueue.main)
                    .sink { completion in
                        guard case let .failure(error) = completion else { return }

                        withAnimation(.easeInOut) {
                            self.error = error
                        }
                    } receiveValue: { movie in
                        if movie.needPremium {
                            dismiss()

                            appState.isPremiumPresented = true
                        } else {
                            self.movie = movie
                            self.episode = nextEpisode

                            setupPlayer(subtitles: subtitles)
                        }
                    }
                    .store(in: &playerSubscriptions)
            }
        } else if let nextSeason = seasons.element(after: season), let nextEpisode = nextSeason.episodes.first {
            withAnimation(.easeInOut(duration: 0.15)) {
                isLoading = true
            }

            resetPlayer {
                getMovieVideoUseCase(voiceActing: voiceActing, season: nextSeason, episode: nextEpisode, favs: favs)
                    .receive(on: DispatchQueue.main)
                    .sink { completion in
                        guard case let .failure(error) = completion else { return }

                        withAnimation(.easeInOut) {
                            self.error = error
                        }
                    } receiveValue: { movie in
                        if movie.needPremium {
                            dismiss()

                            appState.isPremiumPresented = true
                        } else {
                            self.movie = movie
                            self.season = nextSeason
                            self.episode = nextEpisode

                            setupPlayer(subtitles: subtitles)
                        }
                    }
                    .store(in: &playerSubscriptions)
            }
        }
    }
}

private struct SystemVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context _: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context _: Context) {
        if controller.player !== player {
            controller.player = player
        }

        controller.videoGravity = .resizeAspect
    }
}
