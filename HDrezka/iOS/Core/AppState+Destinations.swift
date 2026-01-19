//
//  AppState+Destinations.swift
//  HDrezka
//
//  Created by Alex Hafros on 19.01.2026.
//

import SwiftUI

enum Destinations: Hashable, Identifiable {
    case watchingLater
    case bookmarks
    case details(MovieSimple)
    case country(MovieCountry)
    case category(Categories)
    case genre(MovieGenre)
    case collection(MoviesCollection)
    case customList([MovieSimple], String)
    case list(MovieList)
    case person(PersonSimple)
    case comments(MovieDetailed)
    case settings
    case licenses
    case downloads

    static func fromNamed(_ item: some Named) -> Destinations {
        if let country = item as? MovieCountry {
            return .country(country)
        } else if let genre = item as? MovieGenre {
            return .genre(genre)
        } else if let person = item as? PersonSimple {
            return .person(person)
        } else if let list = item as? MovieList {
            return .list(list)
        } else if let collection = item as? MoviesCollection {
            return .collection(collection)
        }

        fatalError("Need \"named\" implementation")
    }

    var name: String {
        switch self {
        case .details:
            "details"
        case .country, .category, .genre, .collection, .customList, .list:
            "list"
        case .person:
            "person"
        case .comments:
            "comments"
        case .watchingLater:
            "watching_later"
        case .bookmarks:
            "bookmarks"
        case .settings:
            "setting"
        case .licenses:
            "licenses"
        case .downloads:
            "downloads"
        }
    }

    var className: String {
        switch self {
        case .details:
            "DetailsView"
        case .country, .category, .genre, .collection, .customList, .list:
            "ListView"
        case .person:
            "PersonView"
        case .comments:
            "CommentsView"
        case .watchingLater:
            "WatchingLaterView"
        case .bookmarks:
            "BookmarksView"
        case .settings:
            "SettingView"
        case .licenses:
            "LicensesView"
        case .downloads:
            "DownloadsView"
        }
    }

    var id: Self { self }
}

extension View {
    @ViewBuilder
    func destinations() -> some View {
        navigationDestination(for: Destinations.self) { destination in
            switch destination {
            case .watchingLater:
                WatchingLaterView()
                    .id("watching_later")
                    .analyticsScreen(name: destination.name, class: destination.className)
            case .bookmarks:
                BookmarksView()
                    .id("bookmarks")
                    .analyticsScreen(name: destination.name, class: destination.className)
            case let .details(movie):
                DetailsView(movie: movie)
                    .id(movie.movieId)
                    .analyticsScreen(name: destination.name, class: destination.className)
            case let .country(country):
                ListView(country: country)
                    .id(country.countryId)
                    .analyticsScreen(name: destination.name, class: destination.className)
            case let .category(category):
                ListView(category: category)
                    .id(category)
                    .analyticsScreen(name: destination.name, class: destination.className)
            case let .genre(genre):
                ListView(genre: genre)
                    .id(genre.genreId)
                    .analyticsScreen(name: destination.name, class: destination.className)
            case let .collection(collection):
                ListView(collection: collection)
                    .id(collection.collectionId)
                    .analyticsScreen(name: destination.name, class: destination.className)
            case let .customList(movies, title):
                ListView(movies: movies, title: title)
                    .id(title)
                    .analyticsScreen(name: destination.name, class: destination.className)
            case let .list(list):
                ListView(list: list)
                    .id(list.listId)
                    .analyticsScreen(name: destination.name, class: destination.className)
            case let .person(person):
                PersonView(person: person)
                    .id(person.personId)
                    .analyticsScreen(name: destination.name, class: destination.className)
            case let .comments(details):
                CommentsView(details: details)
                    .id(details.movieId)
                    .analyticsScreen(name: destination.name, class: destination.className)
            case .settings:
                SettingsView()
                    .id("settings")
                    .analyticsScreen(name: destination.name, class: destination.className)
            case .licenses:
                LicensesView()
                    .id("licenses")
                    .analyticsScreen(name: destination.name, class: destination.className)
            case .downloads:
                DownloadsView()
                    .id("downloads")
                    .analyticsScreen(name: destination.name, class: destination.className)
            }
        }
    }
}
