//
//  HDrezkaApp.swift
//  HDrezka
//
//  Created by Alex Hafros on 15.01.2026.
//

import Combine
import Defaults
import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import Kingfisher
import SwiftData
import SwiftUI
import UserNotifications

@main
struct HDrezkaApp: App {
//    @State private var appState: AppState = .shared
//    @State private var downloader: Downloader = .shared
    @State private var cookiesManager: CookiesManager = .shared

    @State private var modelContainer: ModelContainer

    @Default(.theme) private var theme
    @Default(.isFirstLaunch) private var isFirstLaunch

    init() {
        do {
            let schema = Schema([PlayerPosition.self, SelectPosition.self])
            let modelContainer = try ModelContainer(for: schema)
            modelContainer.mainContext.autosaveEnabled = true
            self.modelContainer = modelContainer

//            Downloader.shared.setModelContext(modelContext: modelContainer.mainContext)

            let cache = ImageCache.default

            switch Defaults[.cache] {
            case .off:
                cache.memoryStorage.config.expiration = .expired
                cache.diskStorage.config.expiration = .expired
            case .memory:
                cache.diskStorage.config.expiration = .expired
            case .disk:
                cache.memoryStorage.config.expiration = .expired
            case .all:
                break
            }
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
//                .environment(appState)
//                .environment(downloader)
                .environment(cookiesManager)
                .preferredColorScheme(theme.scheme)
        }
        .modelContainer(modelContainer)
    }
}
