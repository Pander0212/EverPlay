import XCTest
@testable import EverPlayCore

final class TranslationTests: XCTestCase {
    func testMaskingKeepsRenPyAndRPGMakerMarkup() throws {
        let line = "{b}Hello{/b}, [player_name]! \\C[2]Gold\\C[0] \\."
        let (masked, tokens) = TranslationMasking.mask(line)
        XCTAssertEqual(masked, "⟦0⟧Hello⟦1⟧, ⟦2⟧! ⟦3⟧Gold⟦4⟧ ⟦5⟧")
        XCTAssertEqual(tokens, ["{b}", "{/b}", "[player_name]", "\\C[2]", "\\C[0]", "\\."])
        let translated = "⟦0⟧Hallo⟦1⟧, ⟦2⟧! ⟦3⟧Gold⟦4⟧ ⟦5⟧"
        XCTAssertEqual(TranslationMasking.unmask(translated, tokens: tokens), "{b}Hallo{/b}, [player_name]! \\C[2]Gold\\C[0] \\.")
        XCTAssertNil(TranslationMasking.unmask("Hallo", tokens: tokens), "a lost placeholder keeps the original line")
        XCTAssertEqual(TranslationMasking.mask("Plain text").tokens, [])
    }

    func testOpenAICompatibleBaseURLWithOrWithoutTheEndpoint() throws {
        for base in ["https://api.electronhub.ai/v1", "https://api.electronhub.ai/v1/", "https://api.electronhub.ai/v1/chat/completions"] {
            let settings = TranslationSettings(provider: .openAI, targetLanguage: "de", model: "m", baseURL: base)
            let request = try TranslationAPI.request(for: ["Hi"], settings: settings, key: "k")
            XCTAssertEqual(request.url?.absoluteString, "https://api.electronhub.ai/v1/chat/completions", base)
        }
    }

    func testGoogleRequestAndReply() throws {
        let settings = TranslationSettings(provider: .google, targetLanguage: "DE")
        let request = try TranslationAPI.request(for: ["Good morning"], settings: settings, key: nil)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "tl" }?.value, "de")
        XCTAssertEqual(query.first { $0.name == "q" }?.value, "Good morning")
        let reply = #"[[["Guten ","Good ",null,null,10],["Morgen","morning",null,null,10]],null,"en"]"#
        XCTAssertEqual(try TranslationAPI.parse(Data(reply.utf8), provider: .google, count: 1), ["Guten Morgen"])
    }

    func testDeepLUsesTheFreeHostForFreeKeys() throws {
        let settings = TranslationSettings(provider: .deepL, targetLanguage: "de")
        let request = try TranslationAPI.request(for: ["a", "b"], settings: settings, key: "abc:fx")
        XCTAssertEqual(request.url?.host, "api-free.deepl.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "DeepL-Auth-Key abc:fx")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["target_lang"] as? String, "DE")
        let reply = #"{"translations":[{"text":"A"},{"text":"B"}]}"#
        XCTAssertEqual(try TranslationAPI.parse(Data(reply.utf8), provider: .deepL, count: 2), ["A", "B"])
        XCTAssertThrowsError(try TranslationAPI.request(for: ["a"], settings: settings, key: nil))
    }

    func testLanguageModelRepliesAreReadFromTheirJSONArray() throws {
        let openAI = #"{"choices":[{"message":{"content":"```json\n[\"Hallo\", \"Tschüss\"]\n```"}}]}"#
        XCTAssertEqual(try TranslationAPI.parse(Data(openAI.utf8), provider: .openAI, count: 2), ["Hallo", "Tschüss"])
        let claude = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"[\"Hallo\"]"}],"stop_reason":"end_turn"}"#
        XCTAssertEqual(try TranslationAPI.parse(Data(claude.utf8), provider: .anthropic, count: 1), ["Hallo"])
        XCTAssertThrowsError(try TranslationAPI.parse(Data(claude.utf8), provider: .anthropic, count: 2)) { error in
            XCTAssertEqual(error as? TranslationError, .countMismatch)
        }
    }

    func testClaudeRequestUsesTheCurrentAPIVersionWithoutSampling() throws {
        let settings = TranslationSettings(provider: .anthropic, targetLanguage: "de")
        let request = try TranslationAPI.request(for: ["Hi"], settings: settings, key: "k")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertNil(body["temperature"])
        let openAI = TranslationSettings(provider: .openAI, targetLanguage: "de", model: "", baseURL: "https://openrouter.ai/api/v1/")
        XCTAssertEqual(try TranslationAPI.request(for: ["Hi"], settings: openAI, key: "k").url?.absoluteString,
                       "https://openrouter.ai/api/v1/chat/completions")
    }
}
