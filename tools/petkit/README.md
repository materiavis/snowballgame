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

## Import in Roblox Studio

Getestet am 18.11.2026 auf einer lokalen Baseplate: Schneehase und Rotfuchs mit dem 3D Importer.

1. **Grösse:** stimmt mit `pets.json` überein (Rotfuchs 4.23 × 3.74 × 3.39, Schneehase 1.74 × 2.70 × 1.69 Studs). Keine Einheit anpassen.
2. **Ausrichtung:** automatisch korrekt, keine Drehung nötig.
3. **Textur:** die eingebettete Textur ist sichtbar.
4. **Variante:** `TextureID` auf `*_gold.png` getauscht, das Pet wird golden.

Upload unter der Gruppe Materiavis (siehe Notion «Asset-Berechtigungen»). Asset-IDs nie von Hand eintippen.

## Upload-Liste

`upload-list.json` ist die einzige Quelle für Asset-IDs der Welt-Teile. Agents lesen sie nur; Einträge macht ein Mensch nach dem Upload von Hand in Studio (Creator = Gruppe Materiavis). Ohne Upload bleibt die Datei eine leere Liste `[]`.

Ein Eintrag pro hochgeladenem Teil:

```json
{
  "part": "tanne_klein",
  "variant": 1,
  "seed": 1234,
  "file": "tools/petkit/modelle/welt1/tanne_klein_v1.glb",
  "meshId": "rbxassetid://...",
  "textureId": "rbxassetid://...",
  "uploadedBy": "Marco",
  "date": "2026-11-23"
}
```

| Feld | Inhalt |
|---|---|
| `part` | Slug des Teils |
| `variant` | Nummer der Variante (1–3) |
| `seed` | Seed, mit dem die Variante gebaut wurde |
| `file` | Pfad der hochgeladenen `.glb`, vom Repository-Wurzelverzeichnis aus |
| `meshId` | Asset-ID des Meshes, `rbxassetid://<Zahl>` |
| `textureId` | Asset-ID der Textur, `rbxassetid://<Zahl>` |
| `uploadedBy` | wer hochgeladen hat |
| `date` | Datum des Uploads, `JJJJ-MM-TT` |

## Offen

- Leichte Version für fremde Pets (ca. 600 Dreiecke): `target` in `Pet.build()` senken und testen
- Erweiterung zum Welt-Baukasten (Bäume, Felsen, Zäune, Stationen) nach der Welt-1-Look-Referenz
