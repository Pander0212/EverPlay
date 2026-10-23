import SwiftUI

@main
struct EverPlayApp: App {
    @StateObject private var library = LibraryModel()
    @StateObject private var plugins = PluginStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(library).environmentObject(plugins)
                .preferredColorScheme(.dark).tint(Theme.accent)
                // A plugin returns with everplay://library after its game ends.
                .onOpenURL { _ in plugins.refresh() }
        }
    }
}
