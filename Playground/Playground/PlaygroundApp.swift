import SwiftUI

@main
struct PlaygroundApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(launch: LaunchConfiguration(environment: ProcessInfo.processInfo.environment))
        }
    }
}
