import SwiftUI

/// Presents a survey webview from the top-most view controller in the key window.
final class PresentSurveyManager {
    init() {
        /*
         This empty initializer prevents external instantiation of the PresentSurveyManager class.
         The class serves as a namespace for the present method, so instance creation is not needed and should be restricted.
        */
    }

    /// The view controller that will present the survey window.
    private weak var viewController: UIViewController?

    /// Walks the active presentation/navigation/tab hierarchy and returns the leaf VC.
    /// Mirrors UIKit's own `presentedViewController` traversal so a single walker is enough.
    private func topMostViewController(from viewController: UIViewController) -> UIViewController {
        if let presented = viewController.presentedViewController,
           !presented.isBeingDismissed {
            return topMostViewController(from: presented)
        }
        if let navigation = viewController as? UINavigationController,
           let visible = navigation.visibleViewController {
            return topMostViewController(from: visible)
        }
        if let tabBar = viewController as? UITabBarController,
           let selected = tabBar.selectedViewController {
            return topMostViewController(from: selected)
        }
        return viewController
    }

    /// Present the webview as a page sheet over the current top-most view controller.
    func present(environmentResponse: EnvironmentResponse, id: String, completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard let window = UIApplication.safeKeyWindow,
                  let rootVC = window.rootViewController else {
                Formbricks.logger?.error("Survey present aborted: no key window or root view controller available.")
                completion?(false)
                return
            }

            let presenter = self.topMostViewController(from: rootVC)

            // UIAlertController/action-sheets/popovers cannot host a modal sheet — presenting on them either
            // crops the survey to the alert frame or is rejected by UIKit. Bail with a clear log so the host
            // app can dismiss the alert before triggering the survey.
            if presenter is UIAlertController {
                Formbricks.logger?.warning("Survey present aborted: top-most VC is a UIAlertController. Dismiss it before triggering the survey.")
                completion?(false)
                return
            }

            let view = FormbricksView(viewModel: FormbricksViewModel(environmentResponse: environmentResponse, surveyId: id))
            let vc = UIHostingController(rootView: view)
            vc.modalPresentationStyle = .pageSheet
            vc.view.backgroundColor = .clear
            if let sheet = vc.sheetPresentationController {
                sheet.detents = [.large()]
            }
            self.viewController = vc
            presenter.present(vc, animated: true, completion: {
                completion?(true)
            })
        }
    }

    /// Dismiss the webview
    func dismissView() {
        viewController?.dismiss(animated: true)
    }

    deinit {
        Formbricks.logger?.debug("Deinitializing \(self)")
    }
}
