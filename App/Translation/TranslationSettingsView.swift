import SwiftUI
import EverPlayCore

/// Settings › Translation: service, target language, model and API key.
struct TranslationSettingsSection: View {
    @State private var settings = TranslationPreferences.settings
    @State private var key = ""

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
            return "Translate games while you play, MTool-style. Turn it on per game on the game's page (Ren'Py for now)."
        case .google:
            return "Free and without a key, through Google Translate's public web endpoint (unofficial; it may limit heavy use). Game text is sent to Google."
        case .deepL:
            return "Uses your DeepL API key (the free plan works). Game text is sent to DeepL. Keys stay in this device's Keychain."
        case .openAI:
            return "Any OpenAI-compatible service with your key: OpenAI, OpenRouter, a local LM Studio or Ollama server. Game text is sent to it. Keys stay in this device's Keychain."
        case .anthropic:
            return "Claude with your Anthropic API key; you can enter a cheaper model such as claude-haiku-5-5. Game text is sent to Anthropic. Keys stay in this device's Keychain."
        }
    }
}
