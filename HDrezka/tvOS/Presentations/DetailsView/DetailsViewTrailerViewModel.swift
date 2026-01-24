//
//  DetailsViewTrailerViewModel.swift
//  HDrezka
//
//  Created by Alex Hafros on 21.01.2026.
//

import Foundation
import YouTubeKit

@Observable
class DetailsViewTrailerViewModel {
    enum State: Equatable {
        case idle
        case url(URL)
        case error
    }

    private let trailerId: String?
    private(set) var state: State = .idle

    init(trailerId: String?) {
        self.trailerId = trailerId
    }

    func start() async {
        guard let trailerId else {
            state = .error
            return
        }
        let video = YouTube(videoID: trailerId)
        do {
            let streams = try await video.streams
            if let url = streams.highestResolutionStream()?.url {
                state = .url(url)
            } else {
                state = .error
            }
        } catch {
            state = .error
        }
    }
}
