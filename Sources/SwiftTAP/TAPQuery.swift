import Foundation

/// The query language used in the query request.
///
/// This enumeration specifies the standard query languages used in a TAP service.
/// Currently only ADQL is supported by default. If another language is needed,
/// you can use the `.other(id: "my-query-language")` case to specify the identifier of the language.
public enum QueryLanguage {
    /// The Astronomical Data Query Language (ADQL).
    case adql

    /// A custom query language.
    /// - Parameter id: The identifier of the query language.
    case other(id: String)

    /// The identifier of the query language. It is the value that will be send in the query request
    /// to the TAP service using the `LANG` parameter.
    public var identifier: String {
        switch self {
        case .adql:
            "adql"
        case let .other(identifier):
            identifier
        }
    }
}

/// A protocol that represents a query to a TAP service.
///
/// This protocol defines a common interface for all query types that can be executed on a TAP service.
/// It provides a way to specify the query language and the query itself.
public protocol TAPQuery {
    /// The language of the query.
    var queryLanguage: QueryLanguage { get }

    /// The query string.
    var query: String { get }
}
