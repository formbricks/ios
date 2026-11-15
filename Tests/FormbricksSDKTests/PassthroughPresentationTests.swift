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
        // The mock service answers synchronously, so the workspace is in place when setup returns.
        Formbricks.setup(with: config)
        return Formbricks.surveyManager?.workspaceResponse
    }

    /// A manager whose survey is a plain view controller. These tests are about where and how the
    /// survey is shown, not what it renders, and rendering it starts WebKit: on a cold CI simulator
    /// that blocked the main thread for 20+ seconds and timed the presentation test out.
    private func makeManager() -> PresentSurveyManager {
        let manager = PresentSurveyManager()
        manager.makeSurveyController = { _ in UIViewController() }
        return manager
    }

    // MARK: - Passthrough window

    func testPassthroughWindowShowsAboveTheAppAndBlocksUntilACardIsReported() throws {
        let workspace = try XCTUnwrap(loadWorkspace())
        let window = PassthroughWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))

        makeManager().installPassthroughWindow(
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
        let relay = makeManager().installPassthroughWindow(
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
        let manager = makeManager()
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
        let manager = makeManager()
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
        let survey = UIViewController()
        // The presenter is also where the survey reads its traits from, which is the one place
        // the walker's choice is visible: UIKit reports the modal on every controller in the chain.
        var traitSource: UITraitEnvironment?
        manager.makeSurveyController = { view in
            traitSource = view.viewModel.traitSource
            return survey
        }

        manager.present(workspaceResponse: workspace, id: surveyID, overlay: .dark)
        // `present` hops to the main queue once; this block is queued behind it. UIKit records the
        // presentation synchronously, but the test runner's scene is never foreground-active, so
        // the presentation's own completion never runs and cannot be waited on.
        let presented = expectation(description: "Present ran")
        DispatchQueue.main.async { presented.fulfill() }
        wait(for: [presented], timeout: 1.0)

        XCTAssertIdentical(leaf.presentedViewController, survey)
        XCTAssertIdentical(traitSource, leaf)
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
