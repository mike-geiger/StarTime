import Combine
import Foundation

/// Server-pushed collections that changed. Mirrors the `resource` strings in
/// backend/cdk/lambda/realtime/stream-fanout.ts.
enum RealtimeResource: String, Decodable {
    case household
    case chores
    case completions
    case rewards
    case redemptions
    case balances
}

/// One shared WebSocket to the household's fan-out channel. Publishes
/// invalidation signals ("these collections changed") rather than the changed
/// data itself — stores respond by refetching, which is exactly what they
/// already do after their own writes.
///
/// This replaces the per-store Firestore snapshot listeners: one socket for
/// the whole app instead of five listeners across three view-owned stores.
@MainActor
final class RealtimeConnectionManager: ObservableObject {
    /// Fires whenever the server reports a change. Stores subscribe and
    /// refetch the collections they own.
    let invalidations = PassthroughSubject<Set<RealtimeResource>, Never>()

    private var task: URLSessionWebSocketTask?
    private var session = URLSession(configuration: .default)
    private var isStopping = false
    private var reconnectAttempt = 0
    private var reconnectWork: Task<Void, Never>?

    private struct Message: Decodable {
        let type: String
        let resources: [RealtimeResource]
    }

    func start(idToken: String) {
        stop()
        isStopping = false
        reconnectAttempt = 0
        connect(idToken: idToken)
    }

    func stop() {
        isStopping = true
        reconnectWork?.cancel()
        reconnectWork = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func connect(idToken: String) {
        // The token goes in the query string because a native WebSocket
        // handshake can't carry custom headers; the authorizer Lambda reads
        // it from there (see ws-authorizer.ts).
        guard var components = URLComponents(string: BackendConfig.webSocketUrl) else { return }
        components.queryItems = [URLQueryItem(name: "token", value: idToken)]
        guard let url = components.url else { return }

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receive(on: task, idToken: idToken)
    }

    private func receive(on task: URLSessionWebSocketTask, idToken: String) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, !self.isStopping else { return }
                switch result {
                case .success(let message):
                    self.handle(message)
                    // receive() delivers exactly one message, so re-arm.
                    self.receive(on: task, idToken: idToken)
                    self.reconnectAttempt = 0
                case .failure:
                    // Covers drops, timeouts, and expired-token rejections
                    // alike — all of them mean "reconnect".
                    self.scheduleReconnect(idToken: idToken)
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .data(let raw): data = raw
        case .string(let text): data = Data(text.utf8)
        @unknown default: data = nil
        }

        guard let data,
              let decoded = try? JSONDecoder().decode(Message.self, from: data),
              decoded.type == "invalidate" else { return }

        invalidations.send(Set(decoded.resources))
    }

    private func scheduleReconnect(idToken: String) {
        guard !isStopping, reconnectWork == nil else { return }

        // Capped exponential backoff: a server-side problem shouldn't turn
        // every client into a reconnect hammer.
        let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)
        reconnectAttempt += 1

        reconnectWork = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, !self.isStopping else { return }
            self.reconnectWork = nil
            self.connect(idToken: idToken)
        }
    }
}
