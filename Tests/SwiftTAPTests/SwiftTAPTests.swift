import Foundation
import OSLog
import Testing

@testable import SwiftTAP

class ADQLQuery: TAPQuery {
    var query: String

    var queryLanguage: QueryLanguage {
        .adql
    }

    init(query: String) {
        self.query = query
    }
}

@Test func simbadSynchronousTestRequest() async throws {
    do {
        let service = TAPService(baseURL: URL(string: "https://simbad.u-strasbg.fr/simbad/sim-tap/")!)
        let query = ADQLQuery(query: "SELECT * FROM basic WHERE ra BETWEEN 20 AND 25 AND dec BETWEEN 10 AND 20")

        // Simbad still requires the request parameter with the value "doQuery" even though
        // it is deprecated.
        let parameters: [TAPParameter: String] = [.request: "doQuery"]

        // Synchronous request.
        if let data = try await service.syncQuery(
            query: query,
            syncMethod: .synchronous,
            parameters: parameters
        ) {
            let msg = "Data: \(data)"
            Logger.tapTests.info("Data: \(msg, privacy: .public)")
            let dataString = String(data: data, encoding: .utf8)
            Logger.tapTests.info("Data String: \(dataString ?? "No data", privacy: .public)")
            assert(true)
        } else {
            assertionFailure("No data returned")
        }
    } catch let TAPException.serviceError(responseCode, responseBody) {
        Logger.tapTests.error("TAP Service Error: \(responseCode, privacy: .public) \(responseBody, privacy: .public)")
        assertionFailure()
    } catch {
        Logger.tapTests.error("Error: \(error, privacy: .public)")
        assertionFailure()
    }
}

@Test func simbadAsynchronousTestRequest() async throws {
    do {
        let service = TAPService(baseURL: URL(string: "https://simbad.u-strasbg.fr/simbad/sim-tap/")!)
        let query = ADQLQuery(query: "SELECT * FROM basic WHERE ra BETWEEN 10 AND 20 AND dec BETWEEN 10 AND 20")

        // Simbad still requires the request parameter with the value "doQuery" even though
        // it is deprecated.
        let parameters: [TAPParameter: String] = [.request: "doQuery"]

        // Asynchronous request.
        if let data = try await service.syncQuery(
            query: query,
            syncMethod: .asynchronous,
            parameters: parameters
        ) {
            Logger.tapTests.info("Data: \(data, privacy: .public)")
            let dataString = String(data: data, encoding: .utf8)
            Logger.tapTests.info("Data String: \(dataString ?? "No data", privacy: .public)")
            assert(true)
        } else {
            assertionFailure("No data returned")
        }
    } catch let TAPException.serviceError(responseCode, responseBody) {
        Logger.tapTests.error("TAP Service Error: \(responseCode, privacy: .public) \(responseBody, privacy: .public)")
        assertionFailure()
    } catch {
        Logger.tapTests.error("Error: \(error, privacy: .public)")
        assertionFailure()
    }
}

/// This test is used to test the timeout of the TAP service.
/// The timeout is set to 1 second to force the test to fail.
/// The test will fail if the timeout is not reached.
@Test func simbadAsynchronousTestRequestWithTimeout() async throws {
    do {
        let service = TAPService(
            baseURL: URL(string: "https://simbad.u-strasbg.fr/simbad/sim-tap/")!,
            timeout: 1 // Timeout of 1 second to force the test to fail
        )
        let query = ADQLQuery(query: "SELECT * FROM basic WHERE ra BETWEEN 11 AND 15 AND dec BETWEEN 10 AND 20")

        // Simbad still requires the request parameter with the value "doQuery" even though
        // it is deprecated.
        let parameters: [TAPParameter: String] = [.request: "doQuery"]

        // Asynchronous request.
        if let data = try await service.syncQuery(
            query: query,
            syncMethod: .asynchronous,
            parameters: parameters
        ) {
            // This should never be reached as the request should time out.
            assertionFailure("Unexpected data returned \(data)")
        } else {
            assertionFailure("No data returned")
        }
    } catch let TAPException.serviceError(responseCode, responseBody) {
        Logger.tapTests.error("TAP Service Error: \(responseCode, privacy: .public) \(responseBody, privacy: .public)")
        assertionFailure()
    } catch let TAPException.serviceTimedOut(process) {
        let processId = await process.id
        Logger.tapTests.info("TAP Service Timed Out as expected: \(processId, privacy: .public)")
        assert(true)
    } catch {
        Logger.tapTests.error("Error: \(error, privacy: .public)")
        assertionFailure()
    }
}

/// This test is used to test the timeout of the TAP service.
/// The timeout is set to 1 second to force the test to fail.
/// The test will fail if the timeout is not reached.
@Test func simbadAsynchronousTestRequestCanceled() async throws {
    do {
        let service = TAPService(
            baseURL: URL(string: "https://simbad.u-strasbg.fr/simbad/sim-tap/")!
        )
        let query = ADQLQuery(query: "SELECT * FROM basic WHERE ra BETWEEN 11 AND 15 AND dec BETWEEN 10 AND 20")

        // Simbad still requires the request parameter with the value "doQuery" even though
        // it is deprecated.
        let parameters: [TAPParameter: String] = [.request: "doQuery"]
        let processId = "Async Request to be canceled"

        // Asynchronous request.
        let process = try await service.asyncQuery(
            id: processId,
            query: query,
            parameters: parameters
        )
        var status = await process.status
        assert(status != .canceled)
        await service.cancelProcess(processId)
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 second
        status = await process.status
        Logger.tapTests.info("Process status: \("\(status)", privacy: .public)")
        assert(status == .canceled)
    } catch let TAPException.serviceError(responseCode, responseBody) {
        Logger.tapTests.error("TAP Service Error: \(responseCode, privacy: .public) \(responseBody, privacy: .public)")
        assertionFailure()
    } catch let TAPException.serviceTimedOut(process) {
        let processId = await process.id
        Logger.tapTests.info("TAP Service Timed Out as expected: \(processId, privacy: .public)")
        assertionFailure()
    } catch {
        Logger.tapTests.error("Error: \(error, privacy: .public)")
        assertionFailure()
    }
}
