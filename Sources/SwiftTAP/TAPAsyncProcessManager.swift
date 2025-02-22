import Foundation
import OSLog

/// Manages the asynchronous processes.
public actor TAPAsyncProcessManager {
    private var processes: [String: TAPAsyncProcess] = [:]

    /// The maximum number of parallel processes.
    public var maxNumberOfParallelProcesses: Int = 5

    /// Initializes the manager.
    public init() {}

    /// Adds a process to the manager.
    /// - Parameter process: The process to add.
    public func addProcess(_ process: TAPAsyncProcess) {
        processes[process.id] = process
    }

    /// Returns the process with the given ID.
    /// - Parameter id: The ID of the process to return.
    /// - Returns: The process with the given ID.
    public func getProcess(_ id: String) -> TAPAsyncProcess? {
        processes[id]
    }

    /// Starts the process with the given ID.
    /// - Parameter id: The ID of the process to start.
    public func startProcess(_ id: String) async throws {
        guard let process = processes[id] else { return }
        Task.detached {
            Logger.tap.debug("Starting process \(process.id, privacy: .public)")
            try await process.run()
        }
    }

    /// Cancels the process with the given ID.
    /// - Parameter id: The ID of the process to cancel.
    public func cancelProcess(_ id: String) async {
        await processes[id]?.cancel()
    }

    /// Monitors the processes.
    public func monitorProcesses() async {
        while true {
            for process in processes.values {
                let status = await process.status
                Logger.tap.debug("Process \(process.id): \(status.rawValue)")
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }

    /// Returns all the processes.
    /// - Returns: All the processes.
    public func getAllProcesses() -> [TAPAsyncProcess] {
        Array(processes.values)
    }

    /// Returns all the pending processes.
    /// - Returns: All the pending processes.
    public func getPendingProcesses() async -> [TAPAsyncProcess] {
        var pendingProcesses: [TAPAsyncProcess] = []
        for process in processes.values where await process.status == .pending {
            pendingProcesses.append(process)
        }
        Logger.tap.debug("Pending processes: \(pendingProcesses.map(\.id), privacy: .public)")
        return pendingProcesses
    }

    /// Waits for completion of the process with the given ID.
    /// - Parameter id: The ID of the process to wait for.
    public func waitForCompletion(_ id: String) async throws {
        guard let process = processes[id] else {
            Logger.tap.error("Process \(id, privacy: .public) not found")
            return
        }

        while true {
            let status = await process.status
            switch status {
            case .completed:
                Logger.tap.debug("Process \(process.id, privacy: .public) completed")
                return
            case .error:
                Logger.tap.error("MANAGER Process \(process.id, privacy: .public) failed")
                throw TAPException.serviceErrorStatus(process: process)
            case .timeout:
                Logger.tap.error("MANAGER Process \(process.id, privacy: .public) timed out")
                throw TAPException.serviceTimedOut(process: process)
            case .canceled:
                Logger.tap.warning("Process \(process.id, privacy: .public) canceled")
                return
            default:
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
    }
}
