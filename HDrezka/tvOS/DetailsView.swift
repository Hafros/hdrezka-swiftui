//
//  DetailsView.swift
//  HDrezka
//
//  Created by Alex Hafros on 19.01.2026.
//

import SwiftUI

struct DetailsView: View {
    private let title: String?

    @State private var viewModel: DetailsViewModel

    init(movie: MovieSimple) {
        title = movie.name
        viewModel = DetailsViewModel(id: movie.movieId)
    }

    var body: some View {
        Rectangle()
            .fill()
    }
}
