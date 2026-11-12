# 0008: HUD, window stack and input device tracking

**Status:** Accepted with merge of PR #92.

Implements the Prototyp slice of `10.2-hud-menus` (#35, owner decision 2026-11-09, Variante B) from the `InputController`, `HudController` and `MenuController` rows of [ADR 0003](0003-snow-rush-intake.md). The Lobby HUD and last-device prompts are #90; the Arena HUD, settings and the other windows are #91.

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

`src/client/Ui/` is a folder of plain modules. The client loader only starts `Controllers/` and the mounted Place folders, so nothing in `Ui/` runs by itself. The pure modules take Config.Ui as an argument and are tested under Lune (`tests/client/Ui/`). `SimulatorSkeletonController` is removed because a real module now lives in its folder.

**Pixels and scaling.** All sizes are ScreenGui pixels (points on phones) computed from the HUD ScreenGui's `AbsoluteSize` (`ScreenInsets = CoreUISafeInsets`, so the Roblox top bar and notches are already excluded). Sizes scale with the short side, clamped to `[MinScale, MaxScale]`, and every button is `max(MinTouchTarget, ceil(ButtonBase × scale))`, so no scaling can push a button under 44 px. No `UIScale` is used, which keeps the 44 px check exact. Layout reruns whenever `AbsoluteSize` changes (rotation, window resize).

**Clear zones on touch screens.** Three rectangles, each `max(fraction of the screen, minimum px)`: joystick (bottom left, 40 % × 50 %, at least 200 × 130), jump button (bottom right, 30 % of the short side, at least 110) and the ball (centred, 20 % × 30 %). HUD parts never overlap them: the left-edge buttons sit under Coins and above the joystick zone, the load hint sits under the ball size and flattens on short screens rather than reach the ball zone. Non-touch screens only have the ball zone, and only for reporting.

**Windows.** A phone is a touch screen whose short side is under `PhoneMaxShortSide` (500). Every window is at most ⅔ of the screen width and height (so at most 4/9 of the area) on every device. On touch screens a window is docked to the right edge, right of the ball zone and above the jump zone, so the joystick, the ball and jumping stay usable while it is open. If the screen is too narrow for `MinWidth` beside the ball (portrait phones), the window keeps `MinWidth` and may overlap the ball, never the joystick; `Layout.window` reports this as `coversBall`. On other screens the window is centred.

**Window stack.** `MenuController.register({ id, root, setOpen, selection?, toggleKeys?, openKeys? })`, then `open`, `close`, `toggle`, `closeTop`, `isOpen`, `top`. Opening an open window moves it to the top. The X and a window's toggle key close that window; gamepad B closes the top window. Bindings use `ContextActionService:BindActionAtPriority` at `Config.Ui.ActionPriority` (High), so they win over default gameplay binds:
- toggle keys (U for Upgrades) are bound once the window is registered and sink the key,
- open keys (D-pad right) open the window and pass while it is open or while any GUI object is selected, so gamepad navigation keeps working,
- B is bound only while at least one window is open and is unbound when the stack is empty, so B is never taken from gameplay otherwise.

With nothing registered, MenuController binds nothing and shows nothing, so Lobby and Arena are unaffected until #90/#91 register windows.

**Gamepad selection.** When a window opens or comes to the top and the last device is a gamepad, `GuiService.SelectedObject` moves to the window's `selection` (its X). When a window closes, a selection inside it is cleared, then the next top window gets it. Switching to a gamepad while a window is open selects it. HUD buttons are `Selectable`.

**Input device.** `InputController` classifies `UserInputService.LastInputTypeChanged`. Inputs that say nothing about the device (Focus, Gyro …) keep the last one. The first value is guessed from the last input type, then a connected gamepad, then touch, then keyboard. Prompts that show the key for this device are #90.

**Balances and load status from player attributes.** The HUD reads `Coins` (CurrencyService, ADR 0007) and `DataLoadStatus` (DataService, ADR 0006) with `GetAttributeChangedSignal`. Both are written by the server on **every** server, live or Studio. Only the diagnostics next to them and every switch are Studio-only (ADR 0006, 0007). These attributes are server-written; a client-side write to its own player's attributes does not replicate and changes nothing on the server. No remote is added.
- Balances are shown only while `DataLoadStatus == "Loaded"`. Every other status, a missing status, and a missing or non-finite balance show `Text.Missing` ("–"), never the stale attribute value and never 0.
- The hint is driven by `Config.Ui.LoadHints` (status → text key). Only `Failed` shows a hint ("Your progress could not be loaded. Trying again…"); it disappears as soon as DataService sets `Loaded` after a successful retry.
- `Loading` shows "–" without a hint: it is the normal state for the first second of every join and a hint would flash every time. This includes `Loading` with detail `WaitingForLock`, which after a server crash can last up to `LockTimeout`.
- `Lost`, `Teleported` and `Released` show "–" without a hint: the player is being kicked, teleported or has left.

**Ball size (from #34).** The field reads the server-published player attributes `BallSizeMetres` and `BallIsMax` (`Config.Ball.PlayerSizeMetresAttribute` / `PlayerIsMaxAttribute`, ADR 0002). BallService writes them on every server. The value is formatted with `NumberFormat.size`: metres up to 999.9 m, then km. Until a size is published, or if the value is not a valid size, the field shows `Text.BallSizePlaceholder` ("– m"). The pure `Ui/BallSize` module decides the text. The temporary top-centre `SizeLabel` and `MaxLabel` of `BallGrowthController` are removed, so nothing overlaps the HUD. The glow, arrow and sound at MAX stay in `BallGrowthController`. No progress bar and no zone name (#90).
- **Interim MAX! (owner decision on PR #92, 2026-11-11).** While `BallIsMax` is `true`, the field's caption reads `Text.BallSizeMax` ("MAX!") in `Colours.Max` instead of "Size". The value stays visible. The final placement and duration (concept 10.2 short centre pop-ups) are an open owner question in a follow-up issue.

**Text.** English source strings in `Config.Ui.Text`. Static labels keep `AutoLocalize` on; value labels (numbers) turn it off and are separate from their captions, so a translated caption never contains a changing value. Text uses `TextScaled` with a `UITextSizeConstraint` so longer translations shrink instead of overflowing. Meaning is never colour-only: the hint and the buttons carry text.

## Consequences

- Client start counts grow: 4 controllers in Lobby and World 1 (InputController, MenuController, the Social skeleton and the Place controller), 3 in Arena.
- New windows (#36 Upgrades content, #90, #91) register with MenuController and use `Layout.window` and `Components.window`; they get the stack, X/key/B closing, the ⅔ limit and the clear zones without new code. #36 fills `UpgradesWindow.Content`.
- The clear zones approximate Roblox's default touch controls and the third-person ball. If Roblox changes its touch layout, or the camera shows the ball elsewhere, only the fractions in `Config.Ui.ClearZones` change. The small-phone playtest verifies them.
- U is sunk in the Simulator whenever the Upgrades window is registered. A later gameplay bind on U would conflict and must pick another key.
- Right-docked windows on touch screens are narrower than half the screen on small phones (about 250 × 190 px on an iPhone SE without the top bar), so window content must scroll or stay compact.
- Whether a modal window may cover the ball is open (see PR); the current layout avoids it in landscape.
