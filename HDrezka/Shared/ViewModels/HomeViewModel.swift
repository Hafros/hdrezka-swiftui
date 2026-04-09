import Combine
import FactoryKit
import Perception
import SwiftUI

@Perceptible
class HomeViewModel {
    @PerceptionIgnored @LazyInjected(\.getHotMoviesUseCase) private var getHotMoviesUseCase
//    @PerceptionIgnored @LazyInjected(\.getFeaturedMoviesUseCase) private var getFeaturedMoviesUseCase
    @PerceptionIgnored @LazyInjected(\.getWatchingNowMoviesUseCase) private var getWatchingNowMoviesUseCase
    @PerceptionIgnored @LazyInjected(\.getLatestMoviesUseCase) private var getLatestMoviesUseCase
    @PerceptionIgnored @LazyInjected(\.getLatestNewestMoviesUseCase) private var getLatestNewestMoviesUseCase
    @PerceptionIgnored @LazyInjected(\.getPopularMoviesUseCase) private var getPopularMoviesUseCase
    @PerceptionIgnored @LazyInjected(\.getSoonMoviesUseCase) private var getSoonMoviesUseCase

    @PerceptionIgnored private var subscriptions: Set<AnyCancellable> = []

    private(set) var state: DataState<[Category]> = .loading
    private(set) var paginationState: DataPaginationState = .idle

    var isSeriesUpdatesPresented: Bool = false

    private func getPublisher(category: Categories) -> AnyPublisher<[MovieSimple], Error> {
        switch category {
        case .hot: getHotMoviesUseCase(genre: 0)
//            case .featured: getFeaturedMoviesUseCase(page: 1, genre: 0)
        case .watchingNow: getWatchingNowMoviesUseCase(page: 1, genre: 0)
        case .latest: getLatestMoviesUseCase(page: 1, genre: 0)
        case .newest: getLatestNewestMoviesUseCase(page: 1, genre: 0)
        case .popular: getPopularMoviesUseCase(page: 1, genre: 0)
        case .soon: getSoonMoviesUseCase(page: 1, genre: 0)
        }
    }

    private func loadAllCategories() {
        let publishers = Categories.allCases.enumerated().map { index, category in
            getPublisher(category: category)
                .map { movies in
                    (index, Category(category: category, title: category.localized, movies: movies))
                }
                .eraseToAnyPublisher()
        }

        Publishers.MergeMany(publishers)
            .collect()
            .map { categories in
                categories
                    .sorted { $0.0 < $1.0 }
                    .map(\.1)
            }
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case let .failure(error) = completion {
                    withAnimation(.easeInOut) {
                        self.state = .error(error)
                        self.paginationState = .error(error)
                    }
                }
            } receiveValue: { categories in
                withAnimation(.easeInOut) {
                    self.state = .data(categories)
                    self.paginationState = .idle
                }
            }
            .store(in: &subscriptions)
    }

    func load() {
        subscriptions.removeAll()
        state = .loading
        paginationState = .idle

        loadAllCategories()
    }

    func loadMore(reset: Bool = false) {
        guard reset else { return }

        if state.data == nil {
            load()
        }
    }
}
