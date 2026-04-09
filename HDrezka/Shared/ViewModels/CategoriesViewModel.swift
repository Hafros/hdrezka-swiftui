import Combine
import FactoryKit
import Perception
import SwiftUI

@Perceptible
class CategoriesViewModel {
    @PerceptionIgnored @LazyInjected(\.categoriesUseCase) private var categoriesUseCase

    private(set) var state: DataState<[MovieType]> = .loading

    @PerceptionIgnored private var subscriptions: Set<AnyCancellable> = []

    func load() {
        state = .loading

        categoriesUseCase()
            .receive(on: DispatchQueue.main)
            .sink { completion in
                guard case let .failure(error) = completion else { return }

                withAnimation(.easeInOut) {
                    self.state = .error(error)
                }
            } receiveValue: { types in
                withAnimation(.easeInOut) {
                    self.state = .data(types)
                }
            }
            .store(in: &subscriptions)
    }
}
