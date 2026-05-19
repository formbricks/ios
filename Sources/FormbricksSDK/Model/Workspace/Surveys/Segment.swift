import Foundation

// MARK: - Segment Model

/// Public client API returns the minimal `{ id, hasFilters }` shape — full
/// filter logic (titles, descriptions, conditions) is evaluated server-side
/// and must not reach the device.
///
/// The custom decoder also accepts legacy cached payloads that still carry a
/// `filters` array (written by older SDK versions before the API was slimmed
/// down). In that case `hasFilters` is derived from the array length so
/// anonymous users continue to be excluded from segment-targeted surveys
/// during the cache window after an SDK upgrade.
struct Segment: Codable {
    let id: String
    let hasFilters: Bool

    private enum CodingKeys: String, CodingKey {
        case id, hasFilters, filters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)

        if let serverHasFilters = try container.decodeIfPresent(Bool.self, forKey: .hasFilters) {
            hasFilters = serverHasFilters
        } else if let legacyFilters = try container.decodeIfPresent([AnyDecodable].self, forKey: .filters) {
            hasFilters = !legacyFilters.isEmpty
        } else {
            hasFilters = false
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(hasFilters, forKey: .hasFilters)
    }
}
