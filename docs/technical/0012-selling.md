# 0012: Selling at the scale

**Status:** Accepted with merge of PR #NN.

Implements `7.5-selling` (#38) from the `SellService` row of [ADR 0003](0003-snow-rush-intake.md). Uses the ball (ADR 0002), Net (ADR 0005), DataService (ADR 0006), CurrencyService and `Formulas.Economy.saleCoins` (ADR 0007), the HUD's pop-up component and Coins display (ADR 0008), the map contract (ADR 0009) and UpgradeService (ADR 0010).

## Context

Concept 7.5 says you push the ball onto the scale and the sale happens automatically, at any size. The coins are `(10 × size³ + finds) × pets × rebirth × Sell value upgrade × bonuses` (Fix), with the 8.3 bonuses: Double coins ×2, Coins boost ×2 and Golden snow ×3 multiply, VIP +10 % and Premium +10 % add. The amount appears as a number ("+3.4K") and flies to the Coins display, and the ball shrinks back to start size. The formula already existed in `Formulas.Economy.saleCoins` (ADR 0007) and is reused unchanged. The ball is client-owned (ADR 0002), so the server must decide a sale from its own view. Finds (#40) and pets (#41) are being built in parallel, and the bonus sources (game passes, boosts, events, VIP, Premium) do not exist yet. Sell value was locked as "Coming soon" until this issue (ADR 0010, owner decision 2026-11-12).

## Decision

**Layout.** `src/places/simulator/server/SellService/` is a Simulator-only service (folder module).

| Module | Kind | Role |
|---|---|---|
| `SellCore` | pure | Sale decision: factors, coins, refusals, the one-sale-per-visit latch, finds per ball, events. Profile, ball, upgrade, pet multiplier, bonus flags and the coin add are injected. |
| `PlateGeometry` | pure | Ball-to-plate gap (sphere against box) and touching / clear. |
| `SaleOverride` | pure | Bonus flag names from `Config.Economy`, all-off flags, and the parser of the `SellFactorOverride` switch. |
| `ScalePlates` | Roblox | Binds `ScalePlate` parts through CollectionService (zone rules from `UpgradeService/StationRules`), finds the nearest plate, builds the Studio test scale. |
| `SellSwitches` | Roblox | Studio switches and diagnostic attributes. |
| `init` | Roblox | Wires the core to BallService, UpgradeService, CurrencyService, DataService, the plates and the `SaleResult` remote. |
| `src/places/simulator/client/SaleController/` | client | `FlightPath` (pure: start, target, inside) and `init` (the "+3.4K" label and its flight). |
| `src/shared/Config/Sell.luau` | data | Margins, check interval, minimum sale, coin reason, `PetMultiplier` attribute name, feedback timing and size, test geometry, diagnostic names. |

**Trigger (server only).** Every `Config.Sell.CheckInterval` (0.1 s) the server takes each player's ball part as it sees it (`BallService.GetBallPart`) and measures the gap between the ball's surface and the box of every bound plate. Touching means a gap ≤ `TouchMargin` (0.25 studs). The owner must also be at the ball: `BallService.IsHeld`, the living character within the 7.4 growth range (`GrowthRange`, `GrowthVerticalRange`), the same distance rule growth uses. There is **no client remote for selling**: the client sends nothing and cannot name a size, an amount or a plate. An exploiting owner can still move its own ball (it owns the physics), but the size and every factor come from the server, so the most it can do is sell the ball it really has, which the concept allows at any time.

**One sale per visit.** A sale attempt (sold or refused) latches the player. While latched, nothing is sold, also when the ball stays on the plate, grows back or is pushed around on it. The latch is released only once the ball is *clear* of every plate: a gap above `ReleaseMargin` (2 studs). The gap between the two margins keeps a ball at the plate's edge from flipping between touching and released. After a sale the ball shrinks to start size on the plate and stays latched, so it cannot be sold again until the player pushes it off and back on. A ball on the plate without its owner at it is not attempted and not latched; it sells when the owner arrives.

**Coins.** `SellCore.quote` collects, all on the server:

| Factor | Source | Invalid |
|---|---|---|
| size (m) | `BallService.GetSizeMetres` (server fraction and zone) | no ball: `NoBall` |
| finds | `SellCore` per player, filled by `SellService.AddFindValue` (#40). 0 until finds exist | the API refuses non-finite, negative and above `MaxFindsValue` |
| pets | Player attribute `Config.Sell.PetMultiplierAttribute` = `PetMultiplier`, written by PetService (#41) on the server; a client-side write does not replicate | missing or not a finite number ≥ 1: ×1 |
| rebirth | `Formulas.Economy.rebirthMultiplier(sim.rebirths)` (1 + 0.5 per rebirth) | not a whole number ≥ 0: `BadProfile` |
| Sell value | `UpgradeService.GetEffect(player, "sellValue")`, read at every sale | — |
| bonuses | `Formulas.Economy.sellBonus(flags)`, flags from `activeBonusFlags(player)` in `SellService/init` | — |

`activeBonusFlags` is the only place the sale reads bonuses from. None of the sources exists yet (game passes and VIP 9.x, boosts, events 7.11; Premium is left to 9.x as well), so it returns every flag off. Those features fill this one function.

The coins are `Formulas.Economy.saleCoins` of these factors: whole coins, rounded down (ADR 0007). A sale worth less than `MinSaleCoins` (1) is refused with `TooSmall` and the ball keeps its size (a ball at zone 1 start size is worth 0.08). Refusals in order: `NotLoaded` (no loaded profile), `NoBall`, `BadProfile`, `TooSmall`, then CurrencyService's own (`NotLoaded`, `TooLarge`, …). A refusal changes nothing.

**After a sale.** In one thread without a yield: `CurrencyService.AddCoins(player, coins, "Sale")` (its normal path, analytics event `Earn` with reason `Sale`), then the finds of the ball are emptied, then `BallService.ResetSize(player)` sets the size fraction to 0, the start size of the ball's zone (7.4: 10 % of the zone maximum). Only a sale CurrencyService accepted resets the ball. Then `SellCore` emits `Sale`, and `SellService` fires `SaleResult(coins)` to that player. A sale is not in the immediate-save list of 6.5 (ADR 0003): its coins land with the next autosave (at most 2 min) or the leave save, like every coin gain. A failed save keeps them on the server and the next save stores them (tested with the fake store).

**Feedback (client).** `SaleResult` is declared in `Net/Remotes` as server → client only, like `Popup`: one whole number 0..`Config.Net.Sale.MaxCoins`, rate limit `Config.Net.RateLimits.SaleResult`, no server handler, so a client call is dropped as `NoHandler`. `SaleController` checks the number again, builds a label with `Components.popup` (the #90 pop-up look), text `NumberFormat.signed(coins)` ("+3.4K", balances round down, ADR 0007), in its own ScreenGui `SaleFeedback` (DisplayOrder 11, the HUD's insets). The label shows at the screen centre (`StartYFraction` 0.4) for `ShowSeconds`, then reads `PlayerGui.SimulatorHud.Coins.AbsolutePosition`/`AbsoluteSize` and tweens to the panel's centre in `FlySeconds` while shrinking to `EndScale`, then fades out in `FadeSeconds`. Without the Coins panel it flies up and fades. The HUD code is not changed: the Coins display updates itself from the `Coins` attribute. Playtest handles on `PlayerGui.SaleFeedback`: `SaleFlights` (count), `LastSaleCoins`, `LastSaleText`, `LastSaleTarget` (`Coins` or `None`), `LastSaleArrived` (the label's centre ended inside the Coins panel). The label is named `SaleGain` and carries `Coins`.

**Map binding (ADR 0009).** `ScalePlate` (tag in `Config.Map.Tags`) is confirmed as the scale's sell area: a `BasePart` below `Workspace.Map` in a zone area with a valid `ZoneIndex`; any number per zone. Binding at start and on `GetInstanceAddedSignal`, unbinding on removal. Outside `Workspace.Map`: ignored silently. Not a BasePart or not in a valid zone: `[MapContract] ScalePlate <full name>: <problem>, ignored`, once per instance. A zone area without any plate: `[MapContract] ScalePlate <area>: zone <n> has no ScalePlate, so it has no selling`, once per zone (checked deferred at start and when an area or plate arrives). The plate's zone is only used for logs and diagnostics: the coins depend on the ball's size, not on which zone's scale it is pushed onto (a ball keeps its size across zones, 7.6). `ScaleAnchor` stays the MAX arrow target and needs no zone; its lookup in `BallService/BallAttributes` now only uses anchors below `Workspace.Map`, so a tagged Kit template elsewhere is never the target.

**Upgrade.** `sellValue` is removed from `Config.Upgrades.Locked`: the menu shows its price and buy button and the server accepts its purchase. Its effect (`1 + 0.05 × level`, ×1.05 at level 1, ×6 at 100) is read at every sale, so a purchase counts from the next sale on.

**Server API.** `SellService.AddFindValue(player, value)` for finds (#40), `SellService.GetFindValue(player)`, `SellService.Subscribe(fn)` (`Sale` and `Refused` events with every factor, for #40 and analytics #43; listeners must not yield). BallService gains `GetBallPart`, `IsHeld` and `ResetSize`.

**Studio playtest support (Studio at `game.PlaceId == 0` only; live servers skip all of it).**
- Startup line, always printed: `[SellService] started plates=<n> studioSwitches=true`. Bound plates print `[SellService] plate bound <full name> zone=<n>`.
- Every sale and refusal prints `[SellService] <name> (<userId>) <text>`, e.g. `sold coins=80 zone=3 size=2.0000m ballValue=80.0000 finds=0 pets=1 rebirths=0 (x1) sellValue=1 (level 0) bonus=1 flags= quote=80 balance=80`.
- Diagnostic Player attributes after every sale or refusal: `SellLastSale` (that text), `SellLastCoins` (coins credited, 0 for a refusal; the number attributes stay as they were for `NotLoaded` and `NoBall`, which compute no factors), `SellLastSizeMetres` (exact), `SellLastBallValue`, `SellLastFindsValue`, `SellLastPetMultiplier`, `SellLastRebirths`, `SellLastRebirthMultiplier`, `SellLastSellValueLevel`, `SellLastSellMultiplier`, `SellLastBonus`, `SellLastBonusFlags` (e.g. `DoubleCoins,Vip`), `SellLastZone`, `SellLastBalance`, `SellLastRefusal` (`""` after a sale), `SellCount`, `SellRefusals`; `SellFindsValue` (finds in the current ball); live, written on change: `SellTouching` (ball touches a plate) and `SellLatched` (must leave the plate before the next sale). A playtest recomputes `floor((10 × SellLastSizeMetres³ + SellLastFindsValue) × SellLastPetMultiplier × SellLastRebirthMultiplier × SellLastSellMultiplier × SellLastBonus × (1 + 1e-12))` and compares it with `SellLastCoins`.
- Switches on `ServerScriptService`, set from the server command bar:
  - `SellTargetUserId` (number): the player the switches act on; `0` means every player (the test scale uses the first).
  - `SellScaleTestGeometry` (number): `n` (a zone of this world that no other `Workspace.Map` area uses) builds `Workspace.Map.SellScaleTest`, a Folder with `ZoneIndex = n` holding one `ScalePlate` (16 × 1 × 16 studs, yellow, its top 0.05 studs above the ground) 24 studs in front of the target's character, with a `ScaleAnchor` Attachment 4 studs above it. It also puts a decoy `ScaleAnchor` part at the character in `ServerStorage.SellScaleTestDecoy`, which the MAX arrow must ignore. `0` removes both. A used or invalid zone builds nothing and prints why. The value picks the `ZoneIndex`, so the test scale cannot clash with other test zones (#39); `UpgradeStandTestGeometry` takes the first free zone and so avoids it.
  - `SellAddFindValue` (number, idle 0): adds that value to the target's ball through `SellService.AddFindValue` and resets to 0. `-5`, `NaN` or `inf` show a refusal.
  - `SellFactorOverride` (string, kept until changed): `pet=<n ≥ 1> rebirths=<whole n> bonus=<Flag>,<Flag>` (flags `DoubleCoins`, `CoinsBoost`, `GoldenSnow`, `Vip`, `Premium`; `bonus=none`), any subset, each once. Replaces those factors in every sale on this Studio server; the profile is not changed. `""` clears it; an invalid text prints the problem and clears it.
- Reused switches: `BallSetSizeFraction`, `BallSetZone`, `BallGrowthPaused`, `BallTargetUserId` (ADR 0002) for exact sizes; `CurrencyAddCoins` (ADR 0007) for coins to buy Sell value; `UpgradePurchase`, `UpgradeSetLevel` (ADR 0010); `DataFailSave`, `DataAutosaveNow`, `DataSimulateRejoin` (ADR 0006) for the save cases.

## Consequences

- Start counts in World 1 grow by one server service (`SellService`) and one client controller (`SaleController`): 12 services and 11 controllers (ADR 0008 recorded 11 and 10). Lobby and Arena are unchanged; their NetService still creates `SaleResult` (the declaration list is shared) and drops client calls as `NoHandler`.
- Finds (#40) call `SellService.AddFindValue` with `Formulas.Economy.findValue` when a find is picked up; leaving loses the value (6.5). Pets (#41) write `PetMultiplier` on the server. Neither needs a change in SellService.
- Bonus features (9.x, 7.11) fill `activeBonusFlags` in `SellService/init`; the flag names are the keys of `Config.Economy.SellMultipliedBonuses` / `SellAddedBonuses`.
- `ScalePlates` uses `UpgradeService/StationRules` in place. Lifting it into a shared map resolver (ADR 0009) is left to the first of #39–#41 that needs it, so parallel branches do not move the same file.
- `BallService/init.luau` is now about 450 lines (the three API functions); splitting it is a separate chore.
- No save format change: `sim.coins`, `sim.totalCoins` and `sim.rebirths` already exist in schema v1; finds in the ball are not saved (6.5).
- The test geometry and decoy exist only in Studio at PlaceId 0. The real scales come with the zone builds (#29), tagged `ScalePlate` and `ScaleAnchor` as above.
