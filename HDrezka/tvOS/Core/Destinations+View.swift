//
//  Destinations+View.swift
//  HDrezka
//
//  Created by Alex Hafros on 30.01.2026.
//

import SwiftUI

extension View {
    @ViewBuilder
    func destinations() -> some View {
        navigationDestination(for: Destinations.self) { destination in
            switch destination {
//            case .watchingLater:
//                WatchingLaterView()
//                    .id("watching_later")
//                    .analyticsScreen(name: destination.name, class: destination.className)
//            case .bookmarks:
//                BookmarksView()
//                    .id("bookmarks")
//                    .analyticsScreen(name: destination.name, class: destination.className)
            case let .details(movie):
                DetailsView(movie: movie)
                    .id(movie.movieId)

            default:
                fatalError()
//                    .analyticsScreen(name: destination.name, class: destination.className)
//            case let .country(country):
//                ListView(country: country)
//                    .id(country.countryId)
//                    .analyticsScreen(name: destination.name, class: destination.className)
//            case let .category(category):
//                ListView(category: category)
//                    .id(category)
//                    .analyticsScreen(name: destination.name, class: destination.className)
//            case let .genre(genre):
//                ListView(genre: genre)
//                    .id(genre.genreId)
//                    .analyticsScreen(name: destination.name, class: destination.className)
//            case let .collection(collection):
//                ListView(collection: collection)
//                    .id(collection.collectionId)
//                    .analyticsScreen(name: destination.name, class: destination.className)
//            case let .customList(movies, title):
//                ListView(movies: movies, title: title)
//                    .id(title)
//                    .analyticsScreen(name: destination.name, class: destination.className)
//            case let .list(list):
//                ListView(list: list)
//                    .id(list.listId)
//                    .analyticsScreen(name: destination.name, class: destination.className)
//            case let .person(person):
//                PersonView(person: person)
//                    .id(person.personId)
//                    .analyticsScreen(name: destination.name, class: destination.className)
//            case let .comments(details):
//                CommentsView(details: details)
//                    .id(details.movieId)
//                    .analyticsScreen(name: destination.name, class: destination.className)
//            case .settings:
//                SettingsView()
//                    .id("settings")
//                    .analyticsScreen(name: destination.name, class: destination.className)
//            case .licenses:
//                LicensesView()
//                    .id("licenses")
//                    .analyticsScreen(name: destination.name, class: destination.className)
//            case .downloads:
//                DownloadsView()
//                    .id("downloads")
//                    .analyticsScreen(name: destination.name, class: destination.className)
            }
        }
    }
}
