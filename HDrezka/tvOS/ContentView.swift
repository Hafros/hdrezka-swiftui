//
//  ContentView.swift
//  HDrezka
//
//  Created by Alex Hafros on 19.01.2026.
//

import Alamofire
import Combine
import Defaults
import FactoryKit
import Pow
import SwiftSoup
import SwiftUI

struct ContentView: View {
    @Injected(\.logoutUseCase) private var logoutUseCase
    @Injected(\.getVersionUseCase) private var getVersionUseCase

    @Default(.isLoggedIn) private var isLoggedIn
    @Default(.mirror) private var mirror
    @Default(.isUserPremium) private var isUserPremium
    @Default(.lastHdrezkaAppVersion) private var lastHdrezkaAppVersion
    @Default(.isFirstLaunch) private var isFirstLaunch
    @Default(.snow) private var snow
    @Default(.forceSnow) private var forceSnow

    @Environment(AppState.self) private var appState

    @State private var showDays = false

    @State private var error: Error?
    @State private var isErrorPresented: Bool = false

    @State private var subscriptions: Set<AnyCancellable> = []

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: Binding<Tabs>(
            get: { appState.selectedTab },
            set: { newValue in appState.selectedTab = newValue },
        )) {
            ForEach(Tabs.allCases.filter { !$0.needAccount }) { tab in
                tab
                    .tabItem {
                        Label {
                            Text(tab.label)
                        } icon: {
                            Image(systemName: tab.image)
                        }
                    }
                    .tag(tab)
            }

            if isLoggedIn {
                ForEach(Tabs.allCases.filter(\.needAccount)) { tab in
                    tab
                        .tabItem {
                            Label {
                                Text(tab.label)
                            } icon: {
                                Image(systemName: tab.image)
                            }
                        }
                        .tag(tab)
                }
            }
        }
        .onAppear {
            getVersionUseCase()
                .receive(on: DispatchQueue.main)
                .sink { _ in } receiveValue: { version in
                    lastHdrezkaAppVersion = version
                }
                .store(in: &subscriptions)
        }
        .sheet(isPresented: $appState.isSignInPresented) {
            SignInSheetView()
                .presentationSizing(.fitted)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: isLoggedIn) {
            if !isLoggedIn, appState.selectedTab.needAccount {
                appState.selectedTab = .home
            }
        }
        .confirmationDialog("key.sign_out.label", isPresented: $appState.isSignOutPresented) {
            Button(role: .destructive) {
                logoutUseCase()
                    .receive(on: DispatchQueue.main)
                    .sink { completion in
                        guard case let .failure(error) = completion else { return }

                        self.error = error
                        isErrorPresented = true
                    } receiveValue: { success in
                        isErrorPresented = !success
                    }
                    .store(in: &subscriptions)
            } label: {
                Text("key.yes")
            }
        } message: {
            Text("key.sign_out.q")
        }
        .alert("key.ops", isPresented: $isErrorPresented) {
            Button(role: .cancel) {} label: {
                Text("key.ok")
            }
        } message: {
            if let error {
                Text(error.localizedDescription)
            }
        }
        .confirmationDialog("key.premium_content", isPresented: $appState.isPremiumPresented) {
            Link("key.buy", destination: (!_mirror.isDefaultValue ? mirror : Const.redirectMirror).appending(path: "payments", directoryHint: .notDirectory))
        } message: {
            Text("key.premium.description")
        }
        .alert("key.disclaimer", isPresented: $isFirstLaunch) {
            Button(role: .cancel) {} label: {
                Text("key.ok")
            }
        } message: {
            Text("key.disclaimer.description")
        }
    }
}
