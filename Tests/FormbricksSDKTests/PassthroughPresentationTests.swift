import XCTest
@testable import FormbricksSDK

/// The no-overlay presentation path: the survey's own window, and which overlay picks that path.
///
/// Tests run without a window scene, so `present` itself can only reach its guard here. The window
/// wiring is driven through `installPassthroughWindow` with a frame-based window instead.
final class PassthroughPresentationTests: XCTestCase {
    let workspaceId = "workspaceId"
    let appUrl = "https://example.com"
    let surveyID = "cm6ovw6j7000gsf0kduf4oo4i"
    let mockService = MockFormbricksService()

    override func setUp() {
        super.setUp()
        Formbricks.cleanup()
        clearPersistedWorkspaceCache()
    }

    override func tearDown() {
        Formbricks.cleanup()
        clearPersistedWorkspaceCache()
        super.tearDown()
    }

    private func clearPersistedWorkspaceCache() {
        UserDefaults.standard.removeObject(forKey: SurveyManager.workspaceResponseObjectKey)
        UserDefaults.standard.removeObject(forKey: SurveyManager.legacyEnvironmentResponseObjectKey)
    }

    /// Sets the SDK up against `Environment.json`, whose workspace overlay is `none` and whose
    /// `surveyID` survey overrides it to `dark`.
    private func loadWorkspace() -> WorkspaceResponse? {
        let config = FormbricksConfig.Builder(appUrl: appUrl, workspaceId: workspaceId)
            .service(mockService)
            .build()
        Formbricks.setup(with: config)
        Formbricks.surveyManager?.refreshWorkspaceIfNeeded(force: true)
        let loaded = expectation(description: "Workspace loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { loaded.fulfill() }
        wait(for: [loaded])
        return Formbricks.surveyManager?.workspaceResponse
    }

    // MARK: - Passthrough window

    func testPassthroughWindowShowsAboveTheAppAndBlocksUntilACardIsReported() throws {
        let workspace = try XCTUnwrap(loadWorkspace())
        let window = PassthroughWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))

        PresentSurveyManager().installPassthroughWindow(
            window, workspaceResponse: workspace, id: surveyID)

        XCTAssertFalse(window.isHidden)
        XCTAssertEqual(window.windowLevel, .normal + 1)
        XCTAssertFalse(window.isOpaque)
        XCTAssertNotNil(window.rootViewController)
        // No rect yet — or never, from an older server — so it blocks like the SDK always did.
        XCTAssertEqual(window.touchRegion, .everything)
    }

    func testReportedCardRectDecidesWhichTouchesTheWindowTakes() throws {
        let workspace = try XCTUnwrap(loadWorkspace())
        let window = PassthroughWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let relay = PresentSurveyManager().installPassthroughWindow(
            window, workspaceResponse: workspace, id: surveyID)

        relay.onCardRectChange?(CardRect(x: 16, y: 500, width: 368, height: 280))
        XCTAssertEqual(window.touchRegion, .card(CGRect(x: 16, y: 500, width: 368, height: 280)))

        // Card animating out: nothing on screen, so nothing is claimed.
        relay.onCardRectChange?(nil)
        XCTAssertEqual(window.touchRegion, .nothing)
    }

    func testDismissTearsTheWindowDown() throws {
        let workspace = try XCTUnwrap(loadWorkspace())
        let window = PassthroughWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let manager = PresentSurveyManager()
        manager.installPassthroughWindow(window, workspaceResponse: workspace, id: surveyID)

        // On the main thread, so the teardown runs synchronously.
        manager.dismissView()

        XCTAssertTrue(window.isHidden, "a leftover window would sit invisibly over the app")
        XCTAssertNil(window.rootViewController)
    }

    func testOverlayPresentAbortsWithoutAKeyWindow() throws {
        let workspace = try XCTUnwrap(loadWorkspace())
        let done = expectation(description: "Present completes")
        // Held for the whole test: `present` hops to the main queue holding `self` weakly.
        let manager = PresentSurveyManager()

        manager.present(workspaceResponse: workspace, id: surveyID, overlay: .dark) { success in
            XCTAssertFalse(success)
            done.fulfill()
        }
        wait(for: [done], timeout: 2.0)
    }

    // MARK: - Modal path (light / dark overlay)

    /// A visible window whose root is `root`, handed to the manager in place of the scene lookup.
    private func manager(presentingIn root: UIViewController) -> (PresentSurveyManager, UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = root
        window.makeKeyAndVisible()
        // Lay the container views out now: UIKit refuses to present from a view not yet in a window.
        window.layoutIfNeeded()
        let manager = PresentSurveyManager()
        manager.keyWindow = { window }
        return (manager, window)
    }

    func testOverlaySurveyIsPresentedOnTheTopMostViewController() throws {
        let workspace = try XCTUnwrap(loadWorkspace())
        // Tab bar -> navigation stack -> leaf: the walker has to go through both containers.
        let leaf = UIViewController()
        let tabs = UITabBarController()
        tabs.viewControllers = [UINavigationController(rootViewController: leaf)]
        let (manager, window) = manager(presentingIn: tabs)
        // Waits on the presentation itself: the test runner's scene is never foreground-active, so
        // UIKit sets `presentedViewController` but never calls the presentation's completion.
        let presented = expectation(
            for: NSPredicate { _, _ in leaf.presentedViewController != nil }, evaluatedWith: nil)

        manager.present(workspaceResponse: workspace, id: surveyID, overlay: .dark)
        wait(for: [presented], timeout: 3.0)

        manager.dismissView()
        withExtendedLifetime(window) {}
    }

    func testOverlaySurveyIsNotPresentedOverAnAlert() throws {
        let workspace = try XCTUnwrap(loadWorkspace())
        let alert = UIAlertController(title: "Busy", message: nil, preferredStyle: .alert)
        let (manager, window) = manager(presentingIn: alert)
        let done = expectation(description: "Present completes")

        manager.present(workspaceResponse: workspace, id: surveyID, overlay: .light) { success in
            XCTAssertFalse(success, "UIKit cannot host a modal on an alert")
            done.fulfill()
        }
        wait(for: [done], timeout: 2.0)
        withExtendedLifetime(window) {}
    }

    func testNoOverlaySurveyGetsItsOwnWindowInsteadOfAModal() throws {
        let workspace = try XCTUnwrap(loadWorkspace())
        let root = UIViewController()
        let (manager, window) = manager(presentingIn: root)
        let done = expectation(description: "Present completes")

        manager.present(workspaceResponse: workspace, id: surveyID, overlay: .none) { success in
            XCTAssertTrue(success)
            done.fulfill()
        }
        wait(for: [done], timeout: 2.0)

        // Not a presented view controller: that would answer the hit test for the whole screen.
        XCTAssertNil(root.presentedViewController)
        let surveyWindow = window.windowScene?.windows.first { $0 is PassthroughWindow }
        XCTAssertEqual(surveyWindow?.windowLevel, .normal + 1)

        manager.dismissView()
        XCTAssertEqual(surveyWindow?.isHidden, true)
    }

    // MARK: - Overlay resolution

    func testSurveyOverlayOverrideWinsOverTheWorkspaceSetting() throws {
        let workspace = try XCTUnwrap(loadWorkspace())
        let manager = try XCTUnwrap(Formbricks.surveyManager)
        let survey = workspace.data.data.surveys?.first { $0.id == surveyID }

        XCTAssertEqual(manager.resolveOverlay(for: survey), .dark)
    }

    func testWithoutASurveyOverrideTheWorkspaceSettingApplies() throws {
        _ = try XCTUnwrap(loadWorkspace())
        let manager = try XCTUnwrap(Formbricks.surveyManager)

        XCTAssertEqual(manager.resolveOverlay(for: nil), .none)
    }

    func testWithNoWorkspaceStateTheOverlayDefaultsToNone() {
        let manager = SurveyManager.create(
            userManager: UserManager(), presentSurveyManager: PresentSurveyManager(),
            service: mockService)

        XCTAssertNil(manager.workspaceResponse)
        XCTAssertEqual(manager.resolveOverlay(for: nil), .none)
    }
}
