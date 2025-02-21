import Foundation

enum TAPException: Error {
    case serviceError(responseCode: Int, responseBody: String)
}