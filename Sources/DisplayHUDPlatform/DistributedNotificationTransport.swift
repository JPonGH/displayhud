import Foundation

public enum BetterDisplayTransportError: Error, Equatable {
    case encodingFailed
    case timedOut
    case rejected(String?)
    case invalidResponse
}

public final class DistributedNotificationTransport: @unchecked Sendable, BetterDisplayTransport {
    private struct Request: Codable {
        let uuid: String
        let commands: [String]
        let parameters: [String: String?]
    }

    private struct Response: Codable {
        let uuid: String?
        let result: Bool?
        let payload: String?
    }

    private struct Pending {
        let continuation: CheckedContinuation<String?, Error>
        let timeout: DispatchWorkItem
    }

    private let center: DistributedNotificationCenter
    private let lock = NSLock()
    private var pending: [String: Pending] = [:]
    private var mostRecentDispatchNanoseconds: Int64?
    private var observer: NSObjectProtocol?
    private let requestName = Notification.Name("com.betterdisplay.BetterDisplay.request")
    private let responseName = Notification.Name("com.betterdisplay.BetterDisplay.response")

    public convenience init() {
        self.init(center: .default())
    }

    init(center: DistributedNotificationCenter) {
        self.center = center
        observer = center.addObserver(
            forName: responseName,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.receive(notification)
        }
    }

    deinit {
        if let observer {
            center.removeObserver(observer)
        }
    }

    public func send(
        commands: [String],
        parameters: [String: String?],
        timeout: Duration
    ) async throws -> String? {
        let uuid = UUID().uuidString
        let request = Request(uuid: uuid, commands: commands, parameters: parameters)
        let encoded = try JSONEncoder().encode(request)
        guard let object = String(data: encoded, encoding: .utf8) else {
            throw BetterDisplayTransportError.encodingFailed
        }
        let timeoutNanoseconds = Self.nanoseconds(for: timeout)

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutItem = DispatchWorkItem { [weak self] in
                self?.timeOut(uuid: uuid)
            }

            lock.lock()
            pending[uuid] = Pending(continuation: continuation, timeout: timeoutItem)
            lock.unlock()

            DispatchQueue.global(qos: .userInteractive).asyncAfter(
                deadline: .now() + .nanoseconds(Int(timeoutNanoseconds)),
                execute: timeoutItem
            )
            let clock = ContinuousClock()
            let dispatchStarted = clock.now
            center.postNotificationName(
                requestName,
                object: object,
                userInfo: nil,
                deliverImmediately: true
            )
            let dispatchDuration = dispatchStarted.duration(to: clock.now)
            lock.lock()
            mostRecentDispatchNanoseconds = Self.nanoseconds(for: dispatchDuration)
            lock.unlock()
        }
    }

    public func lastDispatchDuration() -> Duration? {
        lock.lock()
        defer { lock.unlock() }
        guard let mostRecentDispatchNanoseconds else { return nil }
        return .nanoseconds(mostRecentDispatchNanoseconds)
    }

    private func receive(_ notification: Notification) {
        guard let object = notification.object as? String,
              let data = object.data(using: .utf8),
              let response = try? JSONDecoder().decode(Response.self, from: data),
              let uuid = response.uuid
        else {
            return
        }

        let item = removePending(uuid: uuid)
        guard let item else { return }
        item.timeout.cancel()
        if response.result == false {
            item.continuation.resume(
                throwing: BetterDisplayTransportError.rejected(response.payload)
            )
        } else {
            item.continuation.resume(returning: response.payload)
        }
    }

    private func timeOut(uuid: String) {
        guard let item = removePending(uuid: uuid) else { return }
        item.continuation.resume(throwing: BetterDisplayTransportError.timedOut)
    }

    private func removePending(uuid: String) -> Pending? {
        lock.lock()
        defer { lock.unlock() }
        return pending.removeValue(forKey: uuid)
    }

    private static func nanoseconds(for duration: Duration) -> Int64 {
        let components = duration.components
        let seconds = components.seconds.multipliedReportingOverflow(by: 1_000_000_000)
        let attoseconds = components.attoseconds / 1_000_000_000
        return max(1, seconds.partialValue + attoseconds)
    }
}
