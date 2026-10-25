import SwiftUI
import UIKit
import EverPlayCore

/// Talks to EverPlayRGSS.rb inside a running XP/VX/VX Ace game: each call is a request file in the
/// temporary folder, which the game answers at its next frames with a JSON reply file.
@MainActor
final class RGSSCheatBridge: CheatEngine {
    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("everplay-rgss", isDirectory: true)
    static let methods: Set<String> = GameSession.cheatMethods.union(["setGod"])
    private static var next = 0

    func cheat<Result: Decodable>(_ method: String, _ arguments: [Any], as type: Result.Type) async throws -> Result {
        guard Self.methods.contains(method) else { throw EverPlayError.invalidRequest }
        Self.next += 1
        let id = "\(ProcessInfo.processInfo.processIdentifier)-\(Self.next)"
        let encoded = arguments.map { argument -> String in
            switch argument {
            case let flag as Bool: return "b:\(flag ? 1 : 0)"
            case let number as Int: return "n:\(number)"
            case let number as Double: return "n:\(number)"
            default: return "s:" + "\(argument)".replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            }
        }
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let request = (["call", id, method] + encoded).joined(separator: "\t")
        try Data(request.utf8).write(to: Self.folder.appendingPathComponent("request-\(id)"), options: .atomic)
        let reply = Self.folder.appendingPathComponent("reply-\(id).json")
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(50))
            guard let data = try? Data(contentsOf: reply) else { continue }
            try? FileManager.default.removeItem(at: reply)
            if let failure = try? JSONDecoder().decode([String: String].self, from: data), let message = failure["error"] {
                throw RGSSCheatError(message: message)
            }
            return try JSONDecoder().decode(Result.self, from: data)
        }
        throw RGSSCheatError(message: "The game did not answer. Cheats need a game started by EverPlay.")
    }

    /// Shows the cheat screen over the game when the ☰ button in the game (MKXP.framework) is tapped.
    static func listen() {
        NotificationCenter.default.addObserver(forName: Notification.Name("EverPlayRGSSMenu"), object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { present() }
        }
    }

    private static func present() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let host = Host()
        let bridge = RGSSCheatBridge()
        let screen = NavigationStack {
            CheatsView(session: bridge)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { host.controller?.dismiss(animated: true) } }
                }
        }
        let controller = UIHostingController(rootView: screen)
        host.controller = controller
        top.present(controller, animated: true)
    }

    private final class Host {
        weak var controller: UIViewController?
    }
}

struct RGSSCheatError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
