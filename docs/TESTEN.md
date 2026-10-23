# EverPlay testen (Nightly in Feather)

Vorher: In Feather die Quelle aktualisieren und den neuesten **EverPlay nightly** installieren.
Die Versionsnummer steht in EverPlay unter Einstellungen (Zahnrad unten links) ganz unten.

Wenn etwas nicht klappt: In der Bibliothek unten links auf die **Lupe** tippen (Diagnose-Log),
oben rechts **Teilen** und mir den Text schicken. Bei Ren'Py-Fehlern zusätzlich auf der Spielseite
unter „Reports from Ren'Py“ die `traceback.txt` teilen.

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

## 4. App-Umschalter
1. Ein Spiel spielen (Ren'Py oder Web).
2. Vom unteren Rand hochwischen und halten (App-Umschalter).
3. Erwartet: EverPlay ist unscharf, mit einem Auge-Symbol. Kein Spielbild zu sehen.

## 5. RPG Maker 2000/2003
1. Ein 2000/2003-Spiel (Ordner mit `RPG_RT.ldb`) als ZIP über **+ → ZIP from Files** importieren.
2. Spielen: Steuerkreuz und A/B unten, **…** oben rechts für Quick save/Quick load.
3. Melden: Startet das Spiel? Ton? Fehlen Grafiken (dann braucht das Spiel die RTP)?

## 6. Import
1. **Degrees of Lewdity** als ZIP importieren: Ein Fortschrittsbalken mit Prozent läuft.
2. **Ordner auswählen** über + → Game folder. Wenn „Öffnen“ nichts tut: Diagnose-Log schicken.

## 7. Übersetzung (optional)
1. Einstellungen, **Translation**: Service „Google (free)“, Sprache Deutsch.
2. Spielseite eines englischen Ren'Py-Spiels, **Translate this game** einschalten.
3. Spielen: Dialoge kommen auf Deutsch, nach kurzer Wartezeit pro neuer Zeile.
