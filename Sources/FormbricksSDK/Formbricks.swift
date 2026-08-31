import Foundation
import Network

/// The main class of the Formbricks SDK. It contains the main methods to interact with the SDK.
@objc(Formbricks) public class Formbricks: NSObject {
    
    static internal var appUrl: String?
    static internal var workspaceId: String?
    /// Backward-compatible alias for `workspaceId`.
    @available(*, deprecated, renamed: "workspaceId", message: "Use workspaceId instead. environmentId will be removed in a future version.")
    static internal var environmentId: String? {
        get { workspaceId }
        set { workspaceId = newValue }
    }
    static internal var language: String = "default"
    static internal var isInitialized: Bool = false
    
    static internal var userManager: UserManager?
    static internal var presentSurveyManager: PresentSurveyManager?
    static internal var surveyManager: SurveyManager?
    static internal var apiQueue: OperationQueue? = OperationQueue()
    static internal var logger: Logger?
    
    // make this class not instantiatable outside of the SDK
    internal override init() {
        /* 
         This empty initializer prevents external instantiation of the Formbricks class.
         All methods are static and the class serves as a namespace for the SDK,
         so instance creation is not needed and should be restricted.
        */
    }
    
    /**
     Initializes the Formbricks SDK with the given config ``FormbricksConfig``.
     This method is mandatory to be called, and should be only once per application lifecycle.
          
     Example:
     ```swift
     let config = FormbricksConfig.Builder(appUrl: "APP_URL_HERE", workspaceId: "TOKEN_HERE")
        .setUserId("USER_ID_HERE")
        .setLogLevel(.debug)
        .build()

     Formbricks.setup(with: config)
     ```
     */
    @objc public static func setup(with config: FormbricksConfig, force: Bool = false) {
        logger = Logger()
        apiQueue = OperationQueue()

        if force {
            isInitialized = false
        }

        guard !isInitialized else {
            let error = FormbricksSDKError(type: .sdkIsAlreadyInitialized)
            Formbricks.logger?.error(error.message)
            return
        }

        self.appUrl = config.appUrl
        self.workspaceId = config.workspaceId
        self.logger?.logLevel = config.logLevel

        if config.usedDeprecatedEnvironmentId {
            Formbricks.logger?.debug("environmentId is deprecated and will be removed in a future version. Please use workspaceId instead.")
        }
        
        // Validate appUrl before proceeding with setup
        guard let url = URL(string: config.appUrl) else {
            Formbricks.logger?.error("Invalid appUrl: \(config.appUrl). SDK setup aborted.")
            return
        }
        
        // Validate that appUrl uses HTTPS (block HTTP for security)
       guard url.scheme?.lowercased() == "https" else {
           let errorMessage = "HTTP requests are blocked for security. Only HTTPS URLs are allowed. Provided app url: \(config.appUrl). SDK setup aborted."
           Formbricks.logger?.error(errorMessage)
           return
       }
        
        let svc: FormbricksServiceProtocol = config.customService ?? FormbricksService()
        
        userManager = UserManager()
        userManager?.service = svc
        if let userId = config.userId {
            userManager?.set(userId: userId)
        }
        if let attributes = config.attributes, !attributes.isEmpty {
            userManager?.set(attributes: attributes)
        }
        if let language = config.attributes?["language"]?.stringValue {
            userManager?.set(language: language)
            self.language = language
        }
    
        presentSurveyManager = PresentSurveyManager()
        surveyManager = SurveyManager.create(userManager: userManager!, presentSurveyManager: presentSurveyManager!, service: svc)
        userManager?.surveyManager = surveyManager
        
        surveyManager?.refreshWorkspaceIfNeeded(force: force)
        userManager?.syncUserStateIfNeeded()
        
        self.isInitialized = true
    }
    
    /**
     Sets the user id for the current user with the given `String`.
     
     - If the same userId is already set, this is a no-op.
     - If a different userId is already set, the previous user state is cleaned up first
       before setting the new userId.
     
     The SDK must be initialized before calling this method.
          
     Example:
     ```swift
     Formbricks.setUserId("USER_ID_HERE")
     ```
     */
    @objc public static func setUserId(_ userId: String) {
        guard Formbricks.isInitialized else {
            let error = FormbricksSDKError(type: .sdkIsNotInitialized)
            Formbricks.logger?.error(error.message)
            return
        }
        
        // If the same userId is already set, no-op
        if let existing = userManager?.userId, existing == userId {
            logger?.debug("UserId is already set to the same value, skipping")
            return
        }
        
        // If a different userId is set, clean up the previous user state first
        if let existing = userManager?.userId, !existing.isEmpty {
            logger?.debug("Different userId is being set, cleaning up previous user state")
            userManager?.logout()
            // An identity switch: the ambient Embedded Data bag may carry the previous user's
            // context, which must not ride onto the next user's responses on a shared device.
            // First-time identification keeps the bag — a host legitimately pushes context before
            // it knows who the user is.
            EmbeddedDataManager.shared.removeAll()
        }
        
        userManager?.set(userId: userId)
    }
    
    /**
     Adds a string attribute for the current user.
     The SDK must be initialized before calling this method.
          
     Example:
     ```swift
     Formbricks.setAttribute("John", forKey: "name")
     ```
     */
    @objc public static func setAttribute(_ attribute: String, forKey key: String) {
        guard Formbricks.isInitialized else {
            let error = FormbricksSDKError(type: .sdkIsNotInitialized)
            Formbricks.logger?.error(error.message)
            return
        }
        
        userManager?.add(attribute: .string(attribute), forKey: key)
    }

    /**
     Adds a numeric attribute for the current user.
     The SDK must be initialized before calling this method.
          
     Example:
     ```swift
     Formbricks.setAttribute(42.0, forKey: "age")
     ```
     */
    public static func setAttribute(_ attribute: Double, forKey key: String) {
        guard Formbricks.isInitialized else {
            let error = FormbricksSDKError(type: .sdkIsNotInitialized)
            Formbricks.logger?.error(error.message)
            return
        }
        
        userManager?.add(attribute: .number(attribute), forKey: key)
    }

    /**
     Adds a date attribute for the current user.
     The date is converted to an ISO 8601 string. The backend will detect the format and treat it as a date type.
     The SDK must be initialized before calling this method.
          
     Example:
     ```swift
     Formbricks.setAttribute(Date(), forKey: "signupDate")
     ```
     */
    public static func setAttribute(_ attribute: Date, forKey key: String) {
        guard Formbricks.isInitialized else {
            let error = FormbricksSDKError(type: .sdkIsNotInitialized)
            Formbricks.logger?.error(error.message)
            return
        }
        
        userManager?.add(attribute: .string(ISO8601DateFormatter().string(from: attribute)), forKey: key)
    }
    
    /**
     Sets the user attributes for the current user.
     
     Attribute types are determined by the value:
     - String values -> string attribute
     - Number values -> number attribute
     - Use ISO 8601 date strings for date attributes
     
     On first write to a new attribute, the type is set based on the value type.
     On subsequent writes, the value must match the existing attribute type.
     
     The SDK must be initialized before calling this method.
          
     Example:
     ```swift
     Formbricks.setAttributes([
         "name": "John",
         "age": 30,
         "score": 9.5
     ])
     ```
     */
    public static func setAttributes(_ attributes: [String : AttributeValue]) {
        guard Formbricks.isInitialized else {
            let error = FormbricksSDKError(type: .sdkIsNotInitialized)
            Formbricks.logger?.error(error.message)
            return
        }
        
        userManager?.set(attributes: attributes)
    }
    
    /**
     Sets the language for the current user with the given `String`.
     This method can be called before or after SDK initialization.
          
     Example:
     ```swift
     Formbricks.setLanguage("de")
     ```
     */
    @objc public static func setLanguage(_ language: String) {
        // Set the language property regardless of initialization status
        if (Formbricks.language == language) {
            return
        }
        
        Formbricks.language = language
        
        // Only update the user manager if SDK is initialized
        if Formbricks.isInitialized {
            userManager?.set(language: language)
        }
    }
    
    /**
     Tracks an action with the given `String`. The SDK will process the action and it will present the survey if any of them can be triggered.
     The SDK must be initialized before calling this method.
          
     Example:
     ```swift
     Formbricks.track("button_clicked")
     ```
     */
    @objc public static func track(_ action: String, completion: (() -> Void)? = nil) {
        guard Formbricks.isInitialized else {
            let error = FormbricksSDKError(type: .sdkIsNotInitialized)
            Formbricks.logger?.error(error.message)
            return
        }
        
        Formbricks.isInternetAvailabile { available in
            if available {
                surveyManager?.track(action, completion: completion)
            } else {
                Formbricks.logger?.warning(FormbricksSDKError.init(type: .networkError).message)
            }
        }
        
    }
    
    /**
     Attaches Embedded Data to future responses without tying it to a trigger.

     Merges into an in-memory bag — last write wins per key, and an explicit `nil` removes a key.
     Values land only on the survey's declared *ingested* fields; anything else is dropped and
     logged by the survey renderer, never fatal.

     **`nil` removes; there is no "leave this alone" value.** Swift has no `undefined`, so this SDK
     maps `nil` onto the JS SDK's `{ key: null }` (remove) and has nothing that spells its
     `{ key: undefined }` (no-op). A host porting the cross-platform idiom of passing every field
     unconditionally — `["plan": user.plan.map(EmbeddedDataValue.string)]` — therefore *clears*
     `plan` here whenever the optional is empty, where the same code on web would leave the previous
     value standing. Build the dictionary from the keys you actually have, or use
     `clearEmbeddedData(_:)` when you mean to remove one.

     Deliberately callable **before** `setup(with:)`, unlike the methods above: a host that pushes
     context at launch must not have that value silently dropped because initialization had not
     finished. The bag is pure memory — nothing here needs the SDK to be running.

     The bag is snapshotted when a survey is displayed and frozen for its lifetime, so a value set
     while a survey is on screen reaches the *next* response, not that one. It is never persisted:
     a cold app start begins empty and the host re-pushes.

     Example:
     ```swift
     Formbricks.setEmbeddedData([
         "plan": "pro",
         "seats": 25,
         "isTrial": false,
         "screen": nil,   // removes the key
     ])
     ```
     */
    public static func setEmbeddedData(_ data: [String: EmbeddedDataValue?]) {
        EmbeddedDataManager.shared.set(data)
    }

    /**
     Removes one Embedded Data key. A key that was never set is a no-op.

     The single-key and clear-everything forms are separate overloads on purpose: a `String` that
     cannot be `nil` means a host reading the key from its own state cannot accidentally wipe the
     whole bag.

     Example:
     ```swift
     Formbricks.clearEmbeddedData("plan")
     ```
     */
    public static func clearEmbeddedData(_ key: String) {
        EmbeddedDataManager.shared.remove(key: key)
    }

    /**
     Clears the whole Embedded Data bag — logout, or a hard context switch.

     Example:
     ```swift
     Formbricks.clearEmbeddedData()
     ```
     */
    public static func clearEmbeddedData() {
        EmbeddedDataManager.shared.removeAll()
    }

    /**
     Logs out the current user. This will clear the user attributes and the user id.
     The SDK must be initialized before calling this method.
          
     Example:
     ```swift
     Formbricks.logout()
     ```
     */
    @objc public static func logout() {
        guard Formbricks.isInitialized else {
            let error = FormbricksSDKError(type: .sdkIsNotInitialized)
            Formbricks.logger?.error(error.message)
            return
        }

        userManager?.logout()
        // Same identity-switch rule as setUserId: logout must not let the previous user's ambient
        // context leak onto whoever uses the app next.
        EmbeddedDataManager.shared.removeAll()
    }
    
    /**
    Cleans up the SDK. This will clear the user attributes, the user id and the workspace state.
    The SDK must be initialized before calling this method.
    If `waitForOperations` is set to `true`, it will wait for all operations to finish before cleaning up.
    If `waitForOperations` is set to `false`, it will clean up immediately.
    You can also provide a completion block that will be called when the cleanup is finished.

    Example:
    ```swift
    Formbricks.cleanup()

    Formbricks.cleanup(waitForOperations: true) {
        // Cleanup completed
    }
    ```
     */
    
    @objc public static func cleanup(waitForOperations: Bool = false, completion: (() -> Void)? = nil) {
        if waitForOperations, let queue = apiQueue {
            DispatchQueue.global(qos: .background).async {
                queue.waitUntilAllOperationsAreFinished()
                performCleanup()
                DispatchQueue.main.async {
                    completion?()
                }
            }
        } else {
            apiQueue?.cancelAllOperations()
            performCleanup()
            completion?()
        }
    }

    private static func performCleanup() {
        // An explicit full reset of the SDK, so the host-supplied context goes too. This is a
        // stronger teardown than the JS SDK's internal one, which deliberately preserves the bag
        // across a setup retry — `cleanup()` is not a retry, it is the host saying "forget it all".
        EmbeddedDataManager.shared.removeAll()
        userManager?.logout()
        userManager?.cleanupUpdateQueue()
        presentSurveyManager?.dismissView()
        presentSurveyManager = nil
        userManager = nil
        surveyManager = nil
        apiQueue = nil
        isInitialized = false
        appUrl = nil
        workspaceId = nil
        logger = nil
        language = "default"
    }
}

// MARK: - Check the network connection -
private extension Formbricks {
    static func isInternetAvailabile(completion: @escaping (Bool) -> Void) {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue.global(qos: .background)
        
        monitor.pathUpdateHandler = { path in
            completion(path.status == .satisfied)
            monitor.cancel()
        }
        
        monitor.start(queue: queue)
    }
}
