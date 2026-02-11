import SwiftUI

/// Presents a survey webview to the window's root
final class PresentSurveyManager {
    init() {
        /*
         This empty initializer prevents external instantiation of the PresentSurveyManager class.
         The class serves as a namespace for the present method, so instance creation is not needed and should be restricted.
        */
    }
    
    /// The view controller that will present the survey window.
    private weak var viewController: UIViewController?
    
    /// Present the webview
    /// The native background is always `.clear` — overlay rendering is handled
    /// entirely by the JS survey library inside the WebView to avoid double-overlay artifacts.
    func present(environmentResponse: EnvironmentResponse, id: String, completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let window = UIApplication.safeKeyWindow {
                let view = FormbricksView(viewModel: FormbricksViewModel(environmentResponse: environmentResponse, surveyId: id))
                let vc = UIHostingController(rootView: view)
                vc.modalPresentationStyle = .overCurrentContext
                vc.view.backgroundColor = .clear
                if let presentationController = vc.presentationController as? UISheetPresentationController {
                    presentationController.detents = [.large()]
                }
                self.viewController = vc
                window.rootViewController?.present(vc, animated: true, completion: {
                    completion?(true)
                })
            } else {
                completion?(false)
            }
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
