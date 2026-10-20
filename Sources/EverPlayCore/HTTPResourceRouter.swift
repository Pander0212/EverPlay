import Foundation

public struct ResourceResponse {
    public let status: Int
    public let headers: [String: String]
    public let file: URL?
    public let offset: UInt64
    public let count: UInt64
    public let headOnly: Bool
}

/// Pure, tested routing shared by the iOS Network.framework server.
public struct HTTPResourceRouter: Sendable {
    public let root: URL
    public let port: UInt16
    public let token: String
    public init(root: URL, port: UInt16, token: String) { self.root = root; self.port = port; self.token = token }

    public func response(to request: Data) throws -> ResourceResponse {
        guard request.count <= 16384, let text = String(data: request, encoding: .utf8),
              text.hasSuffix("\r\n\r\n") else { throw EverPlayError.invalidRequest }
        let lines = text.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, ["GET", "HEAD"].contains(String(parts[0])),
              parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0" else { throw EverPlayError.invalidRequest }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else {
                throw EverPlayError.invalidRequest
            }
            let name = line[..<colon].lowercased()
            guard headers[name] == nil else { throw EverPlayError.invalidRequest }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["host"] == "127.0.0.1:\(port)", headers["transfer-encoding"] == nil,
              headers["content-length"] == nil || headers["content-length"] == "0" else { throw EverPlayError.invalidRequest }
        let rawPath = parts[1].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        guard let path = String(rawPath).removingPercentEncoding, path.hasPrefix("/\(token)/") else {
            throw EverPlayError.resourceNotFound
        }
        let relative = String(path.dropFirst(token.count + 2))
        let file = try SafePath.destination(relative, in: root)
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular, let size = attrs[.size] as? NSNumber else {
            throw EverPlayError.resourceNotFound
        }
        let total = size.uint64Value
        var start: UInt64 = 0
        var count = total
        var status = 200
        var output = [
            "Content-Type": Self.mimeType(file.pathExtension),
            "Accept-Ranges": "bytes", "Cache-Control": "no-store", "Connection": "close",
            "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer",
            "Content-Security-Policy": "default-src 'self' data: blob:; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; connect-src 'self' blob:; frame-src 'none'; object-src 'none'; base-uri 'self'; form-action 'none'"
        ]
        if let range = headers["range"] {
            guard range.hasPrefix("bytes="), !range.contains(","), total > 0 else { throw EverPlayError.invalidRange }
            let bounds = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
            guard bounds.count == 2 else { throw EverPlayError.invalidRange }
            if bounds[0].isEmpty {
                guard let suffix = UInt64(bounds[1]), suffix > 0 else { throw EverPlayError.invalidRange }
                count = min(suffix, total); start = total - count
            } else {
                guard let lower = UInt64(bounds[0]), lower < total else { throw EverPlayError.invalidRange }
                let upper: UInt64
                if bounds[1].isEmpty { upper = total - 1 }
                else {
                    guard let value = UInt64(bounds[1]), value >= lower else { throw EverPlayError.invalidRange }
                    upper = min(value, total - 1)
                }
                start = lower; count = upper - lower + 1
            }
            output["Content-Range"] = "bytes \(start)-\(start + count - 1)/\(total)"
            status = 206
        }
        output["Content-Length"] = String(count)
        return ResourceResponse(status: status, headers: output, file: file, offset: start, count: count, headOnly: parts[0] == "HEAD")
    }

    public static func mimeType(_ extensionName: String) -> String {
        ["html": "text/html; charset=utf-8", "htm": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
         "mjs": "text/javascript; charset=utf-8", "css": "text/css; charset=utf-8", "json": "application/json",
         "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "svg": "image/svg+xml",
         "webp": "image/webp", "ico": "image/x-icon", "mp3": "audio/mpeg", "m4a": "audio/mp4", "ogg": "audio/ogg",
         "wav": "audio/wav", "mp4": "video/mp4", "webm": "video/webm", "wasm": "application/wasm",
         "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf", "otf": "font/otf",
         "txt": "text/plain; charset=utf-8"][extensionName.lowercased()] ?? "application/octet-stream"
    }
}
