import Combine
import FactoryKit
import Perception
import SwiftUI

@Perceptible
class PersonViewModel {
    @PerceptionIgnored @LazyInjected(\.getPersonDetailsUseCase) private var getPersonDetailsUseCase

    @PerceptionIgnored let id: String

    init(id: String) {
        self.id = id
    }

    private(set) var state: DataState<PersonDetailed> = .loading

    @PerceptionIgnored private var subscriptions: Set<AnyCancellable> = []

    func load() {
        state = .loading

        getPersonDetailsUseCase(id: id)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                guard case let .failure(error) = completion else { return }

                withAnimation(.easeInOut) {
                    self.state = .error(error)
                }
            } receiveValue: { detail in
                withAnimation(.easeInOut) {
                    self.state = .data(detail)
                }
            }
            .store(in: &subscriptions)
    }
}
