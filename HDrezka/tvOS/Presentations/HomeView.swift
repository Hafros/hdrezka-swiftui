//
//  HomeView.swift
//  HDrezka
//
//  Created by Alex Hafros on 19.01.2026.
//

import Defaults
import SwiftUI

struct HomeView: View {
    private let title = String(localized: "key.home")

    @State private var viewModel = HomeViewModel()

    @State private var movieDestination: MovieSimple?

    @FocusState private var headerFocus: HeaderFocus?

    enum HeaderFocus: Hashable {
        case seeAll(Category.ID)
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let categories = viewModel.state.data, !categories.isEmpty {
                    ForEach(categories) { category in
                        Section {
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 18) {
                                    ForEach(category.movies) { movie in
                                        NavigationLink(value: Destinations.details(movie)) {
                                            TVPosterViewRepresentable(movie: movie)
                                        }
//                                        CardView(movie: movie)
//                                            .frame(width: 300)
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
                                            .foregroundStyle(Color.accentColor)

                                        Image(systemName: "chevron.right")
                                            .font(.subheadline)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .focused($headerFocus, equals: .seeAll(category.id))
                            }
                            .defaultFocus($headerFocus, .seeAll(category.id))
                            .viewModifier { view in
                                view.focusSection()
                            }
                            .padding(.horizontal, 36)
                        }

                        if category.category != Categories.allCases.last {
                            Divider().padding(.horizontal, 36)
                        }
                    }
                }
            }
            .scrollTargetLayout()
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
        .onScrollTargetVisibilityChange(idType: Category.ID.self) { onScreenCategories in
            if viewModel.paginationState == .idle,
               let categories = viewModel.state.data,
               !categories.isEmpty,
               let last = categories.last,
               onScreenCategories.contains(where: { $0 == last.id })
            {
                viewModel.loadMore()
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
        .onAppear {
            switch viewModel.state {
            case .data:
                break
            default:
                viewModel.load()
            }
        }
        .navigationDestination(item: $movieDestination) {
            DetailsView(movie: $0)
        }
    }
}
