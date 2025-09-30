import SwiftUI

/// A view model for the Formbricks WebView.
/// It generates the HTML string with the necessary data to render the survey.
final class FormbricksViewModel: ObservableObject {
    @Published var htmlString: String?
    let surveyId: String
    
    init(environmentResponse: EnvironmentResponse, surveyId: String) {
        self.surveyId = surveyId
        if let webviewDataJson = WebViewData(environmentResponse: environmentResponse, surveyId: surveyId).getJsonString(),
           let surveyScriptUrl = FormbricksEnvironment.surveyScriptUrlString {
            htmlString = htmlTemplate.replacingOccurrences(of: "{{WEBVIEW_DATA}}", with: webviewDataJson)
                .replacingOccurrences(of: "{{SURVEY_SCRIPT_URL}}", with: surveyScriptUrl)
        }
    }
}

private extension FormbricksViewModel {
    /// The HTML template to render the Formbricks WebView.
    var htmlTemplate: String {
        return """
        <!doctype html>
        <html>
            <meta name="viewport" content="initial-scale=1.0, maximum-scale=1.0">
            
            <head>
                <title>Formbricks WebView Survey</title>
            </head>

            <body style="overflow: hidden; height: 100vh; display: flex; flex-direction: column; justify-content: flex-end;">
                <div id="formbricks-react-native" style="width: 100%;"></div>
            </body>

            <script type="text/javascript">
                const json = `{{WEBVIEW_DATA}}`
                let surveyProps = '';

                function onClose() {
                    window.webkit.messageHandlers.jsMessage.postMessage(JSON.stringify({ event: "onClose" }));
                };

                function onDisplayCreated() {
                    window.webkit.messageHandlers.jsMessage.postMessage(JSON.stringify({ event: "onDisplayCreated" }));
                };
        
                function onResponseCreated() {
                    window.webkit.messageHandlers.jsMessage.postMessage(JSON.stringify({ event: "onResponseCreated" }));
                };
        
                function onOpenExternalURL(url) {
                    window.webkit.messageHandlers.jsMessage.postMessage(JSON.stringify({ event: "onOpenExternalURL", onOpenExternalURLParams: { url: url } }));
                };

                let setResponseFinished = null;
                function getSetIsResponseSendingFinished(callback) {
                    setResponseFinished = callback;
                }  

                function loadSurvey() {
                    const options = JSON.parse(json);
                    surveyProps = {
                        ...options,
                        getSetIsResponseSendingFinished,
                        onDisplayCreated,
                        onResponseCreated,
                        onClose,
                        onOpenExternalURL,
                    };
                    window.formbricksSurveys.renderSurvey(surveyProps);
                }

                const script = document.createElement("script");
                script.src = "{{SURVEY_SCRIPT_URL}}";
                script.async = true;
                script.onload = () => loadSurvey();
                script.onerror = (error) => {
                    window.webkit.messageHandlers.jsMessage.postMessage(JSON.stringify({ event: "onSurveyLibraryLoadError" }));
                    console.error("Failed to load Formbricks Surveys library:", error);
                };
                document.head.appendChild(script);
            </script>
        </html>
        """
    }
    
}

// MARK: - Helper class -
private class WebViewData {
    var data: [String: Any] = [:]
    
    init(environmentResponse: EnvironmentResponse, surveyId: String) {
        let matchedSurvey = environmentResponse.data.data.surveys?.first(where: {$0.id == surveyId})
        let project = environmentResponse.data.data.project
        
        data["survey"] = environmentResponse.getSurveyJson(forSurveyId: surveyId)
        data["appUrl"] = Formbricks.appUrl
        data["environmentId"] = Formbricks.environmentId
        data["contactId"] = Formbricks.userManager?.contactId
        data["isWebEnvironment"] = false
        data["isBrandingEnabled"] = project.inAppSurveyBranding ?? true
        
        if let placementEnum = matchedSurvey?.projectOverwrites?.placement {
            data["placement"] = placementEnum.rawValue
        } else {
            data["placement"] = project.placement
        }
        
        data["darkOverlay"] = matchedSurvey?.projectOverwrites?.darkOverlay ?? project.darkOverlay
        
        let isMultiLangSurvey = (matchedSurvey?.languages?.count ?? 0) > 1
        
        if isMultiLangSurvey {
            data["languageCode"] = Formbricks.language
        } else {
            data["languageCode"] = "default"
        }
        
        let hasCustomStyling = matchedSurvey?.styling != nil
        let enabled = project.styling?.allowStyleOverwrite ?? false
            
        data["styling"] = hasCustomStyling && enabled ? environmentResponse.getSurveyStylingJson(forSurveyId: surveyId): environmentResponse.getProjectStylingJson()
    }
    
    func getJsonString() -> String? {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
            return String(data: jsonData, encoding: .utf8)?.replacingOccurrences(of: "\\\"", with: "'")
        } catch {
            Formbricks.logger?.error(error.message)
            return nil
        }
    }
    
}
