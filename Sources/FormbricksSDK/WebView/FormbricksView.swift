import SwiftUI

/// SwiftUI view for the Formbricks survey webview.
struct FormbricksView: View {
    @ObservedObject var viewModel: FormbricksViewModel
    /// Present only for a no-overlay survey, which needs the card's rect to decide which touches
    /// reach the host app. Nil for an overlaid survey, and then nothing is measured or reported.
    var layoutRelay: SurveyLayoutRelay?

    var body: some View {
        if let htmlString = viewModel.htmlString {
            SurveyWebView(surveyId: viewModel.surveyId, htmlString: htmlString, layoutRelay: layoutRelay)
                .ignoresSafeArea()
        }
    }
}
