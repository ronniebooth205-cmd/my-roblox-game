# Working on SURRON LIFE: WHEELIE CITY

Read README.md first for the layout, then docs/PHYSICS.md before touching the bike.

## Ground rules

- **Server-authoritative.** Cash, XP, purchases, ownership, rewards and saves are decided in
  ServerScriptService. The client predicts (HUD scores) but never grants. Validate every
  remote's argument types and ranges, and rate-limit it.
- **Config, not constants.** Tunables live in ReplicatedStorage/Shared (*Config, BikeDefinitions,
  MapLayout). Changing the saved profile shape needs a SchemaVersion bump and a step in
  PlayerDataService.migrate.
- **Physics.** Only the Chassis has mass. Don't add massive parts to bikes or make the rider
  massive. Visuals (Motor6D.Transform, rider joint offsets) never feed back into physics.
  After changing wheelie/bike numbers, mirror them in tools/wheelie_sim.py and run it.
- **No invented asset IDs.** Sounds go in AudioConfig (empty until real licensed IDs are added).
  Names and brands in the world stay fictional.
- **UI** is built from UI/Theme + UI/Components (dark surfaces, white text, electric green
  accent). Every screen must work with touch (44px+ targets, safe-area insets, portrait and
  landscape), gamepad (selectable buttons, B closes) and keyboard.
- **Performance.** Per-frame loops skip far-away bikes and switch effects off on Low graphics.

## You can't run the game here

There's no Roblox Studio in a cloud session. Keep changes small and easy to review, say what
still needs testing in Studio (docs/TESTING.md), and run `scripts/lint.sh` after every change
(selene + luau-lsp with the Roblox API; it fails on syntax errors, unknown globals and selene
errors; luau-lsp strict-mode type warnings are reported but don't fail).

## Style

- Luau, tabs, `local` everything, services fetched at the top of each script.
- Keep the header comment on each script (`-- Service > Folder > Name (ClassName)` plus a short
  description) and update it if behaviour changes.
- Comments explain *why*, in plain English.
