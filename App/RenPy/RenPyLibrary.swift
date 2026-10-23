import SwiftUI
import UIKit

/// A Ren'Py runtime bundled in the app: Frameworks/RenPyNN.framework plus Runtimes/NN/base.
/// Several versions ship side by side; each framework hides its own Python, SDL and FFmpeg,
/// and only one is loaded per app run.
struct RenPyRuntime: Identifiable, Hashable {
    let id: String
    let version: String
    var title: String { "Ren'Py \(version.split(separator: ".").prefix(2).joined(separator: "."))" }
    var major: Int { Int(version.prefix(1)) ?? 0 }
    var directory: URL { Bundle.main.bundleURL.appendingPathComponent("Runtimes/\(id)") }
    var binary: URL? { Bundle.main.privateFrameworksURL?.appendingPathComponent("RenPy\(id).framework/RenPy\(id)") }

    static func bundled() -> [RenPyRuntime] {
        let root = Bundle.main.bundleURL.appendingPathComponent("Runtimes")
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return ids.compactMap { id in
            guard let text = try? String(contentsOf: root.appendingPathComponent("\(id)/version.txt"), encoding: .utf8) else { return nil }
            return RenPyRuntime(id: id, version: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    /// The exact version first (games may ship a modified engine of that version), otherwise the
    /// newest runtime of the same major version; Ren'Py 6 games run on 7.x.
    static func best(for version: String?, among runtimes: [RenPyRuntime]) -> RenPyRuntime? {
        guard let version else { return runtimes.first { $0.major == 8 } ?? runtimes.first }
        let exact = version.split(separator: ".").prefix(3).joined(separator: ".")
        if let match = runtimes.first(where: { $0.version == exact }) { return match }
        let major = max(Int(version.prefix(1)) ?? 8, 7)
        return runtimes.first { $0.major == major }
    }
}

struct RenPyTitle: Identifiable, Hashable {
    let folder: String
    let engineVersion: String?
    let runtime: RenPyRuntime?
    var id: String { folder }
    var title: String { folder }
}

@MainActor
final class RenPyLibrary: ObservableObject {
    @Published private(set) var games: [RenPyTitle] = []
    @Published private(set) var installing: String?
    @Published var message: String?
    let runtimes = RenPyRuntime.bundled()
    /// Visible in Files under On My iPhone › EverPlay › Ren'Py.
    let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Ren'Py", isDirectory: true)
    private var saves: URL { root.deletingLastPathComponent().appendingPathComponent("Saves", isDirectory: true) }

    func refresh() {
        guard !runtimes.isEmpty else { games = []; return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        games = names.filter { !$0.hasPrefix(".") && RenPyGame.isGame(root.appendingPathComponent($0)) }
            .map { name in
                let version = RenPyGame.version(of: root.appendingPathComponent(name))
                return RenPyTitle(folder: name, engineVersion: version, runtime: RenPyRuntime.best(for: version, among: runtimes))
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Copies a desktop Ren'Py game folder into the library; returns false if it is no Ren'Py game.
    func install(folder source: URL) async -> Bool {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        guard RenPyGame.isGame(source) else { return false }
        guard !runtimes.isEmpty else {
            message = "This build of EverPlay does not include Ren'Py."
            return true
        }
        let destination = root.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        guard source.standardizedFileURL != destination.standardizedFileURL else { refresh(); return true }
        installing = source.lastPathComponent
        defer { installing = nil }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            // Games can be gigabytes; copy away from the main thread.
            try await Task.detached(priority: .userInitiated) {
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
                try FileManager.default.copyItem(at: source, to: destination)
            }.value
            refresh()
            message = "\(source.lastPathComponent) is ready in your library."
        } catch { message = "The game could not be copied: \(error.localizedDescription)" }
        return true
    }

    /// Starts the game in this process. Ren'Py takes over the screen until the game quits,
    /// which currently also closes EverPlay (one embedded Python per app run).
    func play(_ game: RenPyTitle) {
        guard let runtime = game.runtime, let binary = runtime.binary else {
            message = "No bundled Ren'Py runtime can start \(game.title) (made with Ren'Py \(game.engineVersion ?? "?"))."
            return
        }
        let folder = root.appendingPathComponent(game.folder)
        let saveDirectory = saves.appendingPathComponent(game.folder)
        // Desktop Ren'Py games are landscape. Rotate before SDL creates its window, which keeps the
        // size it starts with, and keep SDL's own view controller in landscape afterwards.
        setenv("SDL_IOS_ORIENTATIONS", "LandscapeLeft LandscapeRight", 1)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
        let delay = scene?.interfaceOrientation.isLandscape == true ? 0.05 : 0.8
        // Let SwiftUI finish the tap (and the rotation) before Ren'Py's loop takes over the main thread.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            // RTLD_GLOBAL: SDL resolves OpenGL ES entry points with dlsym(RTLD_DEFAULT), so the
            // runtime's MetalANGLE must be visible globally. Python, SDL and FFmpeg stay private
            // because the framework exports only everplay_renpy_main.
            guard let handle = dlopen(binary.path, RTLD_NOW | RTLD_GLOBAL),
                  let symbol = dlsym(handle, "everplay_renpy_main") else {
                let reason = dlerror().map { String(cString: $0) } ?? "unknown"
                self?.message = "\(runtime.title) could not be loaded: \(reason)"
                return
            }
            typealias Entry = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32
            let entry = unsafeBitCast(symbol, to: Entry.self)
            setenv("EVERPLAY_SAVE_DIR", saveDirectory.path, 1)
            UIApplication.shared.isIdleTimerDisabled = true
            let status = runtime.directory.path.withCString { runtimePath in
                folder.path.withCString { gamePath in entry(runtimePath, gamePath) }
            }
            print("EverPlay: Ren'Py exited with status \(status)")
            exit(status)
        }
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

/// Library section for Ren'Py games.
struct RenPyGamesSection: View {
    @EnvironmentObject private var renpy: RenPyLibrary
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ren'Py").font(.title3.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 22) {
                ForEach(renpy.games) { game in
                    Button { renpy.play(game) } label: { RenPyGameCard(game: game) }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("renpy-\(game.title)")
                }
            }
        }
    }
}

private struct RenPyGameCard: View {
    let game: RenPyTitle
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
                Text(game.runtime?.title ?? "Ren'Py").font(.caption2.weight(.semibold))
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

/// Settings: which Ren'Py versions this build carries.
struct RenPySettingsSection: View {
    @EnvironmentObject private var renpy: RenPyLibrary
    var body: some View {
        Section {
            if renpy.runtimes.isEmpty {
                Text("Not included in this build.").foregroundStyle(.secondary)
            }
            ForEach(renpy.runtimes) { runtime in
                LabeledContent(runtime.title, value: runtime.version)
            }
        } header: {
            Text("Ren'Py")
        } footer: {
            Text("Games use the exact Ren'Py version they were made with when it is included, otherwise the newest of the same major version. Quitting a Ren'Py game currently closes EverPlay.")
        }
    }
}
