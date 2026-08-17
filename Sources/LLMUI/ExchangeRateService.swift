import Foundation
import LLMClient

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - ExchangeRateService

/// Fetches a USD→JPY rate, so a dollar cost can be shown in yen.
///
/// Backed by [Frankfurter](https://frankfurter.dev), which needs no key and no account — the point
/// is a rate good enough to read a debug figure by, not a settlement price.
public struct ExchangeRateService: Sendable {
    public enum Failure: Error, Sendable, Equatable {
        case http(status: Int)
        case rateMissing
    }

    private let session: URLSession
    private let endpoint = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD&symbols=JPY")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// - Returns: The rate, stamped with the time it was fetched rather than the quote's own date,
    ///   so staleness is measured from when this app last managed to ask.
    public func fetchUSDJPY() async throws -> ExchangeRate<USD, JPY> {
        let (data, response) = try await session.data(from: endpoint)

        if let status = (response as? HTTPURLResponse)?.statusCode, status >= 400 {
            throw Failure.http(status: status)
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let jpy = payload.rates["JPY"] else {
            throw Failure.rateMissing
        }
        return ExchangeRate(jpy, asOf: Date())
    }

    private struct Payload: Decodable {
        let rates: [String: Double]
    }
}
