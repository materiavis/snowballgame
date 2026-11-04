# 0005: Net layer for remotes

**Status:** Proposed in the PR for #24.

Implements the "Networking" principle of [ADR 0003](0003-snow-rush-intake.md) (`x-net-remotes`) and records what it left to the implementation (API shape and schema format).

## Context

CLAUDE.md §6 requires every remote handler to validate type, range and rate, and concept 6.5 says clients only send intents that the server checks. Without one place that owns remotes, each service would create its own instances and write its own (or no) checks. ADR 0003 decided on one `Net` module in `src/shared/Net`, remotes under `ReplicatedStorage.Remotes`, dropped and counted failures, and no errors to the client.

## Decision

- **One declaration list.** `src/shared/Net/Remotes.luau` declares every remote: `kind` (`"Event"` or `"Function"`), `args` (a list of `Net.Schema` validators, `{}` for none), `rateLimit` (a `Config.Net.RateLimits` entry) and an optional `authorize` hook. `Net/Registry` checks the list when `Net` is required. A missing schema or rate limit, an unknown field (e.g. `schema =`), a non-validator argument or a required argument after an optional one is an error, so the Place does not start.
- **Validators demand their bounds.** `Schema.number` needs `min` and `max`, `string`/`array` need `maxLength`, `vector3` needs `maxMagnitude`. Numbers reject NaN and ±inf, strings reject invalid UTF-8, arrays reject holes and non-index keys, structs reject unknown keys. There is no "any" validator.
- **Check order:** rate, argument count, argument types/ranges, `authorize`, then the handler. Rate comes first, so malformed floods also spend budget and are capped cheaply.
- **Ownership and game-state checks are a hook, not built in.** `authorize(player, ...args)` returns `true` or `false, reason`. Distance, line of sight, cooldowns and ownership belong to the feature that owns that state; `Net` stays game-agnostic so it can move into the Materiavis toolkit.
- **Per-player token bucket** (`Burst`, `RefillPerSecond`) per remote. It allows a short burst and then a steady rate. Buckets are dropped on `PlayerRemoving`.
- **Nothing throws.** Validator, `authorize` and handler errors are caught. A dropped call returns no values (an `InvokeServer` caller gets `nil`). Handler errors are `warn`ed on the server only.
- **Counted, with a hook for analytics.** `Net/Stats` counts accepted, rejected (by reason: `Rate`, `Arity`, `Args`, `Auth`, `NoHandler`) and handler-error calls per remote. `NetService.subscribe` gets every event, so analytics (#43) attaches without changing the guard.
- **Pure core, thin service.** `Schema`, `Registry`, `RateLimiter`, `Stats` and `Guard` have no requires and no service access, so `lune run tests` loads them. The clock is injected (`os.clock` live, a fake clock in tests). `Remotes.luau` is a function of `(Schema, Config.Net)` for the same reason. `NetService` creates the instances and wires the pieces.
- **"Net initialises first" without changing the loaders.** `NetService` sets up on the first `Start()` or `handle()` call. The loaders start services in no fixed order, so a dependent service that calls `NetService.handle` first still finds the remotes. Each remote's guard is connected when the remote is created, before any handler exists, so there is never an unguarded window. Calls before a handler is registered are dropped as `NoHandler`.
- **Studio-only counters on the instances.** In Studio, every remote carries `NetAccepted`, `NetRejected`, `NetRejected<Reason>`, `NetHandlerErrors` and `NetLastRejection` attributes, so a playtest can read them from server or client. Live servers skip this, because clients do not need to learn why their calls are dropped.
- **One example remote, `NetExample`,** handled by `NetExampleService`. Both are marked as examples and are removed when the first real remote lands.

## Consequences

- Adding a remote means one entry in `Net/Remotes` and one in `Config.Net.RateLimits`, then `NetService.handle(name, fn)` on the server and `Net.waitForRemote(name)` on the client. Nothing else may create a remote or connect `OnServerEvent` / `OnServerInvoke`.
- `ReplicatedStorage.Remotes` must not be mapped by any Rojo project; `NetService` refuses to start if it already exists.
- Server start counts grow by two (`NetService`, `NetExampleService`): 4 in Lobby and World 1, 3 in Arena (ADR 0004 recorded 2 and 1 before this change).
- Server-to-client traffic (`FireClient`) is not validated by `Net`; the server trusts its own values. Whether server-only events also need declared schemas is open.
- Not save-relevant: `Net` reads and writes no player data.
