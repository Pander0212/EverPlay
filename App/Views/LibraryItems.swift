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
    /// The player's own picture if they chose one, else the one the game ships.
    var cover: URL? {
        if let custom = CustomCovers.url(for: id) { return custom }
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
    /// The engine's symbol for generated covers.
    var symbol: String {
        switch self {
        case .renpy: return "text.bubble.fill"
        case .web(let game, _):
            switch game.engine {
            case .rpgMakerMV, .rpgMakerMZ, .rpgMaker2000, .rgss, .wolfRPG: return "map.fill"
            case .kirikiri, .onscripter: return "book.closed.fill"
            case .html5: return "globe"
            }
        }
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
        if entryPoint.lowercased().hasSuffix("rpg_rt.ldb") {
            // RPG Maker 2000/2003: the title screen picture (PNG or BMP; XYZ images cannot be shown).
            let titles = (try? FileManager.default.contentsOfDirectory(at: base.appendingPathComponent("Title"),
                                                                       includingPropertiesForKeys: nil)) ?? []
            return titles.filter { ["png", "bmp", "jpg"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }.first
        }
        if entryPoint.lowercased().hasSuffix("game.ini") {
            // RPG Maker XP/VX/VX Ace: a title picture, when the game keeps its graphics as loose files.
            for folder in ["Graphics/Titles1", "Graphics/Titles"] {
                let pictures = (try? FileManager.default.contentsOfDirectory(at: base.appendingPathComponent(folder),
                                                                             includingPropertiesForKeys: nil)) ?? []
                if let picture = pictures.filter({ ["png", "jpg"].contains($0.pathExtension.lowercased()) })
                    .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first { return picture }
            }
            return nil
        }
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

/// Pictures the player chose for games (Photos or Files), kept in Application Support. Each change
/// gets a new file name, so cached thumbnails of the old picture are not shown again.
enum CustomCovers {
    private static let key = "library.customCovers"
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EverPlay/Covers", isDirectory: true)
    }
    private static var names: [String: String] { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }

    static func url(for id: String) -> URL? {
        guard let name = names[id] else { return nil }
        let url = folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Stores the picture as a JPEG of at most 1200 pixels on its long side.
    static func set(_ image: UIImage, for id: String) throws {
        let scale = min(1, 1200 / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        remove(id)
        var all = names
        all[id] = name
        UserDefaults.standard.set(all, forKey: key)
    }

    static func remove(_ id: String) {
        var all = names
        if let old = all.removeValue(forKey: id) { try? FileManager.default.removeItem(at: folder.appendingPathComponent(old)) }
        UserDefaults.standard.set(all, forKey: key)
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
        // The picture fills the space it is given; it never decides the size (wide pictures overflowed).
        Rectangle().fill(.clear)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    GeneratedCover(title: item.title, symbol: item.symbol)
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

/// A cover for games without a picture: colours from the title, the engine's symbol large and
/// faint, and the title set like a box cover.
struct GeneratedCover: View {
    let title: String
    let symbol: String

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width, height = proxy.size.height
            let hues = Self.hues(title)
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(hue: hues.0, saturation: 0.55, brightness: 0.55),
                                        Color(hue: hues.1, saturation: 0.60, brightness: 0.22)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(hue: hues.1, saturation: 0.35, brightness: 0.95).opacity(0.45), .clear],
                               center: UnitPoint(x: 0.85, y: 0.12), startRadius: 0, endRadius: max(width, height) * 0.75)
                Image(systemName: symbol)
                    .font(.system(size: width * 0.62, weight: .bold))
                    .foregroundStyle(.white.opacity(0.13))
                    .rotationEffect(.degrees(-14))
                    .position(x: width * 0.72, y: height * 0.36)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                Text(title)
                    .font(.system(size: max(11, width * 0.13), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .padding(width * 0.09)
                    .frame(width: width, alignment: .leading)
            }
        }
    }

    private static func hues(_ title: String) -> (Double, Double) {
        var hash: UInt64 = 1469598103934665603
        for byte in title.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let first = Double(hash % 360) / 360
        let second = (first + 0.08 + Double((hash >> 16) % 10) / 100).truncatingRemainder(dividingBy: 1)
        return (first, second)
    }
}

/// A library card: cover, title, engine and version, playtime, last played and a play button.
/// The card opens the game's page; the play tile starts the game straight away.
struct GameRow: View {
    let item: LibraryItem
    let identifier: String
    var favorite = false
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if favorite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
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

/// Library filter chips.
enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, favorites, renpy, rpgMaker, novels, web

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .renpy: return "Ren'Py"
        case .rpgMaker: return "RPG Maker"
        case .novels: return "Visual novels"
        case .web: return "Web"
        }
    }

    func includes(_ item: LibraryItem) -> Bool {
        switch (self, item) {
        case (.all, _): return true
        case (.favorites, _): return FavoriteGames.contains(item.id)
        case (.renpy, .renpy): return true
        case (.rpgMaker, .web(let game, _)): return [.rpgMakerMV, .rpgMakerMZ, .rpgMaker2000, .rgss, .wolfRPG].contains(game.engine)
        case (.novels, .web(let game, _)): return [.kirikiri, .onscripter].contains(game.engine)
        case (.web, .web(let game, _)): return game.engine == .html5
        default: return false
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent, title, playtime

    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: return "Recently played"
        case .title: return "Title"
        case .playtime: return "Playtime"
        }
    }

    /// Favorites first, then this order.
    func ordered(_ items: [LibraryItem]) -> [LibraryItem] {
        items.sorted { lhs, rhs in
            let left = FavoriteGames.contains(lhs.id), right = FavoriteGames.contains(rhs.id)
            if left != right { return left }
            switch self {
            case .recent:
                switch (lhs.lastPlayed, rhs.lastPlayed) {
                case let (l?, r?) where l != r: return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
            case .playtime:
                if lhs.playSeconds != rhs.playSeconds { return lhs.playSeconds > rhs.playSeconds }
            case .title:
                break
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}

/// Favorite games stay on top of the library.
enum FavoriteGames {
    static func contains(_ id: String) -> Bool { all.contains(id) }

    static func set(_ id: String, favorite: Bool) {
        var ids = all
        if favorite { ids.insert(id) } else { ids.remove(id) }
        UserDefaults.standard.set(Array(ids), forKey: "library.favorites")
    }

    private static var all: Set<String> { Set(UserDefaults.standard.stringArray(forKey: "library.favorites") ?? []) }
}
