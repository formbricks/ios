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
        print("from mocked getEnvironmentState")
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
    
//    func execute<T: Decodable>(_ response: MockResponse,
//                                   completion: @escaping (ResultType<T>) -> Void) {
//            let name = response.rawValue
//            var data: Data?
//            
//            // 1️⃣ Try Bundle.module
//            if let url = Bundle.module.url(forResource: name, withExtension: "json") {
//                print("🔍 Found \(name).json in Bundle.module at \(url.path)")
//                data = try? Data(contentsOf: url)
//            } else {
//                print("⚠️ \(name).json not found in Bundle.module")
//            }
//            
//            // 2️⃣ Try test bundle root
//            if data == nil {
//                let testBundle = Bundle(for: type(of: self))
//                if let url = testBundle.url(forResource: name, withExtension: "json") {
//                    print("🔍 Found \(name).json in test bundle at \(url.path)")
//                    data = try? Data(contentsOf: url)
//                } else {
//                    print("⚠️ \(name).json not found in test bundle root")
//                }
//            }
//        
//            print("is data set now? ")
//            print(data)
//            
//            // 3️⃣ Try “Mock/” subdirectory
//            if data == nil {
//                let testBundle = Bundle(for: type(of: self))
//                if let url = testBundle.url(forResource: name, withExtension: "json", subdirectory: "Mock") {
//                    print("🔍 Found \(name).json in test bundle Mock/ at \(url.path)")
//                    data = try? Data(contentsOf: url)
//                } else {
//                    print("⚠️ \(name).json not found in test bundle Mock/ subdirectory")
//                }
//            }
//            
//            // 4️⃣ If still missing, log folder listings
//            guard let jsonData = data else {
//                print("❌ \(name).json not found in any bundle location.")
//                
//                // List Bundle.module resources
//                if let resDir = Bundle.module.resourceURL?.path {
//                    print("📂 Contents of Bundle.module.resourceURL (\(resDir)):")
//                    if let files = try? FileManager.default.contentsOfDirectory(atPath: resDir) {
//                        files.forEach { print("  • \($0)") }
//                    }
//                }
//                // List test bundle resources
//                let testBundle = Bundle(for: type(of: self))
//                if let testResDir = testBundle.resourceURL?.path {
//                    print("📂 Contents of test bundle.resourceURL (\(testResDir)):")
//                    if let files = try? FileManager.default.contentsOfDirectory(atPath: testResDir) {
//                        files.forEach { print("  • \($0)") }
//                    }
//                }
//                
//                completion(.failure(RuntimeError(message: "Unable to find or parse mock response")))
//                return
//            }
//        
//            // 6️⃣ Decode as before
//            do {
//                let body = try JSONDecoder.iso8601Full.decode(T.self, from: jsonData)
//                if(name == "Environment") {
//                    print("Setting environmentResponseObjectKey")
//                    UserDefaults.standard.set(data, forKey: "environmentResponseObjectKey")
//                    UserDefaults.standard.synchronize()
//                }
//                completion(.success(body))
//            } catch {
//                print("❌ JSON Decode Error for \(name).json: \(error)")
//                completion(.failure(error))
//            }
//    }
    
    func execute<T: Decodable>(_ response: MockResponse, completion: @escaping (ResultType<T>) -> Void) {
        guard let url = Bundle.module.url(forResource: response.rawValue, withExtension: "json"), let data = try? Data(contentsOf: url) else {
        completion(.failure(RuntimeError(message: "Unable to parse response")))
        return
      }
      
      do {
          let body = try JSONDecoder.iso8601Full.decode(T.self, from: data)
        completion(.success(body))
      } catch {
        completion(.failure(error))
      }
    }

}
