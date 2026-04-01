//
//  TVPosterViewRepresentable.swift
//  HDrezka
//
//  Created by Alex Hafros on 31.01.2026.
//

import Kingfisher
import SwiftUI
import TVUIKit

struct TVPosterViewRepresentable: UIViewRepresentable {
    let movie: MovieSimple
    let posterWidth = CGFloat(UIScreen.main.bounds.width / 4) - 20
    let posterHeight = CGFloat(((UIScreen.main.bounds.width / 4) - 20) * 281 / 500)
//    let onSelect: () -> Void

    func makeUIView(context _: Context) -> TVPosterView {
        let poster = TVPosterView()
//        poster.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didSelect)))
        poster.isUserInteractionEnabled = true
        return poster
    }

    func updateUIView(_ uiView: TVPosterView, context _: Context) {
        uiView.contentSize = CGSize(width: posterHeight, height: posterWidth)
        if let name = movie.name, let details = movie.details {
            uiView.title = name
            uiView.subtitle = details
        }
        if let poster = movie.poster,
           let url = URL(string: poster)
        {
            KF.url(url)
                .loadDiskFileSynchronously()
                .cacheMemoryOnly(false)
                .fade(duration: 0.25)
                .set(to: uiView.imageView)
        } else {
            uiView.image = nil
        }
    }

//    func makeCoordinator() -> Coordinator {
//        Coordinator(onSelect: onSelect)
//    }

//    class Coordinator: NSObject {
//        let onSelect: () -> Void
//        init(onSelect: @escaping () -> Void) { self.onSelect = onSelect }
//        @objc func didSelect() { onSelect() }
//    }
}
