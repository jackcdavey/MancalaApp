# Option B: Parchment & Ink

The app's own chrome as an icon. Same warm page the board sits on in the
Immersive theme (`BoardBackgroundStyle.parchment`), same ink-brown rules, same
`StoneSetStyle.classic` gems — pits pressed straight into the page, exactly the
idea behind the Flat theme.

Three pits a side rather than the real six: at icon sizes the true count turns
the wells into a dotted line. Option E is the direction where the count matters,
and it carries all twelve.

Import these layers into Icon Composer in numeric order:
1. `01-page.svg`
2. `02-board.svg`
3. `03-stones.svg`
4. `04-sheen.svg`

Recommended Icon Composer settings:
- Background stays opaque cream; no gradient of its own beyond the layer.
- Liquid Glass on the stones group only, Individual mode — the wells are carved
  page, not glass, and glassing them flattens the concavity.
- Specular low. The page is paper; a mirror highlight fights it.
- Dark mode: swap `01-page.svg` for the app's dark page tones
  (`#1A1815` → `#282521`) and lift the well gradient's light stop.
