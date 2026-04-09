//
//  Tabs.swift
//  HDrezka
//
//  Created by Alex Hafros on 19.01.2026.
//

import SwiftUI

enum Tabs: Hashable, Identifiable, CaseIterable {
    case home
    case categories
    case collections
    case profile
    case search

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
        case .profile:
            "key.profile"
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
        case .profile:
            "person.crop.circle"
        }
    }

    @available(iOS 18.0, *)
    var role: TabRole? {
        switch self {
        case .search:
            .search
        default:
            nil
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
        case .profile:
            "profile"
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
        case .profile:
            "ProfileView"
        }
    }

    var id: Self { self }
}
