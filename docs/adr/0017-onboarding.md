# 0017: Onboarding hints of the first five minutes

**Status:** Accepted with merge of PR #128.

Implements `10.1-onboarding` (#42, Vertical Slice) on top of the Lobby portals and first-join arrow ([ADR 0015](0015-lobby-portals.md)), selling ([ADR 0012](0012-selling.md)), the HUD and input device tracking ([ADR 0008](0008-hud-and-windows.md)), the map contract ([ADR 0009](0009-map-contract.md)), Net ([ADR 0005](0005-net-remotes.md)), DataService ([ADR 0006](0006-player-data.md)) and CurrencyService ([ADR 0007](0007-economy-config.md)).

## Context

Concept 10.1 gives a timeline for the first minutes with the help shown at each step and fixes: no text tutorial, only arrows and symbols; new players start in the Lobby. The look of the hints is Spielraum. Acceptance: a new player finds the Singleplayer portal within 20 s and sells the first ball within 90 s of arriving in zone 1, both without explanation; every hint appears once and disappears after its action; the tutorial state is saved. Concept 3.2 asks prompts to show the glyph of the last used device. The schema v1 profile already has `tutorial = { seenSingleArrow, seenMultiArrow, hints = { [id] = true }, firstMatchHints }`; the save format must not change. The 0:00 ground arrow and portal rim exist (#37, ADR 0015, `seenSingleArrow`). "MAX!" is the HUD's (#35, #109) and a small arrow above a MAX ball pointing at the scale is BallGrowthController's (7.4). Egg stations (#41), barriers (#39), the real zones (#29) and the real Lobby are not built; the first-match symbols need the Arena match flow (7.15, Launch).

## Decision

**Layout.**

| Path | Kind | Role |
|---|---|---|
| `src/shared/Config/Tutorial.luau` | data | Hint ids and order, Place, channel and prerequisites per hint, the client-reportable ids, distances, timings, colours, glyph names, Studio stand-in layout. |
| `src/shared/TutorialAttributes.luau` | pure | Attribute names and the comma list format, shared by server and client. |
| `src/server/Services/TutorialService/` | service (every Place) | `TutorialCore` (pure rules), `Stations` (egg station and barrier lookup, read-only, ADR 0009), `TutorialSwitches` (Studio), `init` (wiring). Inactive in the Arena. |
| `src/client/Ui/TutorialGlyphs.luau`, `TutorialPointer.luau` | pure | Device symbol and its screen rectangle; world chevron positions. |
| `src/client/Ui/TutorialHand.luau`, `TutorialWorld.luau`, `TutorialControls.luau` | Roblox | Screen symbols (finger, key caps, joystick, stick, D-pad, ring, arrow), world symbols (trail, beacon, pulse), the shared controls hint. |
| `src/places/lobby/client/TutorialController.luau` | controller | Lobby hints; draws the Multiplayer arrow with ADR 0015's `GuideArrow`. |
| `src/places/simulator/client/TutorialController/` | controller | Simulator hints; child `UpgradesHint`. |

**Hints.** One id per row of 10.1 in this slice, in timeline order (`Config.Tutorial.Order`):

| Id | 10.1 | Place, channel | Shows when | Done when (server) | Drawing (client) |
|---|---|---|---|---|---|
| `LobbyMove` | 0:00 | Lobby, Controls | a loaded profile and a character | the character walked `MoveDoneDistance` (6) studs | finger on W A S D / touch joystick / gamepad stick |
| `LobbyMultiArrow` | next Lobby visit 🟦 | Lobby, World; requires `LobbyMove` | this load is a later visit (`seenSingleArrow` already true when the profile loaded) and the Multiplayer portal position is known | the character enters any portal (`PortalCurrent ≠ ""`) | ground arrow spawn → Multiplayer portal and its rim (`GuideArrow`) |
| `ZoneMove` | 0:20 | Simulator, Controls | a loaded profile and a character | walked 6 studs | the controls finger and chevrons ahead of the own ball along character → ball |
| `MaxScale` | 1:00 | Simulator, World; requires `ZoneMove` | `BallIsMax` and `BallScaleAnchor` set (ADR 0002) | the first sale (any sale) | chevron trail from the character towards the scale and a beacon on it |
| `UpgradesButton` | 1:20 | Simulator, Screen; requires `MaxScale` | always once `MaxScale` is done ("after the first sale") | the client reports the Upgrades window opened while it shows | ring and arrow at `SimulatorHud.UpgradesButton`, the key of the device (U / D-pad right / tap) |
| `EggStation` | 2:20 | Simulator, World; requires `ZoneMove` | Coins ≥ `Formulas.Pets.eggPrice(1)` (240) and an `EggStation` of egg 1's zone exists | the character is within `EggReachDistance` (8) of the station's bounding box, or `TutorialService.MarkDone(player, "EggStation", …)` (for #41's purchase) | trail and beacon to the nearest station |
| `BarrierPulse` | 4:20 | Simulator, Pulse; requires `ZoneMove` | Coins ≥ `Formulas.Zones.barrierPrice(1)` (320), a `Barrier` in zone 1 exists, zone 2 not unlocked | zone 2 unlocked (`sim.unlockedZones["2"]`, any time), within `BarrierReachDistance` (4) of the barrier, or `MarkDone` (for #39) | pulsing `Highlight` on the zone 1 Barrier Model |

Rules (`TutorialCore.select`): a hint shows when its Place is this Place, it is not done, everything it `Requires` is done, its condition holds and its channel (Controls, World, Screen, Pulse) is free; the first eligible hint in Order takes a free channel. A hint that shows keeps its channel until it is done, even if its condition goes away for a moment (an obstacle takes the ball under MAX, Coins are spent), so no hint appears twice. Hints of different channels show together: at 0:00 the finger, the #37 arrow and the rim; after the first sale the Upgrades arrow and, once there are Coins, the egg arrow and the barrier pulse. Without a loaded profile (`DataLoadStatus ≠ Loaded`) nothing shows, so a failed load never looks like a new player.

**Server authoritative.** `TutorialService` checks every `CheckInterval` (0.25 s) with the server's view only: the character root (walked distance, step longer than `MaxStepPerCheck` = teleport or respawn and not counted), the ball attributes BallService writes, the Coins balance from CurrencyService, the portal attribute PortalService writes, the profile's `unlockedZones`, and the tagged stations below `Workspace.Map`. The first sale comes from `CurrencyService.Subscribe` (`Earn` with reason `Config.Sell.CoinReason`), so SellService is unchanged. Station lookup follows ADR 0009 (station Model with `PrimaryPart`, zone from the area root's unique valid `ZoneIndex`); it is read-only and does not warn, because the egg and barrier services own binding and warnings. It should use the shared resolver once #39–#41 lift `UpgradeService/StationRules`.

**One client report.** Only the client sees a window open. `Net/Remotes` declares `TutorialHintDone(id)`: client → server event, argument `Schema.enum(Config.Tutorial.ClientReportable)` (only `"UpgradesButton"`), rate limit `Config.Net.RateLimits.TutorialHintDone` (burst 3, 0.5/s). The handler (`TutorialCore.checkReport`) accepts it only while that hint is showing for that player (`NotReportable`, `NotActive` otherwise) and then only sets that known id to done. Nothing ever sets a hint back to unseen except the Studio reset. The Lobby and the Simulator handle it; the Arena drops it as `NoHandler`. `Remotes` takes `Config.Tutorial` as a fourth argument.

**Saved state.** `hints[id] = true` for every id except `LobbyMultiArrow`, which is `seenMultiArrow`. `seenSingleArrow` stays with PortalService. Changes are made in the live profile and stored by the normal saves (autosave, leave, portal teleport save); a hint is not in the immediate-save list of 6.5. A hint done just before a portal travel is in that travel's save. Hint progress lost in a crash before the next save shows that hint once more; nothing else is lost. `firstMatchHints` is untouched (first match, 7.15). No save-format change.

**Return visit.** A Lobby load counts as a later visit when `seenSingleArrow` is already true at that load. `Teleported → Loaded` (the session resumed after a failed teleport or the Studio stub, ADR 0011) is the same visit, so neither the stub travel nor a failed teleport shows the Multiplayer arrow; `DataSimulateRejoin` (a load from the store) does.

**Attributes.**

| Where | Name | Type | Servers | Meaning |
|---|---|---|---|---|
| Player | `TutorialActive` | string | all | showing ids in Order, comma-joined; `""` while not loaded |
| Player | `TutorialDone` | string | all | done ids in Order; `""` while not loaded |
| Player | `TutorialTarget` | Vector3 | all | where the World-channel hint points (portal, scale, egg station); absent when none |
| Player | `TutorialLast`, `TutorialLastAt` | string, number | Studio | last change, e.g. `ZoneMove done source=Moved`, `UpgradesButton refused NotActive source=Client`, `EggStation shown`, `reset source=Studio`; `Workspace:GetServerTimeNow()` of it |
| Player | `TutorialReturnVisit` | bool | Studio | this Lobby load is a later visit |
| Player | `TutorialWalked` | number | Studio | studs walked while the controls hint shows |
| Player | `TutorialRefusals` | number | Studio | refused reports |
| `PlayerGui.TutorialHints` | `TutorialShown`, `TutorialDevice`, `TutorialGlyph`, `TutorialMenuGlyph`, `TutorialReports` | string, number | all (client) | what is drawn, last device, controls glyph (`Keys:W`, `Joystick`, `Stick:L`), Upgrades key glyph (`Key:U`, `DPad:Right`, `Tap`), reports fired |

Client objects: `PlayerGui.TutorialHints.Controls` (attribute `Glyph`), `.PointAt` and `.MenuKey`; `workspace.TutorialPushArrow`, `workspace.TutorialPointer` (attribute `Chevrons`), `workspace.TutorialBeacon`, `workspace.LobbyGuideMultiplayer`, Highlights `TutorialMultiRim` (Multiplayer portal) and `TutorialBarrierPulse` (barrier).

**Look (Spielraum 10.1).** Guide yellow (the MAX colour), Frames and neon parts only, no image assets. The "hand" is a stylised finger (a rounded white bar). Key caps carry key names (symbols, `AutoLocalize` off); no sentence appears. Every screen object is inert (`Active`, `Selectable`, `Interactable` false) in its own ScreenGui (`DisplayOrder` 12, the HUD's insets), so taps reach the joystick and the HUD, and gamepad selection is unchanged. The touch symbol sits inside the joystick clear zone because it shows the joystick; keyboard and gamepad symbols sit bottom centre under the ball zone. The symbols follow `InputController.onChanged`, so a device switch redraws them at once. The HUD code is not changed: the Upgrades button is found by name.

### Studio playtest support (Studio at `game.PlaceId == 0` only; live servers skip all of it)

Startup line: `[TutorialService] started place=<Lobby|Simulator> hints=7 remote=TutorialHintDone studioSwitches=true` (Arena: `… place=Arena inactive …`). Every change prints `[TutorialService] <name> (<userId>) <text>` and `… active=<ids>`.

Switches on `ServerScriptService`:

| Switch | Type, default | Effect | Resets |
|---|---|---|---|
| `TutorialTargetUserId` | number, `0` | the player the switches act on; `0` = every player (the stand-ins use the first) | stays |
| `TutorialStudioReset` | bool, `false` | `true` empties `tutorial.hints`, sets `seenMultiArrow` and `firstMatchHints` to false in the target's live profile (saved with the next save), restarts the session (walked 0, return visit recomputed). `seenSingleArrow` is `LobbyStudioReset`'s (ADR 0015). Prints `TutorialStudioReset <name> (<id>): …` | itself to `false` |
| `TutorialTestStations` | number, `0` (Simulator only) | `n` (a zone of this world no other `Workspace.Map` area uses) builds `Workspace.Map.TutorialTest`, a Folder with `ZoneIndex = n` holding an `EggStation` Model (6 × 6 × 6, sand) 30 studs right and 20 ahead of the target's character and a `Barrier` Model (20 × 12 × 2, blue, collides) 30 left and 20 ahead, both on the ground below, tagged, `PrimaryPart`, Atomic. `n = 1` makes them egg 1's station and the zone 1 barrier; any other zone tests that the hints ignore them. `0` removes it. A used or invalid zone builds nothing and prints why. They stand in for #41 and #39 and are only read by the hints. | stays |

Reused: `LobbyTestGeometry`, `LobbyStudioReset` (ADR 0015); `SellScaleTestGeometry` (ADR 0012; use a zone other than the stand-ins', e.g. 2); `BallSetSizeFraction`, `BallSetZone` (ADR 0002); `CurrencyAddCoins` (ADR 0007); `DataFailSave`, `DataFailLoad`, `DataAutosaveNow`, `DataSimulateRejoin` (ADR 0006); `TravelFailTeleport` (ADR 0011).

Read-only checks, server: `local p = game.Players:GetPlayers()[1]; print(p:GetAttribute("TutorialActive"), p:GetAttribute("TutorialDone"), p:GetAttribute("TutorialLast"), p:GetAttribute("TutorialWalked"), p:GetAttribute("TutorialTarget"))`, `local t = require(game.ServerScriptService.Server.Services.DataService).GetProfile(p).tutorial; print(t.seenSingleArrow, t.seenMultiArrow, t.firstMatchHints); for id in t.hints do print(id) end`. Client: `local g = game.Players.LocalPlayer.PlayerGui.TutorialHints; print(g:GetAttribute("TutorialShown"), g:GetAttribute("TutorialDevice"), g:GetAttribute("TutorialGlyph"), g:GetAttribute("TutorialMenuGlyph"))`, `print(workspace:FindFirstChild("TutorialPointer"), workspace:FindFirstChild("TutorialBeacon"))`.

## Consequences

- Server start counts grow by one (`TutorialService`) in every Place: 13 in the Lobby, 13 in World 1, 8 in the Arena (ADR 0015 recorded 12 for the Lobby, ADR 0012 12 for World 1, ADR 0008 7 for the Arena). Client counts grow by one (`TutorialController`) in the Lobby (10) and World 1 (12); the Arena is unchanged (5). (Counts on this branch include #90, #28, #37 and #38.)
- `Config.Map.Tags` gains `EggStation` and `Barrier` (the ADR 0009 names). #41 and #39 bind them for real; their purchases should call `TutorialService.MarkDone(player, "EggStation" | "BarrierPulse", "<source>")`, so the hint ends on the purchase too.
- A new client → server remote: `TutorialHintDone`, one enum argument, handler only sets a showing hint to done. Its abuse can only hide a hint for the sender.
- AC1 and AC2 are usability tests with players who do not know the game; an agent can only check that the hints are there, in order, and time the guided path on the Studio test layouts. They need the human END PLAYTEST (owner decision pending on #42), and the real Plaza and zone 1 need the same check once built.
- The Simulator's world arrows are a new trail (`TutorialPointer`), not ADR 0015's `ArrowPath`: the Lobby arrow is fixed from the spawn, these follow the moving player, and the Lobby client folder is not mounted in the Simulator.

## Open points

- Real art: the finger, key caps and D-pad are shapes. A drawn hand, a joystick and gamepad glyph set (and optional sounds) want `/design` art and the asset-upload workflow.
- First-match symbols (throw, reload, `firstMatchHints`) come with the Arena match flow (7.15).
- `LobbyMultiArrow` ends on entering either portal: entering the Singleplayer portal is also a mode choice, and the arrow is shown "einmal". The owners may prefer it to end only at the Multiplayer portal.
- `MaxScale` is done by any sale, also one before MAX, and it is the "has sold" fact `UpgradesButton` waits for.
