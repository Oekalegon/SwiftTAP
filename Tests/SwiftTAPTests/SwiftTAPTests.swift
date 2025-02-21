import Testing
import Foundation
import OSLog

@testable import SwiftTAP

class ADQLQuery: TAPQuery {

    var query: String

    var queryLanguage: QueryLanguage {
        return .adql
    }
    
    init(query: String) {
        self.query = query
    }
}

@Test func simbadTestRequest() async throws {
    do {
        let service = TAPService(baseURL: URL(string: "https://simbad.u-strasbg.fr/simbad/sim-tap/")!)
        let query = ADQLQuery(query: "SELECT * FROM basic WHERE ra BETWEEN 10 AND 20 AND dec BETWEEN 10 AND 20")
        
        // Simbad still requires the request parameter with the value "doQuery" even though
        // it is deprecated.
        let parameters: [TAPParameter : String] = [.request: "doQuery"]

        let data = try await service.query(syncMethod: .synchronous, query: query, parameters: parameters)
        Logger.tapTests.info("Data: \(data, privacy: .public)")
        let dataString = String(data: data, encoding: .utf8)
        Logger.tapTests.info("Data String: \(dataString ?? "No data", privacy: .public)")    
        assert(true)
    } catch TAPException.serviceError(let responseCode, let responseBody) {
        Logger.tapTests.error("TAP Service Error: \(responseCode, privacy: .public) \(responseBody, privacy: .public)")
        assert(false)
    } catch {
        Logger.tapTests.error("Error: \(error, privacy: .public)")
        assert(false)
    }
}
