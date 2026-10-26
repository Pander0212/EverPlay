# EverPlay testen (Nightly in Feather)

Vorher: In Feather die Quelle aktualisieren und den neuesten **EverPlay nightly** installieren.
Die Versionsnummer steht in EverPlay unter Einstellungen (Zahnrad unten links) ganz unten.

Wenn etwas nicht klappt: In der Bibliothek unten links auf die **Lupe** tippen (Diagnose-Log),
oben rechts **Teilen** und mir den Text schicken. Bei Ren'Py-Fehlern zusätzlich auf der Spielseite
unter „Reports from Ren'Py“ die `traceback.txt` teilen.

## Stand

| Test | Stand |
|---|---|
| 1. Ren'Py-Tastatur (q und a sichtbar) | offen |
| 2. Ren'Py-Menü und Cheats | offen |
| 3. Spielstände sichern und wiederherstellen | offen |
| 4. App verlassen und zurückkehren (Antippen danach) | offen (im Simulator bestanden) |
| 5. App-Umschalter unscharf | erledigt, funktioniert |
| 6. RPG Maker MV/MZ: Speicher-Editor | offen (MV-Spiel selbst läuft) |
| 7. RPG Maker 2000/2003 | offen |
| 8. ONScripter | offen (niedrige Priorität) |
| 9. Import, auch Electron-Spiele mit `resources/app.asar` | offen |
| 10. Übersetzung und Übersetzungs-Editor | offen |
| 11. Bibliothek: Filter, Sortierung, Favoriten (langes Drücken auf ein Spiel) | offen |
| 12. RPG Maker XP/VX/VX Ace (mit RTP-Import) | läuft (Spotlight), Cheats neu und offen |
| 13. KiriKiri | offen (neu im Nightly, inkl. verschlüsselte Spiele) |
| 14. Bibliothek | offen (neu) |
| 15. Übersetzung: Apple + ganzes Spiel | offen (neu) |
| 16. Engine-Erkennung | offen (neu) |
| 17. Wolf RPG | offen (neu, experimentell) |

## 1. Ren'Py-Spiel: Tastatur (Namenseingabe)
1. Ein Spiel starten, das nach einem Namen fragt.
2. Erwartet: Eine eigene EverPlay-Tastatur (QWERTZ, mit ä/ö/ü) erscheint im Spiel, oben oder unten.
3. Namen tippen, mit **⌫** löschen, mit **Enter** bestätigen.
4. Melden: Erscheint die Tastatur? Kommen die Buchstaben an? Verdeckt sie etwas Wichtiges?

## 2. Ren'Py-Spiel: EverPlay-Menü und Cheats
1. Spiel starten. Oben links ist ein dunkles **☰**-Feld, schon auf dem ersten Bild (Disclaimer).
2. Feld gedrückt halten und verschieben: Es bleibt an der neuen Stelle.
3. Antippen: Menü mit 16 Feldern. **Quick save**, dann **Quick load** testen.
4. **Variables**: Oben ins Suchfeld tippen, die Tastatur erscheint. Z. B. `money` oder `=100` suchen.
   Bei einer Zahl **+100** tippen, dann **Close**. Wirkt der neue Wert im Spiel?
5. **Unlock gallery**, mit „Yes“ bestätigen, dann im Spiel die Galerie öffnen.

## 3. Spielstände
1. Einstellungen, Abschnitt **Saves & cheats**: das Spiel antippen.
2. **Back up all saves now**: Ein Backup erscheint in der Liste.
3. Im Spiel einen neuen Spielstand anlegen, dann hier das Backup antippen und **Restore backup**.
   Erwartet: Der alte Stand ist wieder da.

## 4. App verlassen und zurückkehren (Ren'Py)
1. Ren'Py-Spiel starten und ein paar Mal tippen.
2. a) Kurz zum Homescreen und sofort zurück. b) Handy sperren, 10 Sekunden warten, entsperren.
   c) Andere App öffnen, 1 Minute warten, zurück.
3. Erwartet: Das Spiel reagiert danach sofort auf Tippen, Musik läuft weiter.
4. Melden: Welcher Fall hängt? Bewegt sich noch etwas im Bild, oder steht es komplett?

## 5. App-Umschalter
1. Ein Spiel spielen (Ren'Py oder Web).
2. Vom unteren Rand hochwischen und halten (App-Umschalter).
3. Erwartet: EverPlay ist unscharf, mit einem Auge-Symbol. Kein Spielbild zu sehen.

## 6. RPG Maker MV/MZ: Speicher-Editor
1. Ein MV/MZ-Spiel starten, im Spiel speichern (z. B. Slot 1).
2. Spielmenü (oben rechts) › Cheats › **Save editor**: Der Slot erscheint mit Spielzeit und Datum.
3. Slot antippen: Gold auf 5000 setzen, bei einer Figur **Max** (Level), unter Items einen Trank **+10**.
4. Im Spiel diesen Spielstand laden. Erwartet: Gold, Level und Items sind geändert.
5. Melden: Kam eine Fehlermeldung (Text abschreiben)? Welches Spiel, MV oder MZ?

## 7. RPG Maker 2000/2003
1. Ein 2000/2003-Spiel (Ordner mit `RPG_RT.ldb`) als ZIP über **+ → ZIP from Files** importieren.
2. Spielen: Steuerkreuz und A/B unten, **…** oben rechts für Quick save/Quick load.
3. Melden: Startet das Spiel? Ton? Fehlen Grafiken (dann braucht das Spiel die RTP)?

## 8. ONScripter (sobald im Update enthalten)
1. Ein ONScripter-Spiel (Ordner mit `0.txt`, `00.txt` oder `nscript.dat`) als ZIP importieren.
2. Starten: Das Spiel läuft im Web-Player. Langes Drücken öffnet das ONScripter-Menü.
3. Melden: Startet es? Ist Text zu sehen (das Spiel braucht eine `default.ttf`)? Ton? Speichern und Laden?

## 9. Import (auch Electron)
1. **Degrees of Lewdity** als ZIP importieren: Ein Fortschrittsbalken mit Prozent läuft.
2. Ein Electron-Spiel (ZIP mit `resources/app.asar`, z. B. TyranoScript 5) importieren und starten.

## 10. Übersetzung (optional)
1. Einstellungen, **Translation**: Service „Google (free)“, Sprache Deutsch.
2. Spielseite eines englischen Ren'Py-Spiels, **Translate this game** einschalten.
3. Spielen: Dialoge kommen auf Deutsch, nach kurzer Wartezeit pro neuer Zeile.
4. Danach auf der Spielseite **Edit translations**: Alle übersetzten Zeilen erscheinen. Eine antippen,
   korrigieren, **Save**. Beim nächsten Spielstart steht die korrigierte Zeile im Spiel.

## 11. Bibliothek
1. Mindestens zwei Spiele in der Bibliothek: Oben erscheinen Filter (All, Favorites, Ren'Py, RPG Maker, Web).
2. Filter antippen: Nur passende Spiele bleiben. Pfeil-Symbol rechts: Sortierung wechseln.
3. Lange auf ein Spiel drücken › **Add to favorites**: Stern am Titel, das Spiel steht oben.

## 12. RPG Maker XP/VX/VX Ace (experimentell)
1. Ein XP-, VX- oder VX-Ace-Spiel als ZIP importieren (Ordner mit `Game.ini` und `Game.rgss3a`/`.rgss2a`/`.rgssad`
   oder `Data/Scripts.rxdata`).
2. Spielseite öffnen: Braucht das Spiel eine RTP (z. B. `RPGVXAce`), steht dort **RPG Maker RTP** mit einem
   orangen Warnzeichen. **Get RTP › Download from rpgmakerweb.com** tippen: EverPlay lädt die kostenlose
   offizielle RTP (VX Ace ca. 190 MB, also lieber im WLAN) und entpackt sie. Danach grüner Haken.
   Kein PC nötig. (Alternativ **Import file…** mit der RTP-ZIP oder `Setup.exe`.)
3. Starten: mkxp-z übernimmt den Bildschirm im Querformat. Beenden schließt EverPlay (wie bei Ren'Py).
4. Melden: Startet es? Bild, Ton? Bei einem Absturz EverPlay neu öffnen und das Diagnose-Log schicken:
   Darin steht jetzt die Ausgabe von mkxp-z und, falls es abstürzt, die Absturzstelle.
5. Spielstände: Im Spiel speichern, Spiel beenden, EverPlay neu öffnen. Erwartet: Der Spielstand liegt in
   Dateien unter **Auf meinem iPhone › EverPlay › Saves › (Spielname)** (`Save01.rvdata2` usw.).
6. **☰** oben links (neben dem Controller-Symbol) öffnet dasselbe **Game menu** wie bei MV/MZ: Tasten
   ein/aus, Deckkraft, **Edit controls**, **Cheats** (Gold, Gruppe, Level, Tempo, Durch Wände, Zufallskämpfe,
   Gott-Modus, Items, Variablen, Schalter) und **Quit game**.
7. Steuerung: Steuerkreuz unten links (auch schräg), rechts **OK**, **Back** (Abbrechen/Menü) und **Dash**.
   Das Controller-Symbol blendet die Tasten aus und ein.
8. **Edit controls**: Tasten verschieben, antippen zum Vergrößern/Löschen/„Hold“ (gedrückt bleiben), über **Add**
   neue Tasten hinzufügen (z. B. A/S/D/Q/W für Spiele, die die nutzen), **Done**. Das Layout bleibt pro Spiel
   gespeichert; **Layout › Save as default** gilt für alle neuen XP/VX-Spiele.

## 13. KiriKiri
1. Ein KiriKiri-Spiel (Ordner mit `data.xp3` und meist einer `.exe`) als ZIP importieren. Es erscheint unter
   dem Filter **Visual novels**.
2. Starten: Das Spiel läuft im Querformat. Tippen = Klick, **zwei Finger tippen** = Rechtsklick (Menü/zurück).
   Oben links **☰**: Menü, Backlog, Skip an/aus, Auto an/aus, Spiel beenden (EverPlay schließt sich dann).
3. Spielstände liegen in Dateien unter **EverPlay › Saves › (Spielname)**.
4. Verschlüsselte Spiele (viele kommerzielle, z. B. Steam-Versionen): Beim ersten Start erkennt EverPlay das
   und zeigt **Encrypted game** mit einer Liste aus GARbro (braucht einmal Internet). Oben stehen Vorschläge
   passend zum Spielnamen – das richtige Spiel antippen. Falsch gewählt? Beim Fehler **Choose another key**
   tippen und neu starten. Steht das Spiel nicht in der Liste, geht es noch nicht.
5. Melden: Startet es? Text, Bild, Ton, Videos? Bei Problemen das Diagnose-Log schicken (enthält das Engine-Log).

## 14. Bibliothek
1. Startseite: Oben das zuletzt gespielte Spiel groß mit **Play**, darunter **Recently played** (ab 4 Spielen),
   dann alle Spiele als Cover-Raster. Das Symbol neben dem Sortieren-Knopf schaltet zwischen Cover und Liste um.
2. Cover antippen = Spieleseite, runder ▶-Knopf auf dem Cover = sofort spielen, lange drücken = Menü
   (Favorit, Ausblenden, Archivieren/Löschen).
3. Eigenes Cover: Spieleseite › **Change cover** › aus Fotos oder Dateien wählen. **Use the game's picture**
   setzt es zurück.

## 15. Übersetzung: Apple und ganzes Spiel vorab
1. Einstellungen › Translation › Service **Apple (on device)** (braucht iOS 26). **Games are in**: Sprache der
   Spiele (oder automatisch), **Translate into**: deine Sprache. **Download languages** tippen: iOS lädt die
   Sprachen (eigenes Fenster). Danach geht es offline und gratis.
2. RPG Maker MV/MZ: Spieleseite › **Translate this game** an › **Translate the whole game now**. Fortschritt läuft,
   die Seite darf zu, man darf schon spielen. Danach erscheinen die Texte sofort übersetzt.
3. Ren'Py: Übersetzung auf der Spieleseite an, Spiel starten, ☰ › **Translate whole game**. Läuft im Hintergrund.

## 16. Engine-Erkennung
1. Ein Spiel importieren, das EverPlay nicht spielen kann (z. B. Unity, Unreal, Godot, GameMaker).
   Erwartet statt „not supported“: „This is a Unity game (found UnityPlayer.dll, …)“ plus Einschätzung, ob es
   aufs iPhone kommen kann. Bei ZIPs passiert das sofort, ohne erst alles zu entpacken.

## 17. Wolf RPG
EverPlay spielt WOLF-RPG-Editor-Spiele (Version 2 und 3) jetzt mit einer eigenen, nativen Engine
(kein Web, kein WASM). Sie ist neu und experimentell: Rechne mit Fehlern in einzelnen Spielen.
1. Ein Wolf-Spiel als ZIP importieren: den Spielordner mit `Game.exe` und dem Ordner `Data` (darin
   `BasicData/Game.dat`) oder mit `.wolf`-Archiven (`Data.wolf` bzw. `Data/BasicData.wolf` usw.).
   Es erscheint unter dem Filter **RPG Maker** mit „WOLF RPG Editor“.
2. Starten: Das Spiel läuft im Querformat. Unten links das Steuerkreuz, rechts **OK**, **Back** (Abbrechen)
   und **Shift**. Oben links blendet der Controller-Knopf die Steuerung aus und ein, **☰** öffnet die Cheats.
   Tippen ins Bild ist ein Mausklick: Spiele mit Maussteuerung (viele WOLF-3-Spiele) bedient man direkt
   per Finger, dann am besten die Steuerung ausblenden. **Zwei Finger tippen** = Rechtsklick (oft „zurück“).
3. Spielstände liegen in Dateien unter **EverPlay › Saves › (Spielname)** (`SaveNN.everplay.sav`, ein eigenes
   Format, nicht mit dem PC austauschbar).
4. App-Wechsel: Home-Geste, kurz warten, zurück zu EverPlay. Das Spiel sollte pausiert sein und weiterlaufen.
5. Cheats (☰): Spielgeschwindigkeit, durch Wände gehen, Variablen ansehen und ändern, Geld (wenn das Spiel eine
   Variable „所持金“/„Money“ hat). Gegenstände und Schalter gibt es bei Wolf nicht.
6. Spiel beenden: über das Spielmenü (EverPlay schließt sich dann, wie bei RPG Maker XP/VX).

Noch nicht möglich:
- Spiele aus WOLF RPG Editor **Pro**, deren Archive einen spieleigenen Schlüssel brauchen. EverPlay sagt das
  beim Import und beim Start. Abhilfe: entpackte Spieldateien verwenden. Normale `.wolf`-Archive (WOLF 2.x
  und 3.x bis 3.5) gehen.
- Spiele mit eigenem Nachrichtensystem zeigen manchmal keinen Text (bekannt bei „MY“).
- Videos und Tastatur-Texteingabe fehlen noch; das Mausrad gibt es per Touch nicht.

Melden: Startet es? Bild, Ton, Musik (auch MIDI), Text, Steuerung, Speichern/Laden? Bei Problemen das
Diagnose-Log schicken: Es enthält die Ausgabe der Wolf-Engine vom letzten Spiel.
