# Snow Rush Pets, Version 2

Alle 51 Pets aus dem Konzept «02 - Snow Rush» (Abschnitt 7.9 und Anhang Pet-Katalog), Stand 11. November 2026.

## Inhalt

- `modelle/`: 51 Modelle als `.glb` (glTF 2.0), die Textur ist eingebettet
- `texturen/`: pro Pet vier Texturen: `_textur` (normal), `_gold`, `_regenbogen`, `_frostig`
- `vorschau/`: pro Pet ein Bild mit 512 × 512 Pixeln und durchsichtigem Hintergrund
- `uebersicht.png`: alle Pets nach Ei und Seltenheit
- `pets.json`: Daten pro Pet: Ei, Seltenheit, Chance, Coin-Bonus, Grösse, Dreiecke, Texturen, Effektfarben, Merkmale
- `sammelbuch.html`: alle Pets drehbar im Browser, mit Umschalter für die Varianten

## Technik

- Ein Mesh und eine Textur pro Pet (256 × 128 Pixel), unter 3'000 Dreiecken
- 1 Einheit = 1 Stud, Y zeigt nach oben, die Vorderseite zeigt nach +Z, der Nullpunkt liegt unten in der Mitte
- Grösse nach Seltenheit: Gewöhnlich 2.7, Ungewöhnlich 2.9, Selten 3.1, Episch 3.4, Legendär 3.7, Geheim 3.9 Studs (Körper ohne Glitzer und Heiligenschein; bei langen oder breiten Pets entsprechend weniger hoch). Die Masse in `pets.json` sind die ganze Box inklusive Glitzer.
- Schatten und Farbverläufe stecken in der Textur, darum sehen die Pets auch mit einfachem Licht auf dem Handy plastisch aus
- Glitzersterne und Heiligenscheine sind Teil des Modells

## Import in Roblox Studio

Getestet am 18.11.2026 auf einer lokalen Baseplate: Schneehase und Rotfuchs mit dem 3D Importer.

1. Die Grösse stimmt mit `pets.json` überein (Rotfuchs 4.23 × 3.74 × 3.39, Schneehase 1.74 × 2.70 × 1.69 Studs).
2. Die Ausrichtung ist automatisch korrekt, keine Drehung nötig.
3. Die eingebettete Textur ist sichtbar. Die Gold-Textur lässt sich per `TextureID` tauschen.

## Varianten

Gold, Regenbogen und Frostig brauchen kein eigenes Modell: Es reicht, die Textur des Pets gegen die passende Datei aus `texturen/` zu tauschen.

## Wow-Effekt beim Schlüpfen (Vorschlag)

- Partikel und Licht in den zwei `effektfarben` aus `pets.json`
- Je seltener, desto mehr: Gewöhnlich kurzer Schein, Selten Glitzer, Episch zusätzlich Lichtstrahlen, Legendär und Geheim zusätzlich die Einblendung, die im Konzept schon vorgesehen ist (7.9)
- Die Pets sind nach Seltenheit unterschiedlich gross, das macht seltene Pets schon beim Mitlaufen erkennbar

## Offen

- Englische Namen ab Ei 3 fehlen noch (Konzept: Development übersetzt nach demselben Muster)
- Goldener Yeti: Das Konzept sagt in 7.9 «ab Welt 2», die Roadmap sagt Update 3
