import Foundation

struct Config {
    struct Environment {
        /// On error, the environment will be refreshed after this amount of time (in minutes)
        static let refreshStateOnErrorTimeoutInMinutes = 10
    }

    struct User {
        /// Floor for the gap between two user-state syncs. Guards against a device clock
        /// running ahead of the server, where every `expiresAt` the server returns is already
        /// in the device's past and an unclamped timer would sync in a tight loop.
        /// A `var` only so tests can shorten it; the SDK never writes to it.
        static var minimumSyncIntervalInSeconds: TimeInterval = 60

        /// How long to wait before retrying a user-state sync that failed. Deliberately much
        /// longer than the minimum interval so a sustained outage doesn't turn into a
        /// fixed-rate request stream. Mirrors `Environment.refreshStateOnErrorTimeoutInMinutes`.
        static var retryAfterFailureInMinutes = 10

        /// Window over which `setUserId` / `setAttribute` calls are coalesced into a single
        /// `POST /user`. A `var` only so tests can shorten it; the SDK never writes to it.
        static var updateDebounceIntervalInSeconds: TimeInterval = 0.5

        /// Ceiling on how long `track()` will wait for a queued user update to land before it
        /// gives up and evaluates targeting anyway. Bounds the delay a dead network can add to
        /// a track call — without it a host that tracks right after `setAttribute` would hang on
        /// a request that is never going to answer.
        /// A `var` only so tests can shorten it; the SDK never writes to it.
        static var pendingUpdateTimeoutInSeconds: TimeInterval = 5
    }
}
