import Foundation

/// Store and manage user state and sync with the server when needed.
final class UserManager: UserManagerSyncable {
    weak var surveyManager: SurveyManager?
    internal var service: FormbricksServiceProtocol
    
    init(surveyManager: SurveyManager? = nil, service: FormbricksServiceProtocol = FormbricksService()) {
        self.surveyManager = surveyManager
        self.service = service
    }
    
    private static let userIdKey = "userIdKey"
    private static let contactIdKey = "contactIdKey"
    private static let segmentsKey = "segmentsKey"
    private static let displaysKey = "displaysKey"
    private static let responsesKey = "responsesKey"
    private static let lastDisplayedAtKey = "lastDisplayedAtKey"
    private static let expiresAtKey = "expiresAtKey"
    
    private var backingUserId: String?
    private var backingContactId: String?
    private var backingSegments: [String]?
    private var backingDisplays: [Display]?
    private var backingResponses: [String]?
    private var backingLastDisplayedAt: Date?
    private var backingExpiresAt: Date?
    
    lazy private var updateQueue: UpdateQueue? = {
        return UpdateQueue(userManager: self)
    }()
    
    internal var syncTimer: Timer?
    
    /// Starts an update queue with the given user id.
    func set(userId: String) {
        updateQueue?.set(userId: userId)
    }
    
    /// Starts an update queue with the given attribute.
    func add(attribute: AttributeValue, forKey key: String) {
        updateQueue?.add(attribute: attribute, forKey: key)
    }
    
    /// Starts an update queue with the given attributes.
    func set(attributes: [String: AttributeValue]) {
        updateQueue?.set(attributes: attributes)
    }
    
    /// Starts an update queue with the given language..
    func set(language: String) {
        updateQueue?.set(language: language)
    }
    
    /// Saves `surveyId` to the `displays` property and the current date to the `lastDisplayedAt` property.
    func onDisplay(surveyId: String) {
        let lastDisplayedAt = Date()
        var newDisplays = displays ?? []
        newDisplays.append(Display(surveyId: surveyId, createdAt: DateFormatter.isoFormatter.string(from: lastDisplayedAt)))
        displays = newDisplays
        self.lastDisplayedAt = lastDisplayedAt
        surveyManager?.filterSurveys()
    }
    
    /// Saves `surveyId` to the `responses` property.
    func onResponse(surveyId: String) {
        var newResponses = responses ?? []
        newResponses.append(surveyId)
        responses = newResponses
        surveyManager?.filterSurveys()
    }

    /// Pulls fresh server-computed `segments` after an interaction that can flip segment
    /// membership, instead of waiting for the state to expire.
    ///
    /// A `surveyInteraction` segment filter ("have seen X", "have completed X", ...) can change
    /// who a contact is the moment they interact with a survey. The local bookkeeping in
    /// `onDisplay` / `onResponse` keeps display caps and recontact days correct on device, but
    /// segment membership is only ever computed by the server, so it has to be refetched.
    ///
    /// The refresh is deliberately gated twice, because a `/user` sync is not cheap:
    ///  - no-op for anonymous users, who never receive segments in the first place;
    ///  - no-op unless the server set the bit for this survey and this event.
    ///
    /// It is routed through the `UpdateQueue` rather than calling `syncUser` directly, so a
    /// display -> response -> finish burst is debounced into a single request.
    func refreshSegmentsAfterInteraction(survey: Survey, source: InteractionSource) {
        guard let userId = userId else { return }
        guard survey.interactionRefresh?.shouldRefresh(on: source) == true else { return }

        Formbricks.logger?.debug("Refreshing segments after \(source.rawValue) on survey \(survey.id)")
        updateQueue?.requestUserStateRefresh(userId: userId)
    }
    
    /// Syncs the user state with the server if the user id is set and the expiration date has passed.
    func syncUserStateIfNeeded() {
        guard let id = userId, let expiresAt = self.expiresAt, expiresAt.timeIntervalSinceNow <= 0 else {
            // Drop only the in-memory caches. Assigning `[]` would mask the
            // persisted UserDefaults arrays because the lazy getter falls back
            // to disk only when the backing is nil; an empty array short-circuits
            // the `??` and the persisted responses/segments never get read.
            backingSegments = nil
            backingDisplays = nil
            backingResponses = nil

            // The state is still valid, but nothing has been scheduled to refresh it when it
            // does expire — `startSyncTimer()` is otherwise only reached from a successful sync,
            // so a launch that finds a warm cache would never refresh segments again.
            startSyncTimer()
            return
        }

        syncUser(withId: id)
    }

    /// Syncs the user state with the server, calls the `self?.surveyManager?.filterSurveys()` method and starts the sync timer.
    func syncUser(withId id: String, attributes: [String: AttributeValue]? = nil) {
        service.postUser(id: id, attributes: attributes) { [weak self] result in
            switch result {
            case .success(let userResponse):
                self?.userId = userResponse.data.state?.data?.userId
                self?.contactId = userResponse.data.state?.data?.contactId
                self?.segments = userResponse.data.state?.data?.segments
                self?.displays = userResponse.data.state?.data?.displays
                self?.responses = userResponse.data.state?.data?.responses
                self?.lastDisplayedAt = userResponse.data.state?.data?.lastDisplayAt
                self?.expiresAt = userResponse.data.state?.expiresAt
                
                let serverLanguage = userResponse.data.state?.data?.language
                Formbricks.language = serverLanguage ?? "default"
                
                // Log errors (always visible) - e.g., invalid attribute keys, type mismatches
                if let errors = userResponse.data.errors {
                    for error in errors {
                        Formbricks.logger?.error(error)
                    }
                }
                
                // Log informational messages (debug only)
                if let messages = userResponse.data.messages {
                    for message in messages {
                        Formbricks.logger?.debug("User update message: \(message)")
                    }
                }
                
                self?.updateQueue?.reset()
                self?.surveyManager?.filterSurveys()
                self?.startSyncTimer()
            case .failure(let error):
                // Release the in-flight lock so a later refresh nudge isn't swallowed.
                // `reset()` already does this on the success path.
                self?.updateQueue?.syncDidFinish()
                Formbricks.logger?.error(error)
            }
        }
    }
    
    /// Logs out the user and clears the user state.
    func logout() {
        Formbricks.logger?.debug("Logging out and cleaning user state")
        
        UserDefaults.standard.removeObject(forKey: UserManager.userIdKey)
        UserDefaults.standard.removeObject(forKey: UserManager.contactIdKey)
        UserDefaults.standard.removeObject(forKey: UserManager.segmentsKey)
        UserDefaults.standard.removeObject(forKey: UserManager.displaysKey)
        UserDefaults.standard.removeObject(forKey: UserManager.responsesKey)
        UserDefaults.standard.removeObject(forKey: UserManager.lastDisplayedAtKey)
        UserDefaults.standard.removeObject(forKey: UserManager.expiresAtKey)
        backingUserId = nil
        backingContactId = nil
        backingSegments = nil
        backingDisplays = nil
        backingResponses = nil
        backingLastDisplayedAt = nil
        backingExpiresAt = nil
        Formbricks.language = "default"
        
        stopSyncTimer()
        updateQueue?.cleanup()

        // Re-filter surveys for logged out user
        surveyManager?.filterSurveys()
    }
    
    func cleanupUpdateQueue() {
        updateQueue?.cleanup()
        updateQueue = nil  // Release the instance so memory can be reclaimed.
    }
    
    deinit {
        Formbricks.logger?.debug("Deinitializing \(self)")
    }
}

// MARK: - Timer -
private extension UserManager {
    /// Schedules the next user-state sync for when the cached state expires.
    ///
    /// This runs inside `syncUser`'s completion, which `APIClient` delivers on URLSession's
    /// background delegate queue — a pooled thread with no run loop. `Timer.scheduledTimer`
    /// installs on `RunLoop.current`, so scheduling it there produced a timer that could never
    /// fire, and the user state was in practice only ever refreshed by the lazy check inside
    /// `Formbricks.setup()`. Build the timer unscheduled and add it to the main run loop
    /// instead, the same way `UpdateQueue` hops to main for its debounce timer.
    func startSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil

        guard let expiresAt = expiresAt, let id = userId else { return }

        // A device clock running ahead of the server makes every `expiresAt` we receive
        // already in the past, which would otherwise sync in a tight loop.
        let interval = max(expiresAt.timeIntervalSinceNow, Config.User.minimumSyncIntervalInSeconds)

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            // The user may have been logged out or swapped while this was pending.
            guard let self = self, self.userId == id else { return }
            self.syncUser(withId: id)
        }
        syncTimer = timer

        // `.common` so an expiry that lands mid-scroll isn't postponed until the gesture ends.
        onMain { RunLoop.main.add(timer, forMode: .common) }
    }

    /// Cancels a pending user-state sync. Safe to call from any thread.
    func stopSyncTimer() {
        let timer = syncTimer
        syncTimer = nil
        guard let timer = timer else { return }
        onMain { timer.invalidate() }
    }

    /// Runs `work` on the main thread, immediately if we are already there. `Timer` and
    /// `RunLoop` are bound to the thread that scheduled them, so all timer bookkeeping has to
    /// funnel through the main run loop.
    func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

// MARK: - Getters -
extension UserManager {
    private(set) var userId: String? {
        get {
            backingUserId = backingUserId ?? UserDefaults.standard.string(forKey: UserManager.userIdKey)
            return backingUserId
        } set {
            UserDefaults.standard.set(newValue, forKey: UserManager.userIdKey)
            backingUserId = newValue
        }
    }
    private(set) var contactId: String? {
        get {
            backingContactId = backingContactId ?? UserDefaults.standard.string(forKey: UserManager.contactIdKey)
            return backingContactId
        } set {
            UserDefaults.standard.set(newValue, forKey: UserManager.contactIdKey)
            backingContactId = newValue
        }
    }
    private(set) var segments: [String]? {
        get {
            backingSegments = backingSegments ?? UserDefaults.standard.stringArray(forKey: UserManager.segmentsKey)
            return backingSegments
        } set {
            UserDefaults.standard.set(newValue, forKey: UserManager.segmentsKey)
            backingSegments = newValue
        }
    }
    private(set) var displays: [Display]? {
        get {
            guard let jsonData = UserDefaults.standard.string(forKey: UserManager.displaysKey)?.data(using: .utf8) else {
                return nil
            }
            let decodedDisplays = try? JSONDecoder().decode([Display].self, from: jsonData)
            backingDisplays = decodedDisplays
            return backingDisplays
        } set {
            guard let jsonData = try? JSONEncoder().encode(newValue), let jsonString = String(data: jsonData, encoding: .utf8) else { return }
            UserDefaults.standard.set(jsonString, forKey: UserManager.displaysKey)
            backingDisplays = newValue
        }
    }
    private(set) var responses: [String]? {
        get {
            backingResponses = backingResponses ?? UserDefaults.standard.stringArray(forKey: UserManager.responsesKey)
            return backingResponses
        } set {
            UserDefaults.standard.set(newValue, forKey: UserManager.responsesKey)
            backingResponses = newValue
        }
    }
    private(set) var lastDisplayedAt: Date? {
        get {
            if let backingLastDisplayedAt = backingLastDisplayedAt {
                return backingLastDisplayedAt
            } else {
                let timeInterval = UserDefaults.standard.double(forKey: UserManager.lastDisplayedAtKey)
                return timeInterval > 0 ? Date(timeIntervalSince1970: timeInterval) : nil
            }
        } set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970, forKey: UserManager.lastDisplayedAtKey)
            backingLastDisplayedAt = newValue
        }
    }
    private(set) var expiresAt: Date? {
        get {
            if let backingExpiresAt = backingExpiresAt {
                return backingExpiresAt
            } else {
                let timeInterval = UserDefaults.standard.double(forKey: UserManager.expiresAtKey)
                return timeInterval > 0 ? Date(timeIntervalSince1970: timeInterval) : nil
            }
        } set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970, forKey: UserManager.expiresAtKey)
            backingExpiresAt = newValue
        }
    }
}
