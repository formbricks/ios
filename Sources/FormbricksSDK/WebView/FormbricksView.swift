import SwiftUI

/// SwiftUI view for the Formbricks survey webview.
struct FormbricksView: View {
    @ObservedObject var viewModel: FormbricksViewModel
    /// Present only for a no-overlay survey, which needs the card's rect to decide which touches
    /// reach the host app. Nil for an overlaid survey, and then nothing is measured or reported.
    var layoutRelay: SurveyLayoutRelay?

    var body: some View {
        if let htmlString = viewModel.htmlString {
            // Only the container safe area, not the keyboard's: when the keyboard opens, SwiftUI
            // shrinks the view above it, the renderer lays the card out in the smaller viewport, and
            // (no-overlay) reports the new rect. Ignoring every region left the card under the
            // keyboard. The top edge never moves, so viewport and window points still line up.
            SurveyWebView(surveyId: viewModel.surveyId, htmlString: htmlString, initialAppearance: viewModel.initialAppearance, layoutRelay: layoutRelay)
                .ignoresSafeArea(.container)
        }
    }
}
