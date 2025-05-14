import UIKit
@testable import FormbricksSDK

/// This can be extended later when needed
enum MockResponse: String {
    case environment = "Environment"
    case user = "User"
}

class MockFormbricksService: FormbricksService {
    
    var isErrorResponseNeeded = false
    
    override func getEnvironmentState(completion: @escaping (ResultType<GetEnvironmentRequest.Response>) -> Void) {
        if isErrorResponseNeeded {
            completion(.failure(RuntimeError(message: "")))
        } else {
            execute(.environment, completion: completion)
        }
    }
    
    override func postUser(id: String, attributes: [String : String]?, completion: @escaping (ResultType<PostUserRequest.Response>) -> Void) {
        if isErrorResponseNeeded {
            completion(.failure(RuntimeError(message: "")))
        } else {
            execute(.user, completion: completion)
        }
    }
    
    func execute<T: Decodable>(_ response: MockResponse, completion: @escaping (ResultType<T>) -> Void) {
        // Try multiple approaches to find the JSON file
        var data: Data?
        
        // First try Bundle.module
        if let url = Bundle.module.url(forResource: response.rawValue, withExtension: "json") {
            data = try? Data(contentsOf: url)
        }
        
        // If that didn't work, try finding the file directly
        if data == nil {
            let testBundle = Bundle(for: type(of: self))
            if let url = testBundle.url(forResource: response.rawValue, withExtension: "json") {
                data = try? Data(contentsOf: url)
            }
        }
        
        // If still no data, try looking in a Mock directory
        if data == nil {
            let testBundle = Bundle(for: type(of: self))
            if let url = testBundle.url(forResource: "Mock/\(response.rawValue)", withExtension: "json") {
                data = try? Data(contentsOf: url)
            }
        }
        
        // Last resort - use embedded strings for simple responses
        if data == nil {
            switch response {
            case .environment:
                let mockEnv = """
                {
                    "data": {
                        "id": "mockEnvironmentId",
                        "noCodeEditorUrl": "https://app.formbricks.com/environments/mockEnvironmentId/surveys/create",
                        "organizationId": "mockOrgId",
                        "productId": "mockProductId",
                        "surveys": [
                            {
                                "id": "cm6ovw6j7000gsf0kduf4oo4i",
                                "name": "Product Demo Survey",
                                "createdAt": "2023-12-13T13:27:40.661Z",
                                "status": "inProgress",
                                "questions": [
                                    {
                                        "id": "54767",
                                        "type": "cta",
                                        "headline": "Welcome to our Product Demo",
                                        "html": "",
                                        "buttonLabel": "Start",
                                        "logic": {
                                            "type": "next"
                                        },
                                        "required": false
                                    }
                                ],
                                "triggers": [{"eventName": "click_demo_button"}],
                                "displayOption": "displayOnce",
                                "autoClose": null,
                                "recontactDays": null,
                                "delay": 0,
                                "autoComplete": null,
                                "closeOnDate": null,
                                "styling": {
                                    "placement": "bottomRight",
                                    "clickOutsideClose": false,
                                    "progressBar": true,
                                    "submitText": "Submit",
                                    "darkOverlay": false,
                                    "highlightBorderColor": "#0E8484"
                                }
                            }
                        ]
                    }
                }
                """
                data = mockEnv.data(using: .utf8)
            case .user:
                let mockUser = """
                {
                    "data": {
                        "id": "6CCCE716-6783-4D0F-8344-9C7DFA43D8F7",
                        "userId": "6CCCE716-6783-4D0F-8344-9C7DFA43D8F7",
                        "createdAt": "2023-12-05T18:23:34.512Z",
                        "updatedAt": "2023-12-05T18:23:34.512Z",
                        "attributes": {}
                    }
                }
                """
                data = mockUser.data(using: .utf8)
            }
        }
        
        guard let jsonData = data else {
            completion(.failure(RuntimeError(message: "Unable to find or parse mock response")))
            return
        }
        
        do {
            let body = try JSONDecoder.iso8601Full.decode(T.self, from: jsonData)
            completion(.success(body))
        } catch {
            print("JSON Decode Error: \(error)")
            completion(.failure(error))
        }
    }
}
