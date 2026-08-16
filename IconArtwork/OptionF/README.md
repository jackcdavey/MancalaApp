# Option F: Terracotta Macro

One pit, three gems, cropped close enough that the rest of the board is out of
frame. Where the other directions describe the game, this one describes the
*objects* — unglazed clay and polished glass, the two materials the app spends
most of its rendering budget on.

Import these layers into Icon Composer in numeric order:
1. `01-clay.svg`
2. `02-pit.svg`
3. `03-stones.svg`
4. `04-light.svg`

Recommended Icon Composer settings:
- Liquid Glass on the stones group, Individual mode, specular **high**. This
  direction is a material study; the gems have to look wet.
- Leave the clay opaque and matte. `BoardMaterialStyle.terracotta` is described
  in the app as "matte and porous" and glassing it contradicts that.
- The speculars in `03-stones.svg` are deliberately small and hard. If Icon
  Composer's own specular is turned up, shrink or delete the baked highlight
  circles or the gems grow a second, softer highlight and read as balloons.
