# Timecounter

Ein schlanker Zeiterfasser für die macOS-Menüleiste, inspiriert von [Tim](https://tim.neat.software/).
Entstanden, um die Arbeitszeit an einer Diplomarbeit zu messen.

*A small menu bar time tracker for macOS. The interface is in German.*

## Installation

```sh
brew install --cask julianglantschnig/tap/timecounter
```

Danach Timecounter aus dem Programme-Ordner starten, das Symbol erscheint oben in der Menüleiste.

> Timecounter ist nicht von Apple notarisiert (dafür braucht es ein kostenpflichtiges Entwicklerkonto).
> Die Homebrew-Installation entfernt deshalb die Quarantäne-Markierung, damit macOS die App öffnet.
> Wer das nicht möchte, kann die App selbst aus dem Quellcode bauen (siehe unten).

Voraussetzung: macOS 15 Sequoia oder neuer, Apple Silicon oder Intel.

## Funktionen

- Timer per Klick in der Menüleiste oder von überall mit **⌃⌥T**
- Projekte mit Farbe und Symbol, zusammengefasst in **Ordnern** mit Gesamtstunden
- Übersicht pro Ordner und Projekt: Kennzahlen, Ring mit Anteilen in Prozent, Balken pro Tag
- Tabelle aller Einträge wie in Tim, sortierbar, mit Notizen
- Mehrere Einträge eines Tages zu **einer Zeile zusammenführen**
- **Leerlauf-Erkennung**: war der Mac unbenutzt, lässt sich die Zeit abziehen
- **Tätigkeit erkennen** (optional): merkt sich, welche App vorne war, und schlägt daraus eine Notiz vor
- Export als CSV (Excel-tauglich), optional gerundet, mit Stundensatz und Betrag
- Import aller Aufgaben und Zeiten aus Tim
- Alle Daten bleiben lokal unter `~/Library/Application Support/Timecounter`

## Aus dem Quellcode bauen

Xcode 26 oder neuer:

```sh
git clone https://github.com/JulianGlantschnig/timecounter.git
cd timecounter
xcodebuild -project Timecounter.xcodeproj -target Timecounter -configuration Release SYMROOT=build build
cp -R build/Release/Timecounter.app /Applications/
```

## Neue Version veröffentlichen

```sh
scripts/release.sh 1.1
gh release create v1.1 dist/Timecounter-1.1.zip --title "Timecounter 1.1"
```

Danach in `Casks/timecounter.rb` im Repository `homebrew-tap` Version und `sha256` aktualisieren.

## Lizenz

MIT
