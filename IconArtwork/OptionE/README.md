# Option E: Malachite & Brass

The board reduced to a mark: two rows of pits between two stores, cut in brass
over banded malachite. Both are finishes the app already ships
(`BoardMaterialStyle.malachite`, `.brushedBrass`). No stones, no rendering, no
lighting to hold up — it is a logo, and it survives any size. Six pits a side
and two stores: the real board, since a mark that miscounts is making a claim
about the game that isn't true.

Import these layers into Icon Composer in numeric order:
1. `01-malachite.svg`
2. `02-mark.svg`
3. `03-light.svg`

Recommended Icon Composer settings:
- Liquid Glass on the mark group, **Combined** mode — the mark is one engraved
  plate, and Individual mode makes ten separate beads of it.
- Specular low to moderate; brass reads as brass through its gradient, not
  through a highlight.
- The engraved shadow inside `02-mark.svg` is baked. If Icon Composer's own
  shadow is enabled, delete that offset group or the mark doubles.
