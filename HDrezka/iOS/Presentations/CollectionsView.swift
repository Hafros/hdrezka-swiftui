import Defaults
import Perception
import SwiftUI

struct CollectionsView: View {
    private let title = String(localized: "key.collections")

    @State private var viewModel = CollectionsViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: .infinity), spacing: 18, alignment: .topLeading),
    ]

    var body: some View {
        WithPerceptionTracking {
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    if let collections = viewModel.state.data, !collections.isEmpty {
                        ForEach(collections) { collection in
                            CollectionCardView(collection: collection)
                                .onAppear {
                                    if viewModel.paginationState == .idle,
                                       collection.id == collections.last?.id
                                    {
                                        viewModel.loadMore()
                                    }
                                }
                        }
                    }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 36)

                if viewModel.paginationState == .loading {
                    LoadingPaginationStateView()
                }
            }
            .scrollIndicators(.visible, axes: .vertical)
            .viewModifier { view in
                if #available(iOS 26, *) {
                    view.scrollEdgeEffectStyle(.soft, for: .all)
                } else {
                    view
                }
            }
            .overlay {
                if let error = viewModel.state.error {
                    ErrorStateView(error) {
                        viewModel.load()
                    }
                    .padding(.vertical, 18)
                    .padding(.horizontal, 36)
                } else if let collections = viewModel.state.data, collections.isEmpty {
                    EmptyStateView(String(localized: "key.collections.empty")) {
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
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                switch viewModel.state {
                case .data:
                    break
                default:
                    viewModel.load()
                }
            }
            .refreshable {
                if viewModel.state.data?.isEmpty == false {
                    viewModel.load()
                }
            }
            .background(.background)
        }
    }
}
