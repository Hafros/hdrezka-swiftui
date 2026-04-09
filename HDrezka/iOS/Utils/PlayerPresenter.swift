import FirebaseAnalytics
import SwiftUI
import UIKit

enum PlayerPresenter {
    static func present(data: PlayerData) {
        present(data: data, attempt: 0)
    }

    private static func present(data: PlayerData, attempt: Int) {
        guard let rootVC = presentationController() else { return }

        if shouldRetryPresentation(for: rootVC), attempt < 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                present(data: data, attempt: attempt + 1)
            }
            return
        }

        let view = PlayerView(data: data)
            .environment(AppState.shared)
            .analyticsScreen(name: "player", class: "PlayerView")

        let hostingController = UIHostingController(rootView: view)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.modalTransitionStyle = .crossDissolve

        rootVC.present(hostingController, animated: true)
    }

    private static func presentationController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        let windows = scenes.flatMap(\.windows)
        let rootController = windows.first(where: \.isKeyWindow)?.rootViewController
            ?? windows.first(where: { !$0.isHidden && $0.windowLevel == .normal })?.rootViewController

        return topViewController(base: rootController)
    }

    private static func topViewController(base: UIViewController?) -> UIViewController? {
        guard let base else { return nil }

        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }

        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }

        if let presented = base.presentedViewController,
           !presented.isBeingDismissed,
           presented.viewIfLoaded?.window != nil
        {
            return topViewController(base: presented)
        }

        return base
    }

    private static func shouldRetryPresentation(for controller: UIViewController) -> Bool {
        if controller.isBeingDismissed || controller.isBeingPresented {
            return true
        }

        if controller.viewIfLoaded?.window == nil {
            return true
        }

        if let transitionCoordinator = controller.transitionCoordinator,
           transitionCoordinator.isAnimated
        {
            return true
        }

        return false
    }
}
