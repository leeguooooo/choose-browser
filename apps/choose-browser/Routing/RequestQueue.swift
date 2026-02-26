import Foundation

struct RoutingRequestEnvelope: Equatable {
    let request: RoutingRequest
    let receivedAt: TimeInterval
}

final class RequestQueue: RoutingRequestQueueing {
    private let lock = NSLock()
    private let now: () -> TimeInterval
    private var envelopes: [RoutingRequestEnvelope] = []
    var onEnqueue: (() -> Void)?

    init(now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }) {
        self.now = now
    }

    func enqueue(_ request: RoutingRequest) {
        let envelope = RoutingRequestEnvelope(request: request, receivedAt: now())
        let callback: (() -> Void)?

        lock.lock()
        envelopes.append(envelope)
        callback = onEnqueue
        lock.unlock()

        callback?()
    }

    func dequeueBurst(window: TimeInterval) -> [RoutingRequest] {
        lock.lock()
        defer { lock.unlock() }

        guard let first = envelopes.first else {
            return []
        }

        var count = 1
        while count < envelopes.count {
            let candidate = envelopes[count]
            if (candidate.receivedAt - first.receivedAt) <= window {
                count += 1
                continue
            }

            break
        }

        let batch = Array(envelopes.prefix(count))
        envelopes.removeFirst(count)
        return batch.map(\.request)
    }

    func snapshot() -> [RoutingRequestEnvelope] {
        lock.lock()
        let copy = envelopes
        lock.unlock()
        return copy
    }
}
