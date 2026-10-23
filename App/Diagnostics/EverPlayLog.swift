import Foundation

/// A small diagnostics journal in Documents (On My iPhone › EverPlay › EverPlay-log.txt) so
/// problems on a real device — a picker that returns nothing, a game that quits without a crash
/// report — can be reported. It records app events only, never game content.
enum EverPlayLog {
    static let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("EverPlay-log.txt")
    private static let queue = DispatchQueue(label: "app.everplay.log")
    private static let limit = 400

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
        print("EverPlay: \(message)")
        queue.sync {
            var lines = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: true)
            lines.append(Substring(line.dropLast()))
            let kept = lines.suffix(limit).joined(separator: "\n") + "\n"
            try? Data(kept.utf8).write(to: file, options: .atomic)
        }
    }

    static func read() -> String {
        queue.sync { (try? String(contentsOf: file, encoding: .utf8)) ?? "" }
    }

    static func clear() {
        queue.sync { try? FileManager.default.removeItem(at: file) }
    }
}
