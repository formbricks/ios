import SwiftUI
@preconcurrency import WebKit
import JavaScriptCore
import SafariServices

/// SwiftUI wrapper for the WKWebView to display a survey.
struct SurveyWebView: UIViewRepresentable {
    let surveyId: String
    let htmlString: String
    
    /// Assemble the WKWebView with the necessary configuration.
    public func makeUIView(context: Context) -> WKWebView {
        clean()
        
        // Add javascript message handlers
        let userContentController = WKUserContentController()
        userContentController.add(LoggingMessageHandler(), name: "logging")
        userContentController.add(JsMessageHandler(surveyId: surveyId), name: "jsMessage")
        userContentController.addUserScript(WKUserScript(source: overrideConsole, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        
        let webViewConfig = WKWebViewConfiguration()
        webViewConfig.userContentController = userContentController
        
        let webView = WKWebView(frame: .zero, configuration: webViewConfig)
        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        // Web Inspector is a debugging aid only; never expose the survey WebView
        // to inspection in release builds (avoids leaking payload/responses and
        // allowing DOM/JS tampering on production devices).
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(htmlString, baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
    /// Called automatically by SwiftUI when the view is torn down.
   static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
       let userContentController = uiView.configuration.userContentController
       userContentController.removeScriptMessageHandler(forName: "logging")
       userContentController.removeScriptMessageHandler(forName: "jsMessage")

       uiView.navigationDelegate = nil
       uiView.uiDelegate = nil
       Formbricks.logger?.debug("SurveyWebView: Dismantled")
   }
    
    /// Clean up cookies and website data.
    func clean() {
        HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            self.remove(records)
        }
    }
    
    private func remove(_ records: [WKWebsiteDataRecord]) {
        records.forEach { record in
            WKWebsiteDataStore.default().removeData(ofTypes: record.dataTypes, for: [record], completionHandler: {
                /*
                 This completion handler is intentionally empty since we only need to
                 ensure the data is removed. No additional actions are required after
                 the website data has been cleared.
                */
            })
        }
    }
}

extension SurveyWebView {
    class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        // webView function handles Javascipt alert
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,  completionHandler: @escaping () -> Void) {
            let alertController = UIAlertController(title: "", message: message, preferredStyle: .alert)
           alertController.addAction(UIAlertAction(title: "OK", style: .default) { _ in 
               /* 
                This closure is intentionally empty since we only need a simple OK button
                to dismiss the alert. The alert dismissal is handled automatically by the
                system when the button is tapped.
               */
           })
            UIApplication.safeKeyWindow?.rootViewController?.presentedViewController?.present(alertController, animated: true)
            completionHandler()
        }
        
        func webView(_ webView: WKWebView, didReceive _: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            // Let the OS perform standard certificate-chain validation. Never force-trust
            // arbitrary certificates, as that would disable TLS validation and expose the
            // survey WebView traffic to man-in-the-middle interception.
            completionHandler(.performDefaultHandling, nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            // The survey is an in-memory document (loaded via loadHTMLString) rendered by the
            // JS library; it never legitimately navigates its own frame. Allow that base
            // document, and treat any other navigation — a link tap, window.location, meta
            // refresh or form submit from survey markup — as an attempt to leave the survey.
            // Route those through the same http/https allowlist as the JS bridge so a
            // `<a href="tel:...">` (etc.) can't reach WKWebView's native scheme handling and
            // trigger unexpected native actions.
            if JsMessageHandler.shouldAllowInWebViewNavigation(to: url) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                if let url {
                    JsMessageHandler.openExternalURL(url)
                }
            }
        }
    }
}

// MARK: - Javascript --> Native message handler -
/// Handle messages coming from the Javascript in the WebView.
final class JsMessageHandler: NSObject, WKScriptMessageHandler {
    
    let surveyId: String

    init(surveyId: String) {
        self.surveyId = surveyId
    }

    /// Whether an external URL from survey content is safe to hand to the OS.
    /// Only web links are allowed; other schemes (tel, sms, custom app deep links,
    /// etc.) are refused so survey content cannot trigger unexpected native actions.
    static func isAllowedExternalURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Whether a WebView navigation to `url` may proceed in-place. Only the in-memory
    /// survey document (`about:blank`, i.e. loaded with a nil base URL) loads in-frame;
    /// every other navigation is handled as an external link (see `openExternalURL`).
    static func shouldAllowInWebViewNavigation(to url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return true }
        return scheme == "about"
    }

    /// Opens an external URL through the http/https allowlist, or blocks and logs it.
    /// Shared by the JS bridge (`onOpenExternalURL`) and the navigation delegate so the
    /// scheme allowlist is enforced on both paths.
    static func openExternalURL(_ url: URL) {
        guard isAllowedExternalURL(url) else {
            Formbricks.logger?.warning("Blocked external URL with disallowed scheme: \(url.scheme ?? "nil")")
            return
        }
        UIApplication.shared.open(url)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Formbricks.logger?.debug(message.body)
        
        if let body = message.body as? String, let data = body.data(using: .utf8), let obj = try? JSONDecoder().decode(JsMessageData.self, from: data) {
            
            switch obj.event {
                /// Happens when the user submits an answer.
            case .onResponseCreated:
                Formbricks.surveyManager?.postResponse(surveyId: surveyId)

                /// Happens when a survey is shown.
            case .onDisplayCreated:
                Formbricks.surveyManager?.onNewDisplay(surveyId: surveyId)
            
            /// Happens when the user closes the survey view with the close button.
            case .onClose:
                Formbricks.surveyManager?.dismissSurveyWebView()
            
            /// Happens when the survey wants to open an external link in the default browser.
            case .onOpenExternalURL:
                if let message = try? JSONDecoder().decode(OpenExternalUrlMessage.self, from: data),
                   let url = URL(string: message.onOpenExternalURLParams.url) {
                    JsMessageHandler.openExternalURL(url)
                }
                
            /// Happens when the survey library fails to load.
            case .onSurveyLibraryLoadError:
                Formbricks.surveyManager?.dismissSurveyWebView()
            }
            
        } else {
            let error = FormbricksSDKError(type: .invalidJavascriptMessage)
            Formbricks.logger?.error("\(error.message): \(message.body)")
        }
    }
}

// MARK: - Handle Javascript console.log -
/// Handle and send console.log messages from the Javascript to the local logger.
final class LoggingMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Formbricks.logger?.debug(message.body)
    }
}

private extension SurveyWebView {
    // https://stackoverflow.com/a/61489361
    var overrideConsole: String {
        return
    """
        function log(emoji, type, args) {
          window.webkit.messageHandlers.logging.postMessage(
            `${emoji} JS ${type}: ${Object.values(args)
              .map(v => typeof(v) === "undefined" ? "undefined" : typeof(v) === "object" ? JSON.stringify(v) : v.toString())
              .map(v => v.substring(0, 3000)) // Limit msg to 3000 chars
              .join(", ")}`
          )
        }
    
        let originalLog = console.log
        let originalWarn = console.warn
        let originalError = console.error
        let originalDebug = console.debug
    
        console.log = function() { log("📗", "log", arguments); originalLog.apply(null, arguments) }
        console.warn = function() { log("📙", "warning", arguments); originalWarn.apply(null, arguments) }
        console.error = function() { log("📕", "error", arguments); originalError.apply(null, arguments) }
        console.debug = function() { log("📘", "debug", arguments); originalDebug.apply(null, arguments) }
    
        window.addEventListener("error", function(e) {
            window.webkit.messageHandlers.jsMessage.postMessage(JSON.stringify({ event: "onSurveyLibraryLoadError" }));
            log("💥", "Uncaught", [`${e.message} at ${e.filename}:${e.lineno}:${e.colno}`])
        })
    """
    }
}
