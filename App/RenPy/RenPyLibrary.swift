import SwiftUI
import UIKit
import os
import EverPlayCore

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

    /// The exact version first (games may ship a modified engine of that version), then the same
    /// minor version (8.3.2 runs on 8.3.7, closest to what it was made for), otherwise the newest
    /// runtime of the same major version; Ren'Py 6 games run on 7.x.
    static func best(for version: String?, among runtimes: [RenPyRuntime]) -> RenPyRuntime? {
        guard let version else { return runtimes.first { $0.major == 8 } ?? runtimes.first }
        let parts = version.split(separator: ".")
        let exact = parts.prefix(3).joined(separator: ".")
        if let match = runtimes.first(where: { $0.version == exact }) { return match }
        let minor = parts.prefix(2).joined(separator: ".") + "."
        if let match = runtimes.first(where: { $0.version.hasPrefix(minor) }) { return match }
        let major = max(Int(version.prefix(1)) ?? 8, 7)
        return runtimes.first { $0.major == major }
    }
}

struct RenPyTitle: Identifiable, Hashable {
    let folder: String
    let title: String
    let engineVersion: String?
    let runtime: RenPyRuntime?
    /// The runtime picked in the game's details; nil means automatic.
    let runtimeChoice: String?
    let cover: URL?
    let lastPlayed: Date?
    let playSeconds: Double
    var id: String { folder }
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
    private let defaults = UserDefaults.standard

    init() {
        RuntimeBridge.shared.start()
        // Playtime of the last session: the game wrote its start time and EverPlay closes with it.
        if let start = defaults.object(forKey: "renpy.sessionStart") as? Double,
           let folder = defaults.string(forKey: "renpy.sessionGame") {
            let end = defaults.object(forKey: "renpy.sessionEnd") as? Double
            if let end, end > start { addPlaytime(end - start, to: folder) }
            EverPlayLog.write("Ren'Py session of \(folder) ended " + (end == nil ? "without returning to EverPlay (closed by iOS or killed)" : "normally"))
            let traceback = root.appendingPathComponent(folder).appendingPathComponent("traceback.txt")
            if let changed = (try? traceback.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               changed.timeIntervalSince1970 >= start {
                EverPlayLog.write("\(folder) reported an error (traceback.txt)")
                message = "\(folder) stopped with an error. Its page shows the report (traceback.txt) to read or share."
            } else if end == nil {
                message = "\(folder) closed without an error report: it was swiped away or iOS ended it (usually for memory)."
            }
            defaults.removeObject(forKey: "renpy.sessionStart")
            defaults.removeObject(forKey: "renpy.sessionEnd")
            defaults.removeObject(forKey: "renpy.sessionGame")
        }
    }

    func refresh() {
        guard !runtimes.isEmpty else { games = []; return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let played = defaults.dictionary(forKey: "renpy.lastPlayed") as? [String: Double] ?? [:]
        let seconds = defaults.dictionary(forKey: "renpy.playSeconds") as? [String: Double] ?? [:]
        let choices = defaults.dictionary(forKey: "renpy.runtimeChoice") as? [String: String] ?? [:]
        games = names.filter { !$0.hasPrefix(".") && RenPyGame.isGame(root.appendingPathComponent($0)) }
            .map { name in
                let folder = root.appendingPathComponent(name)
                let version = RenPyGame.version(of: folder)
                let chosen = choices[name].flatMap { id in runtimes.first { $0.id == id } }
                return RenPyTitle(folder: name, title: RenPyGame.title(of: folder), engineVersion: version,
                                  runtime: chosen ?? RenPyRuntime.best(for: version, among: runtimes),
                                  runtimeChoice: chosen?.id,
                                  cover: RenPyGame.cover(of: folder), lastPlayed: played[name].map(Date.init(timeIntervalSince1970:)),
                                  playSeconds: seconds[name] ?? 0)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Copies a desktop Ren'Py game folder into the library; returns false if it is no Ren'Py game.
    func install(folder source: URL) async -> Bool {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        guard RenPyGame.isGame(source) else {
            EverPlayLog.write("Not a Ren'Py folder: \(source.lastPathComponent) (access granted: \(accessed))")
            return false
        }
        guard !runtimes.isEmpty else {
            message = "This build of EverPlay does not include Ren'Py."
            return true
        }
        let destination = root.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        guard source.standardizedFileURL != destination.standardizedFileURL else { refresh(); return true }
        installing = source.lastPathComponent
        defer { installing = nil }
        EverPlayLog.write("Copying Ren'Py folder \(source.lastPathComponent)")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            // Games can be gigabytes; copy away from the main thread.
            try await Task.detached(priority: .userInitiated) {
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
                try FileManager.default.copyItem(at: source, to: destination)
            }.value
            refresh()
            EverPlayLog.write("Ren'Py folder ready: \(source.lastPathComponent)")
            message = "\(source.lastPathComponent) is ready in your library."
        } catch {
            EverPlayLog.write("Ren'Py folder copy failed: \(error)")
            message = "The game could not be copied: \(error.localizedDescription)"
        }
        return true
    }

    /// Extracts a Ren'Py game ZIP (safely, as every import) into the library.
    func install(zip source: URL) async {
        guard !runtimes.isEmpty else { message = "This build of EverPlay does not include Ren'Py."; return }
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let name = source.deletingPathExtension().lastPathComponent
        installing = name
        defer { installing = nil }
        EverPlayLog.write("Extracting Ren'Py ZIP \(source.lastPathComponent)")
        let root = self.root
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let installed = try await Task.detached(priority: .userInitiated) { () -> String in
                let staging = root.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: staging) }
                try GameImporter().extractArchive(zip: source, into: staging)
                guard let game = RenPyGame.findGame(in: staging) else { throw EverPlayError.unsupportedGame }
                // A ZIP usually holds one top folder ("Game-1.0-pc"); otherwise name it after the ZIP.
                let folderName = game == staging ? name : game.lastPathComponent
                let destination = root.appendingPathComponent(folderName, isDirectory: true)
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
                try FileManager.default.moveItem(at: game, to: destination)
                return folderName
            }.value
            refresh()
            EverPlayLog.write("Ren'Py ZIP ready: \(installed)")
            message = "\(installed) is ready in your library."
        } catch {
            EverPlayLog.write("Ren'Py ZIP import failed: \(error)")
            message = "The game could not be imported: \(error.localizedDescription)"
        }
    }

    func delete(_ game: RenPyTitle) {
        do {
            try FileManager.default.removeItem(at: root.appendingPathComponent(game.folder))
            EverPlayLog.write("Deleted Ren'Py game \(game.folder); saves kept in Saves/\(game.folder)")
        } catch { message = "The game could not be deleted: \(error.localizedDescription)" }
        refresh()
    }

    /// Runs the game on a specific bundled runtime (nil: pick automatically).
    func setRuntime(_ id: String?, for game: RenPyTitle) {
        var choices = defaults.dictionary(forKey: "renpy.runtimeChoice") as? [String: String] ?? [:]
        choices[game.folder] = id
        defaults.set(choices, forKey: "renpy.runtimeChoice")
        EverPlayLog.write("Runtime for \(game.folder): \(id ?? "automatic")")
        refresh()
    }

    func folder(of game: RenPyTitle) -> URL { root.appendingPathComponent(game.folder) }
    func saveFolder(of game: RenPyTitle) -> URL { saves.appendingPathComponent(game.folder) }

    /// MB of decoded images Ren'Py may keep: less on devices with less memory (Settings can override).
    static func imageCacheLimit() -> Int {
        let chosen = UserDefaults.standard.integer(forKey: "renpy.imageCacheMB")
        return chosen > 0 ? chosen : automaticImageCacheLimit()
    }

    static func automaticImageCacheLimit() -> Int {
        let gigabytes = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        switch gigabytes {
        case ..<3.5: return 120
        case ..<5.5: return 200
        case ..<7.5: return 300
        default: return 400
        }
    }

    private func addPlaytime(_ seconds: Double, to folder: String) {
        var all = defaults.dictionary(forKey: "renpy.playSeconds") as? [String: Double] ?? [:]
        all[folder, default: 0] += seconds
        defaults.set(all, forKey: "renpy.playSeconds")
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
        var played = defaults.dictionary(forKey: "renpy.lastPlayed") as? [String: Double] ?? [:]
        played[game.folder] = Date().timeIntervalSince1970
        defaults.set(played, forKey: "renpy.lastPlayed")
        defaults.set(Date().timeIntervalSince1970, forKey: "renpy.sessionStart")
        defaults.set(game.folder, forKey: "renpy.sessionGame")
        EverPlayLog.write("Starting \(game.folder) (made with \(game.engineVersion ?? "unknown")) on \(runtime.title) \(runtime.version)")
        // Desktop Ren'Py games are landscape. Rotate before SDL creates its window, which keeps the
        // size it starts with, and keep SDL's own view controller in landscape afterwards.
        setenv("SDL_IOS_ORIENTATIONS", "LandscapeLeft LandscapeRight", 1)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
        let delay = scene?.interfaceOrientation.isLandscape == true ? 0.05 : 0.8
        // Let SwiftUI finish the tap (and the rotation) before Ren'Py's loop takes over the main thread.
        // A run loop timer, not DispatchQueue.main: Ren'Py never returns, and inside a main-queue
        // block the main queue stays blocked for the whole game, together with all UIKit and
        // SwiftUI work queued there (suspected cause of lost taps after returning to the game and
        // of a stale app switcher snapshot). SDL's own app delegate starts the game loop the same
        // way (performSelector:afterDelay:).
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in MainActor.assumeIsolated {
            // RTLD_GLOBAL: SDL resolves OpenGL ES entry points with dlsym(RTLD_DEFAULT), so the
            // runtime's MetalANGLE must be visible globally. Python, SDL and FFmpeg stay private
            // because the framework exports only everplay_renpy_main.
            guard let handle = dlopen(binary.path, RTLD_NOW | RTLD_GLOBAL),
                  let symbol = dlsym(handle, "everplay_renpy_main") else {
                let reason = dlerror().map { String(cString: $0) } ?? "unknown"
                EverPlayLog.write("\(runtime.title) could not be loaded: \(reason)")
                self?.message = "\(runtime.title) could not be loaded: \(reason)"
                return
            }
            typealias Entry = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32
            let entry = unsafeBitCast(symbol, to: Entry.self)
            setenv("EVERPLAY_SAVE_DIR", saveDirectory.path, 1)
            // The in-game EverPlay button (quick actions, variable editor) in renpy/common.
            let menu = UserDefaults.standard.object(forKey: "renpy.menuButton") as? Bool ?? true
            setenv("EVERPLAY_MENU", menu ? "1" : "0", 1)
            // Machine translation of dialogue and choices (game page › Translate), see TranslationEngine.
            let translation = TranslationPreferences.settings
            let translate = translation.provider != .off && TranslationPreferences.isEnabled(for: game.folder)
            TranslationEngine.shared.start(game: game.folder, settings: translate ? translation : nil)
            setenv("EVERPLAY_TRANSLATE", translate ? "1" : "0", 1)
            RuntimeBridge.shared.export()
            // iOS's keyboard does not come up in the embedded game window; Ren'Py draws EverPlay's
            // docked keyboard (renpy/common/00everplay.rpy) instead.
            setenv("RENPY_TOUCH_KEYBOARD", "1", 1)
            // Ren'Py's image cache defaults to 400 MB; iOS ends apps that use too much memory.
            let cache = RenPyLibrary.imageCacheLimit()
            setenv("EVERPLAY_IMAGE_CACHE_MB", String(cache), 1)
            EverPlayLog.write("Device memory \(ProcessInfo.processInfo.physicalMemory / 1_048_576) MB, available \(os_proc_available_memory() / 1_048_576) MB, image cache limit \(cache) MB")
            let warnings = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                  object: nil, queue: .main) { _ in
                EverPlayLog.write("Memory warning while playing \(game.folder): \(os_proc_available_memory() / 1_048_576) MB still available")
            }
            UIApplication.shared.isIdleTimerDisabled = true
            let status = runtime.directory.path.withCString { runtimePath in
                folder.path.withCString { gamePath in entry(runtimePath, gamePath) }
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "renpy.sessionEnd")
            TranslationEngine.shared.flush()
            NotificationCenter.default.removeObserver(warnings)
            EverPlayLog.write("Ren'Py returned with status \(status) for \(game.folder)")
            exit(status)
        } }
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

    /// The game folder itself or one nested up to two levels deep (ZIPs add a top folder).
    static func findGame(in folder: URL) -> URL? {
        if isGame(folder) { return folder }
        var level = [folder]
        for _ in 0..<2 {
            var next: [URL] = []
            for directory in level {
                let children = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                                                                            options: [.skipsHiddenFiles])) ?? []
                for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if isGame(child) { return child }
                    next.append(child)
                }
            }
            level = next
        }
        return nil
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

    /// config.name from game/options.rpy when the source ships, else a cleaned folder name
    /// ("School-0.981-win" → "School").
    static func title(of folder: URL) -> String {
        if let text = try? String(contentsOf: folder.appendingPathComponent("game/options.rpy"), encoding: .utf8),
           let match = text.firstMatch(of: #/config\.name\s*=\s*_?\(?\s*u?["']([^"'\n]+)["']/#) {
            let name = String(match.1).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        let platforms: Set<String> = ["pc", "win", "windows", "mac", "linux", "market", "all", "android", "ios"]
        let words = folder.lastPathComponent.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .filter { word in
                let lower = word.lowercased()
                if platforms.contains(lower) { return false }
                if lower.first?.isNumber == true { return false }
                if lower.hasPrefix("v"), lower.dropFirst().first?.isNumber == true { return false }
                return true
            }
        let cleaned = words.joined(separator: " ")
        return cleaned.isEmpty ? folder.lastPathComponent : cleaned
    }

    /// A picture shipped as a loose file: the main menu background, else the window icon.
    static func cover(of folder: URL) -> URL? {
        let candidates = ["game/gui/main_menu.png", "game/gui/main_menu.jpg", "game/gui/main_menu.webp",
                          "game/images/main_menu.png", "game/images/main_menu.jpg", "game/gui/game_menu.png",
                          "game/gui/game_menu.jpg", "game/gui/window_icon.png", "game/icon.png"]
        return candidates.map { folder.appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// Settings: which Ren'Py versions this build carries.
struct RenPySettingsSection: View {
    @EnvironmentObject private var renpy: RenPyLibrary
    @AppStorage("renpy.menuButton") private var menuButton = true
    @AppStorage("renpy.imageCacheMB") private var imageCache = 0
    var body: some View {
        Section {
            Toggle("In-game menu button", isOn: $menuButton)
            Picker("Image memory", selection: $imageCache) {
                Text("Automatic (\(RenPyLibrary.automaticImageCacheLimit()) MB)").tag(0)
                ForEach([100, 200, 300, 400], id: \.self) { Text("\($0) MB").tag($0) }
            }
            if renpy.runtimes.isEmpty {
                Text("Not included in this build.").foregroundStyle(.secondary)
            }
            ForEach(renpy.runtimes) { runtime in
                LabeledContent(runtime.title, value: runtime.version)
            }
        } header: {
            Text("Ren'Py")
        } footer: {
            Text("The in-game menu button (drag it anywhere) offers quick save and load, rollback, skip, auto, hiding the interface, a variable editor for cheats and unlocking galleries. Games use the exact Ren'Py version they were made with when it is included, otherwise the newest of the same major version; change it on a game's page. Quitting a Ren'Py game currently closes EverPlay.")
        }
    }
}
