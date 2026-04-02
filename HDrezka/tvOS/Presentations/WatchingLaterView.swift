import SwiftData
import SwiftUI

struct WatchingLaterView: View {
    private let title = String(localized: "key.watching_later")

    @State private var viewModel = WatchingLaterViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 260, maximum: .infinity), spacing: 24, alignment: .topLeading),
    ]

    @Environment(\.modelContext) private var modelContext

    @Query private var playerPositions: [PlayerPosition]

    var body: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                if let movies = viewModel.state.data, !movies.isEmpty {
                    ForEach(movies) { movie in
                        WatchingLaterCardView(movie: movie)
                            .contextMenu {
                                Button {
                                    viewModel.switchWatchedItem(movie: movie)
                                } label: {
                                    Text(movie.watched ? String(localized: "key.mark.unwatched") : String(localized: "key.mark.watched"))
                                }

                                Button(role: .destructive) {
                                    viewModel.removeWatchingItem(movie: movie)

                                    playerPositions
                                        .filter { $0.id == movie.watchLaterId.id }
                                        .forEach { modelContext.delete($0) }
                                } label: {
                                    Text("key.delete")
                                }
                            }
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 18)
            .padding(.horizontal, 36)
        }
        .scrollIndicators(.visible, axes: .vertical)
        .overlay {
            if let error = viewModel.state.error {
                ErrorStateView(error) {
                    viewModel.load()
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 36)
            } else if let movies = viewModel.state.data, movies.isEmpty {
                EmptyStateView(String(localized: "key.watching_later.empty"), String(localized: "key.watching_later.empty.description")) {
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
        .transition(.opacity)
        .navigationTitle(title)
        .onAppear {
            switch viewModel.state {
            case .data:
                break
            default:
                viewModel.load()
            }
        }
        .alert("key.ops", isPresented: $viewModel.isErrorPresented) {
            Button(role: .cancel) {} label: {
                Text("key.ok")
            }
        } message: {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            }
        }
        .background(.background)
    }
}
