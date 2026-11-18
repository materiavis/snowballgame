# Snow Rush Pets: 3D-Modelle

Stand: 2. November 2026. Quelle der Pet-Liste: Notion «02 - Snow Rush», Abschnitt 7.9.

## Stand

- 51 Pets: 10 Eier mit je 5 Pets, dazu der geheime Goldene Yeti
- Reihenfolge: eines nach dem anderen, ab Schneehase (Ei 1)
- Marcos Entscheide: drehbares Modell plus Mesh-Datei, Stil «weich und rund»
- Version 2 vom 11. November 2026: alle 51 Pets bunter und auffälliger überarbeitet, auf Marcos Wunsch fertig zum Weitergeben an Miggi. Paket «Snow-Rush-Pets-v2.zip» mit Modellen, Texturen inklusive Gold, Regenbogen und Frostig, Vorschaubildern, pets.json, LIESMICH.md und Sammelbuch
- Version 2 im Detail: farbige Iris mit Pupille, rosa Wangen, Farbverläufe, farbige Schatten, Glitzersterne ab Selten, goldener Heiligenschein bei Polarlicht-Fuchs und Yeti, Grösse nach Seltenheit von 2.7 bis 3.9 Studs
- Budget: jedes Pet unter 3'000 Dreiecken, ein Mesh, eine Textur
- Import in Roblox Studio noch nicht getestet
- Im Notion-Konzept «02 - Snow Rush» steht seit dem 2. November der Anhang Pet-Katalog mit Stilregeln und allen 51 Pets als 🟦, noch mit den Texten von Version 1. Die Bilder fehlen dort noch: Der Upload lief nicht, weil api.notion.com für diese Sitzung gesperrt ist. Sobald sie drin sind, den Satz «Die Bilder folgen.» im Anhang entfernen
- Die Seite ist nicht als Artifact veröffentlicht: Marco hat die Veröffentlichung abgelehnt. Sie liegt nur als Datei im Chat.

## Stilregeln

- Form: weich und rund, grosser Kopf, kurze Beine, ein bis zwei klare Merkmale
- Farbe: kräftige Farbverläufe, farbige statt graue Schatten
- Gesicht: grosse Augen mit farbiger Iris, dunkler Pupille und zwei Glanzpunkten, rosa Wangen. Dunkle Pets bekommen einen hellen Ring um die Augen
- Seltenheit: je seltener, desto grösser und auffälliger (2.7 bis 3.9 Studs). Ab Selten Zubehör und Glitzer, Legendär mit Krone, Heiligenschein oder eigenem Blickfang
- Technik: ein Mesh, eine kleine Textur, unter 3'000 Dreiecken, Schatten in der Textur
- Varianten: Gold, Regenbogen und Frostig sind fertige Texturen (varianten.py)

## Für die Überarbeitung

- Mit Glitzer werden manche Legendären breit, der Polarlicht-Fuchs bis 5.7 Studs
- Astronauten-Hund hat keinen Helm: Glas geht mit einem Mesh und einer Textur nicht

## Offene Punkte aus dem Konzept

- Goldener Steinbock (Legendär) sieht fast aus wie ein Steinbock in der Gold-Variante und braucht ein eigenes Merkmal
- Murmeltier bewusst ohne Schoggi: Die Kombination erinnert an eine bekannte Schokoladen-Werbung, das Konzept verbietet bekannte Marken und Figuren
- Goldener Yeti: Abschnitt 7.9 sagt «ab Welt 2» (Update 1), die Roadmap sagt Update 3

## So geht es weiter

Der Code liegt in diesem Ordner. `petkit.py` ist das Grundwerkzeug, `kit.py` der Baukasten mit den Tierformen, `katalog_1.py` bis `katalog_3.py` enthalten 48 Pets, `schneehase.py`, `bergdohle.py` und `murmeltier.py` die ersten drei, `pets_meta.py` die Designnotizen. `bauen.py` baut ein Pet, `viewer.js`, `template.html`, `build_page.py` und `build_standalone.py` bauen die Seite. Die Pfade in den Skripten zeigen auf `/home/claude/pets` mit den Unterordnern `modelle`, `page` und `build`. Version 2: `wow.py` legt pro Pet Farben, Iris, Wangen, Glitzer und Heiligenschein fest, `alt3.py` holt die ersten drei Pets in den Baukasten, `bauen2.py slug` baut nach `build2/`, `varianten.py build2 build2/tex` macht die Varianten-Texturen. Ablauf: Pet ändern, bauen, Ansichten anschauen, Seite neu bauen.
