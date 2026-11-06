# Headless tests

Unit tests for pure Luau modules, run with [Lune](https://github.com/lune-org/lune)
(pinned in `rokit.toml`) outside Roblox, locally and in CI.

```sh
lune run tests            # all tests, from the repository root
lune run tests Trade      # only spec files whose path contains "Trade"
stylua --check src tests
selene --config tests/selene.toml tests
```

The runner exits non-zero if any test fails, a spec cannot load, or no test runs.

## Layout

| Path | What |
|---|---|
| `tests/init.luau` | Runner. Finds every `*.spec.luau` under `tests/`. |
| `tests/TestKit.luau` | `suite`, `equal`, `near`, `isTrue`, `throws`. |
| `tests/helpers/SeededRandom.luau` | Deterministic generator (Roblox `Random` does not exist under Lune). |
| `tests/helpers/Distribution.luau` | Chance-table check in percentage points (concept 4.4). |
| `tests/helpers/FakeClock.luau` | Hand-driven clock for code that takes a `() -> number` clock (e.g. `Net.RateLimiter`). |
| `tests/examples/` | **Examples only.** Fixtures and specs that show the formula, RNG and trade-state-machine patterns. They are not game code and their numbers are not design values. |
| `tests/helpers/Economy.luau` | Binds the pure Formulas, NumberFormat, Rarity and Rng children to the real `Config/*`, like their Roblox `init.luau` files (ADR 0007). |
| `tests/shared/` | Specs for real modules in `src/shared/`: `Formulas/` (concept 7.6, 7.8, 7.9, 8.3, 8.4 tables), `Rng/` (10,000 seeded rolls per table, ±1 pp), `NumberFormat`, `Rarity`, `ConfigEconomy`. |
| `tests/server/CurrencyService/` | CurrencyService specs (ADR 0007): balance rules, save edge cases against DataService's `Harness` and fake store, and a source scan that no other module writes a balance. |
| `tests/server/DataService/` | DataService specs (ADR 0006): save rules, session lock between simulated servers, erase, store selection. `Harness.luau` builds servers that share one `FakeStore`, with a `FakeClock` and injected JobIds. |

Put a spec for `src/<area>/Foo.luau` in `tests/<area>/Foo.spec.luau`.

## Writing a spec

```luau
--!strict
local T = require("../TestKit")
local Places = require("../../src/shared/Config/Places") -- relative to this spec file

return T.suite("Places", function(test)
	test("World 1 is listed", function()
		T.isTrue(Places.Worlds[1] ~= nil)
	end)
end)
```

Paths in `require` are relative to the spec file. A folder with an `init.luau`
is required by its folder name, e.g. `../../src/shared/Config`.

## What can be tested here

Only modules that are pure at require time load under Lune. A module that calls
`game:GetService`, reads Instances or uses Roblox globals such as `Random` when it is
required fails to load. `src/shared/PlaceInfo.luau` is one: it reads Workspace
attributes as soon as it loads. To keep logic testable:

- put formulas, chance tables, state machines and validation in pure modules with no
  service access,
- pass randomness in as a roll or generator argument, so tests use `SeededRandom` and
  live code passes `Random.new()`,
- pass storage in as an interface, so DataService locking can be tested against an
  in-memory fake store,
- keep the Roblox-facing service a thin layer that wires these pieces together.

Seed every random test. A fixed seed makes CI give the same result on every run.
