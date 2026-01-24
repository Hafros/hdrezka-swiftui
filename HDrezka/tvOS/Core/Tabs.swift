//
//  Tabs.swift
//  HDrezka
//
//  Created by Alex Hafros on 19.01.2026.
//

import SwiftUI

enum Tabs: Hashable, Identifiable, CaseIterable, View {
    case home
    case categories
    case collections
    case search
    case watchingLater
    case bookmarks

    var label: LocalizedStringKey {
        switch self {
        case .home:
            "key.home"
        case .search:
            "key.search"
        case .categories:
            "key.categories"
        case .collections:
            "key.collections"
        case .watchingLater:
            "key.watching_later"
        case .bookmarks:
            "key.bookmarks"
        }
    }

    var image: String {
        switch self {
        case .home:
            "house"
        case .search:
            "magnifyingglass"
        case .categories:
            "square.grid.2x2"
        case .collections:
            "film.stack"
        case .watchingLater:
            "clock.arrow.circlepath"
        case .bookmarks:
            "bookmark"
        }
    }

    var needAccount: Bool {
        switch self {
        case .watchingLater, .bookmarks:
            true
        default:
            false
        }
    }

    var name: String {
        switch self {
        case .home:
            "home"
        case .search:
            "search"
        case .categories:
            "categories"
        case .collections:
            "collections"
        case .watchingLater:
            "watching_later"
        case .bookmarks:
            "bookmarks"
        }
    }

    var className: String {
        switch self {
        case .home:
            "HomeView"
        case .search:
            "SearchView"
        case .categories:
            "CategoriesView"
        case .collections:
            "CollectionsView"
        case .watchingLater:
            "WatchingLaterView"
        case .bookmarks:
            "BookmarksView"
        }
    }

    var body: some View {
        NavigationStack {
            switch self {
            case .home:
                HomeView()
                    .id("home")
//                    .destinations()
                    .analyticsScreen(name: name, class: className)
            case .search:
                SearchView()
                    .id("search")
//                    .destinations()
                    .analyticsScreen(name: name, class: className)
            case .categories:
                CategoriesView()
                    .id("categories")
//                    .destinations()
                    .analyticsScreen(name: name, class: className)
            case .collections:
                CollectionsView()
                    .id("collections")
//                    .destinations()
                    .analyticsScreen(name: name, class: className)
            case .watchingLater:
                WatchingLaterView()
                    .id("watching_later")
//                    .destinations()
                    .analyticsScreen(name: name, class: className)
            case .bookmarks:
                BookmarksView()
                    .id("bookmarks")
//                    .destinations()
                    .analyticsScreen(name: name, class: className)
            }
        }
    }

    var id: Self { self }
}
