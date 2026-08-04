import Foundation
import OrderedCollections

struct MovieVideo: Identifiable, Codable, Hashable {
    let videos: [Video]
    let subtitles: [MovieSubtitles]
    let needPremium: Bool
    let thumbnails: String?
    let fallback: BrowserFallback?
    let id: UUID

    init(videos: [Video], subtitles: [MovieSubtitles], needPremium: Bool, thumbnails: String?, fallback: BrowserFallback? = nil, id: UUID = .init()) {
        self.videos = videos
        self.subtitles = subtitles
        self.needPremium = needPremium
        self.thumbnails = thumbnails
        self.fallback = fallback
        self.id = id
    }

    func getMaxQuality() -> [URL]? {
        videos.last(where: { !$0.needAccount && !$0.needPremium })?.urls
    }

    func getClosestTo(quality: String) -> [URL]? {
        videos.first(where: { $0.quality == quality })?.urls ?? getMaxQuality()
    }

    func getFallbackURLs(startingAt quality: String) -> [URL]? {
        let availableVideos = videos.filter { !$0.needAccount && !$0.needPremium && !$0.urls.isEmpty }

        guard !availableVideos.isEmpty else {
            return nil
        }

        let startIndex = fallbackStartIndex(in: availableVideos, preferredQuality: quality)
        let lowerQualityVideos = availableVideos[..<startIndex].reversed()
        let higherQualityVideos = availableVideos[availableVideos.index(after: startIndex)...]
        let orderedVideos = [availableVideos[startIndex]] + lowerQualityVideos + higherQualityVideos
        let urls = orderedVideos.flatMap(\.urls)

        return urls.isEmpty ? nil : urls
    }

    private func fallbackStartIndex(in videos: [Video], preferredQuality: String) -> Int {
        let preferredIndex = videos.firstIndex { $0.quality == preferredQuality } ?? videos.index(before: videos.endIndex)

        guard let stableIndex = videos.firstIndex(where: { $0.quality == "720p" }), preferredIndex > stableIndex else {
            return preferredIndex
        }

        return stableIndex
    }

    func getAvailableQualities() -> [String] {
        videos.filter { !$0.needAccount && !$0.needPremium }.map(\.quality)
    }

    func getAccountQualities() -> [String] {
        videos.filter { $0.needAccount && !$0.needPremium }.map(\.quality)
    }

    func getPremiumQualities() -> [String] {
        videos.filter { !$0.needAccount && $0.needPremium }.map(\.quality)
    }

    func getLockedQualities() -> [String] {
        videos.filter { $0.needAccount && $0.needPremium }.map(\.quality)
    }

    struct Video: Identifiable, Codable, Hashable {
        let quality: String
        let urls: [URL]
        let needAccount: Bool
        let needPremium: Bool
        let id: UUID

        init(quality: String, urls: [URL], needAccount: Bool, needPremium: Bool, id: UUID = .init()) {
            self.quality = quality
            self.urls = urls
            self.needAccount = needAccount
            self.needPremium = needPremium
            self.id = id
        }
    }

    struct BrowserFallback: Codable, Hashable {
        let stream: URL?
        let streamUri: String?
        let autoswitch: Bool
        let restartHost: URL?
        let geoIP: String?
        let geoISO: String?
        let tst: Bool?

        var isAvailable: Bool {
            stream != nil || restartHost != nil || autoswitch || streamUri != nil
        }

        init(stream: URL?, streamUri: String?, autoswitch: Bool, restartHost: URL?, geoIP: String?, geoISO: String?, tst: Bool?) {
            self.stream = stream
            self.streamUri = streamUri
            self.autoswitch = autoswitch
            self.restartHost = restartHost
            self.geoIP = geoIP
            self.geoISO = geoISO
            self.tst = tst
        }
    }
}
