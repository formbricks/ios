import SwiftUI

/// SwiftUI view for the Formbricks survey webview.
public struct FormbricksView: View {
    @ObservedObject var viewModel: FormbricksViewModel
    
    public var body: some View {
        if let htmlString = viewModel.htmlString {
            SurveyWebView(surveyId: viewModel.surveyId, htmlString: htmlString)
        }
    }
}
