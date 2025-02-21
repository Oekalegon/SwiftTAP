import Foundation
import OSLog

/// The status of an asynchronous TAP process.
@frozen
public enum TAPAsyncProcessStatus: String, Sendable {
    /// The process is queued on the TAP service.
    case queued = "QUEUED"

    /// The process is pending.
    case pending = "PENDING"

    /// The process is executing.
    case executing = "EXECUTING"

    /// The process is completed.
    case completed = "COMPLETED"

    /// The process failed.
    case error = "ERROR"

    /// The process was canceled.
    case canceled

    /// The process timed out.
    case timeout

    /// The process status is unknown.
    case unknown = "UNKNOWN"
}

/// This actor manages an asynchronous TAP process.
///
/// This actor is used to manage the lifecycle of an asynchronous TAP process.
/// It is responsible for creating the process, polling for completion, and retrieving the results.
public actor TAPAsyncProcess {
    /// The ID of the process.
    public let id: String

    /// The ID of the job.
    public internal(set) var jobID: String?

    /// The status of the process.
    public internal(set) var status: TAPAsyncProcessStatus

    /// The date the process was created.
    public let createdAt: Date

    /// The date the process was updated.
    public internal(set) var updatedAt: Date

    /// The request that is encapsulated by this process.
    public let request: URLRequest

    /// The result of the process.
    public var result: Data?

    /// The timeout for the process.
    public var timeout: TimeInterval

    /// A flag that can be set when the process is canceled.
    private var canceled: Bool = false

    /// Initialize a new asynchronous TAP process.
    ///
    /// - Parameter request: The request that is encapsulated by this process.
    public init(
        request: URLRequest
    ) {
        id = UUID().uuidString
        jobID = nil
        status = .pending
        createdAt = Date()
        updatedAt = Date()
        self.request = request
        result = nil
        timeout = 300
    }

    public func cancel() {
        canceled = true
    }

    /// Run the process.
    ///
    /// This method will:
    /// 1. Create the async job
    /// 2. Start the job
    /// 3. Poll for completion until the job is complete
    /// 4. Retrieve the results
    ///
    /// - Throws: An error if the process fails.
    public func run() async {
        do {
            // 1. Create the async job
            let (data, response) = try await URLSession.shared.data(for: request)

            Logger.tap.debug("ASYNC Process \(self.id, privacy: .public) created async job")

            // Try standard 303 redirect first
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 303,
               let jobURL = httpResponse.value(forHTTPHeaderField: "Location")
            {
                try await handleStandardJob(jobURL: jobURL)
                return
            }

            // Try parsing XML response for non-compliant services
            if let jobId = parseJobIdFromXML(data) {
                let jobURL = "\(request.url!)/\(jobId)"
                Logger.tap.debug("""
                ASYNC Process \(self.id, privacy: .public) found job ID \(jobId, privacy: .public) in XML
                """)
                try await handleStandardJob(jobURL: jobURL)
                return
            }

            // If both methods fail, log error and fail
            let httpResponse = response as? HTTPURLResponse
            Logger.tap.error("""
            ASYNC Process \(self.id, privacy: .public) failed because of invalid response.
            Status code: \(String(describing: httpResponse?.statusCode), privacy: .public)
            """)
            status = .error
        } catch {
            Logger.tap.error("Error running process \(self.id): \(error)")
            status = .error
        }
    }

    /// Parse the job ID from the XML response.
    ///
    /// - Parameter data: The data to parse.
    /// - Returns: The job ID if it is found.
    private func parseJobIdFromXML(_ data: Data) -> String? {
        guard let xmlString = String(data: data, encoding: .utf8) else { return nil }
        guard let jobIdRange = xmlString.range(of: "<jobId>") else { return nil }
        guard let jobIdEndRange = xmlString.range(of: "</jobId>") else { return nil }

        let start = jobIdRange.upperBound
        let end = jobIdEndRange.lowerBound
        return String(xmlString[start ..< end])
    }

    /// Handle a standard job.
    ///
    /// This method will start the job and poll for completion until the job is complete.
    ///
    /// - Parameter jobURL: The URL of the job, including the job ID.
    private func handleStandardJob(jobURL: String) async throws {
        // 2. Start the job
        var runRequest = URLRequest(url: URL(string: "\(jobURL)/phase")!)
        runRequest.httpMethod = "POST"
        runRequest.httpBody = Data("PHASE=RUN".utf8)

        Logger.tap.debug("""
        Process \(self.id, privacy: .public) started job for request: \(self.request, privacy: .public)
        """)

        _ = try await URLSession.shared.data(for: runRequest)
        status = .executing

        // 3. Poll for completion
        var phaseRequest = URLRequest(url: URL(string: "\(jobURL)/phase")!)
        phaseRequest.httpMethod = "GET"

        while !canceled {
            // Check if the process has timed out
            if Date().timeIntervalSince(createdAt) > timeout {
                status = .timeout
                Logger.tap.debug("Process \(self.id, privacy: .public) timed out")
                throw TAPException.serviceTimedOut(process: self)
            }

            let (data, _) = try await URLSession.shared.data(for: phaseRequest)
            let phaseString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let phase = TAPAsyncProcessStatus(rawValue: phaseString ?? "") ?? .unknown

            switch phase {
            case .completed:
                // 4. Get results
                let resultsURL = URL(string: "\(jobURL)/results/result")!
                let (resultData, _) = try await URLSession.shared.data(for: URLRequest(url: resultsURL))
                result = resultData
                status = .completed
                Logger.tap.debug("""
                Process \(self.id, privacy: .public) completed for request: \(self.request, privacy: .public)
                """)
                return
            case .error, .unknown:
                status = .error
                Logger.tap.debug("""
                Process \(self.id, privacy: .public) failed because the TAP service returned an error
                """)
                throw TAPException.serviceErrorStatus(process: self)
            case .executing, .pending, .queued:
                status = phase
                try await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            case .canceled, .timeout:
                status = phase
                Logger.tap.debug("""
                Process \(self.id, privacy: .public) failed because of \(phase.rawValue, privacy: .public) phase
                """)
                return
            }
        }
    }
}
