# Unity-Windows-Spiele auf dem iPhone: Machbarkeitsstudie

Branch `claude/unity-research` (von `claude/beautiful-wozniak-ryh9su`). Dies ist eine Studie, kein Support.
Diese Datei wird nach jedem Schritt gepflegt; die Arbeit wechselt zwischen Accounts.

Kennzeichnung jeder Aussage:
- **[R]** recherchiert (Quelle oder gelesener Code)
- **[S]** im Simulator gesehen
- **[i]** auf dem iPhone bestätigt

Stand: 2026-10-26. Bisher ist alles **[R]**; nichts wurde im Simulator oder auf dem iPhone gesehen.

## Ergebnis (vorläufig)

**Geht nicht auf dem im Auftrag vermuteten Weg. Geht höchstens unter starken Bedingungen, mit Forschungsaufwand
in Monaten, nicht Tagen.**

1. **Den vermuteten Hauptweg gibt es nicht** [R]: Ein „Android-Unity-Player ARM64 mit Mono“ existiert nicht.
   Unity baut Mono auf Android nur für **ARMv7 (32 Bit)**; ARM64 auf Android gibt es nur mit IL2CPP. Unitys
   Doku listet für Mono: „Windows x86/x64/Arm64, OSX x64/Arm64, Linux x64, **Android Armv7**“; alles andere ist
   IL2CPP-only ([Unity Manual: Scripting backends](https://docs.unity3d.com/Manual/scripting-backends-intro.html)).
   iPhones führen seit dem A11 keinen 32-Bit-ARM-Code mehr aus (auch Husk lehnt `armeabi-v7a`-only-APKs deshalb ab,
   `docs/04-translation-layer.md` in Husk). Ein ARM64-Android-`libunity.so` stammt also immer aus einem IL2CPP-Build
   und erwartet ein `libil2cpp.so`, kein Mono und keine `Managed/*.dll`.
2. **Das Shader-Problem gilt für jeden Weg** [R, aus Unitys Datenformat]: Ein Windows-Build enthält Shader in der
   Regel nur als D3D11-Bytecode (DXBC). Ein Android- oder Apple-Player braucht GLES-/Vulkan-/Metal-Varianten derselben
   Shader. Ohne Umwandlung bleibt das Bild schwarz/pink, selbst wenn der Code liefe. Ausnahme: Der Entwickler hat
   zusätzlich OpenGLCore oder Vulkan als Grafik-API eingetragen (bei jedem Testspiel prüfen).
3. **Unity-Player-Dateien darf EverPlay nicht mitliefern** [R]: Die Unity-Runtime ist proprietär; Weitergabe ist nur als
   Teil eines mit gültiger Lizenz gebauten Spiels erlaubt. Jeder Weg braucht deshalb eine vom Nutzer selbst
   beschaffte Player-Datei passender Version („Spender“), so wie Husk nur APKs ausführt, die der Nutzer mitbringt.
   (Unity-Lizenzbedingungen noch im Wortlaut zu zitieren, siehe Checkliste.)

Was trotzdem denkbar ist, steht unter „Wege“. Keiner davon ist ein Wochenendprojekt.

## Testspiele

Nur Name, Unity-Version, Mono oder IL2CPP. Niemals Dateien, Spielstände oder Screenshots ins Repo.

| Spiel | Unity-Version | Backend | Grafik-APIs im Build | Anmerkung |
|---|---|---|---|---|
| (folgt) | | | | |

Erkennung (nur Dateinamen und Header lesen, nichts ausführen):
- **Mono**: `<Name>_Data/Managed/Assembly-CSharp.dll` vorhanden, `MonoBleedingEdge/` neben der `.exe`.
- **IL2CPP**: `GameAssembly.dll` neben der `.exe` und `<Name>_Data/il2cpp_data/Metadata/global-metadata.dat`.
- **Version**: steht als Text im Kopf von `<Name>_Data/globalgamemanagers` (bzw. `mainData` bei alten Versionen,
  `data.unity3d` bei komprimierten Builds), z. B. `2021.3.16f1`; zusätzlich in der Dateiversion von `UnityPlayer.dll`.

## Wie Android-Launcher Unity-Spiele starten

- **JoiPlay** [R]: unterstützt laut eigener Seite RPG Maker, Ren'Py, TyranoBuilder, Construct 2/3, Godot (GDScript),
  Flash und HTML5. **Kein Unity** ([joiplay.net](https://joiplay.net/)). Nutzerberichte auf itch.io bestätigen, dass
  Unity-Spiele dort nicht laufen.
- **MinHub** [R]: Mit Websuche nicht auffindbar (weder Store-Eintrag noch Quellcode noch Forenthread).
  → Link vom Auftraggeber nötig, siehe Checkliste.
- Was es auf Android sonst gibt [R, Allgemeinwissen, ohne Quelle im Detail geprüft]: **Winlator** und Ähnliche starten das
  Windows-Spiel unverändert unter Wine + Box64 (x86-64→ARM64) + DXVK. Das ist Windows-Emulation, keine Unity-Lösung.
- Händische „Ports“ von PC-Unity-Spielen nach Android in Communitys entstehen über einen Neuaufbau des Projekts
  (AssetRipper/Dekompilierung, neu bauen, meist IL2CPP), nicht über einen fertigen Player, der Windows-Daten lädt.

Die Vermutung „Android-Unity-Player mit Mono lädt die Windows-`_Data`“ ist damit für ARM64 widerlegt (Punkt 1 oben).
Auf ARMv7-Android-Geräten wäre sie prinzipiell denkbar, bringt fürs iPhone aber nichts.

## Husk: was es kann und was davon nutzbar wäre

Quelle: [github.com/Leviidev/Husk](https://github.com/Leviidev/Husk), gelesen bei Commit `b390dfa` (2026-10-26). [R]

- **Lizenz**: GPL-2.0 (`LICENSE`), eigene Dateien `GPL-2.0-or-later` (SPDX-Header). Begründung in Husks
  `docs/01-licensing.md`: QEMU ist GPLv2. Der Built-in-JIT nutzt StikJIT (MPL-2.0) und idevice (MIT).
  → Wiederverwendung ist erlaubt, wenn EverPlays verteilte IPA als Ganzes GPL-kompatibel ist und der Quellcode
  veröffentlicht wird. EverPlay ist MIT, bündelt aber schon mkxp-z (GPL) und plant EasyRPG (GPLv3); GPL-2.0-or-later
  verträgt sich mit GPLv3. Übernommene Dateien behalten ihren GPL-Header.
- **Translation Layer** (`src/translation-layer-next/`, ca. 10 000 Zeilen nur Loader/bionic-Shim/Unity): lädt ARM64-
  Android-`.so` direkt in JIT-Speicher, ersetzt bionic durch Darwin-libc, stellt eine eigene JNI/„Java“-Umgebung
  (HLE) bereit, GLES über ANGLE. Kein Android-System, kein Emulator.
- **Unity-Treiber** (`husk-tl-unity.c`, `husk-tl-unity-app.c`): startet `libmain.so` → `JNI_OnLoad` →
  `NativeLoader.load` → `nativeRecreateGfxState`/`nativeResume`/`nativeRender`-Schleife, wie Unitys Java-Seite.
  Der Scanner erkennt „Unity (IL2CPP)“, „Unity (Mono)“ und „Unity 6“. Laut README laufen Unity-Spiele (IL2CPP).
- **Mono auf ARM64**: Husks Loader behandelt Mono-AOT-Images aus .NET 8–10 (`mono_aot_code_only` in `husk-tl-ld.c`),
  liefert `/proc/self/maps` für Mono und legt RX/RW-Ansicht so, dass Monos `tramp-arm64.c` funktioniert
  (`husk-tl-xmem.c`). D. h. ein ARM64-Mono-JIT läuft in Husks Umgebung grundsätzlich (für .NET/Xamarin-Apps).
- **JIT**: `docs/06-built-in-jit.md`: Helper-Extension `HuskJITHelper.appex` mit StikJIT.framework hängt sich als
  Debugger an (iOS 26+, LocalDevVPN, Pairing-Datei; auf iOS 27 Pairing ohne Computer). Die App braucht
  `get-task-allow`; App, Extension und Framework müssen zusammen signiert sein, der Sideloader muss Extensions
  behalten. Danach: RX-Region + RW-Alias per `vm_remap`, einmalig, feste Größe.
- Für EverPlay heißt das: Husks Schicht wäre **der** Unterbau, um überhaupt Unity-Android-Code (ARM64) auf iOS zu
  starten. Das löst aber nicht Punkt 1 (es gibt kein ARM64-Mono-Unity) und nicht Punkt 2 (Shader).

## Wege (alle unbewiesen)

### Weg A: Android-IL2CPP-`libunity.so` + eigenes „`libil2cpp.so`“, das Mono nutzt (für Mono-Spiele)

Idee: `libunity.so` (ARM64, IL2CPP-Variante, exakt gleiche Unity-Version) spricht die Skript-Runtime nur über die
exportierte `il2cpp_*`-API an (`il2cpp_init`, `il2cpp_domain_get`, `il2cpp_class_from_name`, `il2cpp_runtime_invoke`,
`il2cpp_add_internal_call`, …). Ein selbst geschriebenes `libil2cpp.so` setzt diese ~200 Funktionen auf ein ARM64-Mono
(Unitys Mono-Fork [github.com/Unity-Technologies/mono](https://github.com/Unity-Technologies/mono) oder
dotnet/runtime-Mono) um und lädt die `Managed/*.dll` des Windows-Spiels.
- Begünstigt [R, Header-Vergleich aus dem Gedächtnis, noch zu prüfen]: IL2CPP-Objekt-, String- und Array-Layouts sind
  Monos nachgebildet (Header 16 Byte, Länge an gleicher Stelle).
- Risiken: ob `libunity` wirklich nur über die API geht (oder Klassenstrukturen direkt liest), ob die Windows-Varianten
  von `UnityEngine.*.dll` dieselben Internal Calls erwarten, Plattformkennung in den Daten, plattformspezifische
  Daten (Shader, Texturformate), Windows-only-Code im Spiel (P/Invoke auf `user32` usw.).
- Aufwand: Monate. Zuerst prüfbar: Liste der `il2cpp_*`-Importe von `libunity.so` einer passenden Version.

### Weg B: macOS-ARM64-Player (Mono) auf iOS

Unity hat für macOS einen Mono-Player auf ARM64 (`UnityPlayer.dylib` + `libmonobdwgc-2.0.dylib`). Gleiche CPU,
fast gleiches Darwin. Aber: linkt AppKit, Carbon, IOKit, OpenGL usw., die es auf iOS nicht gibt (Stub-Frameworks nötig),
dyld lehnt macOS-Binärdateien ab (Load-Command umschreiben), Shader müssten nach Metal. Aufwand: Monate, Stubs für
AppKit sind ein Fass ohne Boden. Nur als Alternative notiert.

### Weg C: ARMv7-Android-Mono-Player + 32-Bit-ARM-Emulation

Technisch der „echte“ Mono-Android-Player, aber iPhones haben kein AArch32. Bräuchte einen ARMv7-Emulator
(z. B. dynarmic) im Prozess plus Husk-artige Schicht. Langsam und aufwendig. Verworfen.

### Weg D: Windows-Spiel unverändert (Wine + Box64-artig + DXVK/MoltenVK)

Das, was Winlator auf Android macht. Auf iOS gibt es dafür nichts Fertiges (Box64 ist Linux-only, Wine auf iOS
existiert nicht in brauchbarer Form). Verworfen für diese Studie.

### Gemeinsamer Baustein für A und B: Shader-Umwandlung

DXBC → GLSL ES / MSL. Unitys eigener Übersetzer [HLSLcc](https://github.com/Unity-Technologies/HLSLcc) macht genau
DXBC → GLSL/Metal (so baut Unity selbst GLES/Metal-Shader). Ein Offline-Konverter müsste in jeder Shader-Asset-Datei die
D3D11-Unterprogramme übersetzen und als GLES3-Unterprogramme samt Parameter-/Binding-Tabellen eintragen. Aufwand: Wochen
bis Monate, versionsabhängig (Shader-Serialisierung ändert sich zwischen Unity-Versionen).

## IL2CPP (nur dokumentiert, nicht gebaut)

Windows-IL2CPP-Spiel = `GameAssembly.dll` (x86-64, Windows-PE, enthält den gesamten Spielcode als nativen Code) +
`global-metadata.dat` + `UnityPlayer.dll`. Skizze eines Box64-artigen Wegs im selben Prozess:

1. ARM64-Android-`libunity.so` (IL2CPP-Variante, gleiche Version) über Husks Schicht als Engine.
2. `GameAssembly.dll` mit eigenem PE-Loader in den Speicher, Code per x86-64→ARM64-JIT ausführen
   (FEXCore wie in AetherPS4s `bachata-core`, oder Box64-Kern; Box64 selbst ist an Linux gebunden).
3. Übergänge: Jede `il2cpp_*`-Funktion, die `libunity` aufruft, wird ein Thunk ARM64 (AAPCS64) → x86-64
   (Microsoft-x64-Konvention). Jeder Internal Call, den `libunity` per `il2cpp_add_internal_call` registriert und den
   Spielcode aufruft, braucht den Thunk zurück (x86-64 → ARM64), inklusive Callbacks, Ausnahmen (SEH ↔ C++), TLS.
4. Die Win32-Importe von `GameAssembly.dll` (`kernel32`: Speicher, Threads, TLS, Events, Dateien, `VirtualAlloc`)
   als HLE nachbauen.
5. GC: IL2CPPs Boehm-GC scannt Stacks und Register; mit gemischtem x86/ARM-Stack nur mit Zusatzarbeit.

Aufwand: Größenordnung eines eigenen Emulatorprojekts (viele Monate, Experten). Hilfreiche Projekte:
- [Box64](https://github.com/ptitSeb/box64) (MIT): x86-64→ARM64-Dynarec, Wrapping von Bibliotheken als Vorbild für Thunks.
- FEXCore (MIT), in Husks Doku als Option für x86-only-Bibliotheken genannt.
- [Cpp2IL](https://github.com/SamboyCoding/Cpp2IL) (MIT) und [Il2CppDumper](https://github.com/Perfare/Il2CppDumper) (MIT):
  rekonstruieren aus `GameAssembly.dll` + `global-metadata.dat` Typen und Methoden-Adressen (Dummy-DLLs). Nützlich zum
  Erzeugen der Thunk-Tabellen und für Diagnose; ausführbaren IL-Code liefern sie nicht verlässlich.
  Ein Weg „IL2CPP → IL zurück → unter Mono laufen lassen“ ist damit nicht realistisch.

## Probiertes und Sackgassen

- Websuche nach MinHub: nichts gefunden.
- JoiPlay: kein Unity.
- Vermutung „ARM64-Android-Unity-Player mit Mono“: Sackgasse, gibt es nicht (Unity-Doku).

## Nächste Schritte (Checkliste)

- [ ] Testspiele vom Auftraggeber: je Unity-Version, Mono/IL2CPP, Grafik-APIs (welche Shader-Varianten im Build sind)
      eintragen. Nur Header und Dateinamen lesen, nichts ausführen.
- [ ] MinHub: Link vom Auftraggeber erfragen und den Startweg dort nachlesen.
- [ ] Unity-Lizenzbedingungen zur Weitergabe der Runtime im Wortlaut zitieren.
- [ ] Für Weg A: von einer frei verfügbaren Android-APK mit Unity (IL2CPP, ARM64) gleicher Version die `il2cpp_*`-Importe
      von `libunity.so` auflisten (nur `readelf`, nichts ausführen). Ergibt die API-Fläche des Shims.
- [ ] Shader: bei einem Testspiel zählen, welche GPU-Programmtypen in den Shader-Assets stecken.
- [ ] Erst wenn alle drei Punkte nicht blockieren: minimaler Prototyp (siehe unten).

## Prototyp

Noch keiner. Höchstens einer, der etwas aus einem Testspiel lädt (z. B. Unity-Version und Backend erkennen).
