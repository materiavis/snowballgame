# petkit – Materiavis Pet-Generator

Erzeugt die Snow-Rush-Pets (Pets.zip, Version 2) als `.glb`: ein Mesh, eine eingebettete Textur (256 × 128), unter 3'000 Dreiecken.
Entstanden im November 2026 in Claude-Chats im Projekt «Materiavis»; die Originaldateien liegen dort unter `spiele/snow-rush-pets/`.

## Voraussetzungen

Python 3.10+ mit `numpy`, `scipy`, `scikit-image`, `Pillow` (für Ansichten zusätzlich `matplotlib`).

```
pip install numpy scipy scikit-image pillow matplotlib
```

## Benutzen

```
python3 bauen2.py schneehase                  # baut build2/schneehase.glb (ca. 20–40 s pro Pet)
python3 varianten.py build2 build2/tex        # Textur + Gold, Regenbogen, Frostig als PNG
python3 pruefen.py build2/*.glb --bilder build2/ansichten   # Prüfung vor dem Studio-Import
```

Die Slugs aller 51 Pets stehen in `pets_meta.py`. Ablauf: Pet ändern → bauen → prüfen → Ansichten anschauen.

## Dateien

| Datei | Inhalt |
|---|---|
| `petkit.py` | Grundwerkzeug: Formfelder (SDF), Marching Cubes, Reduktion mit Farbgrenzen, Baked AO, GLB-Export |
| `kit.py` | Baukasten: `Pet`-Klasse, Augen, Ohren, Vorlagen (sitter, stander, birdy, penguin, whale, yeti, dragon), `RARITY_SIZE` |
| `katalog_1.py` … `katalog_3.py` | Formen von 48 Pets |
| `modelle/schneehase.py`, `bergdohle.py`, `murmeltier.py` | Formen der ersten drei Pets (Version 1) |
| `alt3.py` | holt die ersten drei Pets in den Baukasten |
| `wow.py` | Version 2: Farben, Iris, Wangen, Glitzer, Heiligenschein, Zielgrösse pro Pet |
| `pets_meta.py` | Anzeigename → Slug und Designnotizen |
| `bauen.py` / `bauen2.py` | baut ein Pet (Version 1 nach `build/`, Version 2 nach `build2/`) |
| `varianten.py` | Varianten-Texturen aus einer GLB |
| `pruefen.py` | Prüfung: Aufbau, Dreiecke, Nullpunkt, Grösse, Vorderseite +Z, UV, Textur |
| `build_page.py`, `build_standalone.py`, `template.html`, `viewer.js` | Sammelbuch-Seite |
| `LIESMICH-paket.md`, `snow-rush-pets-3d.md` | Doku zum Pet-Paket und Stilregeln |

## Konventionen

- 1 Einheit = 1 Stud, Y oben, Vorderseite +Z, Nullpunkt unten in der Mitte des Körpers (Glitzer zählt nicht zur Mitte)
- Körperhöhe nach Seltenheit: 2.7 / 2.9 / 3.1 / 3.4 / 3.7 / 3.9 Studs
- Varianten tauschen nur die Textur, das Mesh bleibt gleich

## Import in Roblox Studio (Test offen)

Mit 2–3 Pets aus `build2/` (oder aus Pets.zip) im 3D Importer prüfen:

1. **Grösse:** Ein Gewöhnlich-Pet muss etwa 2.7 Studs hoch sein. glTF gilt als Meter; ist das Pet rund 3.5-mal zu gross, im Importer die Einheit auf Studs stellen.
2. **Ausrichtung:** Gesicht zeigt nach +Z. Roblox-Modelle schauen mit `LookVector` nach −Z, darum im Script beim Folgen evtl. um 180° drehen.
3. **Textur:** Wird die eingebettete Textur nicht übernommen, `*_textur.png` aus `varianten.py` von Hand als `TextureID` setzen.
4. **Variante:** `TextureID` auf `*_gold.png` tauschen, das Pet muss golden werden, Augen bleiben gleich.

Upload unter der Gruppe Materiavis (siehe Notion «Asset-Berechtigungen»). Asset-IDs nie von Hand eintippen.

## Offen

- Leichte Version für fremde Pets (ca. 600 Dreiecke): `target` in `Pet.build()` senken und testen
- Erweiterung zum Welt-Baukasten (Bäume, Felsen, Zäune, Stationen) nach der Welt-1-Look-Referenz
