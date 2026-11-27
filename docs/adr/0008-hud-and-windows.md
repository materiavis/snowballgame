# 0008: HUD, window stack and input device tracking

**Status:** Accepted with merge of PR #92.

Implements the Prototyp slice of `10.2-hud-menus` (#35, owner decision 2026-11-09, Variante B) from the `InputController`, `HudController` and `MenuController` rows of [ADR 0003](0003-snow-rush-intake.md). Revised by #90 (Vertical Slice scaffold): Lobby HUD, progress bar and zone name, left-edge button registry, pop-up component, prompt wrapper and their Studio switches (section "HUD scaffold (#90)"). The Arena HUD, settings and the other windows are #91.

## Context

Concept 10.2 fixes where the Simulator shows Coins (top left), the ball size (top centre) and the menu buttons (left edge), and says: on a small phone nothing covers the joystick or the ball, every button is at least 44 px, windows fill at most two thirds of a phone screen, and every window closes with its X, its menu key or B. Concept 7.8 puts Upgrades on U, a left-edge button and D-pad right. Concept 6.5 and the owner decision of 2026-11-06 on #35 say a player whose profile cannot be loaded sees a short hint that reflects only the server's load status, and balances show "–" instead of a stale value or 0 while the profile is not loaded. The repository has no package manager, and any third-party code would need an audit (CLAUDE.md §10).

## Decision

**No UI framework.** Plain Instances built in Luau with a few small helpers. Nothing third-party.

**Layout.**

| Path | Kind | Role |
|---|---|---|
| `src/shared/Config/Ui.luau` | pure data | Every number and text: 44 px floor, ⅔ limit, phone threshold, scale, margins, sizes, clear zones, colours (RGB), fonts (Enum.Font names), keybinds (Enum.KeyCode names), action priority, English strings, load-hint map. |
| `src/client/Ui/Layout.luau` | pure | Scale, button size, clear zones, HUD rectangles, window rectangle, overlap check. |
| `src/client/Ui/WindowStack.luau` | pure | Order of open windows: open, close, toggle, closeTop. |
| `src/client/Ui/InputDevice.luau` | pure | UserInputType name to `Touch`, `KeyboardMouse` or `Gamepad`. |
| `src/client/Ui/LoadStatus.luau` | pure | Balance text and hint text for a `DataLoadStatus`. |
| `src/client/Ui/Theme.luau`, `Components.luau` | Roblox | Config values as Color3/Enum.Font; builders for panel, label, button and window. |
| `src/client/Controllers/InputController.luau` | controller | Last-used device, `getDevice()` and `onChanged(fn)`. |
| `src/client/Controllers/MenuController.luau` | controller | The window stack, menu keys and gamepad B. |
| `src/places/simulator/client/SimulatorHudController.luau` | controller | The Simulator HUD and the placeholder Upgrades window. |
| `src/client/Ui/ZoneProgress.luau` (#90) | pure | Progress fraction, bar text and zone name from the published size and zone. |
| `src/client/Ui/ButtonRegistry.luau` (#90) | pure | Registered left-edge buttons in `Config.Ui.LeftButtons` order. |
| `src/client/Ui/PopupQueue.luau` (#90) | pure | Order and timing of the centre pop-ups. |
| `src/shared/PopupText.luau` (#90) | pure | Allowed pop-up keys, number checks and formatting; shared by server and client. |
| `src/shared/Prompts/` (#90) | pure + Roblox | `PromptSpec` resolves a `Config.Ui.Prompts` preset; `Prompts.create` builds the ProximityPrompt. |
| `src/client/Controllers/PopupController.luau` (#90) | controller | Shows pop-ups from client callers and the `Popup` remote in the attached HUD. |
| `src/places/lobby/client/LobbyHudController.luau` (#90) | controller | The Lobby HUD (replaces `LobbySkeletonController`). |
| `src/server/Services/PopupService.luau` (#90) | service | Server path for pop-ups: fires the `Popup` remote. |
| `src/server/Services/HudTestService/` (#90) | service | Studio-only HUD switches (see "Studio switches"). |

`src/client/Ui/` is a folder of plain modules. The client loader only starts `Controllers/` and the mounted Place folders, so nothing in `Ui/` runs by itself. The pure modules take Config.Ui as an argument and are tested under Lune (`tests/client/Ui/`). `SimulatorSkeletonController` is removed because a real module now lives in its folder.

**Pixels and scaling.** All sizes are ScreenGui pixels (points on phones) computed from the HUD ScreenGui's `AbsoluteSize` (`ScreenInsets = CoreUISafeInsets`, so the Roblox top bar and notches are already excluded). Sizes scale with the short side, clamped to `[MinScale, MaxScale]`, and every button is `max(MinTouchTarget, ceil(ButtonBase × scale))`, so no scaling can push a button under 44 px. No `UIScale` is used, which keeps the 44 px check exact. Layout reruns whenever `AbsoluteSize` changes (rotation, window resize).

**Clear zones on touch screens.** Three rectangles, each `max(fraction of the screen, minimum px)`: joystick (bottom left, 40 % × 50 %, at least 200 × 130), jump button (bottom right, 30 % of the short side, at least 110) and the ball (centred, 20 % × 30 %). HUD parts never overlap them: the left-edge buttons sit under Coins and above the joystick zone (wrapping into columns when needed, #90), the progress bar and zone name sit under the ball size and the zone name flattens on short screens rather than reach the ball zone, and the load hint sits in the top row (#90). Non-touch screens only have the ball zone, and only for reporting.

**Windows.** A phone is a touch screen whose short side is under `PhoneMaxShortSide` (500). Every window is at most ⅔ of the screen width and height (so at most 4/9 of the area) on every device. On touch screens a window is docked to the right edge, right of the ball zone and above the jump zone, so the joystick, the ball and jumping stay usable while it is open. If the screen is too narrow for `MinWidth` beside the ball (portrait phones), the window keeps `MinWidth` and may overlap the ball, never the joystick; `Layout.window` reports this as `coversBall`. On other screens the window is centred.

**Window stack.** `MenuController.register({ id, root, setOpen, selection?, toggleKeys?, openKeys? })`, then `open`, `close`, `toggle`, `closeTop`, `isOpen`, `top`. Opening an open window moves it to the top. The X and a window's toggle key close that window; gamepad B closes the top window. Bindings use `ContextActionService:BindActionAtPriority` at `Config.Ui.ActionPriority` (High), so they win over default gameplay binds:
- toggle keys (U for Upgrades) are bound once the window is registered and sink the key,
- open keys (D-pad right) open the window and pass while it is open or while any GUI object is selected, so gamepad navigation keeps working,
- B is bound only while at least one window is open and is unbound when the stack is empty, so B is never taken from gameplay otherwise.

With nothing registered, MenuController binds nothing and shows nothing, so Lobby and Arena are unaffected until #90/#91 register windows.

**Gamepad selection.** When a window opens or comes to the top and the last device is a gamepad, `GuiService.SelectedObject` moves to the window's `selection` (its X). When a window closes, a selection inside it is cleared, then the next top window gets it. Switching to a gamepad while a window is open selects it. HUD buttons are `Selectable`.

**Input device.** `InputController` classifies `UserInputService.LastInputTypeChanged`. Inputs that say nothing about the device (Focus, Gyro …) keep the last one. The first value is guessed from the last input type, then a connected gamepad, then touch, then keyboard. Prompts do not need it: Roblox's default ProximityPrompt style already follows the last device (#90, below).

**Balances and load status from player attributes.** The HUD reads `Coins` (CurrencyService, ADR 0007) and `DataLoadStatus` (DataService, ADR 0006) with `GetAttributeChangedSignal`. Both are written by the server on **every** server, live or Studio. Only the diagnostics next to them and every switch are Studio-only (ADR 0006, 0007). These attributes are server-written; a client-side write to its own player's attributes does not replicate and changes nothing on the server. No remote is added.
- Balances are shown only while `DataLoadStatus == "Loaded"`. Every other status, a missing status, and a missing or non-finite balance show `Text.Missing` ("–"), never the stale attribute value and never 0.
- The hint is driven by `Config.Ui.LoadHints` (status → text key). Only `Failed` shows a hint ("Your progress could not be loaded. Trying again…"); it disappears as soon as DataService sets `Loaded` after a successful retry.
- `Loading` shows "–" without a hint: it is the normal state for the first second of every join and a hint would flash every time. This includes `Loading` with detail `WaitingForLock`, which after a server crash can last up to `LockTimeout`.
- `Lost`, `Teleported` and `Released` show "–" without a hint: the player is being kicked, teleported or has left.

**Ball size (from #34).** The field reads the server-published player attributes `BallSizeMetres` and `BallIsMax` (`Config.Ball.PlayerSizeMetresAttribute` / `PlayerIsMaxAttribute`, ADR 0002). BallService writes them on every server. The value is formatted with `NumberFormat.size`: metres up to 999.9 m, then km. Until a size is published, or if the value is not a valid size, the field shows `Text.BallSizePlaceholder` ("– m"). The pure `Ui/BallSize` module decides the text. The temporary top-centre `SizeLabel` and `MaxLabel` of `BallGrowthController` are removed, so nothing overlaps the HUD. The glow, arrow and sound at MAX stay in `BallGrowthController`. The progress bar and zone name under it came with #90 (below).
- **Interim MAX! (owner decision on PR #92, 2026-11-11).** While `BallIsMax` is `true`, the field's caption reads `Text.BallSizeMax` ("MAX!") in `Colours.Max` instead of "Size". The value stays visible. The final placement and duration (concept 10.2 short centre pop-ups) are an open owner question in a follow-up issue.

**Text.** English source strings in `Config.Ui.Text`. Static labels keep `AutoLocalize` on; value labels (numbers) turn it off and are separate from their captions, so a translated caption never contains a changing value. Text uses `TextScaled` with a `UITextSizeConstraint` so longer translations shrink instead of overflowing. Meaning is never colour-only: the hint and the buttons carry text.

## HUD scaffold (#90)

The shared scaffold the Vertical Slice features build on (owner decisions 2026-11-10 and 2026-11-16 on #90). Windows, prompts and effects of a feature stay in that feature's issue.

**Lobby HUD.** `LobbyHudController` builds `PlayerGui.LobbyHud`: `Coins` and `SnowCoins` panels top left (one under the other) and `LoadHint` top centre. Same rules as the Simulator: `Coins` / `SnowCoins` attributes (ADR 0007) shown only while `DataLoadStatus == "Loaded"`, otherwise "–"; the hint only on `Failed` (`Config.Ui.LoadHints`, `Ui/LoadStatus`). No left-edge buttons yet (Shop, Handel, Einstellungen are #91). The ScreenGui has `ResetOnSpawn = false` and the controller lives in PlayerScripts, so the HUD survives the repeated respawns of the floorless Lobby.

**Progress bar and zone name (Simulator).** Under the ball size field: `SimulatorHud.ZoneProgress` (track, `Fill`, `Value` text "1.2 m / 2 m") and `SimulatorHud.ZoneName`. Inputs are server attributes only: `BallSizeMetres` and the new player attribute **`BallZone`** (`Config.Ball.PlayerZoneAttribute`), which `BallAttributes.publish` writes on every server next to `BallSizeMetres` / `BallIsMax`, with the same value as the ball's `Zone`. The zone maximum is `Formulas.Zones.maxSize(BallZone)`, the shared formula the server uses; the client sends nothing. Fraction = size / maximum, clamped to 0..1. Names come from `Config.Zones.Names` (zones 1–10, Startwerte from the concept appendix, 🟦 proposal for Game Design). A missing or invalid size or zone shows `Text.ProgressPlaceholder` / `Text.ZoneNamePlaceholder` ("–"), never an error; zones above 10 have no name yet and show the placeholder. The bar carries its value as text, so the fill colour is never the only cue. The interim MAX! caption is unchanged (#109).

**Load hint position.** Under the ball size is now the progress bar, so the Simulator hint moved to the top row, right of the ball size against the right margin, one row high. In the Lobby it is top centre.

**Left-edge buttons.** `Config.Ui.LeftButtons` = Upgrades, Pets, ZoneTeleport, Lobby (top to bottom). A button is **hidden until its feature registers it**:

```luau
-- a window (Pets #41, Zonen-Teleport #39): register the window without keys, then the button
MenuController.register({ id = "Pets", root = …, setOpen = …, selection = … })
local unregister = MenuController.registerButton({ id = "Pets", window = "Pets" })
-- an action (Lobby, once TravelController.RequestLobby exists)
MenuController.registerButton({ id = "Lobby", activate = function() … end })
```

`registerButton` binds the button's keys from `Config.Ui.Keybinds[id]` (action names `MenuToggle<id>` / `MenuOpen<id>`) and unbinds them in the returned function, so hidden buttons bind no keys. Keys: Upgrades U / D-pad right, Pets P / D-pad left, ZoneTeleport T / D-pad up, Lobby L and no D-pad (controller players reach it by normal GUI selection). Open keys pass while a GUI object is selected, as before. Upgrades now goes through the same registry (its window registers without keys); behaviour is unchanged. `MenuController.visibleButtons()` and `onButtonsChanged(fn)` drive the HUD; the Simulator HUD creates one `TextButton` per id (`UpgradesButton`, `PetsButton`, `ZoneTeleportButton`, `LobbyButton`), shows the registered ones and lays them out with `Layout.hud(screen, Ui, #visible)`. The layout depends only on the number of visible buttons, so any subset is laid out like the first buttons of the full set. Buttons form one column under Coins; when the column would reach the joystick zone (small landscape phones) they wrap into further columns, narrowed to end left of the ball zone and the top-centre parts, never under 44 px. On a 568 × 262 screen four buttons form one row of 47 × 45 px. Labels shrink with `TextScaled`.

**Pop-ups.** `PopupController` shows a short text in the centre for `Config.Ui.Popup.DurationSeconds` (1.5 s) and hides it; pop-ups that arrive meanwhile wait in order, at most `MaxQueued` (3), the oldest waiting one dropped (`Ui/PopupQueue`). Text is always `Config.Ui.Text[key]` for a key in `Config.Ui.PopupTexts`, with `{1}`, `{2}` replaced by numbers formatted with `NumberFormat.number` (K, M, B …, "+3.4K"); there is no free text (`PopupText`). Two entry points:
- client: `PopupController.show(key, numbers?)`;
- server: `PopupService.show(player, key, numbers?)` / `PopupService.showAll(key, numbers?)` fire the declared remote **`Popup`** (ADR 0005, server → client). Its schema is a string key (1..`Config.Net.Popup.MaxKeyLength`) plus `MaxNumbers` (2) optional numbers within ±`MaxNumberMagnitude`; rate limit `Config.Net.RateLimits.Popup`. There is no server handler, so a client call is dropped as `NoHandler`. PopupService checks key and numbers before firing; the client checks them again and ignores anything invalid.

The pop-up label (`<Hud>.Popup`, ZIndex above the HUD, below windows, not `Active`) lives in the Place HUD's ScreenGui (`PopupController.attach`). `Layout.popup` places it below every HUD part crossing the centre line and just above the ball zone where the screen has room; it narrows to stay clear of the HUD parts beside it and of the joystick and jump zones, and flattens if it would still reach the joystick. On landscape phones there is no room above the ball, so the pop-up covers the top of the ball zone (`coversBall`) for its 1.5 s; it never covers the joystick. Pop-ups with numbers have `AutoLocalize` off (a changing value is no translation source). The Arena attaches no HUD, so pop-ups are dropped there (#91).

**Prompts.** `Prompts.create(preset, parent, { name?, tag? })` (`src/shared/Prompts`) creates a ProximityPrompt with `Style = Default` and keys, hold time, distance, line of sight and texts from `Config.Ui.Prompts[preset]` over `Config.Ui.Prompts.Default` (E, ButtonX, 0 s, 10 studs). Roblox's default prompt UI shows the key of the most recently used device (keyboard key, gamepad button, tap target) and switches when the player changes device, which is concept 3.2; no custom glyphs are built. Features (#37, #38, #39, #41) add presets and create their station prompts with it. The existing upgrade stand prompt (ADR 0010) keeps its own config for now.

### Studio switches (#90)

`HudTestService` binds these only in Studio at `game.PlaceId == 0` and not in the Arena. They are attributes on `ServerScriptService`, which does not replicate, so each one turns into something the client sees.

| Attribute | Type, idle | Effect | Reset |
|---|---|---|---|
| `HudTargetUserId` | number, `0` | Player the switches act on; `0` = every player. | stays |
| `HudTestPopup` | string, `""` | `"<TextKey>[,<n1>[,<n2>]]"`, e.g. `"PopupTest"` or `"PopupTestNumber,3400"` (shows "+3.4K"): PopupService shows that pop-up to the targets through the `Popup` remote. Invalid values warn. | itself to `""` |
| `HudTestPrompt` | bool, `false` | `true` builds `Workspace.HudTestPromptPart` (anchored, no collision) 10 studs in front of and 2 above the first `SpawnLocation` (else the target's character) with the placeholder prompt `HudTestPrompt` (preset `Placeholder`: "Test" / "Placeholder prompt", E / ButtonX). Each trigger prints `[HudTestService] placeholder prompt triggered by <name> (<n>)`, raises `ServerScriptService.HudTestPromptTriggers` and shows the "Prompt used!" pop-up to that player. `false` removes the part. | stays |
| `HudTestButtons` | bool, `false` | Mirrored to the targets' player attribute `HudTestButtons`. While it is `true`, the Simulator HUD registers inert placeholder entries for Pets, ZoneTeleport and Lobby (each prints and shows "Coming soon"); `false` unregisters them. Real registrations are kept. | stays |

The zone, the load hint and the balances use existing switches: `BallSetZone` (ADR 0002), `DataFailLoad` + `DataSimulateRejoin` (ADR 0006), the CurrencyService switches (ADR 0007).

## Consequences

- Client start counts (#90): 5 controllers in Lobby (InputController, MenuController, PopupController, the Social skeleton, LobbyHudController), 10 in World 1 (the three core controllers, the Social skeleton and the six Simulator controllers), 4 in Arena (the core three and the Arena skeleton). Server start counts grow by two (`PopupService`, `HudTestService`) in every Place: 8 in Lobby, 11 in World 1, 7 in Arena.
- Features show their left-edge button with one `registerButton` call; Pets (#41) and Zonen-Teleport (#39) register a window, the Lobby button an action once the Travel feature can request the Lobby. Until then the buttons, and their keys, do not exist for the player.
- Server features show pop-ups through `PopupService.show` with a key they add to `Config.Ui.PopupTexts`; translated texts with numbers need a localization-table approach later.
- New windows (#36 Upgrades content, #90, #91) register with MenuController and use `Layout.window` and `Components.window`; they get the stack, X/key/B closing, the ⅔ limit and the clear zones without new code. #36 fills `UpgradesWindow.Content`.
- The clear zones approximate Roblox's default touch controls and the third-person ball. If Roblox changes its touch layout, or the camera shows the ball elsewhere, only the fractions in `Config.Ui.ClearZones` change. The small-phone playtest verifies them.
- U is sunk in the Simulator whenever the Upgrades window is registered. A later gameplay bind on U would conflict and must pick another key.
- Right-docked windows on touch screens are narrower than half the screen on small phones (about 250 × 190 px on an iPhone SE without the top bar), so window content must scroll or stay compact.
- Whether a modal window may cover the ball is open (see PR); the current layout avoids it in landscape.
