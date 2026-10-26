# Godot in EverPlay

Arbeitsstand für Godot-Spiele (Windows-Builds mit `.pck` oder in die `.exe` eingebettetem pck).
Wird nach jedem Teilschritt aktualisiert, weil die Arbeit zwischen Accounts wechselt.
Branch: `claude/godot` (nie in `claude/beautiful-wozniak-ryh9su` mergen oder pushen, keine Force-Pushes).

## Stand

| Was | Im Simulator/CI gesehen | Vom Nutzer auf dem iPhone bestätigt |
|---|---|---|
| Godot-Engine als iOS-Framework | nein | nein |
| Erkennung (`.pck`, eingebettetes pck, Engine-Version) | nein | nein |
| Bild | nein | nein |
| Ton | nein | nein |
| Touch als Maus, Tasten | nein | nein |
| Spielstände unter Dateien › EverPlay › Saves › Spielname | nein | nein |

Heute: `EngineFingerprint` erkennt Godot nur am Dateinamen (`.pck`, `project.godot`) und meldet „nicht spielbar“.

## Plan (Kurzfassung)

1. Engine-Version der Testspiele aus dem pck-Header lesen (Magic `GDPC`, dann Format-Version,
   Major, Minor, Patch). Bei eingebettetem pck steht am Ende der `.exe` die Länge und wieder `GDPC`.
2. Godot genau dieser Version (Major.Minor; Godot 3 und 4 sind getrennte Engines) als iOS-Framework
   bauen: offizielle Quellen am gepinnten Tag, `platform=ios target=template_release`, Module für
   Editor/Tools aus, plus ein kleiner EverPlay-Einstieg (C-Funktion), der statt Godots eigenem
   `main()`/App-Delegate in EverPlays UIApplication läuft, eine View bekommt und die pck mit
   `--main-pack` lädt.
3. Workflow `.github/workflows/godot-ios.yml` baut das Framework und lädt es ins Release
   `libretro-cores` (nie ein veröffentlichtes überschreiben, neuer Name pro Commit/Version).
4. `allinone.yml` pinnt Name und SHA-256, kopiert nach `Frameworks/`.
5. App: `App/Godot/` (Laden per `dlopen`, Player-View, Touch → Maus, Tasten-Overlay),
   `GameEngine.godot`, Erkennung in `GameDetector.swift`/`EngineFingerprint.swift`.
6. `user://` zeigt auf `Documents/Saves/<Spielname>`.

## Nächste Schritte

- [ ] Testspiele vom Nutzer: Godot-Version jedes Spiels bestimmen (nur Header lesen, kein Spielcode ausführen)
- [ ] Godot-Quelltext der Version ansehen: iOS-Plattform (`platform/ios`, ab 4.5 `drivers/apple_embedded`),
      wo `main`, App-Delegate, View-Controller und `OS_IOS::get_user_data_dir` sitzen
- [ ] Einstieg `everplay_godot_start(config)` entwerfen (Spielordner, pck-Pfad, Save-Ordner, Log-Callback, UIView)
- [ ] `godot-ios.yml` schreiben und laufen lassen
- [ ] In `allinone.yml` pinnen
- [ ] App-Seite und Erkennung
- [ ] Testanleitung in `docs/TESTEN.md`

## Entscheidungen und Sackgassen

- Branch: `claude/godot` laut Auftrag. `allinone.yml` veröffentlicht den Nightly nur von
  `claude/beautiful-wozniak-ryh9su`; für Tests von diesem Branch braucht es einen eigenen Weg
  (IPA als Actions-Artefakt oder eigenes Pre-Release, offen).

## Builds

Noch keine.

## Testspiele

Noch keine (nur Name und Engine-Version eintragen, nie Dateien).
