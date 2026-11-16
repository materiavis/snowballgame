# 0013: Pets and Egg 1 (Vertical Slice slice of 7.9)

**Status:** Accepted with merge of PR #PR_NUMBER.

Implements the Vertical Slice part of `7.9-pets-eggs` (#41): Egg 1 bought at an egg station, hatching, equipping in the slots, the additive pet multiplier and equipped pets following in the Simulator. Egg 2, Best Equip, Gold, Frosty, deletion, inventory expansion and following in the Lobby are #103 (owner decision 2026-11-10). Uses the `PetService`, `EggService` and `sim.pets` rows of [ADR 0003](0003-snow-rush-intake.md), the Net layer (ADR 0005), DataService (ADR 0006), CurrencyService, `Formulas.Pets` and `Rng` (ADR 0007), the window stack, left-edge buttons, pop-ups and prompts (ADR 0008, #90), the map contract (ADR 0009) and the station rules of the upgrade stand (ADR 0010).

## Context

Concept 7.9 fixes: pets only give coins, bonuses add up (`1 + bonus 1 + bonus 2 + …`), the egg price is 3 full balls of the egg's zone (Egg 1 = 240), the chances 60/25/10/4/1 are always visible at the station, eggs are never sold for Robux, equipped pets follow (Simulator and Lobby; never in the Arena, decision 15.10), 3 equip slots at the start, an inventory of 50. Concept 6.5 says the server decides egg results and that a double tap on an egg is one purchase. ADR 0003 R2 asks for client-side pet rendering and simplified foreign pets. Spielraum: walking behaviour, hatch animation, look of the inventory, the simplification of foreign pets. No pet models exist yet.

## Decision

**Layout.**

| Module | Where | Kind | Role |
|---|---|---|---|
| `PetService` (`init`, `PetCore`, `PetAttributes`) | `src/places/social/server` | server, Lobby + Simulator | Only writer of `sim.pets`: add, equip/unequip within the slots, multiplier, attributes, `PetEquip` remote. Replaces `SocialSkeletonService`. |
| `EggService` (`init`, `EggCore`, `EggStations`) | `src/places/simulator/server` | server, Simulator | Egg stations, `EggHatch` remote, price, roll, hatch, pop-ups. |
| `PetCatalogue` (`init`, pure `Catalogue`) | `src/shared` | shared | Pet ids, names, egg, rarity, availability, `bonusOf`, zone → egg. |
| `PetCodec` | `src/shared` | pure | Text form of `PetInventory` / `PetEquipped`. |
| `Config/Eggs` (new), additions to `Config/Pets`, `Config/Map`, `Config/Net`, `Config/Ui` | `src/shared/Config` | data | All numbers and names below. |
| `PetFollowController` (`init`, `PetFormation`, `PetModels`) | `src/places/social/client` | client | Followers. Runs only for `Config.Pets.Follow.Roles` (Simulator now; #103 adds the Lobby). Replaces `SocialSkeletonController`. |
| `PetsWindowController` (`init`, `PetsPanel`, `PetsView`) | `src/places/simulator/client` | client | Pets window and the left-edge "Pets" button. |
| `EggStationController` (`init`, `EggLabel`, `EggStationView`) | `src/places/simulator/client` | client | Station label with price and chances, hatch request, missing amount, reveal. |

PetService sits in `social` because ADR 0003 runs it in the Lobby and the Simulator. In the Lobby it already loads, publishes the attributes and accepts `PetEquip`; #103 only adds the client parts there. EggService is Simulator-only (stations exist only in zones). The pets window stays in the Simulator client in this slice (no Lobby window in scope).

**Data (save format v1, unchanged).** `sim.pets[uid] = { kind, variant = "normal", frosty = false, equipped }` as in ADR 0003 and `DataService/Schema`. `kind` is a `Config.Pets.Catalogue` key (`SnowHare`, `AlpineChough`, `Marmot`, `RedFox`, `SnowyOwl`), so these keys are part of the save format and are never renamed. The uid is `"<userId>_<unix time hex>_<16-bit random hex>"` (at most 36 characters, `Config.Net.Pets.MaxUidLength` = 48); the userId prefix keeps uids unique across players, and PetCore retries a candidate that clashes with the player's own pets. The capacity is the stored `sim.inventorySize` (default `Config.Data.InventorySize` = 50; a broken value falls back to the default). Equip slots are `Formulas.Pets.equipSlots(sim.highestZone, false)`: 3 in the Vertical Slice; the game pass flag is `false` until monetisation. `sim.collection.pets` is not written (open question).

**Multiplier.** `Formulas.Pets.totalMultiplier` over the bonuses (`Formulas.Pets.petBonus` via `PetCatalogue.bonusOf`) of the valid equipped pets. If a stored profile has more equipped pets than slots, only the strongest `slots` count. Pets give only coins: the multiplier is used by selling only.

**Interface to selling (#38).** PetService writes the player attribute **`PetMultiplier`** (`Config.Pets.MultiplierAttribute`) on every server when the profile loads and after every add, equip, unequip or clear. SellService (#38) reads the same literal (its `Config.Sell.PetMultiplierAttribute`). It is absent until the profile has loaded. Server code may also call `PetService.GetMultiplier(player)` (1 while not loaded).

**Remotes (ADR 0005).**

| Remote | Args | Rate (`Config.Net.RateLimits`) | Server checks |
|---|---|---|---|
| `EggHatch` | none | burst 3, 2/s | Station: the closest bound station within `prompt MaxActivationDistance (10) + Config.Eggs.StationReachTolerance (6)` studs of the HumanoidRootPart, else `NoStation`. Then `EggCore.purchase`. |
| `PetEquip` | `uid` string 1..48, `equipped` boolean | burst 10, 5/s | `PetCore.setEquipped`: uid must be a key of the player's own `sim.pets` (`BadUid`), the record valid (`BadPet`), a free slot for equip (`SlotsFull`), not already in that state (`Unchanged`). |

No egg number, price, rarity or pet is ever sent. Lobby and Arena drop `EggHatch` as `NoHandler`; the Arena also drops `PetEquip`.

**Purchase (`EggCore.purchase`), refusal order.** `BadEgg` (not a whole egg number), `NotAvailable` (not in `Config.Eggs.Available`; Egg 2 until #103), `Busy` (a hatch of this player less than `Config.Eggs.HatchCooldownSeconds` = 1 s ago: concept 6.5 double tap), `NotLoaded` / `BadProfile` / `InventoryFull` (from `PetService.HasRoom`), roll, `Insufficient` (CurrencyService), then `PetService.AddPet`. The roll is `Rng.pick(Rng.eggOdds(egg, false), generator.next())` on the server's `Rng.new()` generator; it happens before the spend, and the spend and the add run in one thread without a yield, so any save snapshot holds both or neither. A refusal changes nothing; only a success starts the cooldown. Not an immediate save (ADR 0003 list): it lands with the next autosave or the leave save. Frosty (1 in 50) and the luck boost are not rolled in this slice; #103 switches to `Rng.rollEgg`.

**Feedback.** Success: `EggLastHatch = "<uid>:<kind>"` (player attribute, every server) and the pop-up `PetHatched` ("New Pet!"). `InventoryFull`: pop-up `PetInventoryFull`. Too few coins: the client checks the server's `Coins` attribute first and shows `Text.EggNeedMore` ("Need 1.2K more", `NumberFormat.price`, rounded up, like the upgrade decision of 2026-11-12) on the station label for `Config.Ui.EggStationLabel.MissingMessageSeconds` (2 s) and sends nothing. The pop-up path is not used for it because pop-up numbers are formatted rounding down.

**Egg station (ADR 0009).** EggService binds every `EggStation` station that `StationRules` (from `UpgradeService`, used unchanged) accepts and whose zone has an egg (`PetCatalogue.eggForZone`, from `Config.Pets.EggZones`); others warn once (`[MapContract] EggStation <name>: zone N has no egg …, ignored`). It creates a prompt with `Prompts.create("EggStation", PrimaryPart, { tag = "EggStationPrompt" })` (E / ButtonX / tap, "Hatch" / "Egg Station") and writes `EggIndex` and `EggOpen` on it. A station of an egg not on sale keeps a label "Coming soon" and its prompt is disabled. The client binds those prompts (they stream in with the Atomic station) and puts a BillboardGui at `LabelAnchor` (or 6 studs above `PrimaryPart`): egg name, price (`Formulas.Pets.eggPrice`), and one line per pet with name, rarity as stars + name in the rarity colour (8.5: never colour alone) and its chance from `Rng.eggOdds`, the same table the server rolls with.

**Hatch reveal (Spielraum).** On `EggLastHatch` the label of the station the player used shows a wobbling egg and "Hatching…" for `Config.Eggs.Reveal.WobbleSeconds` (0.6 s), then the pet's name, rarity (stars, name, colour, the panel tinted in the rarity colour) and bonus "×1.22" for `ShowSeconds` (1.8 s). The "own effect per rarity" is that colour and star count for now; the server-wide Legendary announcement is 7.24.

**Pets window (Spielraum).** Own ScreenGui `PetsHud` (DisplayOrder `Config.Ui.DisplayOrder.PetsHud` = 11), `Components.window` sized by `Layout.window` (≤ ⅔ of the screen, clear zones; X, P and B close). Registered with `MenuController.register` and `MenuController.registerButton({ id = "Pets", window = "Pets" })`, so P, D-pad left and the left-edge "Pets" button open it. Header: "Equipped 1/3", "Coins ×1.22" (the server's `PetMultiplier`), "2/50 pets". A grid of cells (as many columns of ≥ 150 px as fit): pet name, rarity (stars + name, the cell outline in the rarity colour), bonus "×1.1", and a button "Equip" / "Unequip" / "Slots full". Order: equipped first, then rarest, then name, then uid. The button sends `PetEquip(uid, not equipped)` only for "Equip" and "Unequip". Everything shows "–" until `DataLoadStatus == "Loaded"`; an empty inventory shows "No pets yet. Hatch an egg at the Egg Station!".

**Player attributes (written by the server).**

| Attribute | Where | Meaning |
|---|---|---|
| `PetMultiplier` | every server | 1 + bonuses of the equipped pets (selling #38). |
| `PetSlots`, `PetInventorySize` | every server | Equip slots now, capacity. |
| `PetInventory` | every server | `"<uid>:<kind>:<1\|0>;…"` (PetCodec), sorted by uid. Read by the own pets window. |
| `PetEquipped` | every server | `"<uid>:<kind>;…"`. Read by every client for the followers. |
| `EggLastHatch` | every server | `"<uid>:<kind>"` of the last hatch (reveal). |
| `PetInventoryCount`, `PetEquippedUids`, `PetLastChange` | Studio at PlaceId 0 | Diagnostics, e.g. `PetLastChange = "Remote Equipped RedFox uid=… multiplier=1.35"`, `"Remote refused: SlotsFull …"`. |
| `EggLastRoll`, `EggRefusals` | Studio at PlaceId 0 | e.g. `"egg 1 Remote Rare -> Marmot uid=… price=240 forced=false"`, `"egg 1 Remote refused: Busy"`, `"egg ? Remote refused: NoStation"`; refusal count. |
| `PetFollowForeignPreview` | Studio at PlaceId 0 | Mirror of the switch below. |

As everywhere, the client only reads them and server code never reads them back.

**Following (`PetFollowController`, R2).** The server publishes `PetEquipped`; each client draws every player's equipped pets as client-only parts in `Workspace.ClientPets.<UserId>.<uid>` (Model attributes `Kind`, `Owner`, `Simplified`; folder attribute `UpdateRate`, 0 = every frame). Placeholder shapes: balls in the rarity colour, anchored, `CanCollide`/`CanTouch`/`CanQuery`/`CastShadow` off, moved with one `Workspace:BulkMoveTo` per frame. Formation (`Config.Pets.Follow`): side by side 5 studs behind the character, 3.5 studs apart, 3 per row, on the ground (`root − half root height − HipHeight`), exponential smoothing (sharpness 10/s, frame-rate independent), a jump when more than 60 studs away (teleport, respawn). Own pets: body + head, a name label with stars (up to 40 studs), a small bob, every frame. Foreign pets (simplified): one part, no label, no bob, updated 10 times a second, hidden beyond 150 studs. Not in the Arena (the Arena does not mount `places/social`), not in the Lobby yet (`Roles`).

**Studio playtest support (Studio at `game.PlaceId == 0` only; live servers skip all of it).**
- Startup lines, always printed: `[PetService] started pets=5 inventory=50 multiplierAttribute=PetMultiplier studioSwitches=true` and (Simulator) `[EggService] started eggs=10 egg1Price=240 stations=<n> studioSwitches=true`. Every change and refusal prints `[PetService] <name> (<userId>) <PetLastChange text>` / `[EggService] <name> (<userId>) <EggLastRoll text>`; bound stations print `[EggService] station bound <full name> zone=1 egg=1 open=true`.
- Switches on `ServerScriptService`, set from the server command bar:
  - `PetTargetUserId` (number, idle 0): the player all pet and egg switches act on; 0 = every player.
  - `EggStationTestGeometry` (bool): `true` builds `Workspace.Map.EggTestZone` (Folder, `ZoneIndex = 1`) 14 studs in front of the target's character with one valid `EggStation` Model (`Base` as PrimaryPart, an egg-shaped part, `LabelAnchor`, Atomic), which binds a prompt and a label. If another map area already has `ZoneIndex 1` (for example `UpgradeStandTest`, which takes the first free zone), it builds nothing and prints why: build the egg test zone first, then `UpgradeStandTestGeometry` takes zone 2. `false` removes it.
  - `EggForceRarity` (string, idle ""): a rarity id (`Common` … `Legendary`) makes every following hatch that rarity; `""` rolls normally. Other values warn and roll normally. The coins, the cooldown and the inventory still apply.
  - `EggPurchase` (string, idle ""): `"<egg>"` or `"<egg> <times>"` (times 1..10). Runs that many purchases in the same frame through `EggCore.purchase` (the remote path without the Net guard and without the station distance), then resets to `""`. `"1 2"` is the double tap: one `Hatched`, one `Busy`. `"2"` shows `NotAvailable`.
  - `PetGrant` (string, idle ""): `"<kind>"` or `"<kind> <count>"` (1..200), e.g. `"RedFox 3"`, through `PetCore.add` (kind and inventory limit checked); resets to `""`.
  - `PetClear` (bool): `true` removes every pet of the target and resets to `false`.
  - `PetFollowForeignPreview` (bool): mirrored to the target's player attribute; the client then also draws its own equipped pets through the foreign (simplified) path, 8 studs to the side, in `Workspace.ClientPets.<UserId>Preview`, so R2 can be checked with one player.
- With `CurrencyAddCoins` (ADR 0007) and `DataFailSave`, `DataAutosaveNow`, `DataSimulateRejoin` (ADR 0006) a playtest can hatch, equip, fail a save, save again and check pets, equip state and `PetMultiplier` after a rejoin.

## Consequences

- Server start counts: Lobby 8 (PetService replaces SocialSkeletonService), World 1 12 (+ EggService), Arena 7 (unchanged). Client: Lobby 5 (PetFollowController replaces SocialSkeletonController; it returns at once there), World 1 12 (+ PetsWindowController, + EggStationController), Arena 4.
- NetService creates two more remotes in every Place (`EggHatch`, `PetEquip`).
- The `CollisionAssign` source check (no remotes in Simulator code) now allows exactly one `FireServer` each in `EggStationController/init.luau` (`remote:FireServer()` on `EggHatch`) and `PetsWindowController/PetsPanel.luau` (`remote:FireServer(current.uid, not current.equipped)` on `PetEquip`).
- No save format change. The catalogue keys are part of the format from now on.
- `StationRules` is required from `UpgradeService` instead of being moved to a shared map resolver, to avoid conflicting with the parallel station work (#38, #39, #40).
- The real World 1 map has no zone areas yet (#29), so only the Studio test station covers the runtime path; a builder's `EggStation` in `Zone01` binds without code changes.
- Slots only change with `sim.highestZone` (zone 10, later); `PetSlots` is refreshed on the next pet change or load. The zone feature (#39) should call a refresh once slots can change mid-session (not needed in zones 1–5).
