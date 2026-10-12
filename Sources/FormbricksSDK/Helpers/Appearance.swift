import UIKit

/// How surveys render. `system` follows the host app's own theme, not the phone's.
public enum FormbricksAppearance: String {
    case light
    case dark
    case system
}

/// The in-memory appearance state (ENG-3452). Never persisted, never sent to the server, and left
/// alone by `logout()`, so a fresh app launch starts light (ENG-3551).
enum AppearanceState {
    /// Posted on the main thread whenever `Formbricks.setAppearance` runs.
    static let didChange = Notification.Name("FormbricksAppearanceDidChange")

    private static let lock = NSLock()
    private static var storedValue: FormbricksAppearance = .light

    static var current: FormbricksAppearance {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    /// Returns false (and falls back to light) for a value that is not a known appearance.
    @discardableResult
    static func set(_ rawValue: String) -> Bool {
        guard let appearance = FormbricksAppearance(rawValue: rawValue) else {
            set(.light)
            return false
        }
        set(appearance)
        return true
    }

    static func set(_ appearance: FormbricksAppearance) {
        lock.lock()
        storedValue = appearance
        lock.unlock()
        let post = { NotificationCenter.default.post(name: didChange, object: nil) }
        if Thread.isMainThread { post() } else { DispatchQueue.main.async(execute: post) }
    }

    /// What the renderer understands: always `light` or `dark`, never `system`. `traits` is the
    /// trait collection of the view the survey is shown in, which carries the app's
    /// `overrideUserInterfaceStyle`; WebViews report the OS preference inconsistently, so the
    /// decision is made here.
    static func resolved(_ appearance: FormbricksAppearance = current, traits: UITraitCollection?) -> String {
        switch appearance {
        case .light: return "light"
        case .dark: return "dark"
        case .system:
            let style = (traits ?? UIApplication.safeKeyWindow?.traitCollection)?.userInterfaceStyle
            return style == .dark ? "dark" : "light"
        }
    }

    /// JavaScript that flips an open survey in place. Optional chaining: a server whose renderer
    /// predates `setAppearance` leaves the survey light instead of throwing.
    static func switchScript(for resolved: String) -> String {
        "window.formbricksSurveys?.setAppearance?.('\(resolved)');"
    }
}
