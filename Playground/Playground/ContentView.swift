import FormbricksSDK
import SwiftUI

/// One screen with a button per SDK call the golden journey makes. Every control has an
/// accessibility identifier that `GoldenJourneyUITests` uses.
struct ContentView: View {
    @State private var appUrl: String
    @State private var workspaceId: String
    @State private var userId: String
    @State private var attributeKey: String
    @State private var attributeValue: String
    @State private var action: String
    @State private var status = "Not set up"
    private let setsUpOnLaunch: Bool

    init(launch: LaunchConfiguration) {
        _appUrl = State(initialValue: launch.appUrl)
        _workspaceId = State(initialValue: launch.workspaceId)
        _userId = State(initialValue: launch.userId)
        _attributeKey = State(initialValue: launch.attributeKey)
        _attributeValue = State(initialValue: launch.attributeValue)
        _action = State(initialValue: launch.action)
        setsUpOnLaunch = launch.setsUpOnLaunch
    }

    var body: some View {
        // A plain stack, not a Form: a Form is lazy, so rows below the fold would be missing from
        // the accessibility tree the UI test queries.
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Formbricks Playground").font(.title2.bold())
                field("App URL (https://)", text: $appUrl, id: "appUrlField")
                field("Workspace ID", text: $workspaceId, id: "workspaceIdField")
                button("Set up", id: "setupButton", action: setUp)
                Divider()
                field("User ID", text: $userId, id: "userIdField")
                button("Set user ID", id: "setUserIdButton") {
                    Formbricks.setUserId(userId)
                    status = "Set user ID \(userId)"
                }
                field("Attribute key", text: $attributeKey, id: "attributeKeyField")
                field("Attribute value", text: $attributeValue, id: "attributeValueField")
                button("Set attribute", id: "setAttributeButton") {
                    Formbricks.setAttribute(attributeValue, forKey: attributeKey)
                    status = "Set \(attributeKey) = \(attributeValue)"
                }
                Divider()
                field("Action", text: $action, id: "actionField")
                button("Track action", id: "trackButton") {
                    Formbricks.track(action)
                    status = "Tracked \(action)"
                }
                button("Log out", id: "logoutButton") {
                    Formbricks.logout()
                    status = "Logged out"
                }
                Text(status).font(.footnote).accessibilityIdentifier("statusLabel")
            }
            .padding()
        }
        .onAppear {
            if setsUpOnLaunch && status == "Not set up" {
                setUp()
            }
        }
    }

    private func button(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(id)
    }

    private func field(_ title: String, text: Binding<String>, id: String) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier(id)
    }

    private func setUp() {
        let config = FormbricksConfig.Builder(appUrl: appUrl, workspaceId: workspaceId)
            .setLogLevel(.debug)
            .build()
        Formbricks.setup(with: config, force: true)
        status = "Set up with \(appUrl)"
    }
}
