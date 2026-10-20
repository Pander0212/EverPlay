import Foundation
import Network
import EverPlayCore

/// Serves only the active game's immutable files. No LAN binding, write methods, or native scripting bridge.
final class LocalGameServer {
    private let queue = DispatchQueue(label: "app.everplay.resources")
    private let router: HTTPResourceRouter
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private var startCompletion: ((Result<Void, Error>) -> Void)?

    init(root: URL, game: GameRecord) {
        router = HTTPResourceRouter(root: root, port: game.port, token: game.resourceToken)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: self.router.port)!)
                    parameters.allowLocalEndpointReuse = true
                    let listener = try NWListener(using: parameters)
                    self.listener = listener
                    self.startCompletion = { continuation.resume(with: $0) }
                    listener.stateUpdateHandler = { [weak self, weak listener] state in
                        guard let self, self.listener === listener else { return }
                        switch state {
                        case .ready: self.completeStart(.success(()))
                        case .failed(let error):
                            self.completeStart(.failure(error)); self.stopOnQueue()
                        case .cancelled: self.completeStart(.failure(CancellationError()))
                        default: break
                        }
                    }
                    listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                    listener.start(queue: self.queue)
                    self.queue.asyncAfter(deadline: .now() + 10) { [weak self] in
                        guard let self, self.startCompletion != nil else { return }
                        self.completeStart(.failure(URLError(.timedOut))); self.stopOnQueue()
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() { queue.async { self.stopOnQueue() } }
    private func completeStart(_ result: Result<Void, Error>) {
        let completion = startCompletion; startCompletion = nil; completion?(result)
    }
    private func stopOnQueue() {
        completeStart(.failure(CancellationError()))
        listener?.cancel(); listener = nil
        for connection in clients.values { connection.cancel() }
        clients.removeAll()
    }
    private func accept(_ connection: NWConnection) {
        guard clients.count < 32 else { connection.cancel(); return }
        let id = UUID(); clients[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.close(id) }
            if case .cancelled = state { self?.clients.removeValue(forKey: id) }
        }
        connection.start(queue: queue)
        // Bound connection lifetime, including clients that never finish a request header.
        queue.asyncAfter(deadline: .now() + 60) { [weak self] in self?.close(id) }
        receive(connection, id: id, buffer: Data())
    }
    private func close(_ id: UUID) { clients.removeValue(forKey: id)?.cancel() }
    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, finished, error in
            guard let self else { return }
            var request = buffer
            if let data { request.append(data) }
            guard request.count <= 16384, error == nil else { self.fail(connection, id: id, status: 400); return }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                do { try self.send(self.router.response(to: request), to: connection, id: id) }
                catch EverPlayError.invalidRange { self.fail(connection, id: id, status: 416) }
                catch { self.fail(connection, id: id, status: 404) }
            } else if finished { self.close(id) }
            else { self.receive(connection, id: id, buffer: request) }
        }
    }
    private func fail(_ connection: NWConnection, id: UUID, status: Int) {
        let data = Data("HTTP/1.1 \(status) Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in self?.close(id) })
    }
    private func send(_ response: ResourceResponse, to connection: NWConnection, id: UUID) throws {
        let header = "HTTP/1.1 \(response.status) \(response.status == 206 ? "Partial Content" : "OK")\r\n" +
            response.headers.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
        let file = try response.headOnly ? nil : response.file.map { try FileHandle(forReadingFrom: $0) }
        try file?.seek(toOffset: response.offset)
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { try? file?.close(); return }
            if error != nil || response.headOnly || response.count == 0 {
                try? file?.close(); self.close(id); return
            }
            guard let file else { self.close(id); return }
            self.stream(file, remaining: response.count, to: connection, id: id)
        })
    }
    private func stream(_ file: FileHandle, remaining: UInt64, to connection: NWConnection, id: UUID) {
        do {
            guard clients[id] != nil, remaining > 0,
                  let data = try file.read(upToCount: Int(min(remaining, 262144))), !data.isEmpty else {
                try? file.close(); close(id); return
            }
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self else { try? file.close(); return }
                if error != nil { try? file.close(); self.close(id) }
                else { self.stream(file, remaining: remaining - UInt64(data.count), to: connection, id: id) }
            })
        } catch { try? file.close(); close(id) }
    }
}
