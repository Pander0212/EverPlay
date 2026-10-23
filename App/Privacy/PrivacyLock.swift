import SwiftUI
import LocalAuthentication

/// Discretion: an optional Face ID / passcode lock and a cover over EverPlay in the app switcher.
@MainActor
final class PrivacyLock: ObservableObject {
    @Published private(set) var locked: Bool

    static var lockEnabled: Bool { UserDefaults.standard.bool(forKey: "privacy.lock") }

    init() { locked = Self.lockEnabled }

    func sceneChanged(to phase: ScenePhase) {
        if phase == .background && Self.lockEnabled { locked = true }
    }

    func unlock() async {
        let context = LAContext()
        var problem: NSError?
        // Without Face ID, Touch ID or a passcode there is nothing to check against.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problem) else { locked = false; return }
        if (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your library")) == true {
            locked = false
        }
    }
}

/// Hidden games stay out of the library list until "Show hidden games" is on.
enum HiddenGames {
    static func contains(_ id: String) -> Bool { all.contains(id) }

    static func set(_ id: String, hidden: Bool) {
        var ids = all
        if hidden { ids.insert(id) } else { ids.remove(id) }
        UserDefaults.standard.set(Array(ids), forKey: "library.hidden")
    }

    private static var all: Set<String> { Set(UserDefaults.standard.stringArray(forKey: "library.hidden") ?? []) }
}

struct PrivacyCover: View {
    let locked: Bool
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Theme.background.opacity(0.85)
            VStack(spacing: 18) {
                Image(systemName: locked ? "lock.fill" : "eye.slash.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("EverPlay").font(.title2.weight(.bold))
                if locked {
                    Button("Unlock", action: unlock)
                        .buttonStyle(GlowButtonStyle())
                        .frame(maxWidth: 220)
                        .accessibilityIdentifier("unlockLibrary")
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Settings › Privacy.
struct PrivacySettingsSection: View {
    @AppStorage("privacy.lock") private var lock = false
    @AppStorage("privacy.cover") private var cover = true
    @AppStorage("library.showHidden") private var showHidden = false

    var body: some View {
        Section {
            Toggle("Lock with Face ID or passcode", isOn: $lock)
            Toggle("Hide EverPlay in the app switcher", isOn: $cover)
            Toggle("Show hidden games", isOn: $showHidden)
        } header: {
            Text("Privacy")
        } footer: {
            Text("The lock asks when you return to EverPlay. Hide a game with a long press on it in the library.")
        }
    }
}
