import Foundation
import OSLog

@frozen
public enum TAPAsyncProcessStatus: String, Sendable {
    case pending = "PENDING"
    case running = "RUNNING"
    case completed = "COMPLETED"
    case failed = "FAILED"
}

public actor TAPAsyncProcess {
    public let id: String
    public internal(set) var jobID: String?
    public internal(set) var status: TAPAsyncProcessStatus
    public let createdAt: Date
    public internal(set) var updatedAt: Date
    public let request: URLRequest
    public var result: Data?

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
    }

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
            status = .failed
        } catch {
            Logger.tap.error("Error running process \(self.id): \(error)")
            status = .failed
        }
    }

    private func parseJobIdFromXML(_ data: Data) -> String? {
        guard let xmlString = String(data: data, encoding: .utf8) else { return nil }
        guard let jobIdRange = xmlString.range(of: "<jobId>") else { return nil }
        guard let jobIdEndRange = xmlString.range(of: "</jobId>") else { return nil }

        let start = jobIdRange.upperBound
        let end = jobIdEndRange.lowerBound
        return String(xmlString[start ..< end])
    }

    private func handleStandardJob(jobURL: String) async throws {
        // 2. Start the job
        Logger.tap.debug("""
        ASYNC Process \(self.id, privacy: .public) starting job using URL: \(jobURL, privacy: .public)
        """)
        var runRequest = URLRequest(url: URL(string: "\(jobURL)/phase")!)
        runRequest.httpMethod = "POST"
        runRequest.httpBody = Data("PHASE=RUN".utf8)

        Logger.tap.debug("ASYNC Process \(self.id, privacy: .public) started job")

        _ = try await URLSession.shared.data(for: runRequest)
        status = .running

        // 3. Poll for completion
        var phaseRequest = URLRequest(url: URL(string: "\(jobURL)/phase")!)
        phaseRequest.httpMethod = "GET"

        while true {
            Logger.tap.debug("ASYNC Process \(self.id, privacy: .public) polling for completion")
            let (data, _) = try await URLSession.shared.data(for: phaseRequest)
            let phase = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            Logger.tap.debug("ASYNC Process \(self.id, privacy: .public) phase: \(phase ?? "nil", privacy: .public)")

            switch phase {
            case "COMPLETED":
                // 4. Get results
                let resultsURL = URL(string: "\(jobURL)/results/result")!
                let (resultData, _) = try await URLSession.shared.data(for: URLRequest(url: resultsURL))
                result = resultData
                status = .completed
                Logger.tap.debug("ASYNC Process \(self.id, privacy: .public) completed")
                return
            case "ERROR":
                status = .failed
                Logger.tap.debug("ASYNC Process \(self.id, privacy: .public) failed because of ERROR phase")
                return
            case "EXECUTING", "PENDING", "QUEUED":
                try await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
                Logger.tap.debug("ASYNC Process \(self.id, privacy: .public) is \(phase ?? "unknown")")
                continue
            default:
                status = .failed
                Logger.tap.debug("ASYNC Process \(self.id, privacy: .public) failed because of unknown phase")
                return
            }
        }
    }
}
