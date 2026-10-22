import SwiftUI

@main
struct EverPlayApp: App {
    @StateObject private var library = LibraryModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(library).preferredColorScheme(.dark).tint(Theme.accent)
        }
    }
}
