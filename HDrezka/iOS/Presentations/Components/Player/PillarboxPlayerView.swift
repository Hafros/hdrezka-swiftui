import SwiftUI

#if canImport(PillarboxPlayer)
    import PillarboxPlayer
#endif

struct PillarboxPlayerView: View {
    private let data: PlayerData

    init(data: PlayerData) {
        self.data = data
    }

    var body: some View {
        // Parallel migration scaffold: keep behavior stable while Pillarbox backend is integrated step-by-step.
        LegacyPlayerView(data: data)
    }
}
