import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Machine translation of game text (MTool-style): which service, into which language.
public enum TranslationProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case off, google, deepL, openAI, anthropic, apple

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: return "Off"
        case .google: return "Google (free)"
        case .deepL: return "DeepL"
        case .openAI: return "OpenAI-compatible"
        case .anthropic: return "Claude"
        case .apple: return "Apple (on device)"
        }
    }

    public var needsKey: Bool { self == .deepL || self == .openAI || self == .anthropic }
    /// Lines sent per request. Google's free endpoint takes one text at a time.
    public var batchSize: Int { self == .google ? 1 : 20 }
}

public struct TranslationSettings: Codable, Equatable, Sendable {
    public var provider: TranslationProvider
    /// ISO 639-1 code, e.g. "de".
    public var targetLanguage: String
    /// Model for the LLM services.
    public var model: String
    /// Base URL of an OpenAI-compatible service (OpenAI, OpenRouter, a local server, ...).
    public var baseURL: String
    /// The games' language for Apple's translation (ISO 639-1); nil or "" detects it per batch.
    public var sourceLanguage: String?

    public init(provider: TranslationProvider = .off, targetLanguage: String = "de", model: String = "", baseURL: String = "") {
        self.provider = provider
        self.targetLanguage = targetLanguage
        self.model = model
        self.baseURL = baseURL
    }

    public var effectiveModel: String {
        if !model.trimmingCharacters(in: .whitespaces).isEmpty { return model.trimmingCharacters(in: .whitespaces) }
        switch provider {
        case .openAI: return "gpt-4o-mini"
        case .anthropic: return "claude-opus-5-5"
        default: return ""
        }
    }
}

public enum TranslationError: Error, Equatable {
    case missingKey, badResponse, countMismatch
}

/// Keeps engine markup out of the translator's hands: Ren'Py text tags ({b}, {color=...}),
/// substitutions ([name]) and RPG Maker escapes (\C[2], \N[1]) become numbered placeholders.
public enum TranslationMasking {
    private static let pattern = try! NSRegularExpression(pattern: #"\{[^{}]*\}|\[[^\[\]]*\]|\\[A-Za-z]+\[[^\]]*\]|\\[{}.|!><^$]"#)

    public static func placeholder(_ index: Int) -> String { "⟦\(index)⟧" }

    public static func mask(_ text: String) -> (masked: String, tokens: [String]) {
        let source = text as NSString
        var tokens: [String] = []
        var masked = ""
        var position = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            masked += source.substring(with: NSRange(location: position, length: match.range.location - position))
            masked += placeholder(tokens.count)
            tokens.append(source.substring(with: match.range))
            position = match.range.location + match.range.length
        }
        masked += source.substring(from: position)
        return (masked, tokens)
    }

    /// nil when the translation lost a placeholder; the caller then keeps the original line.
    public static func unmask(_ text: String, tokens: [String]) -> String? {
        var result = text
        for (index, token) in tokens.enumerated() {
            let marker = placeholder(index)
            guard result.contains(marker) else { return nil }
            result = result.replacingOccurrences(of: marker, with: token)
        }
        return result
    }
}

/// Builds requests for each service and reads their replies. Pure, so it is unit tested.
public enum TranslationAPI {
    static func instructions(_ language: String) -> String {
        "You translate lines of dialogue and menu text from a video game into the language with the code \"\(language)\". "
        + "The user message is a JSON array of strings. Reply with only a JSON array of strings of the same length "
        + "and order, one translation per line. Keep placeholders like ⟦0⟧ exactly as they are, keep names, "
        + "tone and line breaks, and add no notes. Return a line unchanged if it is already in that language."
    }

    public static func request(for texts: [String], settings: TranslationSettings, key: String?) throws -> URLRequest {
        let language = settings.targetLanguage.trimmingCharacters(in: .whitespaces).lowercased()
        switch settings.provider {
        case .off, .apple:
            // Apple's translation runs on the device (TranslationEngine), not over HTTP.
            throw TranslationError.badResponse
        case .google:
            var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
            components.queryItems = [URLQueryItem(name: "client", value: "gtx"), URLQueryItem(name: "sl", value: "auto"),
                                     URLQueryItem(name: "tl", value: language), URLQueryItem(name: "dt", value: "t"),
                                     URLQueryItem(name: "q", value: texts.joined(separator: "\n"))]
            return URLRequest(url: components.url!)
        case .deepL:
            guard let key, !key.isEmpty else { throw TranslationError.missingKey }
            let host = key.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
            var request = URLRequest(url: URL(string: "https://\(host)/v2/translate")!)
            request.httpMethod = "POST"
            request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "text": texts, "target_lang": language.uppercased(), "preserve_formatting": true,
            ])
            return request
        case .openAI:
            guard let key, !key.isEmpty else { throw TranslationError.missingKey }
            var base = settings.baseURL.trimmingCharacters(in: .whitespaces).isEmpty
                ? "https://api.openai.com/v1" : settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            // The full endpoint pasted as base URL works too.
            if base.lowercased().hasSuffix("/chat/completions") { base.removeLast("/chat/completions".count) }
            guard let url = URL(string: base + "/chat/completions") else { throw TranslationError.badResponse }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": settings.effectiveModel,
                "messages": [["role": "system", "content": instructions(language)],
                             ["role": "user", "content": try json(texts)]],
            ])
            return request
        case .anthropic:
            guard let key, !key.isEmpty else { throw TranslationError.missingKey }
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": settings.effectiveModel,
                "max_tokens": 16000,
                "output_config": ["effort": "low"],
                "system": instructions(language),
                "messages": [["role": "user", "content": try json(texts)]],
            ])
            return request
        }
    }

    public static func parse(_ data: Data, provider: TranslationProvider, count: Int) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: data)
        let lines: [String]
        switch provider {
        case .off, .apple:
            throw TranslationError.badResponse
        case .google:
            // [[["Hallo","Hello",...],["Welt","World",...]], ...]: the pieces of one text.
            guard let root = object as? [Any], let pieces = root.first as? [Any] else { throw TranslationError.badResponse }
            let text = pieces.compactMap { ($0 as? [Any])?.first as? String }.joined()
            lines = count == 1 ? [text] : text.components(separatedBy: "\n")
        case .deepL:
            guard let root = object as? [String: Any], let items = root["translations"] as? [[String: Any]] else {
                throw TranslationError.badResponse
            }
            lines = items.compactMap { $0["text"] as? String }
        case .openAI:
            guard let root = object as? [String: Any], let choices = root["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any], let content = message["content"] as? String else {
                throw TranslationError.badResponse
            }
            lines = try array(in: content)
        case .anthropic:
            guard let root = object as? [String: Any], let blocks = root["content"] as? [[String: Any]] else {
                throw TranslationError.badResponse
            }
            let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            lines = try array(in: text)
        }
        guard lines.count == count else { throw TranslationError.countMismatch }
        return lines
    }

    static func json(_ texts: [String]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: texts), as: UTF8.self)
    }

    /// The JSON array in a model reply, also when it is wrapped in a code fence or prose.
    static func array(in reply: String) throws -> [String] {
        guard let start = reply.firstIndex(of: "["), let end = reply.lastIndex(of: "]"), start < end,
              let strings = try JSONSerialization.jsonObject(with: Data(reply[start...end].utf8)) as? [String] else {
            throw TranslationError.badResponse
        }
        return strings
    }
}

/// The text RPG Maker MV/MZ games show in message windows, read from their data files before
/// playing, so a whole game can be translated up front. The lines are the same strings
/// RPGMakerTranslate.js asks for while playing: message and scrolling text lines (401, 405),
/// choices (102) and MZ speaker names (101).
public enum RPGMakerText {
    /// The game's data folder (data/ or www/data/ next to index.html).
    public static func dataFolder(gameRoot: URL) -> URL? {
        ["data", "www/data"].map { gameRoot.appendingPathComponent($0, isDirectory: true) }
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("System.json").path) }
    }

    /// Every line, once, in the order the files list them.
    public static func lines(dataFolder: URL) -> [String] {
        let files = ((try? FileManager.default.contentsOfDirectory(at: dataFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var seen = Set<String>(), out: [String] = []
        func add(_ text: Any?) {
            guard let text = text as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty, seen.insert(text).inserted else { return }
            out.append(text)
        }
        func walk(_ value: Any) {
            if let list = value as? [Any] {
                list.forEach(walk)
            } else if let object = value as? [String: Any] {
                if let code = object["code"] as? Int, let parameters = object["parameters"] as? [Any] {
                    switch code {
                    case 401, 405: add(parameters.first)
                    case 102: (parameters.first as? [Any])?.forEach(add)
                    case 101 where parameters.count > 4: add(parameters[4])
                    default: break
                    }
                    return
                }
                object.values.forEach(walk)
            }
        }
        for file in files {
            guard let data = try? Data(contentsOf: file), let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            walk(json)
        }
        return out
    }
}
