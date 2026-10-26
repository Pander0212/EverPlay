# Unity-Windows-Spiele auf dem iPhone: Machbarkeitsstudie

Branch `claude/unity-research` (von `claude/beautiful-wozniak-ryh9su`). Dies ist eine Studie, kein Support.
Diese Datei wird nach jedem Schritt gepflegt; die Arbeit wechselt zwischen Accounts.

Kennzeichnung jeder Aussage:
- **[R]** recherchiert (Quelle oder gelesener Code)
- **[S]** im Simulator gesehen
- **[i]** auf dem iPhone bestätigt

Stand: 2026-10-26. Alles ist **[R]**; nichts wurde im Simulator oder auf dem iPhone gesehen.

## Ergebnis

**Geht nicht, für die vorliegenden Testspiele. Abbruchgrenze erreicht:** Es ist kein Weg erkennbar, auf dem eines
der Testspiele in absehbarer Zeit auch nur ein Bild zeigt. Beide geprüften Spiele sind IL2CPP (x86-64-Spielcode) und
haben nur D3D11-Shader. Dafür bräuchte es gleichzeitig einen x86-64→ARM64-Übersetzer mit Win32-Nachbau im Prozess
und eine Shader-Umwandlung DXBC → GLES/Metal, beides Projekte in der Größenordnung von Monaten bis Jahren.

Für Mono-Spiele allgemein: **geht nicht auf dem im Auftrag vermuteten Weg; höchstens unter starken Bedingungen**
(Weg A unten, Forschungsaufwand in Monaten), und auch dann nur mit Shader-Umwandlung.

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

- Websuche nach MinHub: nur Patreon-Titel. Changelog-Seite und Patreon: 403 (Cloudflare), nicht umgangen; Inhalt
  später aus der PDF-Abschrift des Auftraggebers (siehe oben).
- JoiPlay: kein Unity.
- Vermutung „ARM64-Android-Unity-Player mit Mono“: Sackgasse, gibt es nicht (Unity-Doku).
- Testspiele: beide IL2CPP, beide nur D3D11-Shader (siehe Tabelle). Der Mono-Weg trifft auf keines zu.
- Die ZIPs der Testspiele nutzen teils LZMA-Kompression (ZIP-Methode 14), die `unzip` nicht kann; Python `zipfile`
  kann es. Für EverPlays Importer prüfen, ob ZIPFoundation Methode 14 kann (sonst schlägt der Import solcher ZIPs fehl).

## Nächste Schritte (Checkliste)

Nur sinnvoll, wenn Unity trotz des Ergebnisses weiterverfolgt werden soll:

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
