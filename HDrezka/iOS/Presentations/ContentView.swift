import Alamofire
import Combine
import Defaults
import FactoryKit
import Perception
import SwiftSoup
import SwiftUI

struct ContentView: View {
    @Injected(\.logoutUseCase) private var logoutUseCase
    @Injected(\.getVersionUseCase) private var getVersionUseCase

    @Default(.isLoggedIn) private var isLoggedIn
    @Default(.mirror) private var mirror
    @Default(.lastHdrezkaAppVersion) private var lastHdrezkaAppVersion
    @Default(.isFirstLaunch) private var isFirstLaunch

    @Environment(AppState.self) private var appState

    @State private var error: Error?
    @State private var isErrorPresented = false
    @State private var subscriptions: Set<AnyCancellable> = []

    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var appState = appState

            TabView(selection: $appState.selectedTab) {
                Tabs.home
                    .tabItem {
                        Label {
                            Text(Tabs.home.label)
                        } icon: {
                            Image(systemName: Tabs.home.image)
                        }
                    }
                    .tag(Tabs.home)

                Tabs.search
                    .tabItem {
                        Label {
                            Text(Tabs.search.label)
                        } icon: {
                            Image(systemName: Tabs.search.image)
                        }
                    }
                    .tag(Tabs.search)

                Tabs.categories
                    .tabItem {
                        Label {
                            Text(Tabs.categories.label)
                        } icon: {
                            Image(systemName: Tabs.categories.image)
                        }
                    }
                    .tag(Tabs.categories)

                Tabs.collections
                    .tabItem {
                        Label {
                            Text(Tabs.collections.label)
                        } icon: {
                            Image(systemName: Tabs.collections.image)
                        }
                    }
                    .tag(Tabs.collections)

                Tabs.profile
                    .tabItem {
                        Label {
                            Text(Tabs.profile.label)
                        } icon: {
                            Image(systemName: Tabs.profile.image)
                        }
                    }
                    .tag(Tabs.profile)
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
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $appState.isSignUpPresented) {
                SignUpSheetView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $appState.isRestorePresented) {
                RestoreSheetView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(item: $appState.presentedDetailsMovie) { movie in
                DetailsView(movie: movie)
            }
            .onChange(of: isLoggedIn) { _ in
                if !isLoggedIn, appState.selectedTab == .profile {
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
            .sheet(isPresented: $appState.commentsRulesPresented) {
                CommentsRulesSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
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
}
