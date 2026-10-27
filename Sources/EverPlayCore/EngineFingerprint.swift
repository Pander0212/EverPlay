import Foundation

/// What a game was made with, told from its file names alone (nothing is opened or run), also for
/// engines EverPlay cannot play: the import then says what the game is instead of only "not supported".
public struct EngineReport: Equatable, Sendable {
    /// The engine's name, e.g. "Unity".
    public let engine: String
    /// Whether EverPlay plays games of this engine.
    public let playable: Bool
    /// What it means for playing on iPhone.
    public let outlook: String
    /// A few of the files that gave it away.
    public let evidence: [String]
}

public enum EngineFingerprint {
    private struct Rule {
        let engine: String
        let playable: Bool
        let outlook: String
        /// Lowercased relative path → whether it is a sign of the engine.
        let matches: (String) -> Bool
    }

    private static func name(_ path: String) -> String { (path as NSString).lastPathComponent }
    private static func ext(_ path: String) -> String { (path as NSString).pathExtension }

    /// Most specific first: engines built on others (RPG Maker on NW.js, TyranoScript on HTML) come
    /// before the base they share.
    private static let rules: [Rule] = [
        Rule(engine: "Ren'Py", playable: true, outlook: "EverPlay plays Ren'Py 6–8 games.") {
            ext($0) == "rpa" || ext($0) == "rpyc" || $0.hasPrefix("renpy/") || $0.contains("/renpy/")
        },
        Rule(engine: "RPG Maker MZ", playable: true, outlook: "EverPlay plays RPG Maker MZ games.") { $0.hasSuffix("js/rmmz_core.js") },
        Rule(engine: "RPG Maker MV", playable: true, outlook: "EverPlay plays RPG Maker MV games.") { $0.hasSuffix("js/rpg_core.js") },
        Rule(engine: "RPG Maker 2000/2003", playable: true, outlook: "EverPlay plays these with EasyRPG Player.") { name($0) == "rpg_rt.ldb" },
        Rule(engine: "RPG Maker XP/VX/VX Ace", playable: true, outlook: "EverPlay plays these with mkxp-z.") {
            ["game.rgssad", "game.rgss2a", "game.rgss3a", "scripts.rxdata", "scripts.rvdata", "scripts.rvdata2"].contains(name($0))
        },
        Rule(engine: "KiriKiri", playable: true, outlook: "EverPlay plays KiriKiri games; encrypted ones need their key from GARbro's list.") {
            ext($0) == "xp3" || name($0) == "startup.tjs"
        },
        Rule(engine: "ONScripter / NScripter", playable: true, outlook: "EverPlay plays ONScripter games.") {
            ["0.txt", "00.txt", "nscript.dat", "nscr_sec.dat", "onscript.nt2", "onscript.nt3"].contains(name($0))
        },
        Rule(engine: "Wolf RPG Editor", playable: true,
             outlook: "EverPlay plays WOLF RPG Editor games with its own engine (experimental).") {
            ext($0) == "wolf" || WolfGame.marker($0)
        },
        Rule(engine: "Unity", playable: false,
             outlook: "Unity games are compiled for Windows, Mac or Android; only a version the developer builds for iOS can run on iPhone.") {
            ["unityplayer.dll", "unitycrashhandler64.exe", "unitycrashhandler32.exe", "globalgamemanagers", "data.unity3d"].contains(name($0))
                || $0.hasSuffix("managed/assembly-csharp.dll") || ext($0) == "assets" && $0.contains("_data/")
        },
        Rule(engine: "Unreal Engine", playable: false,
             outlook: "Unreal games are compiled for Windows; they cannot run on iPhone without the developer's iOS build.") {
            ($0.contains("/content/paks/") && ext($0) == "pak") || $0.hasPrefix("engine/binaries/") || $0.contains("/engine/binaries/")
        },
        Rule(engine: "Godot", playable: false,
             outlook: "Godot keeps the game in a .pck file; a Godot player of the same version could run it on iPhone (not in EverPlay yet).") {
            ext($0) == "pck" || name($0) == "project.godot"
        },
        Rule(engine: "GameMaker", playable: false,
             outlook: "GameMaker games are compiled into data.win for Windows; there is no player for iPhone.") {
            name($0) == "data.win" || (name($0).hasPrefix("audiogroup") && ext($0) == "dat")
        },
        Rule(engine: "SRPG Studio", playable: false, outlook: "SRPG Studio games run only on Windows.") { name($0) == "data.dts" },
        Rule(engine: "SiglusEngine", playable: false,
             outlook: "A SiglusEngine player for iPhone exists (siglus_rs); EverPlay does not include it yet.") {
            name($0) == "scene.pck" || name($0) == "gameexe.dat"
        },
        Rule(engine: "RealLive", playable: false, outlook: "RealLive visual novels are not supported yet.") {
            name($0) == "seen.txt" || name($0) == "gameexe.ini"
        },
        Rule(engine: "Artemis", playable: false, outlook: "Artemis visual novels are not supported yet.") {
            ext($0) == "pfs" || ext($0).hasPrefix("pfs.")
        },
        Rule(engine: "CatSystem2", playable: false, outlook: "CatSystem2 visual novels are not supported yet.") {
            ext($0) == "int" && name($0) != "desktop.int" || name($0) == "cs2.exe"
        },
        Rule(engine: "Adventure Game Studio", playable: false,
             outlook: "AGS games could run with an AGS or ScummVM player for iPhone; EverPlay does not include one yet.") {
            name($0) == "acsetup.cfg" || ext($0) == "ags"
        },
        Rule(engine: "Adobe Flash", playable: false,
             outlook: "Flash games could run with the Ruffle emulator; EverPlay does not include it yet.") {
            ext($0) == "swf" || $0.hasSuffix("meta-inf/air/application.xml")
        },
        Rule(engine: "QSP", playable: false, outlook: "QSP text games need a QSP player, which EverPlay does not include yet.") {
            ext($0) == "qsp"
        },
        Rule(engine: "LÖVE", playable: false,
             outlook: "LÖVE (Lua) games could run with the LÖVE player for iPhone; EverPlay does not include it yet.") {
            ext($0) == "love" || name($0) == "love.dll"
        },
        Rule(engine: "XNA / MonoGame / FNA", playable: false, outlook: "These C# games are built for Windows and cannot run on iPhone.") {
            ext($0) == "xnb"
        },
        Rule(engine: "Clickteam Fusion", playable: false, outlook: "Clickteam Fusion games run only on Windows.") {
            ext($0) == "mfx" || name($0) == "mmfs2.dll"
        },
        Rule(engine: "Java", playable: false, outlook: "Java games cannot run on iPhone.") { ext($0) == "jar" },
        Rule(engine: "Python / Pygame", playable: false, outlook: "Python desktop games other than Ren'Py cannot run on iPhone.") {
            name($0).hasPrefix("python3") && ext($0) == "dll" || $0.contains("/pygame/")
        },
        Rule(engine: "Android app", playable: false, outlook: "Android apps cannot run on iPhone.") { ext($0) == "apk" },
        Rule(engine: "HTML5", playable: true,
             outlook: "Browser games (TyranoScript, Construct, Twine and others) play in EverPlay.") {
            ["html", "htm"].contains(ext($0)) && name($0) != "credits.html" || name($0) == "package.nw" || name($0) == "app.asar"
        },
    ]

    /// Which scripting backend a Windows Unity build uses, told from its files: IL2CPP builds carry
    /// GameAssembly.dll and il2cpp_data, Mono builds Managed/Assembly-CSharp.dll and MonoBleedingEdge.
    static func unityBackend(_ lowered: [String]) -> String? {
        if lowered.contains(where: { name($0) == "gameassembly.dll" || $0.hasSuffix("il2cpp_data/metadata/global-metadata.dat") }) {
            return "IL2CPP"
        }
        if lowered.contains(where: { $0.hasSuffix("managed/assembly-csharp.dll") || $0.contains("monobleedingedge/") }) {
            return "Mono"
        }
        return nil
    }

    /// Windows Unity games cannot run in EverPlay; Madeira (an open-source app that runs Windows games on
    /// iPhone through FEX-Emu, Wine and DXMT) can start many of them, with JIT from StikDebug.
    static func unityOutlook(_ lowered: [String]) -> String {
        let backend = unityBackend(lowered).map { " It uses Unity's \($0) scripting backend." } ?? ""
        let windows = lowered.contains { name($0) == "unityplayer.dll" }
        let hint = windows
            ? " EverPlay cannot play Windows Unity games yet. The free app Madeira runs many Windows games on iPhone (it needs JIT through StikDebug)."
            : ""
        return "Unity games are compiled for Windows, Mac or Android; only a version the developer builds for iOS runs natively on iPhone."
            + backend + hint
    }

    /// The engine the files point to, or nil when nothing is recognised.
    public static func identify(paths: [String]) -> EngineReport? {
        let lowered = paths.map { $0.lowercased() }
            .filter { !$0.contains("__macosx/") && !$0.split(separator: "/").contains { $0.hasPrefix(".") } }
        for rule in rules {
            let hits = lowered.filter(rule.matches)
            if !hits.isEmpty {
                let outlook = rule.engine == "Unity" ? unityOutlook(lowered) : rule.outlook
                return EngineReport(engine: rule.engine, playable: rule.playable, outlook: outlook,
                                    evidence: Array(hits.prefix(3)).map(name))
            }
        }
        if lowered.contains(where: { ext($0) == "exe" }) {
            return EngineReport(engine: "Windows program", playable: false,
                                outlook: "No known game engine was found next to the .exe; Windows programs cannot run on iPhone.",
                                evidence: Array(lowered.filter { ext($0) == "exe" }.prefix(3)).map(name))
        }
        return nil
    }
}
