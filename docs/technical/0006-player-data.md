# 0006: DataService, player data and session locking

**Status:** Accepted with merge of PR #84.

Implements `12.1-player-data` (#26) from the "Data model and failure behaviour" section of [ADR 0003](0003-snow-rush-intake.md) (plan revision 2, D1: in-house `UpdateAsync` lock) and records what that section left to the implementation.

## Context

Concept 6.5 and 12.1 set the save rules: never write an empty profile over saved data, save immediately for purchases, barriers, rebirths and trades, keep state on the server when a save fails, never write an older state over a newer one, save before every teleport, lose at most 2 minutes in a crash, and honour Roblox deletion requests. ADR 0003 decided the schema v1 table, the lock record `{lockServer, lockTime}`, `saveSeq`, the trade ledger, the ordered-store encoding and that `game.PlaceId == 0` uses in-memory stores only. CLAUDE.md §6 allows only one module to touch DataStoreService.

## Decision

**Layout.** `src/server/Services/DataService/` is one service (folder module). `init.luau` is the only Roblox-facing part and the only file that names DataStoreService. Its children are pure (no requires, no `game`), so `lune run tests` loads them, the same pattern as `Net` (ADR 0005):

| Module | Role |
|---|---|
| `DataCore` | Session lifecycle: load, save, release, teleport hand-off, autosave pass, erase. Store, clock, JobId, wait, kick and logging are injected. |
| `LockRecord` | The `UpdateAsync` transforms for acquire, write and resume (the lock and `saveSeq` rules). |
| `Schema` | Schema v1 defaults, migrations (none yet), filling missing fields. |
| `GlobalStores` | `TradeLedger` access and global leaderboard stores. |
| `Retry` | Exponential backoff for store calls. |
| `FakeStore` | In-memory DataStoreService with fault injection. |
| `StoreProvider` | Chooses fake or real before DataStoreService is touched. |
| `EraseUserCommand` | Owner-run right-to-erasure script. |

All numbers are in `src/shared/Config/Data.luau`.

**Stored record.** One key per player, `ProfileKeyPrefix .. userId` in `ProfileStoreName`: `{ saveSeq, lockServer?, lockTime?, data }`. `data` is the schema v1 profile from ADR 0003. Sets keyed by zone, find or pet id use string keys, because DataStores store JSON.

**Session lock (ADR 0003 rev 2).**
- Load is one `UpdateAsync`. Nothing stored: a new profile from defaults is written with our lock. A free, own or stale lock (`now - lockTime >= LockTimeout`, 600 s) is taken. A fresh foreign lock cancels the update without writing, and the server retries every `LockRetryInterval` (6 s) until the holder releases or the lock goes stale. A stale lock is stolen and logged.
- Every write (autosave, `SaveNow`, release) is one `UpdateAsync` that checks `lockServer == JobId` and renews `lockTime` in the same call. If the lock belongs to someone else or the record is gone, the write is cancelled, the session becomes `Lost`, the player is kicked with `LockLostKickMessage` and that server never calls the store for that profile again.
- `saveSeq` grows by one per write. A write is refused (`Stale`, session lost) if the stored `saveSeq` is above the highest seq this server ever tried. The new seq is `max(stored, last known) + 1`, so a write that landed but reported an error still moves forward.
- One write at a time per profile (a per-session queue), so a later save never runs with an older snapshot. Each write stores a deep copy taken when it starts.
- Wall clock `os.time()` is the lock clock, because it is shared across servers.

**Loading (6.5 Laden).** A store error is never treated as "new player": only a successful `UpdateAsync` that sees no record creates defaults. After `StoreAttempts` failed calls (backoff 1, 2, 4, 8 s) the status becomes `Failed`, nothing is written, and loading retries every `LoadRetryInterval` (30 s) while the player stays. A record this server cannot use (newer `schemaVersion`, not a table) is treated the same way and never overwritten. Load status per player: `Loading`, `Loaded`, `Failed`, `Lost`, `Teleported`, `Released`. `IsPortalLocked` is true unless `Loaded`. #35 shows the hint, #37 locks the portals, and TravelService (#28) sends players outside the Lobby back to it; #26 adds no UI, client code or remote.

**Saving (6.5, 12.1).** Autosave every `AutosaveInterval` (120 s) renews every lock and flushes leaderboard values. `SaveNow(player, reason)` yields until the write is stored and returns `true`, or returns `false` with the state still in memory. Callers that grant something (receipts, barriers, rebirths, trades) act on that result. On leave and on `BindToClose` (parallel, `BindToCloseTimeout` 25 s) the profile is saved and the lock released in one write. If that fails, the session keeps the lock and autosave retries the release, so no other server can load an older state meanwhile. A player who rejoins the same server before then resumes the in-memory state.

**Teleport (6.5).** `PrepareTeleport(player)` saves and releases. On `false` the lock is still held and the player stays (TravelService shows the message). On `true` the session is `Teleported` and no longer writes. If the teleport then fails, `ResumeAfterTeleportFailure(player)` takes the lock back only if nobody locked or wrote the profile in between; otherwise the session is lost and the player is kicked.

**Server crash (6.5).** At most the last `AutosaveInterval` is lost. Immediate saves are stored before `SaveNow` returns. The next server waits for the dead server's lock to age out (up to `LockTimeout`) and then steals it.

**Not saved (6.5).** The schema has no ball size and no "finds in the ball". Collection finds live in `sim.collection` from launch.

**Load hook for trades.** `RegisterLoadHook(fn(userId, profile))` runs after the lock is taken and before the status becomes `Loaded`. Saves are allowed in that window. The trade reconcile on load (`pendingTradeId`) is registered by TradeService (#49). Until then there is no extra step.

**Trade ledger and leaderboards.** `GetLedgerEntry` / `UpdateLedgerEntry(tradeId, transform)` give UpdateAsync-based check-and-set on `TradeLedger`. The trade state machine is #49. Leaderboard values are queued with `QueueLeaderboardValue(board, userId, value)` and written on the next autosave only. Boards and their encodings are in `Config.Data.Boards`: `Log` = `floor(log10(max(v, 1)) * 1e6)` for coins, `Raw` = whole number otherwise. `GetLeaderboardTop` decodes. `SetLeaderboardWritesEnabled(false)` is the switch for private servers; deciding where to use it and excluding bots belong to the leaderboard issue.

**Deletion requests (12.1).** `DataService.EraseUser(userId)` removes the profile and the player's entry on every board. It refuses while the player has a session on that server. A server elsewhere that still holds the player finds the record missing on its next save and stops (`Lost`) instead of writing it back. **Owner-run only**, never a remote: open the published Place in Studio with *Game Settings > Security > Enable Studio Access to API Services*, make sure the player is in no server, and run in the command bar:

```lua
require(game.ServerScriptService.Server.Services.DataService.EraseUserCommand)(123456789, "ERASE 123456789")
```

The second argument must repeat the id. At PlaceId 0 the command only touches the fake store.

**PlaceId 0.** `StoreProvider.select(game.PlaceId, getReal, makeFake)` runs before any store is opened. At PlaceId 0 it builds `FakeStore.newService()` and never calls `getReal`, so `GetService("DataStoreService")` does not run. A headless test checks this wiring in the source and that no other module under `src/` names DataStoreService. The fake copies values in and out, rejects what a DataStore rejects (functions, NaN, mixed or sparse tables), and keeps data for the life of the Studio server, so a rejoin finds the saved profile.

**Studio playtest support (PlaceId 0 and Studio only; live servers skip all of it).**
- Startup line, always printed: `[DataService] store=Fake (PlaceId 0) autosave=120s lockTimeout=600s`.
- `ServerScriptService` attribute `DataStoreMode` (`Fake`/`Real`).
- Player attributes: `DataLoadStatus`, `DataLoadDetail` (e.g. `WaitingForLock`, `StoreError`, `Resumed`), `DataPortalLocked`, `DataSaveSeq`, `DataLastSave` (e.g. `Autosave ok seq=3`, `Autosave failed: FakeStore: injected UpdateAsync failure`), `DataSaveFailures`. Each change also prints `[DataService] <name> (<userId>) status=<status> <detail>` or `... save <reason> ok seq=<n>` / `failed: <error>`.
- Switches on `ServerScriptService` (set with `SetAttribute` from the server command bar):
  - `DataFailLoad` (bool): every profile load attempt fails like a store outage.
  - `DataFailSave` (bool): every profile save, release and teleport save fails.
  - `DataAutosaveNow` (bool): set `true` to run one autosave pass now. It resets itself to `false`.
  - `DataSimulateRejoin` (number): set to a player's UserId (`Player1` = `-1`, `Player2` = `-2` in a local server test; your own UserId in Play solo) to release and load that player again without disconnecting. This is how a load failure is tested with a connected player. It resets itself to `0`.

## Consequences

- Server start counts grow by one (`DataService`): 5 in Lobby and World 1, 4 in Arena (ADR 0005 recorded 4 and 3).
- Other services call `DataService.WhenProfileLoaded(player)`, which yields until loaded and returns the live profile table (or `nil` if the player left or the session ended). Setup runs on the first call, as with `NetService`, so start order does not matter. Owning services change the table in place. Only `DataService` decides when it is stored.
- After a server crash the player waits up to `LockTimeout` (10 min) before another server takes over the profile. Their status stays `Loading` with detail `WaitingForLock` meanwhile. This is the price of never letting two servers write the same profile. The value can be tuned in `Config.Data`, but it must stay well above the autosave interval.
- Any later change to the stored format needs a `Schema` migration step and owner escalation (CLAUDE.md §13). Store names and key prefixes in `Config.Data` are part of the format.
- Trade ledger entries are keyed by trade id and are not removed by `EraseUser`. Whether entries that name an erased player must be removed or anonymised is an open question for the trade feature (#49).
- `RemoveAsync` keeps the old versions that Roblox retains for DataStore keys. That is Roblox's documented erasure path, and it is stated here so nobody assumes immediate physical deletion.
- No remote is added, so `NetExample` stays until the first real remote lands (cleanup moves to that issue, ADR 0005).
