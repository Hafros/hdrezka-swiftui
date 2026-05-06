import FirebaseAnalytics
import Perception
import SwiftUI

@Perceptible
class AppState {
    @PerceptionIgnored static let shared = AppState()

    var isSignInPresented = false
    var isSignUpPresented = false
    var isRestorePresented = false
    var isSignOutPresented = false

    var commentsRulesPresented = false

    var isPremiumPresented = false
    var presentedDetailsMovie: MovieSimple?
    var presentedPlayerData: PlayerData?

    var selectedTab: Tabs = .home
}
