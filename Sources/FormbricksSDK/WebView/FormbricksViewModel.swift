import SwiftUI

/// A view model for the Formbricks WebView.
/// It generates the HTML string with the necessary data to render the survey.
final class FormbricksViewModel: ObservableObject {
    @Published var htmlString: String?
    let surveyId: String

    init(workspaceResponse: WorkspaceResponse, surveyId: String) {
        self.surveyId = surveyId
        if let webviewDataJson = WebViewData(workspaceResponse: workspaceResponse, surveyId: surveyId).getJsonString(),
           let surveyScriptUrl = FormbricksWorkspace.surveyScriptUrlString {
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

    init(workspaceResponse: WorkspaceResponse, surveyId: String) {
        let matchedSurvey = workspaceResponse.data.data.surveys?.first(where: {$0.id == surveyId})
        let settings = workspaceResponse.data.data.settings

        data["survey"] = workspaceResponse.getSurveyJson(forSurveyId: surveyId)
        data["appUrl"] = Formbricks.appUrl
        data["workspaceId"] = Formbricks.workspaceId
        // Keep `environmentId` in the payload for backward compatibility with older
        // survey-script versions that still read it.
        data["environmentId"] = Formbricks.workspaceId
        data["contactId"] = Formbricks.userManager?.contactId
        data["isWebEnvironment"] = false
        data["isBrandingEnabled"] = settings.inAppSurveyBranding ?? true

        if let placementEnum = matchedSurvey?.projectOverwrites?.placement {
            data["placement"] = placementEnum.rawValue
        } else {
            data["placement"] = settings.placement
        }

        data["clickOutside"] = matchedSurvey?.projectOverwrites?.clickOutsideClose ?? settings.clickOutsideClose ?? false
        data["overlay"] = (matchedSurvey?.projectOverwrites?.overlay ?? settings.overlay ?? .none).rawValue

        let isMultiLangSurvey = (matchedSurvey?.languages?.count ?? 0) > 1

        if isMultiLangSurvey {
            data["languageCode"] = Formbricks.language
        } else {
            data["languageCode"] = "default"
        }

        let hasCustomStyling = matchedSurvey?.styling != nil
        let enabled = settings.styling?.allowStyleOverwrite ?? false

        data["styling"] = hasCustomStyling && enabled ? workspaceResponse.getSurveyStylingJson(forSurveyId: surveyId): workspaceResponse.getSettingsStylingJson()
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
