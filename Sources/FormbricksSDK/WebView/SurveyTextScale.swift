import UIKit

/// Makes the survey's text follow the user's Dynamic Type setting.
///
/// WKWebView never applies Dynamic Type to web content, and the survey renderer sizes its text in CSS
/// pixels, so without this every respondent sees the default size whatever they chose in Settings.
/// Android's WebView already scales page text by the system font scale, and this mirrors it: the text
/// grows, the layout around it does not.
///
/// The factor reaches the page as `-webkit-text-size-adjust` on the root element (see
/// `FormbricksViewModel.htmlTemplate`). WebKit multiplies it into every computed font size, which is
/// what Android's text zoom does. It is inherited, and the renderer never sets it on the survey.
///
/// WebKit honours the percentage in mobile content mode, which every iPhone and the iPad mini use.
/// Larger iPads load the WebView in desktop-class mode, where WebKit ignores it and the text stays at
/// the default size, as it did before.
enum SurveyTextScale {
    /// Body text at the default ("Large") size: the reference the factor is measured against.
    private static let defaultBodyPointSize: CGFloat = 17

    /// The largest factor applied — Android's largest font scale, and WCAG 1.4.4's 200%. iOS's
    /// accessibility sizes go up to about 3.1×, where fixed-width rows such as the 0–10 NPS scale no
    /// longer fit a phone-width card, so those sizes get the same 2× Android users get.
    static let maximumFactor: CGFloat = 2

    /// How much larger than default the user's setting makes body text, capped at `maximumFactor`.
    /// Sizes below the default shrink the text, as they do in native apps.
    static func factor(for category: UIContentSizeCategory) -> CGFloat {
        // What a trait collection reports when it carries no Dynamic Type setting at all.
        guard category != .unspecified else { return 1 }
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let scaled = UIFontMetrics(forTextStyle: .body)
            .scaledValue(for: defaultBodyPointSize, compatibleWith: traits)
        return min(scaled / defaultBodyPointSize, maximumFactor)
    }

    /// The `-webkit-text-size-adjust` value for `category`: a whole percentage, or `auto` — the
    /// property's initial value — at the default size, so the page renders exactly as it did before.
    static func textSizeAdjust(for category: UIContentSizeCategory) -> String {
        let percent = Int((factor(for: category) * 100).rounded())
        return percent == 100 ? "auto" : "\(percent)%"
    }
}
