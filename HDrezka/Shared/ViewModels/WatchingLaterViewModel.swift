import Combine
import FactoryKit
import Perception
import SwiftUI

@Perceptible
class WatchingLaterViewModel {
    @PerceptionIgnored @LazyInjected(\.getWatchingLaterMoviesUseCase) private var getWatchingLaterMoviesUseCase
    @PerceptionIgnored @LazyInjected(\.switchWatchedItemUseCase) private var switchWatchedItemUseCase
    @PerceptionIgnored @LazyInjected(\.removeWatchingItemUseCase) private var removeWatchingItemUseCase

    @PerceptionIgnored private var subscriptions: Set<AnyCancellable> = []

    private(set) var state: DataState<[MovieWatchLater]> = .loading

    private(set) var error: Error?
    var isErrorPresented: Bool = false

    func load() {
        state = .loading

        getWatchingLaterMoviesUseCase()
            .receive(on: DispatchQueue.main)
            .sink { completion in
                guard case let .failure(error) = completion else { return }

                // Avoid animating full-screen state transitions for large lists.
                self.state = .error(error)
            } receiveValue: { result in
                // Inserting hundreds of cards with animation is noticeably slow.
                self.state = .data(result)
            }
            .store(in: &subscriptions)
    }

    func switchWatchedItem(movie: MovieWatchLater) {
        switchWatchedItemUseCase(item: movie)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                guard case let .failure(error) = completion else { return }

                self.error = error
                self.isErrorPresented = true
            } receiveValue: { result in
                if result, var movies = self.state.data {
                    if let index = movies.firstIndex(of: movie) {
                        movies[index].watched.toggle()

                        if !movie.watched {
                            movies.move(
                                fromOffsets: IndexSet(integer: index),
                                toOffset: movies.count,
                            )
                        }

                        withAnimation(.easeInOut) {
                            self.state = .data(movies)
                        }
                    }
                }
            }
            .store(in: &subscriptions)
    }

    func removeWatchingItem(movie: MovieWatchLater) {
        removeWatchingItemUseCase(item: movie)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                guard case let .failure(error) = completion else { return }

                self.error = error
                self.isErrorPresented = true
            } receiveValue: { delete in
                if delete, var movies = self.state.data {
                    movies.removeAll(where: {
                        $0.id == movie.id
                    })

                    withAnimation(.easeInOut) {
                        self.state = .data(movies)
                    }
                }
            }
            .store(in: &subscriptions)
    }
}
