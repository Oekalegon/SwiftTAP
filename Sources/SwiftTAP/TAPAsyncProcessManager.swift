import Foundation
import OSLog

public actor TAPAsyncProcessManager {
    private var processes: [String: TAPAsyncProcess] = [:]
    public var maxNumberOfParallelProcesses: Int = 5

    public init() {}

    public func addProcess(_ process: TAPAsyncProcess) {
        processes[process.id] = process
    }

    public func getProcess(_ id: String) -> TAPAsyncProcess? {
        processes[id]
    }

    public func startProcess(_ id: String) async {
        guard let process = processes[id] else { return }
        Task.detached {
            Logger.tap.debug("Starting process \(process.id, privacy: .public)")
            await process.run()
        }
    }

    public func monitorProcesses() async {
        while true {
            for process in processes.values {
                let status = await process.status
                Logger.tap.debug("Process \(process.id): \(status.rawValue)")
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }

    public func getAllProcesses() -> [TAPAsyncProcess] {
        Array(processes.values)
    }

    public func getPendingProcesses() async -> [TAPAsyncProcess] {
        var pendingProcesses: [TAPAsyncProcess] = []
        for process in processes.values where await process.status == .pending {
            pendingProcesses.append(process)
        }
        Logger.tap.debug("Pending processes: \(pendingProcesses.map(\.id), privacy: .public)")
        return pendingProcesses
    }

    public func waitForCompletion(_ id: String) async -> Data? {
        guard let process = processes[id] else {
            Logger.tap.error("Process \(id, privacy: .public) not found")
            return nil
        }

        while true {
            let status = await process.status
            if status == .completed {
                Logger.tap.debug("Process \(process.id, privacy: .public) completed")
                return await process.result
            } else if status == .error {
                Logger.tap.debug("Process \(process.id, privacy: .public) failed")
                return nil
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }
}
