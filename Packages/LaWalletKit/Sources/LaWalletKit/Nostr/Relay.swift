import Foundation

public enum RelayError: Error, Equatable {
    case notConnected, rejected(String), timeout
}

/// One websocket per relay URL, shared across the app (`Relay.shared(url)`).
/// Subscriptions survive reconnects: on drop the socket reopens with backoff and every live REQ is re-sent.
public actor Relay {
    public let url: URL
    private var task: URLSessionWebSocketTask?
    private var isOpen = false
    private var retry: Double = 1
    private var subs: [String: Sub] = [:]
    private var pendingOK: [String: CheckedContinuation<Void, Error>] = [:]
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    private struct Sub {
        let filters: [JSONValue]
        let cont: AsyncStream<NostrEvent>.Continuation
        let finishOnEOSE: Bool
        /// Newest `created_at` delivered, so a reconnect resumes from there instead of replaying the whole window.
        var latest: Int?
    }

    private static let registry = Registry()
    public static func shared(_ url: URL) async -> Relay { await registry.relay(for: url) }

    public init(url: URL) { self.url = url }

    public var connected: Bool { isOpen }

    // MARK: connection

    private func open() {
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        // A ping completes only after the handshake, so it doubles as the "open" signal.
        t.sendPing { [weak self] err in Task { await self?.handshake(t, failed: err != nil) } }
        receive(t)
    }

    private func handshake(_ t: URLSessionWebSocketTask, failed: Bool) {
        guard t === task else { return }
        if failed { return dropped(t) }
        isOpen = true
        retry = 1
        for (id, sub) in subs { sendRaw(.array(["REQ", .string(id)] + Self.resumed(sub.filters, after: sub.latest))) }
        for (_, w) in waiters { w.resume(returning: true) }
        waiters.removeAll()
    }

    private nonisolated func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                if case .string(let s) = msg { Task { await self.handle(s) } }
                self.receive(t)
            case .failure:
                Task { await self.dropped(t) }
            }
        }
    }

    private func dropped(_ t: URLSessionWebSocketTask) {
        guard t === task else { return }
        task = nil
        isOpen = false
        t.cancel()
        for (_, c) in pendingOK { c.resume(throwing: RelayError.notConnected) }
        pendingOK.removeAll()
        guard !subs.isEmpty || !waiters.isEmpty else { return }
        let delay = retry
        retry = min(retry * 2, 30)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.reopenIfNeeded()
        }
    }

    /// Live filters with `since` moved up to the newest event already seen (inclusive: same-second events re-arrive and
    /// are deduped by the consumer, none are lost).
    static func resumed(_ filters: [JSONValue], after latest: Int?) -> [JSONValue] {
        guard let latest else { return filters }
        return filters.map { filter in
            guard case .object(var o) = filter else { return filter }
            o["since"] = .number(Double(max(latest, Int(o["since"]?.double ?? 0))))
            return .object(o)
        }
    }

    private func reopenIfNeeded() {
        if task == nil, !subs.isEmpty || !waiters.isEmpty { open() }
    }

    /// Waits for the socket to be open, up to `timeout`.
    public func waitConnected(timeout: Duration = .seconds(10)) async -> Bool {
        if isOpen { return true }
        if task == nil { open() }
        let id = UUID()
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.expireWaiter(id)
        }
        return await withCheckedContinuation { waiters[id] = $0 }
    }

    private func expireWaiter(_ id: UUID) { waiters.removeValue(forKey: id)?.resume(returning: false) }

    public func disconnect() {
        let t = task
        task = nil
        isOpen = false
        t?.cancel()
    }

    // MARK: messages

    private func handle(_ text: String) {
        guard let msg = try? JSONValue.parse(Data(text.utf8)).array, let type = msg.first?.string, msg.count >= 2,
              let id = msg[1].string else { return }
        switch type {
        case "EVENT":
            guard msg.count >= 3, let ev = try? msg[2].decode(NostrEvent.self), ev.isValid, var sub = subs[id] else { return }
            if !sub.finishOnEOSE, ev.created_at > sub.latest ?? 0 {
                sub.latest = ev.created_at
                subs[id] = sub
            }
            sub.cont.yield(ev)
        case "EOSE":
            if subs[id]?.finishOnEOSE == true { subs.removeValue(forKey: id)?.cont.finish(); sendRaw(["CLOSE", .string(id)]) }
        case "OK":
            guard msg.count >= 3, let c = pendingOK.removeValue(forKey: id) else { return }
            if msg[2].bool == true { c.resume() } else { c.resume(throwing: RelayError.rejected(msg.count > 3 ? msg[3].string ?? "" : "")) }
        case "CLOSED":
            subs.removeValue(forKey: id)?.cont.finish()
        default: break
        }
    }

    private func sendRaw(_ value: JSONValue) {
        guard let task, let data = try? value.data(), let s = String(data: data, encoding: .utf8) else { return }
        // A socket the OS killed while suspended still looks open until something is sent: treat a failed send as a
        // drop so pending publishes fail fast and the socket reconnects, instead of waiting out the OK timeout.
        task.send(.string(s)) { [weak self] error in
            guard error != nil else { return }
            Task { await self?.dropped(task) }
        }
    }

    // MARK: API

    /// Live subscription; the REQ is closed when the consumer stops iterating.
    public func subscribe(_ filters: [JSONValue]) -> AsyncStream<NostrEvent> {
        makeSub(filters, finishOnEOSE: false)
    }

    private func makeSub(_ filters: [JSONValue], finishOnEOSE: Bool) -> AsyncStream<NostrEvent> {
        let id = Data.random(8).hex
        let (stream, cont) = AsyncStream<NostrEvent>.makeStream(bufferingPolicy: .bufferingNewest(500))
        subs[id] = Sub(filters: filters, cont: cont, finishOnEOSE: finishOnEOSE)
        cont.onTermination = { [weak self] _ in Task { await self?.close(id) } }
        if isOpen { sendRaw(.array(["REQ", .string(id)] + filters)) } else if task == nil { open() }
        return stream
    }

    private func close(_ id: String) {
        guard subs.removeValue(forKey: id) != nil else { return }
        if isOpen { sendRaw(["CLOSE", .string(id)]) }
    }

    /// Stored events matching `filters`, collected until EOSE or `timeout`.
    public func query(_ filters: [JSONValue], timeout: Duration = .seconds(8)) async -> [NostrEvent] {
        let stream = makeSub(filters, finishOnEOSE: true)
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.finishAll(of: filters)
        }
        defer { timer.cancel() }
        var out: [NostrEvent] = []
        for await ev in stream { out.append(ev) }
        return out
    }

    private func finishAll(of filters: [JSONValue]) {
        for (id, sub) in subs where sub.finishOnEOSE && sub.filters == filters { subs.removeValue(forKey: id); sub.cont.finish() }
    }

    /// Publishes and waits for the relay's OK.
    public func publish(_ event: NostrEvent, timeout: Duration = .seconds(10)) async throws {
        guard await waitConnected(timeout: timeout) else { throw RelayError.notConnected }
        let value = try JSONValue.parse(Data(event.json.utf8))
        let id = event.id
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.expireOK(id)
        }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            pendingOK[id] = c
            sendRaw(["EVENT", value])
        }
    }

    private func expireOK(_ id: String) { pendingOK.removeValue(forKey: id)?.resume(throwing: RelayError.timeout) }

    private actor Registry {
        var relays: [URL: Relay] = [:]
        func relay(for url: URL) -> Relay {
            if let r = relays[url] { return r }
            let r = Relay(url: url)
            relays[url] = r
            return r
        }
    }
}

/// Runs `op` against `timeout`; `op` must itself honour cancellation (all Kit waits do, via their own timers).
public func withTimeout<T: Sendable>(_ timeout: Duration, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw RelayError.timeout
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
