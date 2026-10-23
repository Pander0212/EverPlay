import SwiftUI

@main
struct EverPlayApp: App {
    @StateObject private var library = LibraryModel()
    @StateObject private var renpy = RenPyLibrary()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(library).environmentObject(renpy)
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
