# Welt-1-Baukasten: Plan

Stand 26.11.2026 · Refs #29 · Status: **F2–F13 entschieden (Abschnitt 10), offen nur F1 (Terrain)**

Plan für den ganzen Welt-1-Baukasten (Alpen, Zonen 1–10), damit `asset-builder` und
`world-builder` an der ganzen Welt getestet werden statt Teil für Teil. Dieses Dokument
entscheidet kein Game Design: Teile, Stil und Zonen-Themen stammen aus Notion. Wo eine Zahl
fehlt, steht ein **Vorschlag** mit Formel und eine offene Frage an die Owner.

Quellen:
- Notion «02 - Snow Rush», Kapitel 6.1, 6.2, 7.3, 7.4, 7.6, 11
- Notion «Welt-1-Look-Referenz (Alpen)»: Baukasten, Technik-Budget, Massstab, offene Fragen
  (Entwurf, Abnahme durch Yowaldy ausstehend)
- `docs/technical/0009-map-contract.md` (Tags), `src/shared/Config/Ball.luau`
  (`KnockOverSizeRatio = 3`, `KnockOverSize` in Studs gegen den sichtbaren Balldurchmesser)
- `.claude/agents/asset-builder.md` (Regel 6), `tools/kit/KitContract.luau`,
  `tools/world/README.md`, `src/shared/Config/WorldRules.luau`

## 1. Vorbedingungen

| Prüfung | Ergebnis |
|---|---|
| asset-builder und world-builder auf `main` (PR #138) | PASS: gemergt am 24.11.2026 |
| petkit unter `tools/petkit/` auf `main` (PR #133) | PASS: gemergt am 18.11.2026 |
| MCP-Server `materiavis-files-agent` | FAIL: `uvx` nicht im PATH, Server startet nicht. Erneut geprüft am 24.11. nach der Meldung «uv installiert, Passwort gesetzt»: in der Umgebung des Development Managers weiterhin kein `uvx` und kein `NC_AGENT_APP_PASSWORD` (Protokoll, Abschnitt 11) |

## 2. Blocker

1. **Files-Server fehlt.** Der asset-builder legt `.glb`, Vorschauen und die Galerie in
   `AI-Output/kits/<kit>/` ab und stoppt ohne Server (Regel 10). Ohne `uvx` kann Batch 1 nicht
   starten. Lösung (Mensch): `uv` installieren, damit `uvx` im PATH liegt, und
   `NC_AGENT_APP_PASSWORD` setzen.
2. **Die Welt-Regeln prüfen noch keine Tags.** `TagKinds` und `PositiveAttributes` in
   `WorldRules.luau` sind leer (Owner-Entscheid Marco, 24.11.). Darum prüft der Kit-Check heute
   weder, ob `Obstacle` auf einem BasePart sitzt, noch ob `KnockOverSize` positiv ist. Der
   asset-builder darf die Welt-Regeln nicht ändern (Regel 13). **Entschieden (F12, Marco,
   26.11.):** Vor Runde 2 von Batch 1 trägt ein kleiner `chore` die Tags aus ADR 0009 ein.
3. **Mesh-Boden passt nicht zum Kit-Check.** Schneehügel, Wechte, Eisrand und Gletscherspalte
   brauchen als Mesh eine Kollision auf dem Mesh (Hull oder Precise), weil eine Box keinen Hang
   abbildet. Der Kit-Check verlangt aber `CanCollide` aus auf jedem MeshPart. Erst wenn der
   Terrain-Test entschieden hat (F1), wird festgelegt, ob Kit-Check und asset-builder dafür eine
   Ausnahme bekommen. Bis dahin sind diese Teile blockiert (Batch 6).
4. **Nicht blockierend, aber vor dem ersten World task zu klären:** Laut Review von #138 bricht
   der world-builder den Bau der ganzen Welt ab, sobald eine Zone von Hand geändert wurde. Das
   wird relevant, sobald jemand eine gebaute Zone in Studio nachbessert.

## 3. Grössen aus 7.3 und 7.4

- Sichtbarer Balldurchmesser am Zonenmaximum (7.3): `D(z) = 4 + 0.94 × (z − 1)` Studs.
  Innerhalb einer Zone wächst er von 40 % auf 100 % von `D(z)`.
- Umrollen (7.4, `Config.Ball.KnockOverSizeRatio = 3`): Der Ball rollt ein kleines Hindernis
  um, wenn sein Durchmesser mindestens `3 × KnockOverSize` ist.
- Damit der Hook «eben noch hängen geblieben, jetzt umgerollt» (5.1) in jeder Zone wirkt, muss
  die Schwelle innerhalb der Zone liegen: `0.4 × D(z) < 3 × K(z) ≤ D(z)`.
- **Vorschlag:** `K(z) = f × D(z) / 3` mit **f = 0.7**. Der Ball rollt also ab 70 % des
  Zonenmaximums um. Den Wert von f bestimmt das Spielgefühl, deshalb entscheiden ihn die Owner
  (F4).

| Zone | D(z) Studs | Ball beim Start (40 %) | K bei f = 0.5 | **K bei f = 0.7** | K bei f = 0.9 | K-Obergrenze (f = 1) |
|---|---|---|---|---|---|---|
| 1 | 4.00 | 1.60 | 0.67 | **0.93** | 1.20 | 1.33 |
| 2 | 4.94 | 1.98 | 0.82 | **1.15** | 1.48 | 1.65 |
| 3 | 5.88 | 2.35 | 0.98 | **1.37** | 1.76 | 1.96 |
| 4 | 6.82 | 2.73 | 1.14 | **1.59** | 2.05 | 2.27 |
| 5 | 7.76 | 3.10 | 1.29 | **1.81** | 2.33 | 2.59 |
| 6 | 8.70 | 3.48 | 1.45 | **2.03** | 2.61 | 2.90 |
| 7 | 9.64 | 3.86 | 1.61 | **2.25** | 2.89 | 3.21 |
| 8 | 10.58 | 4.23 | 1.76 | **2.47** | 3.17 | 3.53 |
| 9 | 11.52 | 4.61 | 1.92 | **2.69** | 3.46 | 3.84 |
| 10 | 12.46 | 4.98 | 2.08 | **2.91** | 3.74 | 4.15 |

Folge (F5): Ein kleines Hindernis in Zone 1 ist höchstens 1.33 Studs gross, bei f = 0.7 etwa
0.93 Studs. Die Figur ist etwa 5 Studs gross, das Hindernis geht ihr also bis ans Knie. Das passt
zu `Config.Ball` («small obstacle the character steps over»). **Entschieden (F5, Marco, 26.11.):**
So gewollt. Kleine Hindernisse sind kniehoch und wachsen Zone für Zone.

**Grössen-Vorlagen (Regel 6):** Jedes Teil gehört zu genau einer Zone (F6, Abschnitt 6). Ein
umrollbares Teil hat darum genau eine Grössen-Stufe: Vorlage `<Teil>_Z<NN>_<Variante>`, zum
Beispiel `Taennchen_Z01_1`, mit `KnockOverSize = K(z)` und einer Kollisionsbox, die `K(z)` hoch
ist. `ScaleMin`/`ScaleMax` hat sie nicht. Für Template-Namen gilt ASCII (ä → ae).

**Grosse Hindernisse (Entschieden, F8, Marco, 26.11.):** `H(z) = 1.5 × D(z)` hoch, also das
Anderthalbfache des grössten Balls der Zone. Sie haben kein `KnockOverSize`. Jedes grosse Teil
wird für seine Zone gebaut (Höhe `H(z)` bei Skalierung 1) und bekommt **`ScaleMin = 1`,
`ScaleMax = 1.3`** (F13), damit gleiche Teile nicht gleich gross wirken.

| Zone | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| `H(z)` Studs | 6.00 | 7.41 | 8.82 | 10.23 | 11.64 | 13.05 | 14.46 | 15.87 | 17.28 | 18.69 |

Übergang (F13): Ein grosses Teil darf in der direkt folgenden Zone höchstens zweimal
stehen, skaliert auf mindestens `H(z+1)`. Das Verhältnis `H(z+1) / H(z)` ist höchstens 1.24
(Zone 1 → 2), passt also in `ScaleMax = 1.3`. Kleine Teile wechseln die Zone nie, weil sie dort
eine zweite Grössen-Stufe bräuchten.

## 4. Teile

Kollision: Jedes Hindernis bekommt unsichtbare Box-Parts mit `Obstacle` (ADR 0009: «box-shaped
contact test»), das Mesh selbst kollidiert nicht. Die Look-Referenz nennt «Box oder Hull». Hull
fällt weg, weil das Mesh nur das Aussehen trägt. Gruppen (Tannengruppe, Felsgruppe) bekommen
mehrere Boxen in einem Model. Die Dreiecks-Budgets stammen aus der Look-Referenz.

### 4.1 Hindernisse pro Zone (entschieden, F13)

Jede Zone bekommt ein eigenes Set aus 3 kleinen und 2 grossen Teilen (F6). Kein Teil kommt aus
einer früheren Zone (Ausnahme: Übergang grosser Teile, Abschnitt 3). Die Teile folgen den
Zonen-Themen aus 7.6 und der Look-Referenz. Die Liste hat Marco am 26.11. freigegeben (F13),
Formen und Stil gibt das Look Review frei.

Gemeinsam für alle: klein = 400 Dreiecke, 1 Box (flach und breit bei Zaun, Ast, Tafel),
`Obstacle` + `KnockOverSize = K(z)`, 2 Seeds. Gross = 1'200 Dreiecke, 1–3 Boxen, `Obstacle`,
Höhe `H(z)` bei Skalierung 1, `ScaleMin = 1`, `ScaleMax = 1.3`, 2 Seeds.

| Zone (7.6) | K(z) | H(z) | Klein (umrollbar) | Gross (fest) |
|---|---|---|---|---|
| 1 Schneegrenze | 0.93 | 6.00 | Tännchen, Kleiner Fels, Wegweiser | Grosse Tanne, Felsblock |
| 2 Tannenwald | 1.15 | 7.41 | Baumstumpf, Liegender Ast, Latschenbusch | Tannengruppe, Hochstand |
| 3 Alphütte | 1.37 | 8.82 | Zaunstück, Holzstapel, Heuballen mit Schneekappe | Heustadel, Grosser Holzstoss |
| 4 Bergsee | 1.59 | 10.23 | Schilfbüschel, Eisbrocken, Ufersteine | Lärche, Aufgestellte Eisscholle |
| 5 Felsgrat | 1.81 | 11.64 | Geröllhaufen, Felszacken, Edelweissbüschel | Felsgruppe, Felsnadel |
| 6 Skipiste | 2.03 | 13.05 | Pistenstange (F7), Schneehaufen, Ski im Schnee | Schneekanone, Pistenraupe |
| 7 Lawinenhang | 2.25 | 14.46 | Lawinenschneeball, Lawinen-Warntafel, Geknickte Jungtanne | Lawinenverbau, Lawinenkegel |
| 8 Gletscherzunge | 2.47 | 15.87 | Eissplitter, Moränenstein, Messstange | Eisblock, Findling |
| 9 Gletscher | 2.69 | 17.28 | Routenfahne, Eiskegel, Eisknolle | Sérac (Eisturm), Gletschertisch |
| 10 Gipfel | 2.91 | 18.69 | Steinmann, Raureif-Fels, Gipfelbuch-Kasten | Gipfelfelsen, Raureif-Felsturm |

Summe: 30 kleine und 20 grosse Teile, 100 Meshes (je 2 Seeds), 100 Uploads. Vorher waren es
12 Teile mit 28 Meshes, die über mehrere Zonen geteilt wurden.

### 4.2 Boden und Deko

Deko darf im Laufweg stehen (F7, Marco, 26.11.). Deko mit Kollision ohne Tag blockiert den Ball,
ohne dass er schrumpft.

| Teil | Budget | Kollision | Tags | Seeds | Zonen | Status |
|---|---|---|---|---|---|---|
| Schneehügel | 1'200 | Mesh-Kollision nötig | `Snow` | 3 | alle | **BLOCKED** (F1, Blocker 3) |
| Schneewechte | 1'200 | Mesh-Kollision nötig | `Snow` | 2 | 6, 7 | **BLOCKED** (F1) |
| Rand der Eisfläche (Bergsee) | 1'200 | Mesh-Kollision nötig | `Ice` (Fläche), Rand `Snow` | 2 | 4 | **BLOCKED** (F1) |
| Gletscherspalte | 1'200 | Mesh-Kollision nötig | — (Loch, Grenzfall 6.5) | 2 | 8, 9 | **BLOCKED** (F1) |
| Liftmast | 1'200 | 1 Box ohne Tag | — | 1 | 6 | am Rand, Kollision ohne Grössenverlust (F7) |
| Alphütte | 3'000 | 1–2 Boxen ohne Tag | — | 1 | 3 | — |
| Gipfelkreuz | 1'200 | 1 Box ohne Tag | — | 1 | 10 | — |

Die Tiefschnee-Felder (6.2: 2–3 pro Zone) und der normale Schneeboden entstehen als Boden-Blöcke
des world-builders mit `DeepSnow`/`Snow`. Für sie braucht es keine Kit-Teile, solange F1 offen ist.

### 4.3 Stationshüllen und Marker

Stationen sind laut ADR 0009 Models mit dem Tag auf dem Model, `PrimaryPart`,
`ModelStreamingMode = Atomic` und optional einem `LabelAnchor`. Konzept 11: Signatur-Assets,
selbst gebaut. Stationen fallen nicht unter F6: Spieler sollen Waage, Upgrade-Stand und
Ei-Station in jeder Zone wiedererkennen.

| Teil | Budget | Kollision | Tags | Seeds | Zonen |
|---|---|---|---|---|---|
| Waage | 3'000 | Boxen | `ScaleAnchor` (Attachment), `ScalePlate` (unsichtbarer, nicht kollidierender Part) | 1 | 1–10 |
| Upgrade-Stand | 3'000 | Boxen | `UpgradeStand` (Station) | 1 | 1–10 |
| Ei-Station | 3'000 | Boxen | `EggStation` (Station) | 1 | 1, 5 |
| Barriere | 3'000 | unsichtbare Sperr-Parts im Model | `Barrier` (Station) | 1 | 1–9 |
| Welten-Tor | 3'000 | unsichtbare Sperr-Parts im Model | `WorldGate` (Station) | 1 | 10 |
| Fundpunkt-Marker | 0 (kein Mesh) | keine | `FindPoint` (Attachment im unsichtbaren Fuss) | — | 1–10, je 8–12 |

Barriere und Welten-Tor sind «halb durchsichtig, leuchtend» (7.6). Den Leuchteffekt trägt das
Mesh. Die Sperr-Parts sind unsichtbar, wie es der Kit-Check verlangt. Der world-builder setzt nur
Vorlagen, darum braucht der Fundpunkt eine Marker-Vorlage. Die Ranglisten-Tafel am Weltstart
gehört zu #44 und nicht zu diesem Baukasten.

## 5. Dreiecks-Budget pro Zone

Annahmen: Maximalfall mit 25 Hindernissen (13 klein, 12 gross), 6 Deko-Teile à 1'200 (Vorschlag,
die Look-Referenz nennt keine Zahl), Stationen à 3'000, Boden-Blöcke 12 Dreiecke (vernachlässigt).
In Zone 3 ersetzt die Alphütte (3'000) ein Deko-Teil. Minimalfall: 15 Hindernisse (8 klein,
7 gross), 3 Deko. Grenze laut Look-Referenz: etwa 40'000 pro Zone.

| Zone | Stationen | Minimum | Maximum | Maximum mit 8 Deko | Maximum mit 3 Mesh-Hügeln | Status |
|---|---|---|---|---|---|---|
| 1 | 4 (mit Ei) | 27'200 | 38'800 | **41'200** | **42'400** | knapp: höchstens 6 Deko |
| 2 | 3 | 24'200 | 35'800 | 38'200 | 39'400 | PASS |
| 3 | 3 + Hütte | 26'000 | 37'600 | **40'000** | **41'200** | knapp: höchstens 6 Deko inkl. Hütte |
| 4 | 3 | 24'200 | 35'800 | 38'200 | 39'400 | PASS |
| 5 | 4 (mit Ei) | 27'200 | 38'800 | **41'200** | **42'400** | knapp: höchstens 6 Deko |
| 6–9 | 3 | 24'200 | 35'800 | 38'200 | 39'400 | PASS |
| 10 | 3 (Tor statt Barriere) | 24'200 | 35'800 | 38'200 | 39'400 | PASS |

Befund:
- Im Maximalfall bleibt keine Zone über 40'000. Die Zonen 1 und 5 liegen aber bei 97 %, weil
  sie die Ei-Station haben.
- Mit 8 Deko-Teilen überschreiten die Zonen 1 und 5 die Grenze, Zone 3 erreicht sie genau.
- Kommt Boden aus Mesh dazu (F1), überschreiten die Zonen 1, 3 und 5 die Grenze schon mit
  3 Hügeln.
- **Regel für die World tasks:** in den Zonen 1 und 5 höchstens 6 Deko-Teile, in Zone 3
  höchstens 5 neben der Hütte. Mesh-Boden zählt mit. Alternativ bleiben die Stationen unter
  2'500 Dreiecken.
- Nicht eingerechnet: Fundstücke (#40), die Bälle und Pets (Look-Referenz: deshalb die Grenze)
  und die nächste Zone hinter der Barriere, die bei Streaming sichtbar sein kann. Den Ausschlag
  gibt der Mobile-Check (#102).

## 6. Abwechslung pro Zone

Massstab, damit eine Zone «nicht kopiert» wirkt: mindestens 3 verschiedene kleine und 2 grosse
Teile, je 2 Seeds. Der Abschnitt `Spielraum` des World task erlaubt dazu Drehung und Skalierung
(nur bei den grossen Teilen).

Der erste Plan teilte rund 12 Teile über alle Zonen. Die Zonen 4 und 7–9 hatten damit kein eigenes
Teil, die Zonen 2, 5 und 10 zu wenige. **Entschieden (F6, Marco, 26.11.):** Keine Teile aus
früheren Zonen wiederverwenden, jede Zone bekommt ein eigenes Set neuer Teile (Tabelle in 4.1).
Damit erfüllt jede Zone den Massstab mit eigenen Teilen (3 klein, 2 gross).

Folgen:
- 100 statt 28 Hindernis-Meshes, entsprechend mehr Upload-Arbeit für die Menschen.
- Das Dreiecks-Budget pro Zone (Abschnitt 5) ändert sich nicht, es zählt platzierte Teile.
- Die Look-Referenz in Notion nennt rund 20 Teile. Die neue Liste muss dort nachgeführt werden
  (Creative/Product).

## 7. Batches (Asset tasks)

Neu geschnitten nach F6 und F13: ein Asset task pro Zone, dazu einer für die Stationen. Die Issues
#142–#146 wurden am 26.11. umgeschrieben, #150–#155 sind neu.

| Batch | Inhalt | Meshes (Seeds) | Warum an dieser Stelle |
|---|---|---|---|
| **1** (#142) | Zone 1 komplett: Tännchen, kleiner Fels, Wegweiser, grosse Tanne, Felsblock | 10 | Vorgabe: Look Review früh (Gate 1). Eine ganze Zone zeigt den Stil für kleine und grosse Teile. Runde 2 klärt nebenbei den Studio-Test des von Lune geschriebenen MeshPart (`InitialSize`). |
| **2** (#143) | Zone 2 komplett | 10 | Danach kann der erste World task (Zonen 1–2) den Workflow testen, auch ohne Stationen (der Zonen-Check verlangt sie nicht). |
| **3** (#144) | Waage, Upgrade-Stand, Ei-Station, Barriere, Fundpunkt-Marker | 4 | Ohne Stationen sind die Zonen nicht spielbar (Ziel G2/G3 des Vertical Slice). Sie kommen nach dem Look Review von Batch 1, damit der Stil feststeht. |
| **4** (#145, #150, #151) | Zonen 3, 4 und 5, dazu die Alphütte in Zone 3 | 31 | Schliesst den Vertical Slice (Zonen 1–5) ab. Ein Issue pro Zone, damit eine Runde des asset-builders klein bleibt. |
| **5** (#146, #152–#155) | Zonen 6–10, dazu Liftmast (6), Gipfelkreuz und Welten-Tor (10) | 53 | Gehört zum Launch (#104, #105), nicht zum Vertical Slice, darum zuletzt. |
| **6** (kein Issue, BLOCKED) | Schneehügel, Schneewechte, Eisrand, Gletscherspalte | 9 | **BLOCKED** bis F1 entschieden ist. Bis dahin entsteht der Boden aus Blöcken des world-builders. |

## 8. World tasks und benötigte Batches

| World task | Zonen | Braucht | Meilenstein |
|---|---|---|---|
| WT-1 | 1–2 (Schneegrenze, Tannenwald) | Batch 1, 2 (Workflow-Test), danach 3 für die Spielbarkeit | Vertical Slice (#29) |
| WT-2 | 3–5 (Alphütte, Bergsee, Felsgrat) | Batch 3, 4 | Vertical Slice (#29) |
| WT-3 | 6–10 (Skipiste bis Gipfel) | Batch 3, 5 | Launch (#104, #105) |
| später | Hügel, Wechten, Eisrand, Spalten nachrüsten | Batch 6 | nach F1 |

Jeder World task trägt die Grenzen aus Abschnitt 5 (Deko pro Zone) und aus 6.2 (15–25 Hindernisse,
davon etwa die Hälfte umrollbar, 2–3 Tiefschnee-Felder, 8–12 Fundpunkte) als Limits für den
Zonen-Check ein.

## 9. Offene Fragen an die Owner

| # | Frage | Warum es zählt |
|---|---|---|
| F1 | Boden aus Roblox-Terrain oder aus Mesh-Teilen? (Test auf Jans Handy) | Batch 6 ist blockiert. Mesh-Boden braucht eine Ausnahme im Kit-Check (Blocker 3) und frisst Budget (Abschnitt 5). |
| F2 | Abnahme der Look-Referenz durch Yowaldy | Batch 1 baut nach ihr. Sie ist bisher ein Entwurf. |
| F3 | Lighting, Atmosphere und Sky von Welt 1: eigenes Issue anlegen? | Gehört nicht zum asset-builder (Entscheid 24.11.). |
| F4 | Wo in der Zone wird ein kleines Hindernis umrollbar? (Vorschlag f = 0.7, also ab 70 % des Zonenmaximums) | Legt alle Werte für `KnockOverSize` fest. Spielgefühl. |
| F5 | Ist ein kleines Hindernis in Zone 1 mit höchstens 1.33 Studs (kniehoch) gewollt? | Folgt aus 7.3 und 7.4. Ein grösseres Hindernis wäre in Zone 1 nie umrollbar. **Entschieden 26.11.** |
| F6 | Welche zusätzlichen kleinen Teile bekommen die Zonen 4, 7, 8 und 9 (und 2, 5, 10)? | Ohne sie wirken diese Zonen kopiert (Abschnitt 6). **Entschieden 26.11.** |
| F7 | Pistenstange und Liftmast: Deko ohne Kollision oder Hindernis? Steht Deko im Laufweg? | Die Look-Referenz sagt «nie im Laufweg», auf einer Skipiste stehen Stangen aber mitten im Weg. **Entschieden 26.11.** |
| F8 | Grosse Hindernisse mindestens 2 × Balldurchmesser hoch? | «Deutlich höher» (Look-Referenz) braucht eine Zahl für das Asset-Issue. **Entschieden 26.11.** |
| F9 | Konzept 11 erlaubt für den Baukasten Creator-Store-Modelle (nach Model-Audit). Bauen wir alles selbst? | Dieser Plan nimmt an: alles selbst gebaut. |
| F10 | Höchstens 6 Deko-Teile in den Zonen 1, 3 und 5 (Budget)? | Sonst über 40'000 Dreiecke. |
| F11 | Wie viele Seeds pro Teil? (Vorschlag: klein 3 bzw. 2, gross 2, Deko und Stationen 1) | Bestimmt den Upload-Aufwand: 36 Meshes ohne Batch 6, 45 mit. |
| F12 | `TagKinds`/`PositiveAttributes` (ADR 0009) vor Batch 1 in `WorldRules.luau` eintragen? | Sonst prüft der Kit-Check die Tags nicht (Blocker 2). Ändert den Entscheid «leer bis ein World task fragt». **Entschieden 26.11.** |
| F13 | Teileliste pro Zone (Abschnitt 4.1) freigeben? Dazu: grosse Teile `ScaleMax = 1.3`, Übergang grosser Teile in die nächste Zone (höchstens 2×), Stationen bleiben in allen Zonen gleich, 2 Seeds pro Hindernis. | Folgt aus F6. Ohne Liste können die Asset tasks #142–#146 nicht angepasst werden, Runde 2 von Batch 1 stoppt. **Entschieden 26.11.** |

## 10. Entscheide (24.11.2026)

| # | Entscheid | Von | Umsetzung |
|---|---|---|---|
| F2 | **Gate 1:** Die Galerie von Batch 1 gilt als Abnahme der Look-Referenz. Die Batches 2–5 starten erst danach. | Yowaldy | AC in #142 |
| F3 | Lighting, Atmosphere und Sky bekommen ein eigenes Issue, nicht den asset-builder. | Yowaldy | #141 |
| F4 | `KnockOverShare = 0.7` gilt provisorisch und ist als **PLAYTEST TUNING** markiert. Endgültig wird der Wert erst nach einem Playtest. | Development Manager (technisch, Auftrag Yowaldy) | `src/shared/Config/WorldRules.luau`, Test in `tests/shared/WorldRules.spec.luau` (0.4 < Wert ≤ 1) |
| F9 | Alles wird selbst gebaut. Teile aus dem Creator Store kommen nur nach einem Model Audit dazu (Look-Referenz, CLAUDE.md Abschnitt 10). | Development Manager | Abschnitt `Fix` in jedem Asset task |
| F10 | In den Zonen 1 und 5 höchstens 6 Deko-Teile, in Zone 3 höchstens 5 neben der Alphütte. Mesh-Boden zählt mit. | Development Manager | Limits im World task, Hinweis in #145 |
| F11 | Seeds: kleine Hindernisse 3 (Tännchen, Fels, Latschen) bzw. 2 (übrige), grosse 2, Deko und Stationen 1. Das ergibt 36 Meshes ohne Batch 6. **Überholt durch F13:** 2 Seeds pro Hindernis, 108 Meshes ohne Batch 6. | Development Manager | Asset tasks #142–#146 |
| F5 | Kleine Hindernisse in Zone 1 sind kniehoch (höchstens 1.33 Studs, bei f = 0.7 0.93 Studs) und wachsen Zone für Zone. | Marco (26.11.) | Abschnitt 3 |
| F6 | Keine Teile aus früheren Zonen wiederverwenden: jede Zone bekommt ein eigenes Set neuer Teile. | Marco (26.11.) | Abschnitte 4.1, 6, 7 |
| F7 | Deko darf im Laufweg stehen. Pistenstange = kleines umrollbares Hindernis (Zone 6), Liftmast = Deko am Rand mit Kollision ohne Grössenverlust. | Marco (26.11.) | Abschnitte 4.1, 4.2 |
| F8 | Grosse Hindernisse sind `1.5 × D(z)` hoch (6 Studs in Zone 1, 18.69 in Zone 10). | Marco (26.11.) | Abschnitt 3 |
| F12 | Ein `chore` trägt vor Runde 2 von Batch 1 die ADR-0009-Tags in `TagKinds`/`PositiveAttributes` ein, ohne Limits. | Marco (26.11.) | #149 |
| F13 | Teileliste pro Zone (4.1) freigegeben, dazu: grosse Teile `ScaleMax = 1.3`, Übergang grosser Teile höchstens 2× in die nächste Zone, Stationen in allen Zonen gleich, 2 Seeds pro Hindernis. | Marco (26.11.) | Asset tasks #142–#146, #150–#155 |

Noch offen:
- F1 (Terrain) bleibt beim Test auf Jans Handy, Batch 6 ist BLOCKED.
- Die Look-Referenz in Notion muss die Teileliste aus 4.1 und F7 (Deko im Laufweg) übernehmen (Creative/Product).
- Vor Runde 2 von Batch 1 muss der F12-chore #149 gemergt sein, sonst stoppt Runde 2.
- Offene Grössen (Alphütte, Liftmast, Gipfelkreuz, Welten-Tor, Stationen) stehen als OPEN in den Asset tasks.

## 11. Protokoll: ungeplante Eingriffe von Menschen

| Wann | Wer | Eingriff | Folge |
|---|---|---|---|
| 24.11.2026 | Marco | Commit `bce7ae9` auf PR #138, während der Development Manager den asset-builder auf denselben Branch brachte: `TagKinds` und `PositiveAttributes` werden leer. | Regel 4 des asset-builders und die Vorlage «Asset task» angepasst (Tag-Art kommt aus dem Issue). Der Kit-Check prüft die Tags erst, wenn sie eingetragen sind (Blocker 2, F12). |
| 24.11.2026 | Yowaldy | Meldung: `uv` installiert und `NC_AGENT_APP_PASSWORD` gesetzt. | In der Umgebung des Development Managers ist beides nicht sichtbar: kein `uvx` im PATH, Variable leer (auch in einer Login-Shell). Vermutlich auf einem anderen Rechner oder nach dem Start dieser Session gesetzt. Batch 1 startet nicht. |
