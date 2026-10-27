import XCTest
@testable import EverPlayCore

final class EngineFingerprintTests: FixtureTestCase {
    func testNamesCommonEnginesFromTheirFiles() {
        let cases: [([String], String, Bool)] = [
            (["Game/Game.exe", "Game/UnityPlayer.dll", "Game/Game_Data/globalgamemanagers"], "Unity", false),
            (["Game/Game.exe", "Game/Game/Content/Paks/Game-WindowsNoEditor.pak"], "Unreal Engine", false),
            (["Game.exe", "Game.pck"], "Godot", false),
            (["Game.exe", "data.win", "options.ini"], "GameMaker", false),
            (["Game.exe", "Data.wolf", "Config.exe"], "Wolf RPG Editor", true),
            (["Game.exe", "Data/BasicData/Game.dat"], "Wolf RPG Editor", true),
            (["game.swf"], "Adobe Flash", false),
            (["Game/www/js/rpg_core.js", "Game/www/index.html"], "RPG Maker MV", true),
            (["story.html", "img/a.png"], "HTML5", true),
            (["Game.exe", "data.xp3"], "KiriKiri", true),
            (["Setup.exe", "readme.txt"], "Windows program", false),
        ]
        for (paths, engine, playable) in cases {
            let report = EngineFingerprint.identify(paths: paths)
            XCTAssertEqual(report?.engine, engine, paths.joined(separator: ", "))
            XCTAssertEqual(report?.playable, playable, engine)
        }
        XCTAssertNil(EngineFingerprint.identify(paths: ["readme.txt", "__MACOSX/._Game.exe"]))
    }

    func testUnityReportsItsScriptingBackend() {
        let il2cpp = EngineFingerprint.identify(paths: [
            "Game/Game.exe", "Game/UnityPlayer.dll", "Game/GameAssembly.dll",
            "Game/Game_Data/il2cpp_data/Metadata/global-metadata.dat", "Game/Game_Data/globalgamemanagers",
        ])
        XCTAssertEqual(il2cpp?.engine, "Unity")
        XCTAssertEqual(il2cpp?.outlook.contains("IL2CPP"), true)
        XCTAssertEqual(il2cpp?.outlook.contains("Madeira"), true)

        let mono = EngineFingerprint.identify(paths: [
            "Game/Game.exe", "Game/UnityPlayer.dll", "Game/MonoBleedingEdge/EmbedRuntime/mono-2.0-bdwgc.dll",
            "Game/Game_Data/Managed/Assembly-CSharp.dll",
        ])
        XCTAssertEqual(mono?.outlook.contains("Mono scripting backend"), true)

        // An Android/Mac build (no UnityPlayer.dll) gets no Windows hint.
        let other = EngineFingerprint.identify(paths: ["Game_Data/globalgamemanagers", "Game_Data/sharedassets0.assets"])
        XCTAssertEqual(other?.engine, "Unity")
        XCTAssertEqual(other?.outlook.contains("Madeira"), false)
    }

    func testImportNamesAnUnplayableEngine() throws {
        let game = temporary.appendingPathComponent("Game")
        try FileManager.default.createDirectory(at: game.appendingPathComponent("Game_Data"), withIntermediateDirectories: true)
        for file in ["Game.exe", "UnityPlayer.dll", "Game_Data/globalgamemanagers"] {
            try Data([1]).write(to: game.appendingPathComponent(file))
        }
        XCTAssertThrowsError(try GameDetector.detect(at: game)) { error in
            guard case EverPlayError.recognizedEngine(let report) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(report.engine, "Unity")
            XCTAssertTrue(error.localizedDescription.hasPrefix("This is a Unity game (found "))
        }
    }
}

final class EngineZipCheckTests: FixtureTestCase {
    func testUnityZipIsNamedBeforeExtracting() throws {
        let unity = try zip([("Game/Game.exe", Data([1])), ("Game/UnityPlayer.dll", Data([1]))])
        XCTAssertThrowsError(try GameImporter.rejectUnplayableEngine(unity)) { error in
            XCTAssertEqual((error as? EverPlayError).map { if case .recognizedEngine(let r) = $0 { return r.engine } else { return "" } }, "Unity")
        }
        let godotWeb = try zip([("index.html", Data([1])), ("game.pck", Data([1]))])
        XCTAssertNoThrow(try GameImporter.rejectUnplayableEngine(godotWeb))
    }
}
