import SwiftUI
#if canImport(Translation)
import Translation
#endif
import EverPlayCore

/// Settings › Translation: service, target language, model and API key.
struct TranslationSettingsSection: View {
    @State private var settings = TranslationPreferences.settings
    @State private var key = ""
    @State private var preparing = false

    private static let languages: [(String, String)] = [
        ("de", "German"), ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("it", "Italian"),
        ("pt", "Portuguese"), ("pl", "Polish"), ("nl", "Dutch"), ("tr", "Turkish"), ("ru", "Russian"),
        ("uk", "Ukrainian"), ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"), ("id", "Indonesian"),
        ("vi", "Vietnamese"), ("ar", "Arabic"),
    ]

    var body: some View {
        Section {
            Picker("Service", selection: $settings.provider) {
                ForEach(TranslationProvider.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("translationService")
            if settings.provider != .off {
                Picker("Translate into", selection: $settings.targetLanguage) {
                    ForEach(Self.languages, id: \.0) { language in Text(language.1).tag(language.0) }
                }
            }
            if settings.provider == .apple {
                Picker("Games are in", selection: Binding(get: { settings.sourceLanguage ?? "" },
                                                          set: { settings.sourceLanguage = $0.isEmpty ? nil : $0 })) {
                    Text("Detect automatically").tag("")
                    ForEach(Self.languages, id: \.0) { language in Text(language.1).tag(language.0) }
                }
                if AppleTranslation.available {
                    Button(preparing ? "Downloading…" : "Download languages", systemImage: "arrow.down.circle") { preparing = true }
                        .disabled(preparing)
                        .modifier(PrepareAppleTranslation(active: $preparing, source: settings.sourceLanguage ?? "ja",
                                                          target: settings.targetLanguage))
                }
            }
            if settings.provider.needsKey {
                SecureField(settings.provider == .deepL ? "DeepL API key" : "API key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { TranslationKeys.write(key, for: settings.provider) }
            }
            if settings.provider == .openAI || settings.provider == .anthropic {
                TextField("Model (default \(TranslationSettings(provider: settings.provider).effectiveModel))", text: $settings.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if settings.provider == .openAI {
                TextField("Base URL (default https://api.openai.com/v1)", text: $settings.baseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Translation")
        } footer: {
            Text(footer)
        }
        .onChange(of: settings) { _, value in TranslationPreferences.settings = value }
        .onChange(of: settings.provider) { _, provider in key = TranslationKeys.read(provider) ?? "" }
        .onChange(of: key) { _, value in TranslationKeys.write(value, for: settings.provider) }
        .onAppear { key = TranslationKeys.read(settings.provider) ?? "" }
    }

    private var footer: String {
        switch settings.provider {
        case .off:
            return "Translate games while you play, MTool-style. Turn it on per game on the game's page (Ren'Py and RPG Maker MV/MZ)."
        case .google:
            return "Free and without a key, through Google Translate's public web endpoint (unofficial; it may limit heavy use). Game text is sent to Google."
        case .deepL:
            return "Uses your DeepL API key (the free plan works). Game text is sent to DeepL. Keys stay in this device's Keychain."
        case .openAI:
            return "Any OpenAI-compatible service with your key: OpenAI, OpenRouter, a local LM Studio or Ollama server. Game text is sent to it. Keys stay in this device's Keychain."
        case .apple:
            return AppleTranslation.available
                ? "Free, offline and private: Apple's translation on this iPhone. Download the game's language and yours once (Download languages; with “Detect automatically” it downloads Japanese). Translations are a little plainer than DeepL or Claude."
                : "Apple's translation needs iOS 26 here. Choose another service."
        case .anthropic:
            return "Claude with your Anthropic API key; you can enter a cheaper model such as claude-haiku-5-5. Game text is sent to Anthropic. Keys stay in this device's Keychain."
        }
    }
}

enum AppleTranslation {
    /// Translating outside SwiftUI (TranslationSession for installed languages) needs iOS 26.
    static var available: Bool {
        #if canImport(Translation) && compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }
}

/// Asks iOS to download the languages for Apple's translation (its own download sheet).
struct PrepareAppleTranslation: ViewModifier {
    @Binding var active: Bool
    let source: String
    let target: String

    func body(content: Content) -> some View {
        #if canImport(Translation) && compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.translationTask(active ? TranslationSession.Configuration(source: Locale.Language(identifier: source),
                                                                               target: Locale.Language(identifier: target)) : nil) { session in
                do {
                    try await session.prepareTranslation()
                } catch {
                    EverPlayLog.write("Apple translation: languages not downloaded: \(error.localizedDescription)")
                }
                await MainActor.run { active = false }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
