import Foundation
import Security
import EverPlayCore

/// Translates game lines for the embedded Ren'Py runtime, which runs on the main thread and asks
/// synchronously (through EverPlayTranslator). Requests run on URLSession's own queue, so waiting
/// here never blocks their completion. Every line is translated once per game and language and
/// kept in Application Support/Translations.
final class TranslationEngine: @unchecked Sendable {
    static let shared = TranslationEngine()

    private let condition = NSCondition()
    private var settings = TranslationSettings()
    private var key: String?
    private var cache: [String: String] = [:]
    private var pending: [String] = []
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []
    private var running = 0
    private var cacheFile: URL?
    private var dirty = false
    private var lastSave = Date.distantPast
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    var isActive: Bool {
        condition.lock(); defer { condition.unlock() }
        return settings.provider != .off && cacheFile != nil
    }

    /// Prepares translation for one game; `nil` settings switch it off.
    func start(game: String, settings: TranslationSettings?) {
        condition.lock(); defer { condition.unlock() }
        guard let settings, settings.provider != .off else {
            self.settings = TranslationSettings(); cacheFile = nil; cache = [:]
            return
        }
        self.settings = settings
        key = settings.provider.needsKey ? TranslationKeys.read(settings.provider) : nil
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Translations", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = game.replacingOccurrences(of: "/", with: "_")
        let file = folder.appendingPathComponent("\(safe).\(settings.targetLanguage.lowercased()).json")
        cacheFile = file
        cache = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))) ?? [:]
        pending = []; inFlight = []; failed = []
        EverPlayLog.write("Translation on (\(settings.provider.title) → \(settings.targetLanguage)), \(cache.count) lines known")
    }

    func cached(_ text: String) -> String? {
        condition.lock(); defer { condition.unlock() }
        return cache[text]
    }

    /// Waits up to `timeout` for a translation; nil keeps the original line.
    func translate(_ text: String, timeout: TimeInterval) -> String? {
        condition.lock()
        defer { condition.unlock() }
        if let known = cache[text] { return known }
        guard settings.provider != .off, cacheFile != nil, !failed.contains(text), Self.worthTranslating(text) else { return nil }
        enqueue([text], first: true)
        let deadline = Date().addingTimeInterval(timeout)
        while cache[text] == nil, !failed.contains(text), condition.wait(until: deadline) {}
        return cache[text]
    }

    func prefetch(_ texts: [String]) {
        condition.lock(); defer { condition.unlock() }
        guard settings.provider != .off, cacheFile != nil else { return }
        enqueue(texts.filter { cache[$0] == nil && !failed.contains($0) && Self.worthTranslating($0) }, first: false)
    }

    func flush() {
        condition.lock(); defer { condition.unlock() }
        save()
    }

    static func worthTranslating(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    // MARK: - Locked helpers

    private func enqueue(_ texts: [String], first: Bool) {
        let fresh = texts.filter { !inFlight.contains($0) && !pending.contains($0) }
        if first { pending.insert(contentsOf: fresh, at: 0) } else { pending.append(contentsOf: fresh) }
        if pending.count > 400 { pending.removeLast(pending.count - 400) }
        pump()
    }

    private func pump() {
        let parallel = settings.provider == .google ? 4 : 2
        while running < parallel, !pending.isEmpty {
            let batch = Array(pending.prefix(settings.provider.batchSize))
            pending.removeFirst(batch.count)
            inFlight.formUnion(batch)
            running += 1
            send(batch, settings: settings, key: key)
        }
    }

    private func send(_ batch: [String], settings: TranslationSettings, key: String?) {
        let masked = batch.map(TranslationMasking.mask)
        let request: URLRequest
        do { request = try TranslationAPI.request(for: masked.map { $0.masked }, settings: settings, key: key) }
        catch { finish(batch, results: nil, error: error); return }
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data, error == nil, (200..<300).contains(status) else {
                self.locked { self.finish(batch, results: nil, error: error ?? URLError(.badServerResponse, userInfo: ["status": status])) }
                return
            }
            let lines = try? TranslationAPI.parse(data, provider: settings.provider, count: batch.count)
            let results = lines.map { lines in
                zip(lines, masked).map { line, mask in TranslationMasking.unmask(line, tokens: mask.tokens) }
            }
            self.locked { self.finish(batch, results: results, error: lines == nil ? TranslationError.badResponse : nil) }
        }.resume()
    }

    private func locked(_ work: () -> Void) {
        condition.lock(); work(); condition.unlock()
    }

    private func finish(_ batch: [String], results: [String?]?, error: Error?) {
        running = max(0, running - 1)
        inFlight.subtract(batch)
        if let results {
            for (source, translated) in zip(batch, results) {
                if let translated { cache[source] = translated } else { failed.insert(source) }
            }
            dirty = true
            if Date().timeIntervalSince(lastSave) > 10 { save() }
        } else {
            failed.formUnion(batch)
            EverPlayLog.write("Translation request failed (\(settings.provider.title)): \(error.map { "\($0)" } ?? "unknown")")
        }
        condition.broadcast()
        pump()
    }

    private func save() {
        guard dirty, let cacheFile, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheFile, options: .atomic)
        dirty = false
        lastSave = Date()
    }
}

/// The Objective-C face of the engine for the Ren'Py runtime (pyobjus: autoclass("EverPlayTranslator")).
@objc(EverPlayTranslator)
final class EverPlayTranslator: NSObject {
    /// Translation or "" (keep the original), waiting briefly for the service.
    @objc static func translate(_ text: String) -> String {
        TranslationEngine.shared.translate(text, timeout: 2.5) ?? ""
    }

    /// Translation if already known, else "" (used while skipping).
    @objc static func cached(_ text: String) -> String {
        TranslationEngine.shared.cached(text) ?? ""
    }

    /// Lines coming up next, separated by U+001E.
    @objc static func prefetch(_ joined: String) {
        TranslationEngine.shared.prefetch(joined.components(separatedBy: "\u{1E}").filter { !$0.isEmpty })
    }
}

/// API keys for translation services, kept in the Keychain (this device only).
enum TranslationKeys {
    private static let service = "app.everplay.translation"

    static func read(_ provider: TranslationProvider) -> String? {
        var item: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: provider.rawValue, kSecReturnData as String: true]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, for provider: TranslationProvider) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: provider.rawValue]
        SecItemDelete(query as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// The translation settings chosen in Settings, and which games use them.
enum TranslationPreferences {
    static var settings: TranslationSettings {
        get {
            guard let data = UserDefaults.standard.data(forKey: "translation.settings"),
                  let value = try? JSONDecoder().decode(TranslationSettings.self, from: data) else { return TranslationSettings() }
            return value
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "translation.settings") }
    }

    static func isEnabled(for game: String) -> Bool {
        (UserDefaults.standard.dictionary(forKey: "translation.games") as? [String: Bool])?[game] ?? false
    }

    static func setEnabled(_ on: Bool, for game: String) {
        var all = UserDefaults.standard.dictionary(forKey: "translation.games") as? [String: Bool] ?? [:]
        all[game] = on
        UserDefaults.standard.set(all, forKey: "translation.games")
    }
}
