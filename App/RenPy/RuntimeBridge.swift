import Foundation
import Network
import UIKit

/// The embedded Ren'Py runtime's line to EverPlay: a loopback-only HTTP endpoint with a random
/// token per app run. Python reaches it with its standard library (http.client / httplib) on both
/// Python 2 and 3, so translation and link opening do not depend on pyobjus, which fails to load
/// under Ren'Py 7's Python 2.
///
/// POST /<token>/translate | cached | prefetch | bulk  (body: UTF-8 text; reply: translation or "")
/// POST /<token>/open                            (body: an http(s) URL, opened in Safari)
final class RuntimeBridge: @unchecked Sendable {
    static let shared = RuntimeBridge()

    let token = UUID().uuidString
    private let queue = DispatchQueue(label: "app.everplay.runtime-bridge")
    private var listener: NWListener?
    private(set) var port: UInt16?

    func start() {
        queue.async {
            guard self.listener == nil else { return }
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
                let listener = try NWListener(using: parameters)
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready: self.port = listener.port?.rawValue
                    case .failed, .cancelled: self.port = nil; self.listener = nil
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.start(queue: self.queue)
                self.listener = listener
            } catch {
                EverPlayLog.write("Runtime bridge could not start: \(error)")
            }
        }
    }

    /// Sets EVERPLAY_BRIDGE_PORT/TOKEN for the runtime about to start.
    func export() {
        let port = queue.sync { self.port }
        guard let port else { EverPlayLog.write("Runtime bridge not ready; translation and links use fallbacks"); return }
        setenv("EVERPLAY_BRIDGE_PORT", String(port), 1)
        setenv("EVERPLAY_BRIDGE_TOKEN", token, 1)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 30) { connection.cancel() }
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, finished, error in
            guard let self else { return }
            var request = buffer
            if let data { request.append(data) }
            guard error == nil, request.count <= 262_144 else { connection.cancel(); return }
            if let parsed = Self.parse(request) {
                self.handle(parsed.path, body: parsed.body, on: connection)
            } else if finished {
                connection.cancel()
            } else {
                self.receive(connection, buffer: request)
            }
        }
    }

    /// The path and body of a complete request, or nil while more bytes are expected.
    static func parse(_ request: Data) -> (path: String, body: Data)? {
        guard let end = request.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: request[..<end.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2, parts[0] == "POST" else { return ("", Data()) }
        let length = lines.dropFirst().compactMap { line -> Int? in
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2, pair[0].lowercased() == "content-length" else { return nil }
            return Int(pair[1].trimmingCharacters(in: .whitespaces))
        }.first ?? 0
        let body = request[end.upperBound...]
        guard body.count >= length else { return nil }
        return (String(parts[1]), Data(body.prefix(length)))
    }

    private func handle(_ path: String, body: Data, on connection: NWConnection) {
        let segments = path.split(separator: "/").map(String.init)
        guard segments.count == 2, segments[0] == token, let text = String(data: body, encoding: .utf8) else {
            respond("", status: "403 Forbidden", on: connection); return
        }
        switch segments[1] {
        case "translate", "cached", "prefetch", "bulk":
            // Translating may wait for the service; keep the listener free meanwhile.
            DispatchQueue.global(qos: .userInitiated).async {
                let engine = TranslationEngine.shared
                let reply: String
                switch segments[1] {
                case "translate": reply = engine.translate(text, timeout: 2.5) ?? ""
                case "cached": reply = engine.cached(text) ?? ""
                case "bulk":
                    reply = String(engine.translateAll(text.components(separatedBy: "\u{1E}").filter { !$0.isEmpty }))
                default:
                    engine.prefetch(text.components(separatedBy: "\u{1E}").filter { !$0.isEmpty })
                    reply = ""
                }
                self.queue.async { self.respond(reply, on: connection) }
            }
        case "open":
            guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                respond("", status: "400 Bad Request", on: connection); return
            }
            // The main thread runs the game; UIKit opens the link when the game next pumps events.
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            EverPlayLog.write("Game opened a link to \(url.host ?? "?")")
            respond("ok", on: connection)
        default:
            respond("", status: "404 Not Found", on: connection)
        }
    }

    private func respond(_ text: String, status: String = "200 OK", on connection: NWConnection) {
        let body = Data(text.utf8)
        var response = Data("HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
