import Defaults
import Perception
import SwiftUI

struct SearchView: View {
    @State private var viewModel = SearchViewModel()

    @FocusState private var searchFocus

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: .infinity), spacing: 18, alignment: .topLeading),
    ]

    var body: some View {
        WithPerceptionTracking {
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    if let movies = viewModel.state.data, !movies.isEmpty {
                        ForEach(movies) { movie in
                            CardView(movie: movie)
                                .onAppear {
                                    if viewModel.paginationState == .idle,
                                       movie.id == movies.last?.id
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
                        viewModel.load(force: true)
                    }
                    .padding(.vertical, 18)
                    .padding(.horizontal, 36)
                } else if let movies = viewModel.state.data, movies.isEmpty {
                    EmptyStateView(String(localized: "key.nothing_found"), String(localized: "key.search.empty"))
                        .padding(.vertical, 18)
                        .padding(.horizontal, 36)
                } else if viewModel.state == .loading {
                    LoadingStateView()
                        .padding(.vertical, 18)
                        .padding(.horizontal, 36)
                }
            }
            .searchable(text: $viewModel.query, placement: .toolbar)
            .viewModifier { view in
                if #available(iOS 18, *) {
                    view.searchFocused($searchFocus)
                } else {
                    view
                }
            }
            .transition(.opacity)
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.large)
            .background(.background)
            .onAppear {
                switch viewModel.state {
                case .data:
                    break
                default:
                    viewModel.load(force: true)
                }

                searchFocus = true
            }
            .refreshable {
                if viewModel.state.data?.isEmpty == false {
                    viewModel.load(force: true)
                }
            }
            .onChange(of: viewModel.query) { _ in
                viewModel.load(force: viewModel.query.trim().isEmpty)
            }
        }
    }
}
