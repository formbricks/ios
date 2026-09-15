import Foundation

protocol UserManagerSyncable: AnyObject {
    func syncUser(withId id: String, attributes: [String: AttributeValue]?)
}

/// Update queue. This class is used to queue updates to the user.
/// The given properties will be sent to the backend and updated in the user object when the debounce interval is reached.
final class UpdateQueue {

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

    /// The values the in-flight request is carrying. `commit()` *moves* them out of `userId` /
    /// `attributes` rather than copying, so anything a host sets while the request is out
    /// accumulates separately and cannot be dropped when the response lands. Kept so a failed
    /// request can hand them back to be retried.
    private var inFlightUserId: String?
    private var inFlightAttributes: [String: AttributeValue]?

    /// Callbacks parked by `waitForPendingWork(completion:)`, keyed so a timeout resolves only
    /// its own waiter. Drained atomically under `syncQueue`, so a waiter is never called twice.
    private var pendingWaiters: [Int: (Bool) -> Void] = [:]
    private var waiterToken = 0

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

    /// Whether anything is queued for the server, or a request carrying such values is still out.
    func hasPendingWork() -> Bool {
        syncQueue.sync { hasPendingWorkLocked }
    }

    /// Calls `completion` once the queued user updates have reached the server, so the caller can
    /// decide against the resulting user state rather than the state that predates it.
    ///
    /// `true` means there was nothing to wait for, or the sync succeeded — `segments` can be
    /// trusted. `false` means the update failed or timed out, so segment membership is still
    /// whatever it was and any segment-targeted decision would be made on stale data.
    ///
    /// Deliberately callback-based rather than blocking. The debounce `Timer` is installed on the
    /// main run loop and `track()` is normally called from the main thread, so parking that thread
    /// on a semaphore would stall the very run loop the timer needs and guarantee a timeout.
    func waitForPendingWork(completion: @escaping (Bool) -> Void) {
        var resolveNow: Bool?
        var shouldFlush = false
        var token = 0

        syncQueue.sync {
            guard hasPendingWorkLocked else {
                resolveNow = true
                return
            }

            // Nothing can be sent for an anonymous user — `commit()` bails before it reaches the
            // network, so nothing would ever resolve the waiter and it would sit until the
            // timeout. `filterSurveys()` already excludes anonymous users from segment-targeted
            // surveys, so there is no stale-membership risk to guard against here.
            guard effectiveUserIdLocked != nil else {
                resolveNow = true
                return
            }

            waiterToken += 1
            token = waiterToken
            pendingWaiters[token] = completion
            // A request carrying these values is already out; join it instead of starting a
            // second concurrent one.
            shouldFlush = !isSyncInFlight
        }

        if let resolveNow = resolveNow {
            completion(resolveNow)
            return
        }

        if shouldFlush {
            flushNow()
        }
        scheduleWaiterTimeout(for: token)
    }

    /// Called by the user manager once a sync finishes. Releases the in-flight lock, resolves
    /// everyone waiting on that request, and gives whatever queued up meanwhile its turn.
    ///
    /// `success: false` hands the failed request's values back to the queue so they are retried
    /// on the next commit — but deliberately does *not* re-arm the debounce timer for them. A
    /// self-retrying failure would turn a dead network into a request every half second;
    /// `UserManager.scheduleSyncRetry()` owns the backoff instead.
    func syncDidFinish(success: Bool = true) {
        var deferredUserId: String?
        var waiters: [(Bool) -> Void] = []
        var hasNewWork = false

        syncQueue.sync {
            isSyncInFlight = false

            // Anything queued while the request was out is genuinely new and needs its own
            // commit. Read before the hand-back below, so a failure's own values don't look new.
            hasNewWork = userId != nil || attributes != nil

            if !success {
                if userId == nil { userId = inFlightUserId }
                if let carried = inFlightAttributes {
                    // Anything set since the request went out is newer, so it wins the key clash.
                    attributes = carried.merging(attributes ?? [:]) { _, newer in newer }
                }
            } else if hasNewWork, userId == nil {
                // A write that arrived mid-request belongs to the same user, but `commit()` moved
                // the id out with the request. Put it back so the follow-up carries an identity
                // of its own rather than depending on the response having already reached the
                // user manager.
                userId = inFlightUserId
            }
            inFlightUserId = nil
            inFlightAttributes = nil

            waiters = Array(pendingWaiters.values)
            pendingWaiters.removeAll()

            deferredUserId = pendingRefreshUserId
            pendingRefreshUserId = nil
        }

        resolve(waiters, with: success)

        // Both calls below take `syncQueue`, so they have to run outside the block above.
        if let deferredUserId = deferredUserId {
            Formbricks.logger?.debug("UpdateQueue - replaying a refresh that arrived mid-sync")
            requestUserStateRefresh(userId: deferredUserId)
        } else if hasNewWork {
            Formbricks.logger?.debug("UpdateQueue - re-arming for updates queued during the sync")
            syncQueue.sync { startDebounceTimer() }
        }
    }

    /// Drops the queued values. Does not touch a request that is already in flight — `commit()`
    /// has moved those values out of the queue by then, and the response is what settles them.
    func reset() {
        syncQueue.sync {
            userId = nil
            attributes = nil
            language = nil
        }
    }
    
    deinit {
        Formbricks.logger?.debug("Deinitializing \(self)")
    }
}

private extension UpdateQueue {
    /// Must be read under `syncQueue`.
    var hasPendingWorkLocked: Bool {
        userId != nil || attributes != nil || isSyncInFlight
    }

    /// The id a commit would send. Must be read under `syncQueue`.
    var effectiveUserIdLocked: String? {
        userId ?? inFlightUserId ?? Formbricks.userManager?.userId
    }

    /// Must be called under `syncQueue`.
    func startDebounceTimer() {
        onMain { [weak self] in
            guard let self = self else { return }
            self.timer?.invalidate()
            self.timer = nil
            self.timer = Timer.scheduledTimer(timeInterval: Config.User.updateDebounceIntervalInSeconds,
                                              target: self,
                                              selector: #selector(self.commit),
                                              userInfo: nil,
                                              repeats: false)
        }
    }

    /// Sends what is queued now instead of waiting the debounce window out. Everything queued so
    /// far still goes in a single request, so calls stay coalesced.
    func flushNow() {
        onMain { [weak self] in
            guard let self = self else { return }
            self.timer?.invalidate()
            self.timer = nil
            self.commit()
        }
    }

    func scheduleWaiterTimeout(for token: Int) {
        let timeout = Config.User.pendingUpdateTimeoutInSeconds
        syncQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self else { return }
            guard let waiter = self.pendingWaiters.removeValue(forKey: token) else { return }
            Formbricks.logger?.debug("UpdateQueue - a queued user update did not land within \(timeout)s")
            self.resolve([waiter], with: false)
        }
    }

    /// Hands every parked waiter the same outcome. Resolution is moved off `syncQueue` so a
    /// waiter that calls back into the queue cannot deadlock on it.
    func resolve(_ waiters: [(Bool) -> Void], with success: Bool) {
        guard !waiters.isEmpty else { return }
        DispatchQueue.main.async {
            waiters.forEach { $0(success) }
        }
    }

    /// `Timer` and `RunLoop` are bound to the thread that scheduled them, so all timer
    /// bookkeeping funnels through the main run loop. Runs inline when already there, so a
    /// `flushNow()` from the main thread sends without waiting for another turn of the loop.
    func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    @objc func commit() {
        var effectiveUserId: String?
        var effectiveAttributes: [String: AttributeValue]?
        var isDeferred = false

        // Capture a consistent snapshot under the sync queue
        syncQueue.sync {
            // Never two at once: `APIClient` does not serialise requests, so a second
            // `POST /user` would race the first and the later response would overwrite
            // `segments` / `displays` / `responses` wholesale. `syncDidFinish()` re-arms.
            guard !isSyncInFlight else {
                isDeferred = true
                return
            }

            effectiveUserId = self.userId ?? Formbricks.userManager?.userId
            effectiveAttributes = self.attributes

            // Only mark a sync in flight when one is actually about to be sent. The guard
            // below decides that, so mirror its condition here — otherwise an anonymous
            // commit would leave the flag stuck and swallow every later refresh nudge.
            if effectiveUserId != nil {
                isSyncInFlight = true
                // Move, don't copy. Leaving these queued meant the success path's `reset()`
                // cleared whatever a host had set while the request was out, and the value was
                // then never sent — a silent write loss.
                inFlightUserId = self.userId
                inFlightAttributes = self.attributes
                self.userId = nil
                self.attributes = nil
                self.language = nil
            }
        }

        if isDeferred {
            Formbricks.logger?.debug("UpdateQueue - commit deferred, a sync is already in flight")
            return
        }

        guard let userId = effectiveUserId else {
            let error = FormbricksSDKError(type: .userIdIsNotSetYet)
            Formbricks.logger?.error(error.message)
            return
        }
        
        // Nothing will call `syncDidFinish()` if there is no user manager left to run the
        // request, so settle it here rather than leaving the flag stuck and waiters parked.
        guard let userManager = userManager else {
            syncDidFinish(success: false)
            return
        }

        Formbricks.logger?.debug("UpdateQueue - commit() called on UpdateQueue with \(userId) and \(effectiveAttributes ?? [:])")
        userManager.syncUser(withId: userId, attributes: effectiveAttributes)
    }
}

// Add a function to to stop the timer for cleanup
extension UpdateQueue {
    func cleanup() {
        var waiters: [(Bool) -> Void] = []

        syncQueue.sync {
            timer?.invalidate()
            timer = nil
            userId = nil
            attributes = nil
            language = nil
            isSyncInFlight = false
            inFlightUserId = nil
            inFlightAttributes = nil
            // Teardown, unlike `reset()`: drop the deferred refresh instead of replaying it.
            pendingRefreshUserId = nil
            waiters = Array(pendingWaiters.values)
            pendingWaiters.removeAll()
        }

        // Nothing is going to land now, so anyone waiting must be told the update did not go
        // through rather than left parked until their timeout.
        resolve(waiters, with: false)
    }
}
