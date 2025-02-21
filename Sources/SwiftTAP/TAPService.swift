import Foundation
import OSLog

/// The method to use for querying the TAP service, either synchronously or asynchronously.
///
/// Note that `SwiftTAP` will run the query asynchronously even if you use `.synchronous`,
/// but it does mean that the remote service will run the query either asynchronously or synchronously.
public enum TAPSyncMethod: String {

    /// The query will be run synchronously on the service.
    case synchronous = "sync"

    /// The query will be run asynchronously on the service.
    case asynchronous = "async"
}

/// The HTTP method to use for the query.
///
/// This enumeration specifies the standard HTTP methods that can be used to query a TAP service.
public enum HTTPMethod: String {

    /// The GET method is used to request a representation of a resource.
    case get = "GET"

    /// The POST method is used to submit an entity to the specified resource, often causing a change in state or side effects on the server.
    case post = "POST"

    /// The PUT method is used to update a resource identified by a URI.
    case put = "PUT"

    /// The DELETE method is used to delete a resource identified by a URI.
    case delete = "DELETE"
}

/// The parameters that can be used to query a TAP service.
public enum TAPParameter: String {

    /// The query language, e.g. "ADQL" or "SQL".
    case language = "LANG"

    /// The query to execute.
    case query = "QUERY"

    /// The request type, e.g. "doQuery" or "doTables".
    /// This should be deprecated, but some services (Simbad) still require it.
    case request = "REQUEST"

    /// The format of the response, e.g. "votable". This property is
    /// deprecated in favour of `responseFormat`, but it is provided for backwards 
    /// compatibility.
    case format = "FORMAT"

    /// The format of the response, e.g. "votable". The default value is "votable".
    case responseFormat = "RESPONSEFORMAT"

    /// The maximum number of records to return.
    case maxRecords = "MAXREC"

    /// The run ID. 
    case runID = "RUNID"

    /// Used when uploading a table to the service.
    case upload = "UPLOAD"
}

/// Instances of this class can be used for interacting with a TAP (Table Access Protocol) service.
public class TAPService {

    /// The base URL of the TAP service.
    public private(set) var baseURL: URL

    /// Creates a new TAP service instance.
    /// - Parameters:
    ///   - baseURL: The base URL of the TAP service.
    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Makes a REST query to the TAP service.
    /// - Parameters:
    ///   - syncMethod: The method to use for querying the TAP service, either synchronously or asynchronously.
    ///   - query: The query to execute.
    ///   - httpMethod: The HTTP method to use for the query.
    ///   - parameters: The parameters to include in the query.
    /// - Returns: The data returned by the server.
    /// - Throws: An error if the request fails.
    public func query(syncMethod: TAPSyncMethod, query: TAPQuery, httpMethod: HTTPMethod = .post, parameters: [TAPParameter: String] = [:]) async throws -> Data {
        let endpoint = syncMethod.rawValue
        var requestParameters: [TAPParameter : String] = parameters
        requestParameters[TAPParameter.language] = query.queryLanguage.identifier
        requestParameters[TAPParameter.query] = query.query
        return try await makeQuery(endpoint: endpoint, httpMethod: httpMethod, parameters: requestParameters)
    }
    
    /// Makes a REST query to the TAP service using async/await.
    /// - Parameters:
    ///   - endpoint: The specific endpoint to query.
    ///   - httpMethod: The HTTP method to use for the query.
    ///   - parameters: The parameters to include in the query.
    /// - Returns: The data returned by the server.
    /// - Throws: An error if the request fails.
    private func makeQuery(endpoint: String, httpMethod: HTTPMethod, parameters: [TAPParameter: String] = [:]) async throws -> Data {
        var url: URL = baseURL.appendingPathComponent(endpoint)
        
        // If the HTTP method is GET, append parameters as query items
        if httpMethod == .get {
            var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
            urlComponents?.queryItems = parameters.map { URLQueryItem(name: $0.key.rawValue, value: $0.value) }
            if let urlWithQuery = urlComponents?.url {
                url = urlWithQuery
            }
        }
        
        // Create a URL request
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = httpMethod.rawValue
        
        // If the HTTP method is POST, encode parameters as form data in the HTTP body
        if httpMethod == .post {
            let formData = parameters.map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: "&")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formData.data(using: .utf8)
        }
        
        // Logging output
        Logger.tap.debug("Request URL: \(request.url?.absoluteString ?? "No URL", privacy: .public)")
        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            Logger.tap.debug("Request Body: \(bodyString, privacy: .public)")
        }
        
        // Perform the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check the response status code
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw NSError(domain: "TAPServiceError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Invalid response: \(httpResponse.statusCode)"])
        }
        
        return data
    }
}
