//
//  CollectionsView.swift
//  HDrezka
//
//  Created by Alex Hafros on 19.01.2026.
//

import Kingfisher
import SwiftUI

struct CollectionsView: View {
    private let title = String(localized: "key.collections")

    @State private var viewModel = CollectionsViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 320, maximum: 460), spacing: 24, alignment: .topLeading),
    ]

    var body: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                if let collections = viewModel.state.data, !collections.isEmpty {
                    ForEach(collections) { collection in
                        TVCollectionCardView(collection: collection)
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
        .onScrollTargetVisibilityChange(idType: MoviesCollection.ID.self) { onScreenCards in
            if viewModel.paginationState == .idle,
               let collections = viewModel.state.data,
               !collections.isEmpty,
               let last = collections.last,
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
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    viewModel.load()
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
                viewModel.load()
            }
        }
    }
}

private struct TVCollectionCardView: View {
    let collection: MoviesCollection

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        NavigationLink(value: Destinations.collection(collection)) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    if let poster = collection.poster,
                       let url = URL(string: poster)
                    {
                        KFImage
                            .url(url)
                            .setProcessor(DownsamplingImageProcessor(size: geometry.size))
                            .placeholder {
                                Color.gray.shimmering()
                            }
                            .resizable()
                            .cancelOnDisappear(true)
                            .fade(duration: 0.2)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipShape(.rect(cornerRadius: 28))
                    }

                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.14), Color.black.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom,
                    )
                    .clipShape(.rect(cornerRadius: 28))

                    Text(collection.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(18)
                }
                .overlay(alignment: .topTrailing) {
                    if let count = collection.count {
                        TVDarkBadge(text: "\(count)")
                            .padding(14)
                    }
                }
                .background(Color.black.opacity(0.22), in: .rect(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(isFocused ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
                }
            }
            .aspectRatio(1.72, contentMode: .fit)
            .contentShape(.rect(cornerRadius: 28))
        }
        .buttonStyle(OnPressButtonStyle { _ in })
        .focusEffectDisabled()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(collection.name))
        .accessibilityHint(Text("key.open"))
    }
}
