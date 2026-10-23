import SwiftUI

@main
struct EverPlayApp: App {
    @StateObject private var library = LibraryModel()
    @StateObject private var renpy = RenPyLibrary()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(library).environmentObject(renpy)
                .preferredColorScheme(.dark).tint(Theme.accent)
        }
    }
}
