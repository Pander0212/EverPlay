# Godot in EverPlay

Arbeitsstand für Godot-Spiele (Windows-Builds mit `.pck` oder in die `.exe` eingebettetem pck).
Wird nach jedem Teilschritt aktualisiert, weil die Arbeit zwischen Accounts wechselt.
Branch: `claude/godot` (nie in `claude/beautiful-wozniak-ryh9su` mergen oder pushen, keine Force-Pushes).

## Stand

| Was | Im Simulator/CI gesehen | Vom Nutzer auf dem iPhone bestätigt |
|---|---|---|
| Godot-Engine 4.7.2 als iOS-Framework (`Godot47.framework`) | Workflow geschrieben, erster Lauf offen | nein |
| Erkennung (`.pck`, eingebettetes pck, Engine-Version) | Swift-Tests grün (Linux, `GodotPackTests`) | nein |
| Bild | nein | nein |
| Ton | nein | nein |
| Touch als Maus, Tasten | nein | nein |
| Spielstände unter Dateien › EverPlay › Saves › Spielname | nein (Patch geschrieben) | nein |

Code für die App-Seite steht (`App/Godot/`), aber noch kein Framework im IPA (Pin in `allinone.yml` leer).

## Aufbau

- `scripts/godot/build-godot-ios.sh <version> <device|simulator> <out>`: holt Godot am Tag
  `<version>-stable`, patcht, baut `scons platform=ios target=template_release vulkan=no`
  (OpenGL ES 3 für `gl_compatibility`, Metal für Mobile/Forward+), linkt die statische
  `libgodot.ios.template_release.arm64.a` mit `-all_load` zu `Godot47.framework/Godot47`
  (nur `_everplay_godot_*` exportiert).
- `scripts/godot/patch-godot-ios.py`: entfernt Godots SwiftUI-`@main` (`drivers/apple_embedded/app.swift`),
  baut `everplay_godot.mm` in `platform/ios` ein, `user://` = Umgebungsvariable
  `EVERPLAY_GODOT_USER_DIR`, `get_tree().quit()` ruft EverPlay (iOS-Godot ignoriert Quit sonst),
  `delegate.window` → `self.window` (EverPlays App-Delegate hat kein `window`), kein Umschreiben
  des Root-View-Controllers (`propagateUIPreferencesToRootViewController`).
- `scripts/godot/everplay_godot.mm` (C-API, alles auf dem Main-Thread):
  - `everplay_godot_start(argc, argv, user_dir, on_quit)` → `apple_embedded_main` (= `Main::setup`).
    argv z. B. `["godot", "--main-pack", "<Spiel.exe oder .pck>", "--log-file", "<log>"]`.
  - `everplay_godot_view_controller()` → `GDTViewController` (+1). Godot macht `Main::setup2` und
    `Main::start` selbst in den ersten Frames (`GDTViewRenderer setupView`), sobald die View erscheint.
  - `everplay_godot_app_state(0..3)`, `everplay_godot_memory_warning()`,
    `everplay_godot_mouse_button(button, pressed, x, y)` (Punkte in der View),
    `everplay_godot_key(godotKey, unicode, pressed)`, `everplay_godot_project_name(buf, size)`.
- Touch → Maus macht Godot selbst (`input_devices/pointing/emulate_mouse_from_touch`, Standard an).
  Rechtsklick und Tasten kommen von EverPlay über die C-API.
- `.github/workflows/godot-ios.yml`: Matrix Version × (device, simulator) auf `macos-26`,
  SCons-Cache, Veröffentlichung in `libretro-cores` als
  `Godot47_ios-arm64[-simulator]-4.7.2-<hash der scripts/godot/*>.framework.zip`, nie überschreiben.

## Nächste Schritte

- [ ] `godot-ios.yml` grün bekommen (Link-Fehler: fehlende Frameworks/Symbole nachtragen)
- [ ] Eigenes MIT-Testspiel (kleines Godot-4-Projekt im Repo, z. B. `Tests/Fixtures/GodotProbe/`), per
      Godot-Editor headless (`--export-pack`) in CI zu `.pck` exportiert; schreibt nach `user://` und
      zeigt „Gold: 37“, beendet sich nach ein paar Sekunden mit `get_tree().quit()`
- [x] App: `GameEngine.godot`, `App/Godot/GodotEngine.swift` (dlopen, Symbole), `GodotPlayerView.swift`
      (Godots View-Controller als Kind, Querformat, ☰-Menü: Escape, Rechtsklick, Tasten, Beenden;
      Zwei-Finger-Tipp = Rechtsklick), Start aus `RootView` (`fullScreenCover`) wie KiriKiri.
      Kompiliert noch nicht gesehen (CI-Lauf allinone.yml abwarten)
- [ ] Hochformat-Spiele: `display/window/handheld/orientation` lesen statt immer Querformat
- [x] Erkennung: `Sources/EverPlayCore/GodotPack.swift` (Header am Anfang oder am Dateiende),
      `GameDetector.godotGame` (flachste Datei, `.pck` vor `.exe`; `.wasm` daneben = Web-Export),
      `EngineFingerprint` Godot spielbar, `GameImporter` lehnt eine einzelne `.exe` nicht mehr vor dem
      Entpacken ab („Windows program“ könnte ein eingebettetes pck haben)
- [x] Laufzeit wählen (`GodotRuntime.framework`): Major 4 und Minor ≤ 7 → `Godot47`; Godot 3, neuere 4.x,
      verschlüsselt → Import bricht mit Grund ab
- [ ] `allinone.yml`: `GODOT_FRAMEWORK`/`GODOT_FRAMEWORK_SHA256` eintragen, sobald godot-ios.yml grün
      ist (Kopierschritt ist schon da); Simulator-Job mit Fixture
- [x] Test-IPA vom Branch: `allinone.yml` veröffentlicht von `claude/godot` das Pre-Release
      `nightly-godot` mit eigener Quelle
      `https://github.com/Pander0212/EverPlay/releases/download/nightly-godot/release-source.json`
      (gleiche Bundle-ID wie der Nightly, ersetzt ihn also auf dem iPhone)
- [ ] `docs/TESTEN.md`: Abschnitt Godot

## Entscheidungen und Sackgassen

- Branch: `claude/godot` laut Auftrag. `allinone.yml` veröffentlicht den Nightly nur von
  `claude/beautiful-wozniak-ryh9su`; dieser Branch bekommt das eigene Pre-Release `nightly-godot`.
- Eine Laufzeit 4.7.2 für alle 4.x-Spiele zuerst: 4.5.1 und 4.7.2 haben dasselbe GDScript-Token-Format
  (`TOKENIZER_VERSION 101`) und Binär-Ressourcenformat (6); 4.7 liest pck-Format 2, 3 und 4. Passt ein
  Spiel nicht, kommt die exakte Version als weiteres Framework dazu (Skript ist versionsparametrisiert,
  der Patch ist aber auf 4.7 geschrieben; 4.4 hat noch `platform/ios` ohne `drivers/apple_embedded`).
- Keine Vulkan/MoltenVK: beide spielbaren Testspiele nutzen `gl_compatibility`.
- Eingebettetes pck: Godot sucht selbst am Dateiende der `.exe` (`PackedSourcePCK::try_open_pack`),
  `--main-pack Spiel.exe` reicht; nichts muss ausgeschnitten werden.
- Verschlüsselte pcks: Der Schlüssel (`script_encryption_key`) ist in die `.exe` kompiliert. Bei
  Agent Feminine (4.4.1 `custom_build`) liegt er nirgends als 32 zusammenhängende Bytes in der Datei
  (jede Byte-Position als AES-256-CFB-Schlüssel gegen den ersten Verzeichnisblock geprüft, 0 Treffer):
  absichtlich versteckt. Zurückgestellt; EverPlay soll verschlüsselte pcks erkennen und das sagen.
  Für Spiele mit Standard-Build wäre ein Schlüsselfund in `.data` möglich (später, eigener Patch, der
  den Schlüssel zur Laufzeit setzt).

## Builds

| Workflow-Lauf | Ergebnis | Gepinnte Datei |
|---|---|---|
| godot-ios.yml, erster Lauf | offen | – |

## Testspiele

| Spiel | Engine | pck | Renderer | Stand |
|---|---|---|---|---|
| Elden Rod v0.1.1 | Godot 4.7.2 official | in der `.exe` eingebettet, Format 4 | gl_compatibility | Ziel 1 |
| Slut Maker 0.42 | Godot 4.5.1 | separate `.pck`, Format 3 | gl_compatibility, `sensor_landscape` | Ziel 2 (mit 4.7.2-Laufzeit) |
| Agent Feminine 0.4.7 | Godot 4.4.1 custom_build | eingebettet, Format 2, Verzeichnis verschlüsselt | ? | zurückgestellt (Schlüssel versteckt) |

Beide offenen Spiele: Texturen verlustfrei (WebP/PNG in `.ctex`), `.gdc` (tokenisiertes GDScript),
keine GDExtension, kein C#. Elden Rod hat ein Theora-Video (`.ogv`) und `use_custom_user_dir`
(`Gobaky/EldenRod`, das ignoriert der iOS-Patch: alles geht nach `EVERPLAY_GODOT_USER_DIR`).
Der Nutzer hat noch ein 2,6-GB-Spiel für spätere Tests angeboten.
