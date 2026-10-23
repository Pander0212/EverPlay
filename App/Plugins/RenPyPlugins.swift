import SwiftUI
import UIKit

/// A separately installed Ren'Py runtime app. iOS lets one app load only one Python, and
/// sideloading certificates rarely allow shared App Groups, so each runtime is its own app:
/// its Documents folder holds the games, and EverPlay starts them with a URL.
struct RenPyPlugin: Identifiable, Hashable {
    let id: String
    let version: String
    var title: String { "Ren'Py \(version.split(separator: ".").prefix(2).joined(separator: "."))" }
    var appName: String { "EverPlay RenPy \(version.split(separator: ".").prefix(2).joined(separator: "."))" }
    var scheme: String { "everplay-renpy\(id)" }
    var major: Int { Int(version.prefix(1)) ?? 0 }

    static let all = [RenPyPlugin(id: "85", version: "8.5.3"),
                      RenPyPlugin(id: "84", version: "8.4.1"),
                      RenPyPlugin(id: "78", version: "7.8.7")]
}

struct PluginGame: Identifiable, Hashable {
    let plugin: RenPyPlugin
    let folder: String
    let engineVersion: String?
    var id: String { "\(plugin.id)/\(folder)" }
    var title: String { folder }
}

@MainActor
final class PluginStore: ObservableObject {
    @Published private(set) var connected: Set<String> = []
    @Published private(set) var games: [PluginGame] = []
    @Published private(set) var installing: String?
    @Published var message: String?
    private let defaults = UserDefaults.standard

    init() {
        connected = Set(RenPyPlugin.all.filter { defaults.data(forKey: Self.key($0)) != nil }.map(\.id))
    }

    private static func key(_ plugin: RenPyPlugin) -> String { "pluginFolder.\(plugin.id)" }

    func isInstalled(_ plugin: RenPyPlugin) -> Bool {
        guard let url = URL(string: "\(plugin.scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// The user picks the plugin's folder (On My iPhone › EverPlay RenPy x.y) once.
    func connect(_ plugin: RenPyPlugin, folder: URL) {
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Self.key(plugin))
            connected.insert(plugin.id)
            refresh()
        } catch { message = "The folder could not be connected: \(error.localizedDescription)" }
    }

    func disconnect(_ plugin: RenPyPlugin) {
        defaults.removeObject(forKey: Self.key(plugin))
        connected.remove(plugin.id)
        refresh()
    }

    /// Runs `work` with access to the plugin's folder; renews a stale bookmark.
    private func withFolder<T>(_ plugin: RenPyPlugin, _ work: (URL) throws -> T) rethrows -> T? {
        guard let data = defaults.data(forKey: Self.key(plugin)) else { return nil }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        if stale, let renewed = try? folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(renewed, forKey: Self.key(plugin))
        }
        return try work(folder)
    }

    func refresh() {
        var found: [PluginGame] = []
        for plugin in RenPyPlugin.all where connected.contains(plugin.id) {
            let names = withFolder(plugin) { folder in
                ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                    .filter { !$0.hasPrefix(".") && RenPyGame.isGame(folder.appendingPathComponent($0)) }
                    .map { ($0, RenPyGame.version(of: folder.appendingPathComponent($0))) }
            } ?? []
            found += names.map { PluginGame(plugin: plugin, folder: $0.0, engineVersion: $0.1) }
        }
        games = found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func play(_ game: PluginGame) {
        var components = URLComponents()
        components.scheme = game.plugin.scheme
        components.host = "play"
        components.queryItems = [URLQueryItem(name: "game", value: game.folder)]
        guard let url = components.url else { return }
        UIApplication.shared.open(url) { [weak self] opened in
            if !opened { Task { @MainActor in self?.message = "Install the \(game.plugin.appName) app to play this game." } }
        }
    }

    /// The best connected plugin: the exact version first (games may ship a modified engine of
    /// that version), then the newest runtime of the same major version.
    func bestPlugin(for version: String?) -> RenPyPlugin? {
        let candidates = RenPyPlugin.all.filter { connected.contains($0.id) }
        guard let version else { return candidates.first { $0.major == 8 } ?? candidates.first }
        let parts = version.split(separator: ".").prefix(3).joined(separator: ".")
        if let exact = candidates.first(where: { $0.version == parts }) { return exact }
        let major = Int(version.prefix(1)) ?? 8
        // Ren'Py 6 games run on the 7.x runtime.
        return candidates.first { $0.major == max(major, 7) }
    }

    /// Copies a Ren'Py game folder into the matching plugin; returns false if it is no Ren'Py game.
    func install(folder source: URL) async -> Bool {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        guard RenPyGame.isGame(source) else { return false }
        let version = RenPyGame.version(of: source)
        guard let plugin = bestPlugin(for: version) else {
            message = "This is a Ren'Py \(version ?? "") game. Install a Ren'Py plugin and connect it in Settings › Plugins first."
            return true
        }
        guard let bookmark = defaults.data(forKey: Self.key(plugin)) else { return true }
        installing = source.lastPathComponent
        defer { installing = nil }
        do {
            // Large games (gigabytes) are copied away from the main thread.
            try await Task.detached(priority: .userInitiated) {
                var stale = false
                let folder = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
                let granted = folder.startAccessingSecurityScopedResource()
                defer { if granted { folder.stopAccessingSecurityScopedResource() } }
                let destination = folder.appendingPathComponent(source.lastPathComponent, isDirectory: true)
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
                try FileManager.default.copyItem(at: source, to: destination)
            }.value
            refresh()
            message = "\(source.lastPathComponent) is ready in \(plugin.appName)."
        } catch { message = "The game could not be copied: \(error.localizedDescription)" }
        return true
    }
}

/// Passive inspection of a desktop Ren'Py game folder; nothing in it is executed.
enum RenPyGame {
    static func isGame(_ folder: URL) -> Bool {
        var directory: ObjCBool = false
        let game = folder.appendingPathComponent("game")
        guard FileManager.default.fileExists(atPath: game.path, isDirectory: &directory), directory.boolValue else { return false }
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("renpy").path) { return true }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: game.path)) ?? []
        return names.contains { $0.hasSuffix(".rpa") || $0.hasSuffix(".rpyc") || $0.hasSuffix(".rpy") }
    }

    /// "8.4.1" from renpy/vc_version.py, else from game/script_version.txt ("(8, 4, 1)").
    static func version(of folder: URL) -> String? {
        if let text = try? String(contentsOf: folder.appendingPathComponent("renpy/vc_version.py"), encoding: .utf8),
           let match = text.firstMatch(of: #/version\s*=\s*u?['"](\d+\.\d+\.\d+)/#) {
            return String(match.1)
        }
        if let text = try? String(contentsOf: folder.appendingPathComponent("game/script_version.txt"), encoding: .utf8) {
            let numbers = text.split(whereSeparator: { !$0.isNumber }).prefix(3)
            if numbers.count == 3 { return numbers.joined(separator: ".") }
        }
        return nil
    }
}

/// Settings › Plugins: install state and the one-time folder connection.
struct PluginSettingsSection: View {
    @EnvironmentObject private var plugins: PluginStore
    @State private var connecting: RenPyPlugin?

    var body: some View {
        Section {
            ForEach(RenPyPlugin.all) { plugin in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plugin.title)
                        Text(status(plugin)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if plugins.connected.contains(plugin.id) {
                        Button("Disconnect", role: .destructive) { plugins.disconnect(plugin) }.font(.subheadline)
                    } else {
                        Button("Connect") { connecting = plugin }.font(.subheadline.weight(.semibold))
                    }
                }
                .accessibilityIdentifier("plugin-\(plugin.id)")
            }
        } header: {
            Text("Plugins")
        } footer: {
            Text("Ren'Py games run in separate plugin apps. Install a plugin, open it once, then tap Connect and choose its folder: On My iPhone › EverPlay RenPy x.y.")
        }
        .sheet(item: $connecting) { plugin in
            DocumentPicker(types: [.folder]) { url in plugins.connect(plugin, folder: url) }
                .ignoresSafeArea()
        }
    }

    private func status(_ plugin: RenPyPlugin) -> String {
        let installed = plugins.isInstalled(plugin) ? "Installed" : "Not installed"
        let connected = plugins.connected.contains(plugin.id) ? "folder connected" : "folder not connected"
        return "\(plugin.version) · \(installed) · \(connected)"
    }
}

/// Library section for games that live in plugin apps.
struct PluginGamesSection: View {
    @EnvironmentObject private var plugins: PluginStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ren'Py").font(.title3.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 22) {
                ForEach(plugins.games) { game in
                    Button { plugins.play(game) } label: { PluginGameCard(game: game) }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("plugin-game-\(game.title)")
                }
            }
        }
    }
}

private struct PluginGameCard: View {
    let game: PluginGame
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Theme.cover(for: game.title)
                LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
                Text(Theme.initials(game.title))
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .aspectRatio(0.78, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                Text(game.plugin.title).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.title).font(.headline).lineLimit(2).foregroundStyle(.primary)
                Text(game.engineVersion.map { "Made with Ren'Py \($0)" } ?? "Ren'Py game")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
    }
}
