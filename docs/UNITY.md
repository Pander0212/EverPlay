# Unity-Windows-Spiele auf dem iPhone: Machbarkeitsstudie

Branch `claude/unity-research` (von `claude/beautiful-wozniak-ryh9su`). Dies ist eine Studie, kein Support.
Diese Datei wird nach jedem Schritt gepflegt; die Arbeit wechselt zwischen Accounts.

Kennzeichnung jeder Aussage:
- **[R]** recherchiert (Quelle oder gelesener Code)
- **[S]** im Simulator gesehen
- **[i]** auf dem iPhone bestätigt

Stand: 2026-10-26. Alles ist **[R]**; nichts wurde im Simulator oder auf dem iPhone gesehen.

## Ergebnis

**Geht unter Bedingungen, aber nicht durch eigenen Bau in EverPlay, sondern über Madeira.** (Neu, 2026-10-26.)

[Madeira](https://github.com/willfaust/Madeira) (GPL-3.0-or-later + Converter-Ausnahme, Release 0.1.x, letzter Commit
2026-10-23) führt **unveränderte Windows-Spiele auf dem iPhone ohne Jailbreak** aus: FEX (x86/x86-64 → ARM64) +
Wine 11.4 als ARM64EC (Wine selbst nativ, nur Spielcode übersetzt) + DXMT (D3D9/10/11 → Metal, DXBC → Metal über
airconv/LLVM) + eigenes D3D12. Alles in **einem Prozess**, `wineserver` als Thread. Voraussetzungen: iOS 26+, JIT
(StikDebug oder eingebautes StikJIT), „Memory+“ (increased-memory-limit). Laut README und Berichten spielbar u. a.
Thumper und ULTRAKILL (Unity, Mono); im Code wird an Unity-Spielen gearbeitet (Unity-Raw-Input, ein FEX-Fehler in
Unitys `mono-2.0-bdwgc.dll`-JIT bei ULTRAKILL, Unitys „Failed to load il2cpp“-Dialog). [R, Code und Doku gelesen]

Das ist genau Weg D, den diese Studie als „Jahre“ eingeschätzt hat, und er existiert schon. Damit:
- **Eigener Hybrid lohnt sich nicht mehr.** Er wäre Monate Arbeit, nur für Unity-IL2CPP und mit Shader-Umwandlung;
  Madeira deckt Mono, IL2CPP und alle anderen Windows-Spiele ab und wird von anderen gepflegt.
- **Empfehlung:** EverPlay erkennt Unity- und andere Windows-Spiele (gibt es schon, `EngineFingerprint`) und bietet
  „Mit Madeira spielen“ an (Anleitung + `madeira://play?exe=…`, siehe unten). Aufwand: Tage.
- Testspiele (Fellworld, FantasyStudio) in Madeira auf dem iPhone ausprobieren; das wäre der erste Wert der Stufe
  „auf dem iPhone bestätigt“.

Frühere Einschätzung (gilt weiter für einen *eigenen* Bau ohne Madeira): Beide Testspiele sind IL2CPP mit nur
D3D11-Shadern; ein Android-Unity-Player hilft dafür nicht, und Mono-ARM64 gibt es auf Android nicht.

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

Geprüft mit `scripts/unity_probe.py` (liest nur Dateinamen und Daten-Header, UnityPy für die Shader). [R, Dateien gelesen]

| Spiel | Unity-Version | Backend | Shader-GPU-Programme | Native Plugins | Anmerkung |
|---|---|---|---|---|---|
| FantasyStudio (Demo, itch.io) | 6000.0.60f1 (Unity 6) | **IL2CPP** | nur D3D11 (55 Shader) | `lib_burst_generated.dll`, `steam_api64.dll` (x86-64) | Liegt mit `D3D12/`. Der Entwickler hat versehentlich `FantasyStudio_BackUpThisFolder_ButDontShipItWithYourGame/il2cppOutput` (generierter C++-Code des Spiels) mitgeliefert. |
| Fellworld | 2021.3.18f1 | **IL2CPP** | nur D3D11 (32 Shader) | `lib_burst_generated.dll` (x86-64) | |
| (zwei weitere, Gofile) | – | – | – | – | nicht geladen: Gofile-Download braucht ein Gastkonto über die API, das in dieser Umgebung nicht erlaubt wurde |

Folgen:
- **Kein Testspiel ist Mono.** Der Mono-Weg (A) trifft auf keines zu. Beide brauchen den IL2CPP-Weg, also
  x86-64-Code (`GameAssembly.dll`) auf ARM64.
- **Kein Testspiel hat Shader für eine andere API als D3D11.** Selbst mit laufendem Code gäbe es ohne
  DXBC-Umwandlung kein Bild.
- **Burst**: `lib_burst_generated.dll` ist von Unity vorab zu x86-64 kompilierter Code für Jobs. Fehlt er, fällt Unity auf
  den verwalteten Code zurück (bei IL2CPP: in `GameAssembly.dll` enthalten), d. h. weglassen wäre möglich [R, Unitys
  Burst-Verhalten; ungetestet].
- Die mitgelieferte `il2cppOutput` von FantasyStudio wäre theoretisch für ARM64 neu übersetzbar (das ist genau, was
  Unitys eigener Android-/iOS-Build tut, mit `libil2cpp` aus dem Unity-Editor 6000.0.60f1). Das ist ein Zufall
  dieses einen Spiels, verlangt die Unity-Editor-Installation und würde Spielcode auf dem Build-Rechner übersetzen
  und in ein Artefakt packen; beides schließen die Regeln aus. Nicht weiterverfolgt.

Erkennung (nur Dateinamen und Header lesen, nichts ausführen):
- **Mono**: `<Name>_Data/Managed/Assembly-CSharp.dll` vorhanden, `MonoBleedingEdge/` neben der `.exe`.
- **IL2CPP**: `GameAssembly.dll` neben der `.exe` und `<Name>_Data/il2cpp_data/Metadata/global-metadata.dat`.
- **Version**: steht als Text im Kopf von `<Name>_Data/globalgamemanagers` (bzw. `mainData` bei alten Versionen,
  `data.unity3d` bei komprimierten Builds), z. B. `2021.3.16f1`; zusätzlich in der Dateiversion von `UnityPlayer.dll`.

## Wie Android-Launcher Unity-Spiele starten

- **JoiPlay** [R]: unterstützt laut eigener Seite RPG Maker, Ren'Py, TyranoBuilder, Construct 2/3, Godot (GDScript),
  Flash und HTML5. **Kein Unity** ([joiplay.net](https://joiplay.net/)). Nutzerberichte auf itch.io bestätigen, dass
  Unity-Spiele dort nicht laufen.
- **MinHub** [R]: Android-App von „h-game18“ (Patreon `hgame18`), Changelog unter `h-game18.xyz/minhub-changelog/`
  (Cloudflare-geschützt; gelesen aus einer PDF-Abschrift, die der Auftraggeber geschickt hat). Was dort zu Unity steht:
  - **0.9.1 (2026-10-10)**: „Play Unity games (Beta). MinHub can now run Windows games made with Unity.“ Einmal eine
    „free Unity runtime“ laden (**ca. 150 MB, ARM64, Android 8+**), dann den Spielordner mit `.exe`, `UnityPlayer.dll`
    und `_Data` importieren. „The first launch of a game takes longer while it is prepared.“ „Unity saves are stored
    inside the Unity runtime. Uninstalling the runtime deletes them.“ (→ die Runtime ist eine eigene App/APK.)
  - **0.9.2**: Runtime 1.0.0-beta2, Speicherstand-Cheat (Zahl suchen und ändern), 60-FPS-Grenze.
  - **0.9.3**: Runtime 1.0.0-beta3, „textures use much less memory“ auf Mali-GPUs, „every Unity game opens in
    **borderless fullscreen**“, Texturspeicher-Sparmodus, 30/60 FPS.
  - **0.9.6 (2026-10-26)**: getrennt davon eine „MinHub EXE Runtime“ für beliebige Windows-EXE-Spiele mit Wahl
    **WineD3D/DXVK**. „Unity games keep their existing runtime.“
  - **0.9.7**: Runtime 1.0.0-beta4, läuft auf Android 15/16, Sprachwahl.

  **Belegt durch die Dateilisten der APKs** [R, nur `unzip -l` und `strings` auf `classes.dex`, nichts ausgeführt]:
  - MinHub 0.9.7 selbst enthält keinen Unity-Player. Es lädt `Plugin/Unity/1.0.0-beta4/MinHubUnityRuntime.apk`
    (Paket `com.minhub.unityruntime`, Signatur geprüft) und startet darin `com.winlator.MinHubLaunchActivity`.
    Die EXE-Runtime (`com.minhub.exeruntime`) startet `com.winlator.ExeLaunchActivity`.
  - Die Unity-Runtime (157 MB) ist ein **Winlator-Fork**: `assets/box64/box64-0.4.4.tzst`, `assets/rootfs.tzst`
    (65 MB, Linux-Userland mit Wine), `dxwrapper/dxvk-1.10.3`, `dxvk-2.4.1`, `vkd3d-2.14.1`, `d7vk`, `d8vk`,
    `cnc-ddraw`, `wincomponents/direct3d`, `vcrun2005/2010`, `xaudio`, GPU-Treiber `turnip-26.2.0`, `zink`, `virgl`,
    `vortek`, `gladio`, dazu `libwinlator.so`, `libvortekrenderer.so`, `libvirglrenderer.so`, PulseAudio.
  - **MinHub führt also den Windows-Player des Spiels unverändert aus**: Box64 (x86-64→ARM64) + Wine + DXVK
    (D3D11→Vulkan). Kein Android-Unity-Player, kein Mono-Trick. Damit laufen IL2CPP- und Mono-Spiele gleich, und
    D3D11-Shader sind kein Problem. Die „Unity-Runtime“ ist ein auf Unity voreingestelltes Winlator.
  - Das bestätigt den Befund dieser Studie: Es gibt keinen Unity-spezifischen Abkürzungsweg; auch auf Android geht es
    nur über Windows-Emulation (Weg D).

- Laut Auftraggeber gibt es unter den gewünschten Spielen **fast keine Mono-Spiele**; die Mehrheit ist IL2CPP.
  Damit ist Weg A (Mono) auch praktisch bedeutungslos.
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

Das, was Winlator auf Android macht, und nachweislich auch MinHubs Unity-Runtime (siehe oben). Es ist der
einzige Weg, der IL2CPP-Spiele und D3D11-Shader ohne Umbau abdeckt, weil Unitys eigener Windows-Player läuft.
Auf iOS fehlt dafür fast alles [R]:
- Box64 setzt Linux voraus (Syscalls, ELF-Loader, eingepackte Linux-Bibliotheken). Für iOS müsste der Dynarec in
  den JIT-Bereich (RX/RW-Paar wie Husk) und die Linux-Schicht durch Darwin ersetzt werden; FEXCore (ohne Frontend,
  wie in AetherPS4) wäre die Alternative.
- Wine braucht einen eigenen `wineserver`-Prozess; iOS-Apps dürfen keine Prozesse starten. Er müsste als Thread im
  selben Prozess laufen. Wine für iOS gibt es nicht.
- D3D11 → Vulkan (DXVK) → Metal (MoltenVK) bzw. WineD3D → OpenGL → ANGLE/Metal: beides auf iOS ungetestet, DXVK
  braucht Vulkan-Funktionen, die MoltenVK nur teilweise hat.
- Lizenzen: Box64 MIT, FEX MIT, Wine LGPL-2.1, DXVK zlib, MoltenVK Apache-2.0. Wäre verteilbar; die Unity-Dateien
  bringt das Spiel selbst mit (kein Lizenzproblem wie bei einem separaten Player).
Aufwand: ein eigenes „Winlator für iOS“, Größenordnung Jahre. Davon würden alle Windows-Spiele profitieren, nicht
nur Unity. Für diese Studie nicht weiterverfolgt.

### Weg E: UTM (QEMU, ganzer PC emuliert)

[UTM](https://github.com/utmapp/UTM) läuft auf iOS (mit JIT per Sideload/StikDebug; UTM SE ohne JIT nur interpretiert)
und emuliert einen ganzen Rechner mit QEMU-TCG. iOS hat keinen Hypervisor, also wird jede Anweisung übersetzt, mit
Software-MMU; Husk nennt genau diesen Modus „much slower“ als seine Translation Layer. [R, nicht gemessen]
- Windows-Gast: keine 3D-Beschleunigung in UTM → D3D11 nur über WARP (Software) auf emulierter CPU. Für Unity unbrauchbar.
- Linux-Gast mit Wine: OpenGL über virgl (→ ANGLE/Metal) ist beschleunigt, WineD3D macht D3D11 → OpenGL. Spielcode doppelt
  übersetzt (ARM-Gast + Box64, oder x86-Gast über TCG). Ein Bild ist denkbar, flüssiges Spielen kaum; Gast-RAM von
  mehreren GB ist auf dem iPhone knapp.
- Lizenz: QEMU ist GPLv2-only, mit GPLv3-Code (EasyRPG) im selben Prozess nicht kombinierbar; UTMs App-Code ist
  Apache-2.0, ebenfalls nicht GPLv2-kompatibel (siehe Husks `docs/01-licensing.md`). Für EverPlay also höchstens:
  auf UTM verweisen, nicht einbauen.
- Prüfbar ohne Code: UTM mit JIT installieren, ARM64-Linux + Box64 + Wine + virgl, Fellworld starten, FPS notieren.
  Das wäre der erste echte Messwert dieser Studie (Stufe „auf dem iPhone bestätigt“).

### Gemeinsamer Baustein für A und B: Shader-Umwandlung

DXBC → GLSL ES / MSL. Unitys eigener Übersetzer [HLSLcc](https://github.com/Unity-Technologies/HLSLcc) macht genau
DXBC → GLSL/Metal (so baut Unity selbst GLES/Metal-Shader). Ein Offline-Konverter müsste in jeder Shader-Asset-Datei die
D3D11-Unterprogramme übersetzen und als GLES3-Unterprogramme samt Parameter-/Binding-Tabellen eintragen. Aufwand: Wochen
bis Monate, versionsabhängig (Shader-Serialisierung ändert sich zwischen Unity-Versionen).

## Madeira im Detail und Anbindung an EverPlay

Gelesen bei Commit `e3a88fd` (2026-10-23). [R]
- Aufbau: `wine/`, `FEX/`, `dxmt/`, `madeira-dock/` sind Madeiras eigene Forks (Submodule); `app/` die iOS-App,
  `madeira-d3d12/` D3D12 auf Metal (DXIL über Apples proprietären Metal Shader Converter, per `dlopen`).
- Lizenz: App GPL-3.0-or-later mit Ausnahme für Apples Converter; Wine-Fork LGPL-2.1+ (statisch gelinkt, mit
  Relink-Pflichten); FEX- und DXMT-Fork: Upstream MIT, Madeiras Änderungen GPL-3.0+. VC++-Runtime nicht enthalten.
- Spiele hinzufügen: Ordner per Dateien-App nach **Madeira › wine › drive_c** kopieren, dann `+` und die `.exe`
  wählen (`docs/LIBRARY.md`). Start von außen: URL-Schema `madeira://play?exe=…` (Home-Bildschirm-Kurzbefehle,
  `ShortcutRouter`). EverPlay kann nicht in Madeiras Container schreiben; der Nutzer muss den Ordner selbst kopieren.

Varianten für EverPlay:
1. **Weiterreichen (empfohlen, Tage):** Bei Unity/Windows-Spielen auf der Spieleseite „Mit Madeira spielen“:
   Anleitung (installieren, JIT, Ordner nach `drive_c` kopieren), danach Knopf, der `madeira://play?exe=…` öffnet.
   Genaues Parameterformat vorher in `SavesAndShortcuts.swift`/`ShortcutRouter` nachlesen.
2. **Madeira in EverPlay einbauen (Monate, Dauerpflege):** FEX, Wine (ARM64EC) und DXMT in EverPlays Prozess, ein
   Spiel pro Start wie bei mkxp-z. Lizenz: EverPlay müsste als Ganzes GPL-3.0 sein; die Converter-Ausnahme gilt
   nicht für EasyRPG oder mkxp-z, also `madeira-d3d12` und den Apple-Converter weglassen (D3D11 über DXMT braucht
   ihn nicht). Riesiger Build (Wine, LLVM, FEX), JIT/Memory+-Pflicht für die ganze App. Nicht empfohlen.
3. **Eigener Hybrid** (siehe unten): durch Madeira überholt.

Weitere neue Projekte [R, nur gelesen, nicht gebaut]:
- [Leviidev/Fathom](https://github.com/Leviidev/Fathom): FEXCore im Prozess auf iOS für statische Linux-x86-64-ELFs,
  eigene Syscall-Schicht, noch ohne Threads und GPU. Zeigt FEX auf iOS, für Spiele zu früh.
- [AetherPS4](https://github.com/Leviidev/AetherPS4): PS4 (x86-64) auf iOS mit FEXCore und HLE, experimentell.
- [DXMT](https://github.com/3Shain/dxmt): D3D11 → Metal inklusive DXBC → Metal (airconv); für einen eigenen Hybrid
  wäre das der Shader-Konverter. DXVK 3.0 nutzt seit Juni 2026 `dxbc-spirv` (DXBC → SPIR-V).
- Switch-Emulatoren auf iOS: `eden-ios` (Switch 1) zeigt laut eigenem Stand (2026-09-11) noch kein Bild; Switch-2-
  Projekte (pound, oboromi) laufen noch keine kommerziellen Spiele. Switch-Code ist ohnehin ARM64, also ein anderes
  Problem als x86-64.

## Hybrid: Arbeitsstand

Entscheidung des Auftraggebers (2026-10-26): Der Hybrid wird trotz Madeira verfolgt (schneller für Unity, neu).
Schritte: M0 GameAssembly analysieren → M1 Android-`libunity.so` analysieren und abgleichen → M2 FEX + PE-Loader +
Mini-Win32 auf dem iPhone, `il2cpp_init` → M3 Husk-Unity-Treiber + Ersatz-`libil2cpp.so`, Engine startet →
M4 Shader-Umwandlung, erstes Bild.

### M0: `GameAssembly.dll` von Fellworld (2021.3.18f1) — erledigt [R, Dateien gelesen, nichts ausgeführt]

Werkzeuge: `pefile` (Python) für den PE-Kopf; ein eigener Parser für `global-metadata.dat` v29 (r2unity zu bauen
wurde in der Cloud-Umgebung als „fremden Code kompilieren“ blockiert). Spielspezifisches steht hier nicht, nur Zahlen
und Unity-/Windows-API-Namen.

- **PE**: x86-64 (`0x8664`), Abschnitte `.text` 2,4 MB + `il2cpp` 14,7 MB Code, `.rdata` 4,6 MB, `.data` 4,1 MB,
  **TLS-Verzeichnis** vorhanden (statisches TLS nötig), **77 489 `.pdata`-Einträge** (x64-Unwind-Info), 527 Reloc-Blöcke.
- **Importe: 206 Funktionen aus 10 DLLs** = Umfang des Mini-Win32:
  - `KERNEL32` 158: Speicher (`VirtualAlloc/Protect/Query`, `Heap*`), Threads und Sync (`CreateThread`, SRW-Locks,
    CriticalSection, Condition Variables, Events, Semaphoren, Mutex, `Tls*`, `Fls*`, `QueueUserAPC`), Dateien
    (`CreateFileW`, `FindFirstFileExW`, Mapping, …), Zeit/Zeitzone, Locale/Codepages, Konsole,
    **Ausnahmen** (`RaiseException`, `RtlUnwindEx`, `RtlVirtualUnwind`, `RtlLookupFunctionEntry`, `RtlCaptureContext`),
    **GC-Thread-Stopp** (`SuspendThread`, `GetThreadContext`, `ResumeThread`).
  - `USER32` 5 (Fenster aufzählen, `MessageBoxA`) → Stubs. `ADVAPI32` 3 (Zufall). `ole32` 6 / `OLEAUT32` 10 (COM-Minimum,
    SafeArray/BSTR). `SHELL32` 2 (Ordnerpfade). `WS2_32` 4, `IPHLPAPI` 3 (Netz). `dbghelp` 2 (Stacktraces → Stub).
  - `baselib.dll` 13 (Unitys eigene Plattformschicht als zweite x64-DLL: Semaphoren, Thread-ID, DynamicLibrary) →
    nativ nachbauen statt übersetzen.
- **Exporte: 380, davon 235 `il2cpp_*`** = die Schnittstelle, über die die Engine mit dem Spielcode spricht. Dazu
  Brotli, ZStream und ~130 `mono_*`-Funktionen (Debugger-Unterstützung, für den Hybrid unwichtig).
- **Metadaten**: Version 29 (r2unity und Il2CppDumper können sie), 49 597 Methoden.
  - **45 P/Invokes**, alle aus der .NET-Bibliothek, Windows-APIs, die zur Laufzeit per `LoadLibrary`/`GetProcAddress`
    geholt werden: Registry (`RegOpenKeyEx` …), ntdll-Dateifunktionen (`NtCreateFile`, `NtQueryDirectoryFile`),
    Zeitzonen, Konsole, `BCryptGenRandom`, drei Fensterfunktionen (`GetActiveWindow`, `GetWindowRect`, `SetWindowPos`).
    → kommen zum Mini-Win32 dazu, meist als Stub.
  - **1 689 InternalCalls** (1 541 verschiedene Namen) = Aufrufe des Spielcodes in die Engine. Im Hybrid sind das
    ARM64-Funktionen der Android-`libunity`, die x86-64-Code aufruft → je ein Übergang x64 (Microsoft-Konvention) →
    ARM64 (AAPCS64). Lässt sich generisch erzeugen, wenn die Signaturen aus den Metadaten gelesen werden.

**Bewertung M0: kein Blocker.** Das Mini-Win32 ist mit rund 250 Funktionen überschaubar, die meisten sind dünne
Hüllen über Darwin/pthreads. Die drei schweren Stellen sind:
1. **x64-Ausnahmen** (C++-Exceptions, mit denen IL2CPP .NET-Exceptions umsetzt): ein x64-Unwinder auf `.pdata`
   (`RtlVirtualUnwind`, `RtlUnwindEx`) im übersetzten Code. Vorlage: Wines `ntdll` (LGPL), FEX hat Hilfen dafür.
2. **GC-Stopp** (Boehm): `SuspendThread` + `GetThreadContext` müssen den x86-Registerstand eines übersetzten
   Threads liefern. FEX kennt ihn, aber nur an sicheren Punkten.
3. **Übergänge** in beide Richtungen: 235 `il2cpp_*` (ARM → x64) und 1 689 InternalCalls plus Callbacks (x64 → ARM).

### M1: Android-`libunity.so` 2021.3.18f1 (IL2CPP, arm64) — erledigt [R, gelesen, nichts ausgeführt]

Quelle: Unitys offizielles Android-Modul für den Editor 2021.3.18f1 (Changeset `3129e69bc0c7`, macOS-Paket
`MacEditorTargetInstaller/UnitySetup-Android-Support-for-Editor-2021.3.18f1.pkg`, 553 MB; ein Linux-Paket gibt es
für diese Version nicht). Darin `Variations/il2cpp/Release/Libs/arm64-v8a/libunity.so` (25,6 MB), `libmain.so`,
`Classes/classes.dex`. Mit `bsdtar` ausgepackt, nur mit `readelf`/`strings` gelesen; nichts davon im Repo.

- **Laden**: `libmain.so` lädt per `dlopen` `libunity.so` **und `libil2cpp.so`**; `libunity` selbst hat keinen
  `NEEDED`-Eintrag für il2cpp und holt die API per Name. `NEEDED`: nur `libandroid`, `liblog`, `libz`, `libEGL`,
  `libm`, `libdl`, `libc` (Husk stellt alle bereit).
- **il2cpp-API: 228 Funktionsnamen** in `libunity`, **alle 228 exportiert die Windows-`GameAssembly.dll`** von
  Fellworld (dort 235; die 7 übrigen sind `il2cpp_profiler_*`). → Der Ersatz-`libil2cpp.so` kann jede Funktion 1:1 an
  den gleichnamigen Export der übersetzten DLL durchreichen.
- **InternalCalls**: Von den 1 670 InternalCall-Namen der Metadaten liegen alle `UnityEngine.*`-Aufrufe als
  Registrierungsnamen in `libunity` vor, **bis auf 8 `UnityEngine.Windows.WebCam.*`** (nur Windows; als Stub, der eine
  Ausnahme wirft). Die übrigen ~300 fehlenden sind `System.*`/`Mono.*`; die implementiert il2cpp selbst in
  `GameAssembly.dll`, sie gehen nicht an die Engine.
- **API-Funktionen mit Funktionszeigern** (brauchen Übergänge ARM64 ↔ x64 für Rückrufe):
  `il2cpp_set_memory_callbacks` (Allokator der Engine, häufig aufgerufen!), `il2cpp_register_log_callback`,
  `il2cpp_set_find_plugin_callback`, `il2cpp_unity_install_unitytls_interface` (Tabelle vieler Funktionszeiger),
  `il2cpp_gc_foreach_heap`, `il2cpp_gchandle_foreach_get_target`, `il2cpp_gc_set_external_allocation_tracker`,
  `il2cpp_gc_set_external_wbarrier_tracker`, `il2cpp_register_debugger_agent_transport` (Debugger, weglassen).
- **16-KiB-Seiten**: `libunity` ist mit 4-KiB-Ausrichtung gelinkt. Code endet bei `0x17e06ec`, Daten beginnen bei
  `0x17e2210` in derselben 16-KiB-Seite, aber dieser Anfang ist `GNU_RELRO` (nur beim Relozieren beschrieben). Laut
  Husks Seitenplanung (`husk-tl-elf.c`) ist das ohne Schreib-Emulation ladbar.

**Bewertung M1: Der Hybrid trägt.** Die Engine spricht den Spielcode über eine benannte API an, die die Windows-DLL
vollständig anbietet, und fast alle Engine-Aufrufe des Spielcodes gibt es in der Android-Engine.

Offene Risiken, die sich erst ab M3 auf dem Gerät klären:
- Ob `libunity` außer über die API auch **direkt in il2cpp-Strukturen** liest (etwa `Il2CppObject::klass`,
  Array-Länge, String-Zeichen). Gleiche Unity-Version → gleiche Strukturdefinitionen; Unterschiede zwischen
  MSVC (Windows) und Clang (Android) gibt es bei **Bitfeldern** (z. B. in `Il2CppClass`) und bei `long`
  (32 Bit unter Windows). Prüfbar durch Disassemblieren der Aufrufer von `il2cpp_object_get_class` u. ä.
- Aufrufkonventionen: Microsoft x64 ↔ AAPCS64, vor allem Strukturen als Wert und Rückgabe großer Strukturen bei
  InternalCalls. Signaturen aus den Metadaten lesen und Übergänge daraus erzeugen.
- Plattformkennung in den Daten (`StandaloneWindows64`) gegenüber dem Android-Player und die D3D11-Shader (M4).

**Ab M2 entsteht der Hybrid in einem eigenen Repo `UnityBridge` (GPL-3.0-or-later)**, Entscheidung des Auftraggebers
2026-10-26. Das Repo muss der Auftraggeber anlegen (die GitHub-Anbindung der Sitzung darf keine Repos erstellen).
Ein erster Commit (README, `docs/STATUS.md` mit M0/M1, GPL-3.0-Text) lag lokal bereit und wird nach dem Anlegen
gepusht. EverPlay bindet später nur die fertige Bibliothek ein, wie bei `WolfRPG.framework`.

### Stand im Repo UnityBridge (2026-10-27)

Weitere Arbeit und Doku in [Pander0212/UnityBridge](https://github.com/Pander0212/UnityBridge) (`docs/STATUS.md`).
- **[i] Auf dem iPhone bestätigt** (iPhone 15, iOS 26.6.2): FEXCore (AetherPS4s Darwin-Port) führt x86-64-Code aus,
  alle 8 Prüfungen der Test-App bestehen (Integer, Flags, SSE, Bridge-Aufruf, Threads, TLS, unausgerichtete
  Zugriffe, Code-Invalidierung). JIT über StikDebug, das die App selbst per `stikdebug://enable-jit` mit Skript
  aufruft; JIT aus StikDebugs App-Liste reicht auf iOS 26 nicht (App stirbt mit SIGTRAP).
- **[i] Auf dem iPhone bestätigt**: eigene Windows-Test-DLL unter FEXCore gegen das Mini-Win32, 25 von 25 Prüfungen
  (PE-Loader, Windows-Aufrufkonvention, Dateien, Sync-Objekte, Locale, Rückrufe in beide Richtungen).
- **[i] Auf dem iPhone bestätigt**: Threads (`CreateThread` u. a.), 27 von 27 Prüfungen. Offen für `il2cpp_init`:
  TLS und x64-Ausnahmen (zwei Anläufe von einem automatischen Filter abgebrochen, zurückgestellt).
- [R] M3: Husks Translation Layer (GPL-2.0+) übernimmt den Android-Teil (libunity.so laden, bionic, JNI, Unity-Treiber);
  UnityBridge braucht dazu ein virtuelles `libil2cpp.so`. Messung an Fellworld: 1.371 Engine-InternalCalls, davon
  1.186 nur Integer/Pointer, 166 mit Floats, keine Structs per Wert. Offene Risiken: Daten mit Zielplattform
  Windows (19 statt 13), DXT-Texturen, D3D11-Shader.

### M2: x64-Seite auf dem iPhone — nächster Schritt

Ziel: In einer Test-App (oder einem versteckten EverPlay-Modus) mit JIT `GameAssembly.dll` laden und `il2cpp_init`
bis zum Log „il2cpp initialisiert“ bringen, ohne Unity-Engine.
- [ ] FEXCore für iOS als Bibliothek: aus Madeiras FEX-Fork (Upstream MIT, Madeiras Änderungen GPL-3.0+) oder
      Fathoms Build. Zuerst prüfen, welcher Fork ohne Wine nutzbar ist (Fathom nutzt FEXCore ohne Wine).
- [ ] PE-Loader (Abschnitte, Relocs, Importe, TLS-Callbacks, `.pdata` registrieren).
- [ ] Mini-Win32 für die 206 Importe + 45 P/Invokes (Liste oben), `baselib.dll` nativ.
- [ ] Übergang ARM64 → x64 für die 228 `il2cpp_*`, x64 → ARM64 für Rückrufe.
- [ ] Build über GitHub Actions (macOS), Test auf dem iPhone mit StikDebug/StikJIT; Spieldateien kommen vom Nutzer
      aufs Gerät, nie in Build oder Artefakte.

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
- [r2unity](https://github.com/radareorg/r2unity) (MIT): radare2-Plugin und CLI, liest `global-metadata.dat`
  (Metadaten v24.1–v35, v38/v39; Windows-, Android-, iOS-Layouts), löst Methodenadressen auf, listet **P/Invoke** und
  **Reverse-P/Invoke**. Führt nichts aus und übersetzt nichts. Nützlich für den Hybrid: Reverse-P/Invoke = Einsprünge,
  die Thunks brauchen; P/Invoke = Windows-DLLs, die der Win32-Nachbau abdecken muss. Skriptbar, daher für automatische
  Thunk-Tabellen besser geeignet als Il2CppDumper.

**Vergleich der zwei Übersetzer-Bauarten:**

| | Ganzes Windows (Box64 + Wine + DXVK, wie MinHub) | Hybrid (nur `GameAssembly.dll` übersetzt) |
|---|---|---|
| Engine | Windows-`UnityPlayer.dll`, übersetzt | ARM64-Android-`libunity.so`, nativ (Husk-Schicht) |
| Tempo | langsamer | deutlich schneller (Rendering, Physik nativ) |
| Shader | D3D11 über DXVK, kein Umbau | **Shader-Umwandlung DXBC → GLES nötig** |
| Unity-Player | bringt das Spiel mit | pro Version vom Nutzer zu beschaffen |
| Win32-Nachbau | komplett (Wine) | klein (Speicher, Threads, Dateien, Zeit) |
| Fehlt auf iOS | Wine ohne Prozesse, Box64 für Darwin | x86-64-JIT im Prozess (Box64/FEXCore), il2cpp-Shim, Shader-Konverter |
| Aufwand | Jahre, nützt allen Windows-Spielen | viele Monate, nur Unity-IL2CPP |

## Probiertes und Sackgassen

- Websuche nach MinHub: nur Patreon-Titel. Changelog-Seite und Patreon: 403 (Cloudflare), nicht umgangen; Inhalt
  später aus der PDF-Abschrift des Auftraggebers (siehe oben).
- JoiPlay: kein Unity.
- Vermutung „ARM64-Android-Unity-Player mit Mono“: Sackgasse, gibt es nicht (Unity-Doku).
- Testspiele: beide IL2CPP, beide nur D3D11-Shader (siehe Tabelle). Der Mono-Weg trifft auf keines zu.
- Die ZIPs der Testspiele nutzen teils LZMA-Kompression (ZIP-Methode 14), die `unzip` nicht kann; Python `zipfile`
  kann es. Für EverPlays Importer prüfen, ob ZIPFoundation Methode 14 kann (sonst schlägt der Import solcher ZIPs fehl).

## Nächste Schritte (Checkliste)

Mit Madeira (empfohlen):

- [ ] Auf dem iPhone: Madeira installieren (Release-IPA, JIT, Memory+), Fellworld und FantasyStudio nach `drive_c`
      kopieren und starten. Ergebnis (Bild? FPS? Absturz?) hier unter „auf dem iPhone bestätigt“ eintragen.
- [ ] `madeira://play?exe=…` nachlesen (`app/Madeira/SavesAndShortcuts.swift`, `ShortcutRouter`) und testen, ob ein
      Start aus einer anderen App (EverPlay) funktioniert.
- [ ] In EverPlay: Unity-/Windows-Meldung beim Import um „Mit Madeira spielen“ erweitern (Anleitung + Knopf).

Ohne Madeira (eigener Bau, nur falls Madeira ausfällt):

- [ ] Die zwei Gofile-Testspiele prüfen (`python3 -I scripts/unity_probe.py <Spielordner>`); als Mega-Link schicken lassen,
      falls Gofile weiter nicht geht. Ein **Mono**-Spiel mit **OpenGLCore- oder Vulkan-Shadern** wäre der einzig
      realistische Kandidat für Weg A.
- [x] MinHub-Changelog gelesen (PDF vom Auftraggeber).
- [x] MinHubs Unity-Runtime-APK aufgelistet: Winlator-Fork (Box64 + Wine + DXVK), siehe oben.
- [ ] Falls Weg D je angegangen wird: prüfen, ob es Box64-, Wine- oder Winlator-Portierungen für iOS/Darwin mit
      Debugger-JIT gibt (Stand 2026), und Winlators Lizenz im Wortlaut festhalten.
- [ ] Unity-Lizenzbedingungen zur Weitergabe der Runtime im Wortlaut zitieren.
- [ ] Für Weg A: von einer frei verfügbaren Android-APK mit Unity (IL2CPP, ARM64) gleicher Version die `il2cpp_*`-Importe
      von `libunity.so` auflisten (nur `readelf`, nichts ausführen). Ergibt die API-Fläche des Shims.
- [ ] Shader-Umwandlung bewerten: HLSLcc auf ein DXBC-Programm aus einem Testspiel anwenden (nur Shader-Bytecode,
      kein Spielcode) und prüfen, ob gültiges GLSL ES herauskommt.
- [ ] EverPlays Erkennung (`EngineFingerprint`) könnte bei Unity zusätzlich Mono/IL2CPP und die Version nennen
      (Logik wie in `scripts/unity_probe.py`). Kleiner, sicherer Gewinn für die Import-Meldung.

## Prototyp

`scripts/unity_probe.py`: liest aus einem Spielordner Unity-Version, Mono/IL2CPP, native Plugins und für welche
GPU-APIs die Shader kompiliert sind. Mit beiden Testspielen gelaufen (Ergebnis in der Tabelle). Nichts darüber hinaus
gebaut, weil die Abbruchgrenze erreicht ist.
