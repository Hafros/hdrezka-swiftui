//
//  Tabs+Views.swift
//  HDrezka
//
//  Created by Alex Hafros on 19.01.2026.
//

import SwiftUI

extension Tabs: View {
    var body: some View {
        NavigationStack {
            switch self {
            case .home:
                HomeView()
                    .id("home")
                    .destinations()
                    .analyticsScreen(name: name, class: className)
            case .search:
                SearchView()
                    .id("search")
                    .destinations()
                    .analyticsScreen(name: name, class: className)
            case .categories:
                CategoriesView()
                    .id("categories")
                    .destinations()
                    .analyticsScreen(name: name, class: className)
            case .collections:
                CollectionsView()
                    .id("collections")
                    .destinations()
                    .analyticsScreen(name: name, class: className)
            case .profile:
                ProfileView()
                    .id("profile")
                    .destinations()
                    .analyticsScreen(name: name, class: className)
            }
        }
    }
}
