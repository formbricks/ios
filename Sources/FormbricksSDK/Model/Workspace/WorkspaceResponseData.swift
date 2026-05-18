import Foundation

struct WorkspaceResponseData: Codable {
    let data: WorkspaceData
    let expiresAt: Date
}
