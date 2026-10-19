# UI design

## Figma

File: **Surron Life UI** — https://www.figma.com/design/vITYOoThSbA8PpHN4vE7sR

What's in it now (page *Foundations*):

- **Variables** (collection *Surron Tokens*, mode *Dark*): every colour in `UI/Theme.luau`
  (`color/background`, `color/surface`, `color/accent` = electric green #39FF88, …), spacing
  (`space/xs`…`space/xl`) and corner radii (`radius/small`…`radius/pill`).
- **Text styles**: Display/Hero 44, Display/Title 24, Heading/Label 18, Heading/Body 16,
  Body/Body 16, Caption/Caption 13. Figma has no Gotham (the font the game uses), so the file
  uses **Montserrat**, the closest match.
- **Components**: Button (Primary / Secondary / Ghost / Danger), QuickButton, StatRow, Swatch,
  Toast, and the 17-colour paint palette.

Not built yet: the screen mockups (desktop HUD, main menu, garage, phone layout). The Figma
Starter plan's limit on MCP tool calls ran out partway through. `tools/figma/build_screens.js`
is the script for the next step; it can be run again with the Figma MCP `use_figma` tool (file
key `vITYOoThSbA8PpHN4vE7sR`) once the limit resets or on a paid seat.

## In the game

The game doesn't import from Figma; screens are built in Luau from the same tokens:

| Figma | Luau |
| --- | --- |
| `color/*` variables | `UI/Theme.luau` `Theme.Colors` |
| `space/*`, `radius/*` | `Theme.Spacing`, `Theme.Radius` |
| Text styles | `Theme.Fonts` + `Theme.TextSize` (GothamBlack/GothamBold/GothamMedium) |
| Button, StatRow, Swatch, Toast | `UI/Components.luau` `button`, `statRow`, `swatch`, `HUD.toast` |

If you change a token in Figma, change it in `Theme.luau` too.

## Layout rules

- Dark charcoal surfaces, white text, electric-green accent, 12–18 px rounded corners.
- Touch targets at least 44 px; touch riding buttons scale with the shorter screen side.
- `ScreenInsets = DeviceSafeInsets` keeps everything out of notches and home bars.
- One window at a time; B closes on gamepad; the bike coasts while a window is open.
- On touch screens the speedometer and bike panel move to the top so the thumbs have the
  bottom corners (`HUD.setTouchLayout`).
