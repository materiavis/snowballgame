# 0010: Upgrades, the UpgradeBuy remote and the upgrade stand

**Status:** Accepted with merge of PR #114.

Implements `7.8-upgrades` (#36) from the `UpgradeService` and `sim.upgrades` rows of [ADR 0003](0003-snow-rush-intake.md). Uses the Net layer (ADR 0005), DataService (ADR 0006), CurrencyService and `Formulas.Upgrades` (ADR 0007), the window stack (ADR 0008) and the map contract (ADR 0009).

## Context

Concept 7.8 fixes five upgrades with 100 levels, the cost formula `BasePrice × Factor^(level − 1)` and the start and end values (already in `Config/Upgrades`, verified against concept v5). They are bought in a menu (U, the left-edge button, D-pad right) and at the upgrade stand, and the menu shows each effect before and after the next level. CLAUDE.md §6 says the server decides levels and coins and never trusts a client value. Ball growth (`GrowthModifiers`) and walk speed (`MovementService`) already had seams waiting for levels. Selling (#38) and finds (#40) do not exist yet.

## Decision

**Layout.** `src/places/simulator/server/UpgradeService/` is a Simulator-only service (folder module).

| Module | Kind | Role |
|---|---|---|
| `UpgradeCore` | pure | Purchase decision, Studio set-level, level reads, events. Config, formulas, profile access and the coin spend are injected. |
| `LevelAttributes` | pure | Writes the player attributes below. |
| `StationRules` | pure | ADR 0009 checks for a zone-bound station on an injected tree: `Workspace.Map` scope, zone from the area root's `ZoneIndex` (missing, invalid, other world, duplicate), Station rule (Model, `PrimaryPart`, `ModelStreamingMode = Atomic`), warning text. No upgrade words, so #38–#41 can lift it into a shared resolver. |
| `UpgradeStands` | Roblox | Binds `UpgradeStand` stations through CollectionService and the Studio test stands. |
| `init` | Roblox | Wires the core to DataService, CurrencyService, NetService, the attributes and the switches. |
| `src/shared/Config/Map.luau` | data | Map contract names used by code (proposed in ADR 0009): `Map`, `ZoneIndex`, `LabelAnchor`, `Atomic`, the `UpgradeStand` tag and the stand prompt settings. |
| `src/shared/UpgradeAttributes.luau` | pure | Attribute names shared by server and HUD. |
| `src/places/simulator/client/SimulatorHudController/` | client | The HUD controller became a folder: `UpgradesView` (pure rows and row layout) and `UpgradesPanel` (Instances) fill `UpgradesWindow.Content`. |

**Purchase (server).** The client sends one remote, `UpgradeBuy(id)`, with `id` checked by `Schema.enum(Config.Upgrades.Order)` and rate limit `Config.Net.RateLimits.UpgradeBuy` (burst 10, 5 per second). Nothing else is sent: no level, no price. `UpgradeCore.purchase` then refuses in this order:
1. `BadId`: not a `Config.Upgrades` id (the guard already drops these; the core checks again because the Studio switch skips the guard).
2. `NotLoaded`: no loaded profile (loading, failed, released, teleported, lost).
3. `BadProfile`: the stored level is not a whole number 0..`MaxLevel`.
4. `MaxLevel`: the level is already `MaxLevel` (100).
5. The price is `Formulas.Upgrades.cost(id, level + 1)` from the server's own level. `CurrencyService.SpendCoins` refuses with `Insufficient` (or its other refusals).
6. Then `sim.upgrades[id] = level + 1`.

A refusal changes nothing and gives no reply to the client; the HUD follows the attributes.

**Coins and level together.** The spend and the level write run in one thread with no yield between them, so any save snapshot (DataService deep-copies when a write starts) holds both or neither. A failed save keeps both in memory and the next save stores both (tested with the fake store). This relies on CurrencyService listeners not yielding or saving; today they only write attributes and print. A purchase is not in the immediate-save list of ADR 0003: it lands with the next autosave (at most 2 min) or the leave save, like coins.

**Effects.** Levels are read live, so a purchase is felt at once:
- `growth`, `stability`: BallService sets `GrowthModifiers.setLevelSource(UpgradeService.GetLevel)`; the next growth step and the next collision use the new effect.
- `walkSpeed`: MovementService stays the only writer of `Humanoid.WalkSpeed` (source check). It sets `UpgradeService.GetEffect(player, "walkSpeed")` on every spawn and again on `UpgradeService.LevelChanged`. The ball follows the walk speed (ADR 0002). At start it warns if the level 0 effect differs from `Config.Ball.WalkSpeed`, which growth is calibrated on.
- `magnet`, `sellValue`: no consumer yet. Finds (#40) and selling (#38) read `UpgradeService.GetEffect(player, "magnet" | "sellValue")`. Until then their effect is visible in the menu and in the Studio attributes only.

**Server API.** `GetLevel(player, id)` (0 while not loaded; errors on an unknown id), `GetEffect(player, id)`, `GetNextPrice(player, id)` (nil at max or not loaded), `LevelChanged` (player, id, level; also once per upgrade when a profile loads) and `Subscribe(fn)` for analytics (#43): `Purchase`, `Set` and `Refused` events with `userId`, `upgrade`, `from`, `to`, `price`, `reason`, `refusal`.

**Player attributes.**

| Attribute | Written | Meaning |
|---|---|---|
| `Upgrade<Id>Level` (`UpgradeGrowthLevel`, `UpgradeWalkSpeedLevel`, `UpgradeMagnetLevel`, `UpgradeSellValueLevel`, `UpgradeStabilityLevel`) | every server, on load and after every change | The saved level. HUD contract. Removed if the stored value is broken. |
| `Upgrade<Id>Effect` | Studio at PlaceId 0 | The effect at that level (seconds to MAX, studs/s, studs, sell multiplier, size share lost per hit). |
| `UpgradeLastPurchase` | Studio at PlaceId 0 | Last purchase, set or refusal as text, e.g. `walkSpeed 0 -> 1 price=40 Remote effect 16 -> 16.16`, `growth Remote refused: Insufficient level=0 price=25`. |
| `UpgradeRefusals` | Studio at PlaceId 0 | Count of refusals. |

As with balances (ADR 0007, 0008), the client only reads them, a client-side write does not replicate, and server code never reads them back. The HUD shows levels only while `DataLoadStatus == "Loaded"`.

**Menu (client).** One row per upgrade in `Config.Upgrades.Order`: name, `level/100`, effect now `→` after the next level, the next price with `NumberFormat.price`, and a buy button. Not enough coins: the button reads "Need coins", is dimmed and sends nothing (meaning is not colour-only). Level 100: the price field reads "MAX", the effect shows only the final value, and there is no buy button. Not loaded or no valid level: every value shows "–" and nothing can be bought. The affordability shown is a display hint from the `Coins` attribute; the server decides. Names, effect units and decimals are in `Config.Ui.UpgradeRows`, texts in `Config.Ui.Text`, sizes in `Config.Ui.UpgradesWindow`. Rows are two button heights (at least 44 px each) and scroll in the window, which keeps the ⅔ limit and the clear zones of ADR 0008. The buy button only fires when the row says it can buy.

**Upgrade stand.** The server binds every `UpgradeStand` that `StationRules` accepts, at start and on `GetInstanceAddedSignal`, and puts a `ProximityPrompt` (`Config.Map.UpgradeStand`: name, tag `UpgradeStandPrompt`, distance, hold, keys; texts from `Config.Ui.Text`) on its `PrimaryPart`. The prompt changes no state. On the client, `ProximityPromptService.PromptTriggered` with that tag opens the same Upgrades window as U. Invalid stands warn once per instance (`[MapContract] UpgradeStand <full name>: <problem>, ignored`); templates outside `Workspace.Map` are ignored silently. `LabelAnchor` is not used: the prompt's own text is the stand's label (Spielraum). World 1 has no zone area with `ZoneIndex` yet (#29), so there is no real stand to bind; the Studio test stands below cover the runtime path.

**Studio playtest support (Studio at `game.PlaceId == 0` only; live servers skip all of it).**
- Startup line, always printed: `[UpgradeService] started upgrades=growth,walkSpeed,magnet,sellValue,stability maxLevel=100 stands=<n> studioSwitches=true`.
- Every purchase, set and refusal prints `[UpgradeService] <name> (<userId>) <text>` (the `UpgradeLastPurchase` text). Bound and unbound stands print `[UpgradeService] stand bound <full name> zone=<n>`.
- Switches on `ServerScriptService`, set from the server command bar:
  - `UpgradeTargetUserId` (number): the player the switches act on; `0` means every player.
  - `UpgradePurchase` (string): an upgrade id. Runs one purchase through the same core path as the remote (id, profile, level, max, price, coins) and resets to `""`. An unknown id shows a `BadId` refusal.
  - `UpgradeSetLevel` (string): `"<id> <level>"`, e.g. `"walkSpeed 100"`. Sets the level without coins, through the same id, level (whole 0..100) and profile checks, and resets to `""`. Used to reach level 100 for AC2 and to test effects at high levels.
  - `UpgradeStandTestGeometry` (bool): `true` builds, in front of the target's character, `Workspace.Map.UpgradeStandTest` (a Folder with the first free `ZoneIndex` of this world) holding one valid stand and one without `PrimaryPart`, and `Workspace.Map.UpgradeStandTestNoZone` (no `ZoneIndex`) holding one otherwise valid stand. The first binds a prompt; the other two warn once each. `false` removes them and their prompt.
- With `CurrencyAddCoins` (ADR 0007) and `DataFailSave`, `DataAutosaveNow`, `DataSimulateRejoin` (ADR 0006), a playtest can buy, fail a save, save again and check the levels after a rejoin.

## Consequences

- Server start count in World 1 grows by one (`UpgradeService`). Lobby and Arena are unchanged; their NetService still creates `UpgradeBuy` (the declaration list is shared) and drops calls as `NoHandler`.
- `Net/Remotes` is now a function of `(Schema, Config.Net, Config.Upgrades)` (ADR 0005 said `(Schema, Config.Net)`), so the enum comes from the one id list.
- `NetExample` and `NetExampleService` are **not** removed here, although ADR 0005 planned that for the first real remote. Removing them touches the Net guard specs and the playtest contract of #24, so it is left to a separate chore.
- The source check in `CollisionAssign.spec` that keeps remotes out of Simulator code now allows exactly one `FireServer(id)` on `UpgradeBuy` in `UpgradesPanel`.
- No save format change: `sim.upgrades` already existed in schema v1.
- Magnet and Sell value become noticeable in play only with #40 and #38.
- A CurrencyService listener that yields or saves would open a window between the spend and the level write. New listeners (#43) must stay synchronous.
