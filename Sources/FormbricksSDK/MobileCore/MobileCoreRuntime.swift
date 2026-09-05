import Foundation
import JavaScriptCore

/// Hosts the server-delivered mobile core bundle in a JavaScriptCore context and
/// exposes its decision API to the shell. Apple's guidelines permit downloaded code
/// only when run by WebKit or JavaScriptCore — this is the JavaScriptCore path,
/// so the brain runs without a DOM and without a hidden WebView.
///
/// The runtime is intentionally dumb about survey logic: it serializes state in,
/// gets a decision out, and never interprets the rules itself.
final class MobileCoreRuntime {

    /// Global the bundle must define: `globalThis.formbricksMobileCore = { protocolVersion, selectSurvey }`.
    private static let globalName = "formbricksMobileCore"

    /// JSContext is not thread-safe; every evaluation goes through this serial queue.
    private let jsQueue = DispatchQueue(label: "com.formbricks.mobilecore.js")
    private let context: JSContext

    /// Fails when the bundle doesn't evaluate, doesn't define the expected global,
    /// or speaks a different bridge protocol than this shell.
    init?(bundleSource: String) {
        guard let context = JSContext() else { return nil }
        self.context = context

        context.exceptionHandler = { _, exception in
            Formbricks.logger?.error("Mobile core JS exception: \(exception?.toString() ?? "unknown")")
        }

        // JSC has no console; route the brain's logging through the SDK logger.
        let log: @convention(block) (String, String) -> Void = { level, message in
            switch level {
            case "error": Formbricks.logger?.error("[mobile-core] \(message)")
            case "warn": Formbricks.logger?.warning("[mobile-core] \(message)")
            default: Formbricks.logger?.debug("[mobile-core] \(message)")
            }
        }
        context.setObject(log, forKeyedSubscript: "__fbNativeLog" as NSString)
        context.evaluateScript("""
        globalThis.console = {
          log: (...a) => __fbNativeLog('log', a.join(' ')),
          warn: (...a) => __fbNativeLog('warn', a.join(' ')),
          error: (...a) => __fbNativeLog('error', a.join(' ')),
          debug: (...a) => __fbNativeLog('log', a.join(' ')),
        };
        """)

        context.evaluateScript(bundleSource)

        let core = context.objectForKeyedSubscript(MobileCoreRuntime.globalName)
        guard let core = core, !core.isUndefined, core.objectForKeyedSubscript("selectSurvey")?.isUndefined == false else {
            Formbricks.logger?.error("Mobile core bundle did not define \(MobileCoreRuntime.globalName).selectSurvey.")
            return nil
        }

        let protocolVersion = core.objectForKeyedSubscript("protocolVersion")?.toInt32() ?? 0
        guard protocolVersion == MobileCoreLoader.bridgeProtocolVersion else {
            Formbricks.logger?.error("Mobile core bundle speaks bridge protocol v\(protocolVersion), shell speaks v\(MobileCoreLoader.bridgeProtocolVersion). Ignoring bundle.")
            return nil
        }
    }

    /// Asks the brain which survey (if any) to display for a tracked action.
    /// Returns `nil` when the brain fails in any way, so the caller can fall back
    /// to the shell's built-in native logic.
    func selectSurvey(action: String,
                      workspaceStateJSON: String,
                      userState: MobileCoreUserState,
                      language: String) -> MobileCoreDecision? {
        guard let userStateData = try? JSONEncoder().encode(userState),
              let userStateJSON = String(data: userStateData, encoding: .utf8) else {
            return nil
        }

        return jsQueue.sync {
            let call = """
            JSON.stringify(globalThis.\(MobileCoreRuntime.globalName).selectSurvey({
              action: \(MobileCoreRuntime.jsStringLiteral(action)),
              workspaceState: \(workspaceStateJSON),
              userState: \(userStateJSON),
              language: \(MobileCoreRuntime.jsStringLiteral(language)),
              nowMs: Date.now(),
            }))
            """

            guard let result = context.evaluateScript(call),
                  result.isString,
                  let json = result.toString(),
                  let data = json.data(using: .utf8),
                  let decision = try? JSONDecoder().decode(MobileCoreDecision.self, from: data) else {
                Formbricks.logger?.error("Mobile core returned an unreadable decision for action '\(action)'.")
                return nil
            }

            return decision
        }
    }

    /// Embeds a Swift string into generated JS as a safe literal.
    private static func jsStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode([value]),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        // Encoded as a one-element array ["..."]; strip the brackets.
        return String(encoded.dropFirst().dropLast())
    }
}
