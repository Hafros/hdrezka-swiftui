import Defaults
import Perception
import SwiftUI

struct HomeView: View {
    private let title = String(localized: "key.home")

    @State private var viewModel = HomeViewModel()

    @State private var movieDestination: MovieSimple?

    var body: some View {
        WithPerceptionTracking {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let categories = viewModel.state.data, !categories.isEmpty {
                        ForEach(categories) { category in
                            Section {
                                ScrollView(.horizontal) {
                                    LazyHStack(alignment: .top, spacing: 18) {
                                        ForEach(category.movies) { movie in
                                            CardView(movie: movie, reservesSpace: true)
                                                .frame(width: 150)
                                        }
                                    }
                                    .padding(.horizontal, 36)
                                }
                                .scrollIndicators(.never)
                            } header: {
                                HStack(alignment: .center, spacing: 9) {
                                    Text(category.title).font(.system(.title, weight: .semibold))

                                    Spacer()

                                    NavigationLink(value: Destinations.category(category.category)) {
                                        HStack(alignment: .center) {
                                            Text("key.see_all")
                                                .font(.subheadline)

                                            Image(systemName: "chevron.right")
                                                .font(.subheadline)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.roundedRectangle(radius: 6))
                                }
                                .padding(.horizontal, 36)
                            }
                            .onAppear {
                                guard viewModel.paginationState == .idle,
                                      let last = viewModel.state.data?.last,
                                      category.id == last.id
                                else {
                                    return
                                }

                                viewModel.loadMore()
                            }

                            if category.category != Categories.allCases.last {
                                Divider().padding(.horizontal, 36)
                            }
                        }
                    }
                }
                .padding(.vertical, 18)

                if let error = viewModel.paginationState.error {
                    ErrorPaginationStateView(error) {
                        viewModel.loadMore(reset: true)
                    }
                } else if viewModel.paginationState == .loading {
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
                } else if let categories = viewModel.state.data, categories.isEmpty {
                    EmptyStateView(String(localized: "key.home.empty")) {
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.isSeriesUpdatesPresented = true
                    } label: {
                        Image(systemName: "bell")
                    }
                    .disabled(viewModel.state.data == nil)
                }
            }
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
            .sheet(isPresented: $viewModel.isSeriesUpdatesPresented) {
                SeriesUpdatesSheetView(movieDestination: $movieDestination)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .navigationDestination(isPresented: Binding(
                get: { movieDestination != nil },
                set: { isPresented in
                    if !isPresented {
                        movieDestination = nil
                    }
                },
            )) {
                if let movieDestination {
                    DetailsView(movie: movieDestination)
                }
            }
        }
    }
}
