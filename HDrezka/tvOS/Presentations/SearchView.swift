//
//  SearchView.swift
//  HDrezka
//
//  Created by Alex Hafros on 19.01.2026.
//

import Defaults
import SwiftUI

struct SearchView: View {
    @State private var viewModel = SearchViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 24, alignment: .topLeading),
    ]

    var body: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                if let movies = viewModel.state.data, !movies.isEmpty {
                    ForEach(movies) { movie in
                        CardView(movie: movie)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 24)
            .padding(.horizontal, 36)

            if viewModel.paginationState == .loading {
                LoadingPaginationStateView()
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .onScrollTargetVisibilityChange(idType: MovieSimple.ID.self) { onScreenCards in
            if viewModel.paginationState == .idle,
               let movies = viewModel.state.data,
               !movies.isEmpty,
               let last = movies.last,
               onScreenCards.contains(where: { $0 == last.id })
            {
                viewModel.loadMore()
            }
        }
        .viewModifier { view in
            if #available(tvOS 26, *) {
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
        .searchable(text: $viewModel.query)
        .transition(.opacity)
        .navigationTitle(viewModel.title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    viewModel.load(force: true)
                } label: {
                    Image(systemName: "arrow.trianglehead.clockwise")
                }
                .disabled(viewModel.state.data?.isEmpty != false)
            }
        }
        .onAppear {
            switch viewModel.state {
            case .data:
                break
            default:
                viewModel.load(force: true)
            }
        }
        .onChange(of: viewModel.query) {
            viewModel.load(force: viewModel.query.trim().isEmpty)
        }
    }
}
