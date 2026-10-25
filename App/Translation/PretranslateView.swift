import SwiftUI
import EverPlayCore

struct PretranslateJob: Identifiable {
    let key: String
    let gameRoot: URL
    var id: String { key }
}

/// Translates a whole RPG Maker MV/MZ game before playing (MTool-style): every message, choice
/// and speaker name from its data files goes into the game's translation memory.
struct PretranslateView: View {
    let job: PretranslateJob
    @Environment(\.dismiss) private var dismiss
    @State private var total = 0
    @State private var done = 0
    @State private var known = 0
    @State private var state = Stage.reading
    @State private var preparing = false

    private enum Stage { case reading, running, finished, failed(String) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "text.badge.star")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                switch state {
                case .reading:
                    ProgressView("Reading the game's text…")
                case .running, .finished:
                    VStack(spacing: 10) {
                        Text(finished ? "Translation finished" : "Translating the whole game")
                            .font(.title3.weight(.bold))
                        ProgressView(value: Double(done), total: Double(max(total, 1)))
                            .tint(Theme.accent)
                        Text("\(done) of \(total) new lines · \(known) lines known")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(finished
                         ? "Play now: the translated lines appear right away."
                         : "You can close this page and even start playing; the translation continues while EverPlay is open.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                case .failed(let message):
                    Text(message).multilineTextAlignment(.center)
                }
                Spacer()
                if case .running = state {
                    Button("Stop", role: .destructive) {
                        TranslationEngine.shared.cancelBulk()
                        dismiss()
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Translate game").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .modifier(PrepareAppleTranslation(active: $preparing, source: TranslationPreferences.settings.sourceLanguage ?? "ja",
                                              target: TranslationPreferences.settings.targetLanguage))
        }
        .task { await run() }
    }

    private var finished: Bool {
        if case .finished = state { return true }
        return false
    }

    private func run() async {
        let settings = TranslationPreferences.settings
        guard settings.provider != .off else { state = .failed("Choose a translation service in Settings › Translation first."); return }
        if settings.provider == .apple {
            guard AppleTranslation.available else { state = .failed("Apple's translation needs iOS 26."); return }
            preparing = true  // iOS shows its download sheet when a language is missing
            while preparing && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(200)) }
        }
        let root = job.gameRoot
        let lines = await Task.detached(priority: .userInitiated) { () -> [String] in
            RPGMakerText.dataFolder(gameRoot: root).map(RPGMakerText.lines(dataFolder:)) ?? []
        }.value
        guard !lines.isEmpty else { state = .failed("No messages found in this game's data files."); return }
        let engine = TranslationEngine.shared
        engine.start(game: job.key, settings: settings)
        engine.translateAll(lines)
        EverPlayLog.write("Translating \(lines.count) lines of a game up front")
        state = .running
        while !Task.isCancelled {
            let progress = engine.bulkProgress
            (done, total, known) = (progress.done, progress.total, engine.knownLines)
            if progress.done >= progress.total {
                engine.flush()
                state = .finished
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
