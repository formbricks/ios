import Foundation

/// The in-memory Embedded Data bag: context a host app attaches to future responses without tying
/// it to a trigger — `Formbricks.setEmbeddedData(["screen": "checkout"])` once, instead of
/// repeating the same values on every possible `track(...)` call.
///
/// Mirrors the JS SDK's store key for key, so web and mobile behave identically.
///
/// Lifetime rules, all deliberate:
///
/// - **In-memory, process scoped, never persisted.** Not `UserDefaults`: persisting this bag would
///   blur the Embedded Data ↔ contact-attribute boundary and create a stale-data / PII-at-rest
///   surface. A cold app start begins empty; the host re-pushes.
/// - **Snapshot at display, then frozen.** The WebView payload copies the bag when the survey is
///   shown, so a later `setEmbeddedData` affects the next response, never the one on screen.
/// - **No filtering here.** The SDK is a dumb pipe: the survey renderer applies the ingest contract
///   — allow-list, coercion, `locked`, size caps — and logs what it refuses, and the server re-runs
///   all of it on ingest. Filtering here would ship a second copy of those rules for the four mobile
///   SDKs to drift from.
/// - **Independent of `setup`.** A singleton rather than a manager hung off `Formbricks`, because a
///   host legitimately pushes context before the SDK finishes initializing, and silently dropping
///   that write is the failure this API exists to avoid. `Formbricks.cleanup()` clears it, since
///   that is an explicit full reset of the SDK.
/// - **No network.** Every method is a synchronous memory write, so calling it on every screen
///   change is free. Values ride the existing response payload.
final class EmbeddedDataManager {
    static let shared = EmbeddedDataManager()

    /// Same idiom as `UpdateQueue`: the host may call from any thread, and the snapshot is read on
    /// the main queue while a survey is being presented.
    private let syncQueue = DispatchQueue(label: "com.formbricks.embeddedData")
    private var data: [String: EmbeddedDataValue] = [:]

    private init() {
        /*
         Private so the bag cannot be instantiated a second time: a host holding its own copy would
         write into a store the survey payload never reads.
        */
    }

    /// Merge — never replace — so refreshing a volatile field (`screen`) cannot wipe the stable ones
    /// (`plan`) set at launch. Per key: last write wins, and an explicit `nil` removes the key.
    ///
    /// A key the caller simply leaves out is untouched; that is how a host skips a field it has no
    /// value for this screen. `nil` is the deliberate "remove this" spelling, matching the JS SDK's
    /// `{ key: null }`.
    func set(_ data: [String: EmbeddedDataValue?]) {
        var setKeys: [String] = []
        var removedKeys: [String] = []
        var held: [String] = []
        syncQueue.sync {
            for (key, value) in data {
                guard let value = value else {
                    self.data.removeValue(forKey: key)
                    removedKeys.append(key)
                    continue
                }
                // Refused rather than stored: `JSONSerialization` throws on a non-finite Double, and
                // the payload it would refuse is the whole survey's props blob — one bad value would
                // cost the survey, not the field. Never fatal, always logged.
                if case .number(let number) = value, !number.isFinite {
                    Formbricks.logger?.error(
                        "setEmbeddedData: \"\(key)\" is not a finite number — the key was skipped")
                    continue
                }
                self.data[key] = value
                setKeys.append(key)
            }
            held = Array(self.data.keys)
        }
        // Built and logged outside the queue, so a log write never holds it.
        Formbricks.logger?.debug(
            EmbeddedDataManager.setTrace(set: setKeys, removed: removedKeys, held: held))
    }

    /// The success trace, because the bag is otherwise invisible: it lives in memory (nothing in
    /// `UserDefaults` to inspect) and the API has no getter, so without this line a host wiring up
    /// `setEmbeddedData` gets no confirmation until a survey happens to display. Logged at `.debug`,
    /// so it is silent at the default log level.
    ///
    /// Keys only, never values: the documented use of this bag includes hashed identity fields.
    /// Separated from the logging call so that property is directly assertable in a test.
    ///
    /// Every list is sorted, unlike the other three SDKs, which preserve insertion order: the bag
    /// and the caller's argument are both Swift `Dictionary`s, whose iteration order is not
    /// specified and varies per process. Sorting is the only way this line reads the same twice.
    static func setTrace(set setKeys: [String], removed removedKeys: [String], held: [String])
        -> String
    {
        let removed =
            removedKeys.isEmpty ? "" : ", removed [\(removedKeys.sorted().joined(separator: ", "))]"
        return "setEmbeddedData: set [\(setKeys.sorted().joined(separator: ", "))]\(removed) — the "
            + "bag now holds [\(held.sorted().joined(separator: ", "))]. Keys land on a response "
            + "only if the survey declares them as ingested Embedded Data fields."
    }

    /// Removes one key. A key that is not set is a no-op.
    func remove(key: String) {
        var held: [String] = []
        syncQueue.sync {
            _ = data.removeValue(forKey: key)
            held = Array(data.keys)
        }
        Formbricks.logger?.debug(
            "clearEmbeddedData: removed \"\(key)\" — the bag now holds "
                + "[\(held.sorted().joined(separator: ", "))]")
    }

    /// Removes everything — logout, or a hard context switch.
    func removeAll() {
        var clearedCount = 0
        syncQueue.sync {
            clearedCount = data.count
            data.removeAll()
        }
        Formbricks.logger?.debug("clearEmbeddedData: cleared the whole bag (\(clearedCount) keys)")
    }

    /// A detached, JSON-safe copy for the display-time snapshot: mutating the bag after a survey has
    /// rendered must not reach that survey's response.
    func snapshot() -> [String: Any] {
        syncQueue.sync {
            data.reduce(into: [String: Any]()) { result, entry in
                if let value = entry.value.jsonValue {
                    result[entry.key] = value
                }
            }
        }
    }
}
