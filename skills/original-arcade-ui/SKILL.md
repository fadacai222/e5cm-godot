---
name: original-arcade-ui
description: Rebuilds E5CM Godot menus and HUDs in the original arcade visual language. Use for ESC menus, song selection overlays, player cards, search, filters, loading states, profile panels, confirmation dialogs, and any new system UI.
---

# E5CM Original Arcade UI

## Goal

Make every system interface read as one original E5CM arcade cabinet UI: deep navy translucent surfaces, cyan primary structure light, magenta secondary positioning light, and gold reserved for selected states, VIP, levels, ranks, and key numbers.

## Required workflow

1. Inspect the target interaction and preserve its signals, node paths, input boundaries, keyboard controls, and persisted state.
2. Reuse `E5HudFrame`, `E5OriginalTheme`, and `UiKit` before creating any page-specific style.
3. Keep the 1920×1080 safe area and verify long Chinese nicknames, empty lists, 1P/2P state, repeated open/close, and disabled controls.
4. Add or update a structural contract test. A visual change without a regression test is incomplete.
5. Run Godot script scan, affected UI tests, and `git diff --check`.

## Visual tokens

- Void: `#030919`
- Main panel: `#071A36`
- Deep data surface: `#031126`
- Cyan structure: `#29E9FF`
- Cyan text: `#8EEBFF`
- Magenta locator: `#FF3CCF`
- Gold state: `#FFD84A`
- Main text: `#F4FBFF`
- Muted text: `#88A8C7`
- Danger: `#FF5068`

## Shape rules

- Large panels use 12–24px cut corners, 2px main borders, 1px inner borders, and controlled scanlines.
- Normal controls use 0–2px corner radius. Do not reintroduce 12–24px rounded web cards.
- A major panel must contain at least two of: cut corners, inner frame, scanlines, corner marks, slanted locator line, or side ticks.
- The root composition uses cyan for the main structural edge and magenta for secondary alignment. Gold must remain scarce.
- Avatar content keeps original color. Parent modulation must not darken it.

## Typography

- Main Chinese title: 30–42px, white/cyan-white, optional 3–5px dark navy outline.
- English/status subtitle: 13–18px, uppercase where appropriate.
- Setting label: 19–23px; helper text: 13–16px; value: 20–25px.
- Player nickname: up to 22px with ellipsis. It must never push the avatar outside the HUD.
- Numeric fields retain fixed widths so option changes do not shift the layout.

## Interaction states

- Default: deep navy fill with a low-brightness cyan edge.
- Hover: brighter edge/text and at most `1.015` scale; no layout movement.
- Pressed: slightly darker and at most `0.985` scale.
- Selected: gold primary edge plus restrained cyan inner light.
- Danger: red edge on a dark surface, never a full solid-red card.
- Disabled: 45% opacity while preserving the structure outline.
- Keyboard focus must remain visibly distinct from hover.

## Motion

- Open: 120–220ms, `0.96 → 1.0` scale, 12–24px short offset, and fade-in.
- Animate only position, scale, and modulation. Do not rebuild nodes per frame.
- Repeated fast open/close must return to the canonical resting position; never accumulate drift.
- Closing an overlay must consume the active input so it cannot click through to the song grid.

## Component contracts

### Player HUD

- Horizontal layout with avatar on the right.
- Show player tag, nickname, highest mode level, rank, and five decorative status hearts.
- Status hearts are decorative presentation, not fake consumable life data.
- Keep avatar `modulate` and `self_modulate` white and use the shared mask shader.

### Search

- Input occupies at least 70% of the panel width.
- Language categories use shared arcade buttons; selected category uses gold.
- Progress uses a deep track, cyan fill, and magenta structural accent with explicit percent text.
- Confirm, reset, and back have distinct hierarchy.

### Play style / star filter

- Separate play-style and difficulty zones with their own labels and locator lines.
- Star buttons stay compact; selected uses a gold edge, not a large yellow block.
- Current filter summary remains in a fixed title area.

### ESC menus

- Gameplay ESC and song-select ESC share one root frame, navigation skin, title hierarchy, buttons, inputs, and progress bars.
- Use the original `设置背景图.png` or `设置背景图2p.png` as a subtle structural texture, not as an opaque screenshot pasted over functional controls.
- Profile, bindings, settings rows, previews, resume/restart/quit, and desktop exit all use the same system.
- Preserve `ModernMenu/ContentPanel/ContentBody` and other established external node paths.

## Forbidden patterns

- Generic purple/blue 45-degree AI gradient cards.
- Large rounded glass panels and stacked black shadows.
- Godot default Button, LineEdit, or ProgressBar skin in a production menu.
- Different arbitrary colors for every control.
- Plain text dialogs with no structural frame.
- Full-page animation or slow web-style easing.
- Decorative status that pretends to be real player data.
