import Foundation

/// Lets APIClient read and refresh Cognito tokens without importing
/// AuthService directly (AuthService conforms; see StarTimeApp.swift for
/// the wiring).
@MainActor
protocol AuthTokenProviding: AnyObject {
    var idToken: String? { get }
    func refreshTokens() async throws
}

struct APIError: LocalizedError {
    let statusCode: Int
    let message: String?

    var errorDescription: String? {
        // Handlers return a human-readable `message` for anything a user
        // could actually cause (bad invite code, insufficient points), so
        // prefer it over a generic status-code string.
        message ?? "The server returned an error (\(statusCode))."
    }
}

@MainActor
final class APIClient {
    static let shared = APIClient()

    weak var tokenProvider: AuthTokenProviding?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // URLSession's default resource timeout is 7 days -- a hung request
        // would otherwise keep a fetch (and any UI waiting on it) pending
        // effectively forever.
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // `.default` respects HTTP caching via the shared URLCache. This
        // backend never sends Cache-Control headers, but URLCache's
        // heuristic caching can still serve a stale response for a
        // fixed-URL GET (no query string) like `GET /chores` -- which is
        // exactly the endpoint an edited chore's own fields depend on to
        // ever show up again. Every store here already does its own
        // explicit refetch-after-mutation, so HTTP-level caching can only
        // reintroduce staleness it was specifically built to avoid.
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // Lambdas emit `new Date().toISOString()`, which includes fractional
        // seconds -- .iso8601 alone rejects those.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = formatter.date(from: raw) ?? fallback.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unrecognized date: \(raw)")
            )
        }
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // Must match `decoder`'s format (ISO8601 with fractional seconds),
        // not the default `.deferredToDate` (a raw number). Otherwise a
        // struct that was *decoded* from a response -- any edit of an
        // existing record, which carries a real `createdAt` -- re-encodes
        // that field as a number on the way back out. The write itself
        // still succeeds (DynamoDB stores whatever it's given), but the
        // next GET response then has a number where `decoder` requires a
        // string, so the whole decode throws -- silently, since background
        // refetch failures are swallowed by design -- and the published
        // state simply never updates again. A single mis-typed field took
        // down decoding for the entire response it was part of.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }()

    @discardableResult
    func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        body: (any Encodable)? = nil,
        as responseType: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await requestData(method, path, body: body)
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        return try Self.decoder.decode(Response.self, from: data)
    }

    func send(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws {
        _ = try await requestData(method, path, body: body)
    }

    private func requestData(_ method: String, _ path: String, body: (any Encodable)?) async throws -> Data {
        let (data, response) = try await perform(method, path, body: body)

        // One retry after a token refresh -- an expired ID token is the
        // common, recoverable case; a second 401 means the session is
        // genuinely gone and should surface to the caller.
        if response.statusCode == 401, let tokenProvider {
            try await tokenProvider.refreshTokens()
            let (retryData, retryResponse) = try await perform(method, path, body: body)
            guard (200..<300).contains(retryResponse.statusCode) else {
                throw Self.apiError(status: retryResponse.statusCode, data: retryData)
            }
            return retryData
        }

        guard (200..<300).contains(response.statusCode) else {
            throw Self.apiError(status: response.statusCode, data: data)
        }
        return data
    }

    private func perform(
        _ method: String,
        _ path: String,
        body: (any Encodable)?
    ) async throws -> (Data, HTTPURLResponse) {
        // `appendingPathComponent` percent-encodes "?" into the path, which
        // silently turns "completions?since=..." into a route that matches
        // nothing -- build the full string and let URL parse the query.
        let base = BackendConfig.apiBaseUrl
        let separator = base.hasSuffix("/") ? "" : "/"
        guard let url = URL(string: base + separator + path) else {
            throw APIError(statusCode: -1, message: "Backend URL is not configured.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token = tokenProvider?.idToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(statusCode: -1, message: "Unexpected response from the server.")
        }
        return (data, http)
    }

    private static func apiError(status: Int, data: Data) -> APIError {
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
        return APIError(statusCode: status, message: message)
    }
}

/// Placeholder for endpoints that return no body (e.g. 204).
struct EmptyResponse: Decodable {}

/// Type-erases the `any Encodable` body so JSONEncoder encodes the concrete
/// value rather than the existential.
private struct AnyEncodable: Encodable {
    private let encodeTo: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        encodeTo = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeTo(encoder)
    }
}
