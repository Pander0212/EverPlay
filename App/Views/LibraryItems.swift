import SwiftUI
import UIKit
import EverPlayCore

/// One row in the library, whatever engine runs it.
enum LibraryItem: Identifiable {
    case web(GameRecord, cover: URL?)
    case renpy(RenPyTitle)

    var id: String {
        switch self {
        case .web(let game, _): return "web-\(game.id.uuidString)"
        case .renpy(let game): return "renpy-\(game.folder)"
        }
    }
    var title: String {
        switch self {
        case .web(let game, _): return game.title
        case .renpy(let game): return game.title
        }
    }
    var engineLabel: String {
        switch self {
        case .web(let game, _): return game.engine.title
        case .renpy(let game): return game.engineVersion.map { "Ren'Py \($0)" } ?? "Ren'Py"
        }
    }
    var runtimeLabel: String? {
        guard case .renpy(let game) = self else { return nil }
        return game.runtime.map { "runs on \($0.version)" } ?? "no matching runtime"
    }
    var cover: URL? {
        switch self {
        case .web(_, let cover): return cover
        case .renpy(let game): return game.cover
        }
    }
    var lastPlayed: Date? {
        switch self {
        case .web(let game, _): return game.lastPlayedAt
        case .renpy(let game): return game.lastPlayed
        }
    }
    var playSeconds: Double {
        switch self {
        case .web(let game, _): return game.playSeconds
        case .renpy(let game): return game.playSeconds
        }
    }
    var playtime: String {
        let seconds = Int(playSeconds)
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return "\(seconds / 3600) h \(seconds % 3600 / 60) min"
    }
    var tint: Color {
        switch self {
        case .web(let game, _): return Theme.engineColor(game.engine)
        case .renpy: return Color(red: 0.93, green: 0.78, blue: 0.40)
        }
    }
}

/// Finds a picture a web or RPG Maker game ships as a loose file (never decrypts or executes).
enum WebCover {
    static func locate(in gameDirectory: URL, entryPoint: String) -> URL? {
        let base = gameDirectory.appendingPathComponent(entryPoint).deletingLastPathComponent()
        var candidates = ["icon/icon.png", "www/icon/icon.png", "favicon.png", "img/icon.png"]
        // RPG Maker MV/MZ: the title screen picture named in data/System.json.
        for data in ["data/System.json", "www/data/System.json"] {
            if let json = try? Data(contentsOf: base.appendingPathComponent(data)),
               let system = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
               let title = system["title1Name"] as? String, !title.isEmpty {
                let folder = data.hasPrefix("www/") ? "www/img/titles1" : "img/titles1"
                candidates.insert("\(folder)/\(title).png", at: 0)
            }
        }
        return candidates.map { base.appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// Loads covers off the main thread, downsampled and cached.
enum CoverCache {
    private static let cache = NSCache<NSURL, UIImage>()

    static func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let full = UIImage(contentsOfFile: url.path) else { return nil }
            return full.preparingThumbnail(of: CGSize(width: 360, height: 480)) ?? full
        }.value
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

struct CoverView: View {
    let item: LibraryItem
    var cornerRadius: CGFloat = 18
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.cover(for: item.title)
                LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
                Text(Theme.initials(item.title))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        .task(id: item.cover) {
            image = nil
            if let cover = item.cover { image = await CoverCache.image(for: cover) }
        }
        .accessibilityHidden(true)
    }
}

/// A library card: cover, title, engine and version, playtime, last played and a play button.
/// The card opens the game's page; the play tile starts the game straight away.
struct GameRow: View {
    let item: LibraryItem
    let identifier: String
    let open: () -> Void
    let play: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) { summary }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("details-\(item.title)")
                .accessibilityHint("Shows details and options")
            Button(action: play) {
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 84)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Theme.accent.opacity(0.45), radius: 12, y: 4)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Play \(item.title)")
            .accessibilityIdentifier(identifier)
        }
        .padding(14)
        .surface(cornerRadius: 26)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var summary: some View {
        HStack(spacing: 16) {
            CoverView(item: item)
                .frame(width: 86, height: 114)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(item.engineLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .foregroundStyle(item.tint)
                        .background(item.tint.opacity(0.16), in: Capsule())
                    if let runtime = item.runtimeLabel {
                        Text(runtime).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                HStack(spacing: 12) {
                    Label(item.playtime, systemImage: "clock").lineLimit(1)
                    Label {
                        if let last = item.lastPlayed {
                            Text(last, format: .relative(presentation: .named))
                        } else {
                            Text("Never")
                        }
                    } icon: { Image(systemName: "calendar") }
                    .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
