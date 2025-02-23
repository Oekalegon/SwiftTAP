import Foundation

/// An exception that can be thrown by the SwiftTAP library.
enum TAPError: Error {
    /// The URL request to the service returned an error.
    case serviceError(responseCode: Int, responseBody: String)

    /// The asynchronous process failed because the service returned an error status.
    case serviceErrorStatus(process: TAPAsyncProcess)

    /// The asynchronous process timed out.
    case serviceTimedOut(process: TAPAsyncProcess)
}
