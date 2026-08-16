# Option G: The Circuit

The board drawn as the loop it actually is. Twelve pits and two stores laid
around a closed track, with the colour warming along your row toward your store
and cooling back down through your opponent's — so the icon states the rule
(stones travel one way, into your store) rather than depicting a position.

Import these layers into Icon Composer in numeric order:
1. `01-obsidian.svg`
2. `02-track.svg`
3. `03-circuit.svg`
4. `04-light.svg`

Recommended Icon Composer settings:
- Liquid Glass on the circuit group, **Individual** mode — each well is its own
  disc, and Combined mode fuses the whole ring into one lozenge.
- Specular low. The hue ramp is carrying the idea; highlights only muddy it.
- Keep the track layer beneath the wells and faint. It should be findable, not
  read as a drawn ring.
- The pits sit exactly on the track's centreline (a stadium, `rx="164"` on a
  784×328 rect). Moving one without moving the other breaks the alignment.
