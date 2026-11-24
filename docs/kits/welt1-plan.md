# Welt-1-Baukasten: Plan

Stand 24.11.2026 · Refs #29 · Status: **Entwurf, wartet auf Owner-Antworten**

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
| MCP-Server `materiavis-files-agent` | FAIL: `uvx` nicht im PATH, Server startet nicht |

## 2. Blocker

1. **Files-Server fehlt.** Der asset-builder legt `.glb`, Vorschauen und die Galerie in
   `AI-Output/kits/<kit>/` ab und stoppt ohne Server (Regel 10). Ohne `uvx` kann Batch 1 nicht
   starten. Lösung (Mensch): `uv` installieren, damit `uvx` im PATH liegt, und
   `NC_AGENT_APP_PASSWORD` setzen.
2. **Die Welt-Regeln prüfen noch keine Tags.** `TagKinds` und `PositiveAttributes` in
   `WorldRules.luau` sind leer (Owner-Entscheid Marco, 24.11.). Darum prüft der Kit-Check heute
   weder, ob `Obstacle` auf einem BasePart sitzt, noch ob `KnockOverSize` positiv ist. Der
   asset-builder darf die Welt-Regeln nicht ändern (Regel 13). Vorschlag: Vor Batch 1 trägt ein
   kleiner `chore` die Tags aus ADR 0009 ein (Frage F12).
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
zu `Config.Ball` («small obstacle the character steps over»). Ob ein «Tännchen» so klein wirken
darf, ist eine Frage des Stils.

**Grössen-Vorlagen (Regel 6):** Ein umrollbares Teil bekommt pro Zone, in der es vorkommt, eine
eigene Vorlage `<Teil>_Z<NN>_<Variante>`, zum Beispiel `Taennchen_Z01_1`. Jede hat
`KnockOverSize = K(z)`, und ihre Kollisionsbox ist `K(z)` hoch. `ScaleMin`/`ScaleMax` hat sie
nicht. Alle Grössen eines Teils nutzen dasselbe Mesh, jedes Mesh wird nur einmal hochgeladen.
Für Template-Namen gilt ASCII (ä → ae).

**Grosse Hindernisse (Vorschlag, F8):** «deutlich höher als der Ball der Zone» heisst hier
mindestens `2 × D(z)`: 8 Studs in Zone 1, 25 Studs in Zone 10. Sie haben kein `KnockOverSize`
und darum eine einzige Vorlage pro Variante, gebaut für Zone 1 (Grundhöhe 8 Studs), mit
`ScaleMin = 1` und `ScaleMax = 3.2`. Der world-builder skaliert sie pro Zone.

## 4. Teile

Kollision: Jedes Hindernis bekommt unsichtbare Box-Parts mit `Obstacle` (ADR 0009: «box-shaped
contact test»), das Mesh selbst kollidiert nicht. Die Look-Referenz nennt «Box oder Hull». Hull
fällt weg, weil das Mesh nur das Aussehen trägt. Gruppen (Tannengruppe, Felsgruppe) bekommen
mehrere Boxen in einem Model. Die Dreiecks-Budgets stammen aus der Look-Referenz.

### 4.1 Hindernisse klein (umrollbar)

| Teil | Budget | Kollision | Tags (ADR 0009) | Seeds | Zonen (Vorschlag nach 7.6-Zuordnung) | Grössen-Vorlagen bei f = 0.7 (KnockOverSize) |
|---|---|---|---|---|---|---|
| Tännchen | 400 | 1 Box | `Obstacle` + `KnockOverSize` | 3 | 1, 2, 3, 6, 7 | Z01 0.93 · Z02 1.15 · Z03 1.37 · Z06 2.03 · Z07 2.25 |
| Latschenbusch | 400 | 1 Box | `Obstacle` + `KnockOverSize` | 3 | 1, 2, 4, 5, 10 | Z01 0.93 · Z02 1.15 · Z04 1.59 · Z05 1.81 · Z10 2.91 |
| Kleiner Fels | 400 | 1 Box | `Obstacle` + `KnockOverSize` | 3 | 1, 4, 5, 8, 9, 10 | Z01 0.93 · Z04 1.59 · Z05 1.81 · Z08 2.47 · Z09 2.69 · Z10 2.91 |
| Zaunstück | 400 | 1 Box (flach, breit) | `Obstacle` + `KnockOverSize` | 2 | 3, 6, 7 | Z03 1.37 · Z06 2.03 · Z07 2.25 |
| Holzstapel | 400 | 1 Box | `Obstacle` + `KnockOverSize` | 2 | 3 | Z03 1.37 |
| Heuballen mit Schneekappe | 400 | 1 Box | `Obstacle` + `KnockOverSize` | 2 | 3 | Z03 1.37 |
| Wegweiser | 400 | 1 Box | `Obstacle` + `KnockOverSize` | 2 | 1, 3, 6 | Z01 0.93 · Z03 1.37 · Z06 2.03 |

Summe: 7 Teile, 17 Meshes (Seeds), 24 Grössen-Stufen, 64 Vorlagen (Stufen × Seeds), 17 Uploads.

### 4.2 Hindernisse gross (fest)

| Teil | Budget | Kollision | Tags | Seeds | Zonen (Vorschlag) | Skalierung |
|---|---|---|---|---|---|---|
| Grosse Tanne | 1'200 | 1 Box (Stamm + Krone) | `Obstacle` | 2 | 1, 2, 3, 6, 7 | 1–3.2 |
| Tannengruppe | 1'200 | 2–3 Boxen | `Obstacle` | 2 | 2, 6, 7 | 1–3.2 |
| Felsblock | 1'200 | 1 Box | `Obstacle` | 2 | 1, 4, 5, 8, 10 | 1–3.2 |
| Felsgruppe | 1'200 | 2–3 Boxen | `Obstacle` | 2 | 5, 9, 10 | 1–3.2 |
| Eisblock (Gletscher) | 1'200 | 1 Box | `Obstacle` | 2 | 8, 9 | 1–3.2 |

### 4.3 Boden und Deko

| Teil | Budget | Kollision | Tags | Seeds | Zonen | Status |
|---|---|---|---|---|---|---|
| Schneehügel | 1'200 | Mesh-Kollision nötig | `Snow` | 3 | alle | **BLOCKED** (F1, Blocker 3) |
| Schneewechte | 1'200 | Mesh-Kollision nötig | `Snow` | 2 | 6, 7 | **BLOCKED** (F1) |
| Rand der Eisfläche (Bergsee) | 1'200 | Mesh-Kollision nötig | `Ice` (Fläche), Rand `Snow` | 2 | 4 | **BLOCKED** (F1) |
| Gletscherspalte | 1'200 | Mesh-Kollision nötig | — (Loch, Grenzfall 6.5) | 2 | 8, 9 | **BLOCKED** (F1) |
| Pistenstange | 1'200 | keine (F7) | — | 1 | 6, 7 | offen (F7) |
| Liftmast | 1'200 | 1 Box ohne Tag (F7) | — | 1 | 6, 7 | offen (F7) |
| Alphütte | 3'000 | 1–2 Boxen ohne Tag | — | 1 | 3 | — |
| Gipfelkreuz | 1'200 | 1 Box ohne Tag | — | 1 | 10 | — |

Die Tiefschnee-Felder (6.2: 2–3 pro Zone) und der normale Schneeboden entstehen als Boden-Blöcke
des world-builders mit `DeepSnow`/`Snow`. Für sie braucht es keine Kit-Teile, solange F1 offen ist.

### 4.4 Stationshüllen und Marker

Stationen sind laut ADR 0009 Models mit dem Tag auf dem Model, `PrimaryPart`,
`ModelStreamingMode = Atomic` und optional einem `LabelAnchor`. Konzept 11: Signatur-Assets,
selbst gebaut.

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

Vorschlag für den Massstab, damit eine Zone «nicht kopiert» wirkt: mindestens 3 verschiedene
kleine und 2 grosse Teile, je 2–3 Seeds. Der Abschnitt `Spielraum` des World task erlaubt dazu
Drehung und Skalierung (nur bei den grossen Teilen).

| Zone (7.6) | Thema (Look-Referenz) | Klein | Gross | Deko | Status |
|---|---|---|---|---|---|
| 1 Schneegrenze | viele Tannen | Tännchen, Latschen, Fels, Wegweiser | Grosse Tanne, Felsblock | — | PASS |
| 2 Tannenwald | viele Tannen | Tännchen, Latschen | Grosse Tanne, Tannengruppe | — | **zu wenig klein** (2) |
| 3 Alphütte | Zäune, Holz, Hütte | Tännchen, Zaun, Holzstapel, Heuballen, Wegweiser | Grosse Tanne | Alphütte | **zu wenig gross** (1) |
| 4 Bergsee | Eisfläche | Latschen, Fels | Felsblock | (Eisrand BLOCKED) | **FAIL**: kein eigenes Teil |
| 5 Felsgrat | Felsen | Latschen, Fels | Felsblock, Felsgruppe | — | **zu wenig klein** (2) |
| 6 Skipiste | Pistenstangen, Liftmasten, Wechten | Tännchen, Zaun, Wegweiser | Grosse Tanne, Tannengruppe | Pistenstange, Liftmast | PASS |
| 7 Lawinenhang | wie 6 | Tännchen, Zaun | Grosse Tanne, Tannengruppe | Pistenstange, Liftmast | **FAIL**: gleich wie Zone 6 |
| 8 Gletscherzunge | Eisblöcke, Spalten | Fels | Eisblock, Felsblock | (Spalte BLOCKED) | **FAIL**: 1 kleines Teil |
| 9 Gletscher | wie 8 | Fels | Eisblock, Felsgruppe | (Spalte BLOCKED) | **FAIL**: 1 kleines Teil |
| 10 Gipfel | Felsen, Gipfelkreuz | Latschen, Fels | Felsblock, Felsgruppe | Gipfelkreuz | **zu wenig klein** (2) |

Befund: Die ca. 20 Teile der Look-Referenz reichen für die Zonen 1, 3 und 6. Für die Zonen 4 und
7–9 fehlen eigene kleine Hindernisse, und die Zonen 2, 5 und 10 sind knapp. Welche Teile dazukommen,
ist eine Stilfrage (F6). Danach wächst Batch 4 oder 5.

## 7. Batches (Asset tasks)

| Batch | Inhalt | Meshes (Seeds) | Warum an dieser Stelle |
|---|---|---|---|
| **1** | Tännchen, kleiner Fels, Zaunstück | 8 | Vorgabe: Look Review früh. Diese drei Formen tragen den Stil (gestufter Kegel, runder Brocken, Pfosten mit Balken) und kommen in 9 von 10 Zonen vor. Runde 2 klärt nebenbei den Studio-Test des von Lune geschriebenen MeshPart (`InitialSize`). |
| **2** | Latschenbusch, grosse Tanne, Tannengruppe, Felsblock, Felsgruppe | 11 | Mit Batch 1 hat dann jede Vertical-Slice-Zone (1–5) kleine **und** grosse Hindernisse. Danach kann der erste World task (Zonen 1–2) den Workflow testen, auch ohne Stationen (der Zonen-Check verlangt sie nicht). |
| **3** | Waage, Upgrade-Stand, Ei-Station, Barriere, Fundpunkt-Marker | 4 | Ohne Stationen sind die Zonen nicht spielbar (Ziel G2/G3 des Vertical Slice). Stationen haben die meisten Funktions-Tags und das grösste Budget. Sie kommen nach dem Look Review von Batch 1, damit der Stil feststeht. |
| **4** | Holzstapel, Heuballen, Wegweiser, Alphütte (+ Teile aus F6 für die Zonen 2, 4, 5) | 7+ | Schliesst den Vertical Slice (Zonen 1–5) ab, vor allem Zone 3. |
| **5** | Eisblock, Welten-Tor, Pistenstange, Liftmast, Gipfelkreuz (+ Teile aus F6 für die Zonen 7–10) | 6+ | Gehört zum Launch (#104, #105), nicht zum Vertical Slice, darum zuletzt. |
| **6** | Schneehügel, Schneewechte, Eisrand, Gletscherspalte | 9 | **BLOCKED** bis F1 entschieden ist. Bis dahin entsteht der Boden aus Blöcken des world-builders. |

## 8. World tasks und benötigte Batches

| World task | Zonen | Braucht | Meilenstein |
|---|---|---|---|
| WT-1 | 1–2 (Schneegrenze, Tannenwald) | Batch 1, 2 (Workflow-Test), danach 3 für die Spielbarkeit | Vertical Slice (#29) |
| WT-2 | 3–5 (Alphütte, Bergsee, Felsgrat) | Batch 1–4 (Zone 4 erst nach F6) | Vertical Slice (#29) |
| WT-3 | 6–10 (Skipiste bis Gipfel) | Batch 1–5 (Zonen 7–9 erst nach F6) | Launch (#104, #105) |
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
| F5 | Ist ein kleines Hindernis in Zone 1 mit höchstens 1.33 Studs (kniehoch) gewollt? | Folgt aus 7.3 und 7.4. Ein grösseres Hindernis wäre in Zone 1 nie umrollbar. |
| F6 | Welche zusätzlichen kleinen Teile bekommen die Zonen 4, 7, 8 und 9 (und 2, 5, 10)? | Ohne sie wirken diese Zonen kopiert (Abschnitt 6). |
| F7 | Pistenstange und Liftmast: Deko ohne Kollision oder Hindernis? Steht Deko im Laufweg? | Die Look-Referenz sagt «nie im Laufweg», auf einer Skipiste stehen Stangen aber mitten im Weg. |
| F8 | Grosse Hindernisse mindestens 2 × Balldurchmesser hoch? | «Deutlich höher» (Look-Referenz) braucht eine Zahl für das Asset-Issue. |
| F9 | Konzept 11 erlaubt für den Baukasten Creator-Store-Modelle (nach Model-Audit). Bauen wir alles selbst? | Dieser Plan nimmt an: alles selbst gebaut. |
| F10 | Höchstens 6 Deko-Teile in den Zonen 1, 3 und 5 (Budget)? | Sonst über 40'000 Dreiecke. |
| F11 | Wie viele Seeds pro Teil? (Vorschlag: klein 3 bzw. 2, gross 2, Deko und Stationen 1) | Bestimmt den Upload-Aufwand: 36 Meshes ohne Batch 6, 45 mit. |
| F12 | `TagKinds`/`PositiveAttributes` (ADR 0009) vor Batch 1 in `WorldRules.luau` eintragen? | Sonst prüft der Kit-Check die Tags nicht (Blocker 2). Ändert den Entscheid «leer bis ein World task fragt». |
