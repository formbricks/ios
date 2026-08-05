import Foundation

protocol UserManagerSyncable: AnyObject {
    func syncUser(withId id: String, attributes: [String: AttributeValue]?)
}

/// Update queue. This class is used to queue updates to the user.
/// The given properties will be sent to the backend and updated in the user object when the debounce interval is reached.
final class UpdateQueue {
    
    private static var debounceInterval: TimeInterval = 0.5
    
    private let syncQueue = DispatchQueue(label: "com.formbricks.updateQueue")
    private var userId: String?
    private var attributes: [String : AttributeValue]?
    private var language: String?
    private var timer: Timer?
    /// True while a commit-triggered sync is airborne. A repeat nudge joins that request
    /// instead of starting a second one: `APIClient` does not serialise requests, so two
    /// concurrent `POST /user` calls would race and whichever response landed last would
    /// overwrite `segments` / `displays` / `responses` wholesale.
    private var isSyncInFlight = false
    /// A refresh that arrived while a sync was already airborne, replayed once that sync
    /// finishes. The in-flight request was built *before* this interaction, so its response
    /// cannot reflect it — dropping the nudge would leave segments stale until the next trigger.
    private var pendingRefreshUserId: String?

    private weak var userManager: UserManagerSyncable?

    init(userManager: UserManagerSyncable) {
        self.userManager = userManager
    }
    
    func set(userId: String) {
        syncQueue.sync {
            self.userId = userId
            startDebounceTimer()
        }
    }
    
    func set(attributes: [String : AttributeValue]) {
        syncQueue.sync {
            self.attributes = attributes
            startDebounceTimer()
        }
    }
    
    func add(attribute: AttributeValue, forKey key: String) {
        syncQueue.sync {
           if var attr = self.attributes {
               attr[key] = attribute
               self.attributes = attr
           } else {
               self.attributes = [key: attribute]
           }
           startDebounceTimer()
       }
    }
    
    func set(language: String) {
        syncQueue.sync {
            self.language = language
            
            // Check if we have an effective userId
            let effectiveUserId = self.userId ?? Formbricks.userManager?.userId
            
            if effectiveUserId != nil {
                // If we have a userId, set attributes
                self.attributes = ["language": .string(language)]
            } else {
                // If no userId, just update locally without API call
                Formbricks.logger?.debug("UpdateQueue - updating language locally: \(language)")
                return
            }
            
            startDebounceTimer()
        }
    }
    
    /// Asks for the user state to be re-read from the server. Carries no new data — it exists
    /// so an interaction that can change segment membership doesn't have to wait for the state
    /// to expire.
    ///
    /// While a sync is airborne the nudge is deferred rather than sent, because two concurrent
    /// `POST /user` calls would race and the later response would overwrite `segments` /
    /// `displays` / `responses` wholesale. It is replayed by `syncDidFinish()`.
    func requestUserStateRefresh(userId: String) {
        syncQueue.sync {
            guard !isSyncInFlight else {
                Formbricks.logger?.debug("UpdateQueue - refresh deferred, a sync is already in flight")
                pendingRefreshUserId = userId
                return
            }
            self.userId = userId
            startDebounceTimer()
        }
    }

    /// Called by the user manager once a sync finishes. Releases the in-flight lock and replays
    /// a refresh that arrived while the request was out.
    func syncDidFinish() {
        var deferredUserId: String?
        syncQueue.sync {
            isSyncInFlight = false
            deferredUserId = pendingRefreshUserId
            pendingRefreshUserId = nil
        }

        guard let deferredUserId = deferredUserId else { return }
        Formbricks.logger?.debug("UpdateQueue - replaying a refresh that arrived mid-sync")
        // Outside the block above: `requestUserStateRefresh` takes the same queue.
        requestUserStateRefresh(userId: deferredUserId)
    }

    func reset() {
        syncQueue.sync {
            userId = nil
            attributes = nil
            language = nil
            isSyncInFlight = false
        }
    }
    
    deinit {
        Formbricks.logger?.debug("Deinitializing \(self)")
    }
}

private extension UpdateQueue {
    func startDebounceTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timer?.invalidate()
            self.timer = nil
            self.timer = Timer.scheduledTimer(timeInterval: UpdateQueue.debounceInterval,
                                              target: self,
                                              selector: #selector(self.commit),
                                              userInfo: nil,
                                              repeats: false)
        }
    }
    
    @objc func commit() {
        var effectiveUserId: String?
        var effectiveAttributes: [String: AttributeValue]?
        
        // Capture a consistent snapshot under the sync queue
        syncQueue.sync {
            effectiveUserId = self.userId ?? Formbricks.userManager?.userId
            effectiveAttributes = self.attributes
            // Only mark a sync in flight when one is actually about to be sent. The guard
            // below decides that, so mirror its condition here — otherwise an anonymous
            // commit would leave the flag stuck and swallow every later refresh nudge.
            if effectiveUserId != nil {
                isSyncInFlight = true
            }
        }

        guard let userId = effectiveUserId else {
            let error = FormbricksSDKError(type: .userIdIsNotSetYet)
            Formbricks.logger?.error(error.message)
            return
        }
        
        // Nothing will call `syncDidFinish()` if there is no user manager left to run the
        // request, so clear the flag here rather than leaving it stuck.
        guard let userManager = userManager else {
            syncQueue.sync { isSyncInFlight = false }
            return
        }

        Formbricks.logger?.debug("UpdateQueue - commit() called on UpdateQueue with \(userId) and \(effectiveAttributes ?? [:])")
        userManager.syncUser(withId: userId, attributes: effectiveAttributes)
    }
}

// Add a function to to stop the timer for cleanup
extension UpdateQueue {
    func cleanup() {
        syncQueue.sync {
            timer?.invalidate()
            timer = nil
            userId = nil
            attributes = nil
            language = nil
            isSyncInFlight = false
            // Teardown, unlike `reset()`: drop the deferred refresh instead of replaying it.
            pendingRefreshUserId = nil
        }
    }
}
