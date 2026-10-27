# Godot in EverPlay

Arbeitsstand für Godot-Spiele (Windows-Builds mit `.pck` oder in die `.exe` eingebettetem pck).
Wird nach jedem Teilschritt aktualisiert, weil die Arbeit zwischen Accounts wechselt.
Branch: `claude/godot` (nie in `claude/beautiful-wozniak-ryh9su` mergen oder pushen, keine Force-Pushes).

## Stand

| Was | Im Simulator/CI gesehen | Vom Nutzer auf dem iPhone bestätigt |
|---|---|---|
| Godot-Engine 4.7.2 als iOS-Framework (`Godot47.framework`) | ja: iPhone + Simulator grün; im Simulator startet GodotProbe aus der Bibliothek, OpenGL ES 3 (Compatibility) (Lauf 40389255051) | **ja: Elden Rod (4.7.2, pck in der .exe) läuft** (Nutzer, 2026-10-27, nightly-godot 0.2.74) |
| Erkennung (`.pck`, eingebettetes pck, Engine-Version) | Swift-Tests grün (Linux, `GodotPackTests`) | nein |
| Bild | ja: Screenshot zeigt GodotProbe („Gold: 37“, Querformat, ☰) (Lauf 40391807381) | Engine startet auf iPhone (A16, Metal 4.0 Forward Mobile, Summer Exchange); Spielbild noch offen |
| Ton | Audiotreiber läuft (mix_rate 48000 im Probe-Spielstand) | nein |
| Touch als Maus, Tasten | nein | nein |
| Spielstände unter Dateien › EverPlay › Saves › Spielname | ja: `Saves/GodotProbe/probe.txt` geschrieben, `get_tree().quit()` beendet EverPlay sauber | nein |

App-Seite (`App/Godot/`) kompiliert fürs iPhone (app-ipa grün). Framework in `allinone.yml` gepinnt; der erste Testbuild `nightly-godot` mit Godot kommt aus dem nächsten allinone-Lauf.

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

- [x] `godot-ios.yml` iPhone grün (fehlten nur `godot_apple_embedded_plugins_(de)initialize`, die sonst Godots
      Xcode-Export erzeugt; jetzt leer in `everplay_godot.mm`)
- [x] Simulator-Build + `simulator-test` (GodotProbe) grün (Lauf 40389255051)
- [ ] Screenshot während des Spiels (Start jetzt im Hintergrund, Screenshot nach 12 s)
- [ ] Vom Nutzer: Elden Rod, Slut Maker, Golden Boy, Corrupting your Guild auf dem iPhone (Godot47)
- [ ] `Godot44` bauen (Matrix in godot-ios.yml hat jetzt 4.4.1; Patch + `compat/4.4.h` geschrieben, noch
      nicht kompiliert gesehen), dann in `allinone.yml` unter `GODOT_FRAMEWORKS` eintragen (eine Zeile pro
      Framework: „Datei SHA-256“). Danach: Summer Exchange und With The Childhood Friend testen
- [ ] Nicht Godot, aber im Log des Nutzers: „RPG Maker saves not copied to Saves: You don’t have
      permission to save the file … in the folder Saves“ (mkxp `RGSSSaves.collect`) – an den RPG-Maker-Zweig melden
- [x] Eigenes MIT-Testspiel `Tests/Fixtures/GodotProbe/` (Text-Szene + GDScript), gepackt von
      `scripts/godot/make-pck.py` (kein Godot-Editor nötig; `--embed` hängt es an eine Platzhalter-.exe).
      Zeigt „Gold: 37“, schreibt `user://probe.txt`, zählt Klicks, beendet sich nach 30 s.
      App-Haken für CI: Startargument `-EverPlayAutoplayZip <ZIP in Documents>`
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
- [x] `allinone.yml`: `GODOT_FRAMEWORK`/`GODOT_FRAMEWORK_SHA256` gepinnt
- [x] Test-IPA vom Branch: `allinone.yml` veröffentlicht von `claude/godot` das Pre-Release
      `nightly-godot` mit eigener Quelle
      `https://github.com/Pander0212/EverPlay/releases/download/nightly-godot/release-source.json`
      (gleiche Bundle-ID wie der Nightly, ersetzt ihn also auf dem iPhone)
- [ ] `docs/TESTEN.md`: Abschnitt Godot

## Entscheidungen und Sackgassen

- Branch: `claude/godot` laut Auftrag. `allinone.yml` veröffentlicht den Nightly nur von
  `claude/beautiful-wozniak-ryh9su`; dieser Branch bekommt das eigene Pre-Release `nightly-godot`.
- **4.4-Spiele brauchen eine 4.4-Laufzeit**: kompilierte Skripte (`.gdc`) tragen eine Token-Version (4.4: 100,
  4.5–4.7: 101), und Godot verlangt exakt die eigene („Binary GDScript is not compatible with this engine
  version“, so auf dem iPhone mit Summer Exchange gesehen). `GodotRuntime` wählt die älteste gebündelte Laufzeit
  ≥ Spielversion: 4.0–4.4 → Godot44, 4.5–4.7 → Godot47.
- 4.4 hat iOS noch in `platform/ios` (`AppDelegate`, `ViewController`, `OS_IOS`, `ios_main`, `main.m`). Der
  Patch benennt `main` um, gibt `AppDelegate.viewController` einen Setter und startet das Rendern in
  `viewDidAppear` (Godot 4.4 startet es sonst erst bei „App wird aktiv“). Versionsunterschiede im Einstieg
  stehen in `scripts/godot/compat/4.4.h` bzw. `4.7.h`. `disable_path_overrides` gibt es erst ab 4.5.
- Zuerst eine Laufzeit 4.7.2 für alle 4.x-Spiele: 4.5.1 und 4.7.2 haben dasselbe GDScript-Token-Format
  (`TOKENIZER_VERSION 101`) und Binär-Ressourcenformat (6); 4.7 liest pck-Format 2, 3 und 4. Passt ein
  Spiel nicht, kommt die exakte Version als weiteres Framework dazu (Skript ist versionsparametrisiert,
  der Patch ist aber auf 4.7 geschrieben; 4.4 hat noch `platform/ios` ohne `drivers/apple_embedded`).
- `disable_path_overrides=no` ist Pflicht: Release-Vorlagen lehnen `--main-pack` sonst ab („compiled without
  support for path overrides“), `Main::setup` endet dann mit 1 (Simulatortest Lauf 40376413760: Import,
  Erkennung und Laden des Frameworks liefen, Start scheiterte genau hier). Das pck aus `make-pck.py` läuft im
  offiziellen Godot 4.7.2 Linux headless (`start gold 37`), ist also in Ordnung.
- Godot schreibt auf iOS nicht nach stdout (os_log); Fehler vor `--log-file` sind in CI unsichtbar.
- `godot.log` zeigt beim Beenden viele „BUG: Unreferenced static string“: harmlos, EverPlay beendet den
  Prozess mit `exit(0)` ohne Godots Aufräumen. „Mouse is not supported by this display server“
  (`mouse_get_position`) kommt von iOS-Godot; Mausposition in Events kommt trotzdem an (Touch-Emulation).
  Falls ein Spiel `get_global_mouse_position()` außerhalb von Events braucht und es hakt: hier ansetzen.
- `simctl launch` blockiert im frischen Simulator teils minutenlang, auch wenn die App läuft: im Hintergrund
  starten und am EverPlay-Log erkennen, ob das Spiel startet.
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
| godot-ios.yml 40369824834 | Kompilierfehler (MainLoop-Include) | – |
| godot-ios.yml 40371282247 | iPhone: Link-Fehler Plugin-Hooks (Kompilieren 14 min) | – |
| godot-ios.yml 40375456849 | iPhone grün, Simulator: falscher Bibliotheksname | `Godot47_ios-arm64-4.7.2-a417992.framework.zip` (ohne Path-Overrides, startet keine Spiele) |
| godot-ios.yml 40376413760 | beide Builds grün; Simulatortest: `--main-pack` abgelehnt | – |
| allinone.yml 40376413743 | IPA → `nightly-godot` (noch mit a417992, startet keine Spiele) | – |
| godot-ios.yml 40389255051 | alles grün, GodotProbe läuft im Simulator | – |
| allinone.yml 40387051117 | IPA → `nightly-godot` mit d97d3e5 (erster Testbuild, der Spiele starten sollte) | – |
| godot-ios.yml 40382732038 | beide Builds grün (mit Path-Overrides); Simulatortest: `simctl launch` hing, App nie gestartet (kein Log) → Wartezeit + 3 Versuche | `Godot47_ios-arm64-4.7.2-d97d3e5.framework.zip` `3d52f6ee3eb2e6a78ab62a1fe1dff81b5a1316ed59ebdd62ded6378a11ac0631` (gepinnt); Simulator: `Godot47_ios-arm64-simulator-4.7.2-d97d3e5.framework.zip` `0016875d0599e2e87194f0fc3d7c6d38af9bcf7a0ee518d9071b6aa7628a28cd` |

## Testspiele

| Spiel | Engine | pck | Renderer | Stand |
|---|---|---|---|---|
| Elden Rod v0.1.1 | Godot 4.7.2 official | in der `.exe` eingebettet, Format 4 | gl_compatibility | **läuft auf dem iPhone** (Nutzer; Ton/Video/Spielstände noch nicht einzeln bestätigt) |
| Slut Maker 0.42 | Godot 4.5.1 | separate `.pck`, Format 3 | gl_compatibility, `sensor_landscape` | Ziel 2 (mit 4.7.2-Laufzeit) |
| Agent Feminine 0.4.7 | Godot 4.4.1 custom_build | eingebettet, Format 2, Verzeichnis verschlüsselt | ? | nicht spielbar: Schlüssel vom Entwickler versteckt; wird nicht ausgelesen. Option: Schlüsselfeld, falls der Nutzer ihn vom Entwickler bekommt |
| Golden Boy v0.1.1 | Godot 4.7.2 | separate `.pck`, Format 4 | gl_compatibility; auch S3TC/RGTC-Texturen (Godot entpackt sie, `bcdec`) | Godot47 |
| Corrupting your Guild Demo 0.3 | Godot 4.7.2 | in der `.exe` eingebettet (1,4 GB), Format 4 | Forward+ am PC, `rendering_method.mobile` = gl_compatibility | Godot47 |
| With The Childhood Friend v1.0.3-BETA | Godot 4.4.1 | separate `.pck`, Format 2 | gl_compatibility, Theora-Videos | braucht Godot44 |
| Summer Exchange v0.3 | Godot 4.4.1 | separate `.pck`, Format 2 | Mobile (Metal), S3TC-Texturen | braucht Godot44 (auf iPhone mit Godot47: Skriptfehler) |

Beide offenen Spiele: Texturen verlustfrei (WebP/PNG in `.ctex`), `.gdc` (tokenisiertes GDScript),
keine GDExtension, kein C#. Elden Rod hat ein Theora-Video (`.ogv`) und `use_custom_user_dir`
(`Gobaky/EldenRod`, das ignoriert der iOS-Patch: alles geht nach `EVERPLAY_GODOT_USER_DIR`).
Alle sieben: keine GDExtension, kein C#.
