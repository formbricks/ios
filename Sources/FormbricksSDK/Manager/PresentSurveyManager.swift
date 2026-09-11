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

    /// Held strongly: a window with no other owner is released and the survey disappears. Only used
    /// for the no-overlay path, where the survey cannot be a presented view controller.
    private var passthroughWindow: PassthroughWindow?

    /// Walks the active presentation/navigation/tab hierarchy and returns the leaf VC.
    /// Mirrors UIKit's own `presentedViewController` traversal so a single walker is enough.
    private func topMostViewController(from viewController: UIViewController) -> UIViewController {
        if let presented = viewController.presentedViewController,
            !presented.isBeingDismissed
        {
            return topMostViewController(from: presented)
        }
        if let navigation = viewController as? UINavigationController,
            let visible = navigation.visibleViewController
        {
            return topMostViewController(from: visible)
        }
        if let tabBar = viewController as? UITabBarController,
            let selected = tabBar.selectedViewController
        {
            return topMostViewController(from: selected)
        }
        return viewController
    }

    /// Shows the survey.
    ///
    /// A `light` or `dark` overlay is presented as a modal over the top-most view controller: the
    /// backdrop is meant to block the host app, so a full-screen barrier is correct. `overlay: none`
    /// cannot work that way — the survey is a corner card over a page the user is still using, and a
    /// presented view controller answers the hit test for the whole screen even when its content
    /// declines the touch. That case gets its own window instead, which can decline a touch and let
    /// UIKit carry on to the host app's window underneath.
    func present(
        workspaceResponse: WorkspaceResponse, id: String, overlay: SurveyOverlay = .none,
        completion: ((Bool) -> Void)? = nil
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if overlay == .none {
                self.presentPassthrough(
                    workspaceResponse: workspaceResponse, id: id, completion: completion)
            } else {
                self.presentModal(
                    workspaceResponse: workspaceResponse, id: id, completion: completion)
            }
        }
    }

    /// The no-overlay path: its own window, masked to the card's rect.
    private func presentPassthrough(
        workspaceResponse: WorkspaceResponse, id: String, completion: ((Bool) -> Void)?
    ) {
        guard let scene = UIApplication.safeKeyWindow?.windowScene else {
            Formbricks.logger?.error(
                "Survey present aborted: no window scene available.")
            completion?(false)
            return
        }

        let relay = SurveyLayoutRelay()
        let view = FormbricksView(
            viewModel: FormbricksViewModel(workspaceResponse: workspaceResponse, surveyId: id),
            layoutRelay: relay)
        let hosting = UIHostingController(rootView: view)
        hosting.view.backgroundColor = .clear

        let window = PassthroughWindow(windowScene: scene)
        window.rootViewController = hosting
        window.backgroundColor = .clear
        window.isOpaque = false
        // Above the app's own windows but below system UI like alerts and the status bar.
        window.windowLevel = .normal + 1

        // The reported rect is relative to the WebView's viewport. The WebView fills the hosting
        // controller, which fills this window, which covers the screen — and `ignoresSafeArea()`
        // means no inset shifts the origin — so viewport points and window points are the same
        // coordinate space and the rect needs no translation.
        relay.onCardRectChange = { [weak window] rect in
            window?.touchRegion = SurveyTouchRegion.forReported(rect: rect)
        }

        // Deliberately `isHidden`, not `makeKeyAndVisible()`. Taking key status would pull the
        // caret out of whatever the host app has focused — a survey appearing mid-form must not do
        // that, which is the entire complaint this fixes. UIKit promotes this window to key on its
        // own once the user actually taps into the survey, so text input still works.
        window.isHidden = false

        self.passthroughWindow = window
        self.viewController = hosting
        completion?(true)
    }

    /// The overlay path, unchanged: a modal over the top-most view controller.
    private func presentModal(
        workspaceResponse: WorkspaceResponse, id: String, completion: ((Bool) -> Void)?
    ) {
        guard let window = UIApplication.safeKeyWindow,
            let rootVC = window.rootViewController
        else {
            Formbricks.logger?.error(
                "Survey present aborted: no key window or root view controller available.")
            completion?(false)
            return
        }

        let presenter = self.topMostViewController(from: rootVC)

        // UIAlertController/action-sheets/popovers cannot host a modal sheet — presenting on them either
        // crops the survey to the alert frame or is rejected by UIKit. Bail with a clear log so the host
        // app can dismiss the alert before triggering the survey.
        if presenter is UIAlertController {
            Formbricks.logger?.warning(
                "Survey present aborted: top-most VC is a UIAlertController. Dismiss it before triggering the survey."
            )
            completion?(false)
            return
        }

        let view = FormbricksView(
            viewModel: FormbricksViewModel(workspaceResponse: workspaceResponse, surveyId: id))
        let vc = UIHostingController(rootView: view)
        vc.modalPresentationStyle = .overFullScreen
        vc.modalTransitionStyle = .crossDissolve
        vc.view.backgroundColor = .clear
        self.viewController = vc
        presenter.present(
            vc, animated: true,
            completion: {
                completion?(true)
            })
    }

    /// Dismiss the webview, whichever way it was shown.
    func dismissView() {
        let tearDown = { [weak self] in
            guard let self = self else { return }
            self.viewController?.dismiss(animated: true)
            // Drop the window as well, or a no-overlay survey leaves an invisible one over the app.
            // Clearing `rootViewController` first releases the hosting controller and the WebView.
            self.passthroughWindow?.isHidden = true
            self.passthroughWindow?.rootViewController = nil
            self.passthroughWindow = nil
        }

        if Thread.isMainThread {
            tearDown()
        } else {
            DispatchQueue.main.async(execute: tearDown)
        }
    }

    deinit {
        Formbricks.logger?.debug("Deinitializing \(self)")
    }
}
