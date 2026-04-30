import Foundation

struct WorkspaceResponse: Codable {
    let data: WorkspaceResponseData

    var responseString: String?

    enum CodingKeys: CodingKey {
        case data
        case responseString
    }
}

extension WorkspaceResponse {
    func getSurveyJson(forSurveyId surveyId: String) -> [String: Any]? {
        guard let jsonData = responseString?.data(using: .utf8) else { return nil }
        let responseDictionary = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        let responseDict = responseDictionary?["data"] as? [String: Any]
        let dataDict = responseDict?["data"] as? [String: Any]
        let surveysArray = dataDict?["surveys"] as? [[String: Any]]
        return surveysArray?.first(where: { $0["id"] as? String == surveyId }) as? [String: Any]
    }

    func getSurveyStylingJson(forSurveyId surveyId: String) -> [String: Any]? {
        guard let jsonData = responseString?.data(using: .utf8) else { return nil }
        let responseDictionary = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        let responseDict = responseDictionary?["data"] as? [String: Any]
        let dataDict = responseDict?["data"] as? [String: Any]
        let surveysArray = dataDict?["surveys"] as? [[String: Any]]
        let survey = surveysArray?.first(where: { $0["id"] as? String == surveyId }) as? [String: Any]
        return survey?["styling"] as? [String: Any]
    }

    func getSettingsStylingJson() -> [String: Any]? {
        guard let jsonData = responseString?.data(using: .utf8) else { return nil }
        let responseDictionary = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        let responseDict = responseDictionary?["data"] as? [String: Any]
        let dataDict = responseDict?["data"] as? [String: Any]
        // Server may respond with `settings`, `workspace`, or legacy `project` — all carry the same shape.
        let settingsDict = (dataDict?["settings"] as? [String: Any])
            ?? (dataDict?["workspace"] as? [String: Any])
            ?? (dataDict?["project"] as? [String: Any])
        return settingsDict?["styling"] as? [String: Any]
    }
}
