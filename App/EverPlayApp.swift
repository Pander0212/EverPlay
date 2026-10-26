import SwiftUI

@main
struct EverPlayApp: App {
    @StateObject private var library = LibraryModel()
    @StateObject private var renpy = RenPyLibrary()
    @StateObject private var privacy = PrivacyLock()
    @Environment(\.scenePhase) private var phase
    init() {
        PrivacyShield.shared.install()
        MKXPLauncher.collectPreviousLog()
        MKXPLauncher.collectSaves()
        KiriKiriEngine.collectPreviousLog()
        GodotEngine.collectPreviousLog()
    }

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(library).environmentObject(renpy)
                .overlay {
                    if privacy.locked {
                        PrivacyCover(locked: privacy.locked) { Task { await privacy.unlock() } }
                    }
                }
                .onChange(of: phase) { _, value in privacy.sceneChanged(to: value) }
                .task { if privacy.locked { await privacy.unlock() } }
                .preferredColorScheme(.dark).tint(Theme.accent)
                // "Open in EverPlay" / Share from Files or Safari: Ren'Py folders go to the Ren'Py
                // library, everything else through the checked ZIP importer.
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    Task { await GameImport.run(url, library: library, renpy: renpy) }
                }
        }
    }
}
