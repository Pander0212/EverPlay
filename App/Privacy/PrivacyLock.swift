import SwiftUI
import UIKit
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

/// Covers every window of EverPlay (library, web games and the Ren'Py window) the moment the app
/// leaves the foreground, before iOS takes the app-switcher snapshot. SwiftUI updates arrive too
/// late for that snapshot, so this works with UIKit views directly.
@MainActor
final class PrivacyShield {
    static let shared = PrivacyShield()
    private var covers: [UIView] = []

    func install() {
        // UIKit posts these on the main thread; handle them right away (queue nil) so the cover is
        // in place before the snapshot, also while a Ren'Py game runs the main thread.
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { PrivacyShield.shared.cover() }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { PrivacyShield.shared.uncover() }
        }
    }

    private func cover() {
        guard UserDefaults.standard.object(forKey: "privacy.cover") as? Bool ?? true, covers.isEmpty else { return }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for window in windows where !window.isHidden {
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
            blur.frame = window.bounds
            blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            let tint = UIView(frame: blur.bounds)
            tint.backgroundColor = UIColor(red: 0.043, green: 0.047, blue: 0.063, alpha: 0.7)
            tint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blur.contentView.addSubview(tint)
            let icon = UIImageView(image: UIImage(systemName: "eye.slash.fill"))
            icon.tintColor = UIColor(red: 0.56, green: 0.53, blue: 0.93, alpha: 1)
            icon.contentMode = .scaleAspectFit
            icon.frame = CGRect(x: 0, y: 0, width: 56, height: 56)
            icon.center = CGPoint(x: blur.bounds.midX, y: blur.bounds.midY)
            icon.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
            blur.contentView.addSubview(icon)
            window.addSubview(blur)
            covers.append(blur)
        }
    }

    private func uncover() {
        covers.forEach { $0.removeFromSuperview() }
        covers.removeAll()
    }
}
