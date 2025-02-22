import Foundation
import OSLog

// MARK: - Helper enums and structs

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

    /// The POST method is used to submit an entity to the specified resource,
    /// often causing a change in state or side effects on the server.
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

// MARK: - TAPService

/// Instances of this class can be used for interacting with a TAP (Table Access Protocol) service.
public class TAPService {
    /// The manager of the asynchronous processes.
    private let processManager: TAPAsyncProcessManager = .init()

    /// The base URL of the TAP service.
    public private(set) var baseURL: URL

    public private(set) var timeout: TimeInterval

    /// Creates a new TAP service instance.
    /// - Parameters:
    ///   - baseURL: The base URL of the TAP service.
    public init(baseURL: URL, timeout: TimeInterval = 300) {
        self.baseURL = baseURL
        self.timeout = timeout
    }

    /// Cancels the process with the given ID.
    /// - Parameter id: The ID of the process to cancel.
    public func cancelProcess(_ id: String) async {
        await processManager.cancelProcess(id)
    }

    /// Makes a REST query to the TAP service.
    /// - Parameters:
    ///   - id: The ID of the process to use for the query. If not provided, a new id will be created.
    ///   - syncMethod: The method to use for querying the TAP service, either synchronously or asynchronously.
    ///   - query: The query to execute.
    ///   - httpMethod: The HTTP method to use for the query.
    ///   - parameters: The parameters to include in the query.
    ///   - awaitCompletion: If `true`, the method will wait for the query to complete before returning. This
    ///     is only applicable if the query is run asynchronously.
    /// - Returns: The data returned by the server if synchronous, otherwise a `TAPAsyncProcess` object,
    ///     which can be used to monitor the status of the query, and/or retrieve the results.
    /// - Throws: An error if the request fails.
    public func query(
        id: String? = nil,
        syncMethod: TAPSyncMethod,
        query: TAPQuery,
        httpMethod: HTTPMethod = .post,
        parameters: [TAPParameter: String] = [:],
        awaitCompletion: Bool = false
    ) async throws -> Any? {
        var requestParameters: [TAPParameter: String] = parameters
        requestParameters[TAPParameter.language] = query.queryLanguage.identifier
        requestParameters[TAPParameter.query] = query.query
        return try await makeQuery(
            id: id,
            syncMethod: syncMethod,
            httpMethod: httpMethod,
            parameters: requestParameters,
            awaitCompletion: awaitCompletion
        )
    }

    private func makeQuery(
        id: String?,
        syncMethod: TAPSyncMethod,
        httpMethod: HTTPMethod,
        parameters: [TAPParameter: String] = [:],
        awaitCompletion: Bool = false
    ) async throws -> Any? {
        var url: URL = baseURL.appendingPathComponent(syncMethod.rawValue)

        // If the HTTP method is GET, append parameters as query items
        if httpMethod == .get {
            var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
            urlComponents?.queryItems = parameters.map { URLQueryItem(name: $0.key.rawValue, value: $0.value) }
            if let urlWithQuery = urlComponents?.url {
                url = urlWithQuery
            }
        }

        // Create a URL request
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod.rawValue

        // If the HTTP method is POST, encode parameters as form data in the HTTP body
        if httpMethod == .post {
            let formData = parameters.map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: "&")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formData.data(using: .utf8)
        }

        // Logging output
        Logger.tap.debug("Request URL: \(request.url?.absoluteString ?? "No URL", privacy: .public)")
        if let body: Data = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            Logger.tap.debug("Request Body: \(bodyString, privacy: .public)")
        }

        switch syncMethod {
        case .synchronous:
            return try await runSynchronousRequest(request: request)
        case .asynchronous:
            let process = try await runAsynchronousRequest(id: id, request: request, awaitCompletion: awaitCompletion)
            if awaitCompletion {
                // If we are awaiting completion, return the result of the process should be returned.
                return await process.result
            } else {
                return process
            }
        }
    }

    private func runSynchronousRequest(
        request: URLRequest
    ) async throws -> Data? {
        // Perform the request
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check the response status code
        if let httpResponse: HTTPURLResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode)
        {
            throw TAPException.serviceError(
                responseCode: httpResponse.statusCode,
                responseBody: "Invalid Response: \(httpResponse.statusCode)"
            )
        }

        return data
    }

    private func runAsynchronousRequest(
        id: String?,
        request: URLRequest,
        awaitCompletion: Bool = false
    ) async throws -> TAPAsyncProcess {
        let process = TAPAsyncProcess(id: id, request: request, timeout: self.timeout)
        await processManager.addProcess(process)
        try await processManager.startProcess(process.id)
        if awaitCompletion {
            try await processManager.waitForCompletion(process.id)
        }
        return process
    }
}
