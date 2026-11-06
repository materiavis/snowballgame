# 0007: Economy config, formulas, number format, rarity, RNG and CurrencyService

**Status:** Accepted with merge of PR #87.

Implements `8.3-economy-config` (#27) from the "Configuration" principle and the `Config/*`, `Formulas/*`, `NumberFormat`, `Rarity`, `Rng` and `CurrencyService` rows of [ADR 0003](0003-snow-rush-intake.md) (plan revision 2). It records what that plan left to the implementation.

## Context

Concept 1.2 and 8.3 say every number is a Startwert that lives in config modules, and the values in chapter 7 win when they differ. The ✅ knobs (1.25, 1.2, 2 + 2n and the other ✅ rows of 8.3) change only through game design. Concept 8.1 keeps Coins and Snow Coins apart and never sells either for Robux. Concept 10.3 fixes the K…Sx abbreviations and the m/km display, and 8.5 says rarity is never shown by colour alone. ADR 0003 asks for pure, unit-tested formulas the client can preview while the server recomputes, seeded RNG with odds tables, and one CurrencyService for every balance change, logged as analytics economy events. The profile schema and save rules come from ADR 0006.

## Decision

**Pure modules, thin Roblox bindings.** Each shared module is a folder. The children are pure (no requires, no `game`, no Roblox globals at load) and take their config in `new(...)`, so `lune run tests` loads them with the real Config. The folder's `init.luau` is the only file that knows the Instance tree and binds the children to `Config/*`. DataService and Net follow the same pattern.

| Module | Children | Role |
|---|---|---|
| `Config/*` | `Zones`, `Ball`, `Finds`, `Pets`, `Upgrades`, `Economy`, `Events`, `Lobby`, `Fight`, `Social`, `Monetization`, `Rarity`, `Display`, `Currency` | Every Startwert of chapters 7 to 9, one module per area, frozen all the way down. Comments name the concept section and the ✅/🟦 status. Robux asset ids are `0` placeholders that humans fill in at publish. |
| `Formulas` | `Zones`, `Economy`, `Pets`, `Upgrades` | Zone size, ball value, expected strength, balls per barrier, barrier price, worlds and gates, zone optics. Also sell with bonuses, find value, rebirth cost, multiplier and rank, income per minute, minutes-of-income rewards and Snow Coins per match. Plus egg zone and price, pet bonus with variants, equip slots, the Q11 inventory expansion, and upgrade cost and effect. |
| `NumberFormat` | `Formatter` | `number`, `signed` ("+3.4K") and `size` ("4.7 m" / "1.2 km"). |
| `Rarity` | `Tiers` | Name, rank, stars or symbol, RGB colour, `label` ("★★★ Rare"), plus `color3` in the binding. Load fails if a tier has neither stars nor a symbol. |
| `Rng` | `Weighted`, `Odds` | Weighted pick on a roll in [0, 1). Egg tables (normal and luck boost, secret pet from egg 3), find tables (zones 1–5 of a world give Legendary's 1 % to Common, secret 1 in 2,000), `rollEgg` (rarity, then an independent Frosty roll), `rollFind`. `Rng.new(seed?)` wraps Roblox `Random` and takes any `{ next }` generator, so tests use `SeededRandom`. |
| `CurrencyService` | `CurrencyCore` | The only writer of `sim.coins`, `sim.totalCoins` and `fight.snowCoins`. |

**Rounding.** Coin amounts that are paid or charged are whole coins, rounded down: barrier, egg, upgrade, rebirth, inventory expansion, sale, minutes of income and Snow Coins. A tiny relative nudge (×(1 + 1e-12)) stops float noise such as 79.999… from costing a coin. Multipliers, find values and income per minute stay exact until the final sum. Spending needs whole numbers, which is why prices are whole.

**Chance tables include the secret.** `eggOdds` and `findOdds` list every outcome in percent, secret included. The secret chance comes off the other rarities in proportion, which is the same as rolling the secret first. The egg station and the collection book can show exactly the table the roll uses (8.5).

**Formula readings the concept leaves open** (assumptions, reported in the PR):
- "Barrier price of the highest unlocked zone" (rebirth) is the barrier at the *end* of that zone. Only this reading gives 8.4's "Rebirth 1 ca. 7.5M" (2 × 3.76M).
- The pet bonus is what the pet adds: the "×1.1" in the egg table is 1 + 0.1. The Golden Yeti is 3 × the Legendary *bonus*. Gold/Rainbow and Frosty multiply the bonus and stack with each other.
- Income per minute is one full ball of the highest unlocked zone × one multiplier the caller passes (pets × rebirth × Sell value upgrade × active bonuses). 8.2 lets Development change this. The ball count is `Config.Economy.IncomeBallsPerMinute`.
- Snow Coins: (30 or 15 + 2 per freeze + 10 MVP) × Double × private 0.5 × (1 + VIP + Premium), rounded down. A private-server loss gives 7.

**Number format** (`Config.Display`). The concept fixes K, M, B, T, Qa, Qi, Sx from 1,000, and one decimal with a decimal point for sizes. Not fixed, so chosen here:
- Abbreviated numbers have one decimal with a trailing ".0" dropped and no space: "1K", "3.4K", "4.6Sx". This follows the in-game examples "+3.4K" and "Zone 6 · 3.7M".
- Values are **rounded down**, so a balance never looks larger than it is. 999,999 shows "999.9K", 3,755,901 "3.7M" (the concept table says "ca. 3.8M"), and the zone 5 maximum 4.88 m shows "4.8 m" (table: "4,9 m").
- The suffix or unit is chosen after rounding, so "1000K" and "1000.0 m" never appear. Metres run up to 999.9 m, kilometres start at 1,000 m.
- `Display.Rounding = "Nearest"` switches to round-half-up (tested too) if design prefers the table's rounding.
- Beyond Sx the suffix stays ("1500Sx").

**CurrencyService.**
- **Generic core.** Currencies come from `Config.Currency`: profile path, optional total path and bounds. The core has no game words in it, so it can move to the Materiavis toolkit.
- **Checks on every change.** The profile must be loaded (`DataService.GetProfile` returns it only while `Loaded`), so changes while loading, after release, after the teleport hand-off and after a lost lock are refused (`NotLoaded`). The amount must be a finite whole number ≥ 0 and ≤ `MaxChange`; NaN, ±inf, negatives, fractions and non-numbers give `BadAmount`, too large gives `TooLarge`. The reason must be a string of 1–64 chars. A stored balance that is not a whole number ≥ 0 gives `BadProfile`. Spending more than the balance gives `Insufficient`. A refused call changes nothing.
- **Balance rules.** `add` grows the balance and the total. `spend` and `reset` (rebirth) leave the total alone. A balance is held at `MaxBalance` and the dropped part is logged.
- **Technical bounds, not design.** Coins: change and balance 1e30, above the about 1e22 that zone 50 reaches. Snow Coins: change 1e6, balance 1e15, below 2^53 so their sums stay exact. Above about 9e15 coins, double precision drops single coins; at those values that does not matter.
- **Analytics hook.** `CurrencyService.Subscribe(fn)` receives `Earn`, `Spend`, `Reset` and `Refused` events: `operation` (`Add`/`Spend`/`Reset`), `userId`, `currency`, `amount`, `balance`, `total`, `reason`, `refusal`, `clamped`. AnalyticsService (#43) subscribes; nothing is sent anywhere yet. A failing listener is caught and logged and never undoes a change.
- **Saving is the caller's job.** The profile is changed in place and DataService stores it with the next autosave (at most 2 min). Immediate saves (concept 6.5: barriers, rebirths, Robux purchases, trades) follow this pattern:

  ```lua
  local ok, why = CurrencyService.SpendCoins(player, price, "Barrier:" .. zone)
  if not ok then return end                      -- "Insufficient", "NotLoaded", ...
  unlockZone(profile, zone)                       -- change the rest of the profile
  local saved = DataService.SaveNow(player, "Barrier")
  -- saved == false: the state stays on the server and lands with the next save (6.5).
  ```

  A Robux grant must succeed in `SaveNow` before `ProcessReceipt` returns `PurchaseGranted` (ADR 0003). That logic belongs to PurchaseService.
- **No remote.** Clients never send amounts. The HUD issue decides how balances reach the client (player attributes or a server-to-client remote); the Studio mirror below is not that mechanism.
- **Leaderboards.** `sim.totalCoins` feeds the TotalCoins board through `DataService.QueueLeaderboardValue`. The leaderboard issue wires that, including private servers and bots.

**Studio playtest support (Studio at `game.PlaceId == 0` only; live servers skip all of it).**
- Startup line, always printed: `[CurrencyService] started currencies=Coins,SnowCoins studioSwitches=true`.
- Player attributes `Coins`, `TotalCoins` and `SnowCoins`, set when the profile loads and after every change. `CurrencyLastChange` holds the last change or refusal as text, `CurrencyRefusals` counts refusals.
- Every change and refusal prints `[CurrencyService] <name> (<userId>) <text>`, for example `Coins +500 StudioSwitch -> 500 total=500` or `Coins Spend 1000 StudioSwitch refused: Insufficient (balance 500)`.
- Switches on `ServerScriptService`, set from the server command bar:
  - `CurrencyTargetUserId` (number): the player the switches act on; `0` means every player.
  - `CurrencyAddCoins`, `CurrencySpendCoins`, `CurrencyAddSnowCoins`, `CurrencySpendSnowCoins` (number): run once with that amount and reset to `0`. The amount goes through the normal checks, so `-5`, `1.5` or `math.huge` show a refusal.
  - `CurrencyResetCoins`, `CurrencyResetSnowCoins` (bool): `true` runs a reset and sets the switch back to `false`.
- Together with the DataService switches (`DataFailSave`, `DataAutosaveNow`, `DataSimulateRejoin`, `DataFailLoad`, ADR 0006), a playtest can show a change that survives a failed save, lands with the next save and is still there after a rejoin.

## Consequences

- Server start counts grow by one (`CurrencyService`): 6 in Lobby and World 1, 5 in Arena (ADR 0006 recorded 5 and 4). It runs in every Place because each one changes a balance: the Lobby group chest gives Coins and Snow Coins, the Simulator earns and spends Coins, and the Arena gives Snow Coins.
- Feature issues read numbers from `Config/*` and call `Formulas`, `Rng` and `NumberFormat`. They do not write their own copies. Changing a ✅ value is a game design decision, not a code review comment.
- A headless test scans `src/` and fails if any file outside CurrencyService assigns `coins`, `totalCoins` or `snowCoins`.
- `Config.Currency` paths are part of the save format and only change with a Schema migration. This PR changes no stored format.
- Not in this PR (content and features): English zone, pet, find and rank names (concept appendix), `MaxCountedSpeed` (PR #7), growth physics, the HUD.
