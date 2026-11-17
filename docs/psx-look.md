# PSX Look

UMBILICAL ships with the **PSX Look** presentation pack by heyheythere
(`addons/psx_look/`, licence in `addons/psx_look/LICENSE.txt`). It is a live
look, not a separate build: every part can be switched from inside the game,
and the master switch puts the authored look back exactly.

Open it with **F5**, from the title screen's **PSX LOOK** button, or from the
pause screen. The panel is ordinary HUD UI outside the low-resolution world, so
its text and controls stay sharp while the game behind it is 240-line and
dithered.

## What it does

The world is drawn into a `SubViewport` at PS1 resolution and scaled up in
whole, square pixels. The screen shader adds 15-bit colour and an ordered
dither; scanlines are kept off. The materials are converted from the project's
`StandardMaterial3D` palette to PSX shaders that add:

- vertices snapped to the screen's pixel grid;
- affine rather than perspective-correct texture mapping;
- nearest (or optional three-point) texel filtering;
- per-vertex depth fog and an optional draw distance;
- optional 4/5/8-bit texture colour depth, texture shrink and palette
  quantisation;
- billboards, flipbook frames and wave motion for sprites, cloth and water.

UMBILICAL deliberately runs those material shaders with **per-pixel lighting**
instead of the stock pack's `vertex_lighting`. The CSG walls are single large
faces, so vertex lighting made the drone flashlight and authored practicals
read as flat fake pools. The PS1 look still comes from the screen resolution,
dither, vertex snap, affine mapping, nearest filtering and fog; the light falloff
is just evaluated per pixel, so the flashlight is a real, narrow beam.

The pack also includes six material kinds — **lit, unlit, cutout, transparent,
chrome, glow** — used by the showcase lab and available to future props through
`PSX.make()`. The game's existing graybox is all lit/unlit opaque geometry, so
the lab is the reference for the other four.

## Defaults

| Setting | Default |
|---|---|
| Master | **On** |
| Preset | `ps1` (no fog) |
| Resolution | 240 lines |
| Dither / colour bits | On / 5 |
| Scanlines | off (not exposed) |
| Vertex snap | 1 px |
| Affine | 1.0 |
| Filter | nearest |
| Vertex colours | on |
| Texture colour depth | 8 bit (off) |
| Texture size / palette | off |
| Fog | off |
| Draw distance | off (24 m when switched on) |
| Geometry density | 2 m |
| Conversion | on |

`ps1` is deliberately the only stock preset with no fog. The game's authored
`assets/environment.tres` fog and the Cold Hold darkness are left alone until a
preset with fog is chosen.

## Panel

The panel is grouped by feature. Every control is live; there is no Apply.

- **Screen:** resolution (160/192/240/480/native), ordered dither, 15-bit
  colour, saturation, tint.
- **Geometry:** vertex snap (toggle + strength), affine (toggle + strength),
  three-point filter, vertex colours, geometry density (off / 2 m / 1 m /
  0.5 m).
- **Textures:** colour depth (4/5/8 bit), PS1 texture size (off/256/128/64/32),
  PS1 palette (off/256/16).
- **Depth:** PS1 fog, fog begin/end/colour, draw distance (toggle + metres).
- **Animation & materials:** sprites/billboards, flipbook animation, wave
  motion, glow, cutout, transparent, chrome.
- **Foot:** reset to the recommended defaults, and save the current settings
  as a named custom preset.

The preset menu lists the pack's thirteen presets plus any saved custom ones:

`ps1`, `ps1_480`, `subtle`, `crunchy`, `64_bit`, `handheld`, `crt`, `horror`,
`fog_town`, `night`, `flashback`, `fog_wall`, `dark_fog`.

Preset changes are presentation-only; they never touch gameplay, AI, physics or
the map.

## Master off is lossless

`PSXLook` keeps a record of every source material, the authored Environment
values and every density bake. Turning the master off:

1. puts every original material override or surface material back;
2. removes every densified replacement mesh and restores the CSG surface,
   shadow setting and visibility;
3. detaches the screen shader, so the 3D is drawn at full resolution in its
   own colours;
4. restores the authored ambient, fog and exposure.

Turning it back on rebuilds the same look. The same path is used by the **F4
debug vision** developer toggle: F4 suspends the look for a clean colour feed
and raised light, then restores the player's exact settings when pressed again.

## Where things live

| Path | Role |
|---|---|
| `addons/psx_look/` | Vendored pack: screen, presets, materials, shaders, demo art. |
| `src/psx/psx_look.gd` | Autoload `PSXLook`: the one owner of settings, conversion, environment, presets and persistence. |
| `src/psx/psx_convert.gd` | CSG- and mesh-aware material conversion plus lossless restore. |
| `src/psx/psx_density.gd` | Optional CSG bake/subdivide for per-vertex effects. |
| `src/psx/psx_settings.gd` | `ConfigFile` round-trip at `user://psx_look.cfg`. |
| `src/ui/psx_panel.gd` | Crisp in-game options panel. |
| `src/dev/psx_lab.gd` | Standalone material/animation showcase. |
| `scenes/main.tscn` | `WorldLayer/PSXScreen/Viewport/World` hierarchy. |

`scenes/main.tscn` keeps the HUD, map overlay, scanner and still-photo
`SubViewport` outside the PSX `SubViewport`. Every gameplay `Node3D` must be
added with `main._add_world()` (or parented under `PSXLook.world`), not directly
to `Main`, or it lands in the empty root World3D.

The table map's paper quad is tagged `psx_exclude`: it carries a live
`ViewportTexture` and must keep its authored material. The still photo uses
`PSXLook.world_3d()` so prints show the converted materials and lighting, but
not the PSX screen shader.

## CSG conversion and density

Almost all level geometry is `CSGShape3D`, which the pack's own `PSX.convert()`
does not walk. `PSXConvert` walks both `CSGShape3D` and `MeshInstance3D`, shares
one PSX `ShaderMaterial` per source material, and records the original override
or surface material for a lossless restore. Repeated sweeps skip nodes already
converted, so dynamic spawns and the periodic dirty sweep are idempotent.

The palette is world-triplanar. The converter carries `uv1_triplanar`,
`uv1_world_triplanar`, scale and offset into the PSX material, which is why
large CSG floors do not stretch a single noise tile across the whole face.

Density is optional and off is lossless. At 2 m (default) each long CSG face is
baked, subdivided toward 2 m edges (bounded per node and by a total triangle
budget), converted, and put in place of the hidden CSG surface. The original
CSG keeps its collision; only its visual surface is replaced. Restoring removes
the bake and restores the CSG. The bake happens once at load/rebuild, not per
frame.

## Persistence

Settings save to `user://psx_look.cfg`. **Reset to preset** returns to the
recommended defaults. **Save custom** writes a `PSXPreset` `.tres` to
`user://psx_presets/` and adds it to the preset menu.

The dev lab sets `PSXLook.persistence = false`; experimenting there never
overwrites the game's saved look.

## Showcase lab

```sh
godot --path . res://scenes/dev/psx_lab.tscn
```

The lab is the pack's courtyard demo (stone, leaves, banners, pool, gem,
torches, grass) driven by UMBILICAL's own manager and panel. It exercises all
six material kinds, a flipbook flame, upright billboards, waved banners, pool
and foliage, and every category switch. It prints a material/count report on
start, including `PSX LAB READY`; a missing kind warns.

Controls: WASD/arrows walk, drag to look, **F5** toggles the panel, **Esc**
quits.

## Tests

`tests/psx_look.tscn` covers the viewport move, mouse forwarding into the PSX
viewport, CSG and actor conversion, lossless master restore, density stability,
all thirteen presets, every live toggle, runtime spawns, the still-photo feed's
shared world and current camera, the table-map exclusion, F4 suspension,
settings round-trip and the panel. It is part of `tools/run_tests.sh`.

Existing suites that instantiate `main.tscn` call
`PSXLook.reset_to_defaults(false)` and query the PSX viewport's active camera.

## Troubleshooting

- **The game looks flat/full-res.** Check the master switch and that
  `PSXLook.master` is on. If the screen shader is detached, the world is drawn
  natively.
- **3D is missing or in the wrong world.** The node was added to `Main` instead
  of `PSXLook.world`. Use `main._add_world()`.
- **Mouse look is dead.** `PSXScreen` is a `SubViewportContainer`; it forwards
  mouse motion to the viewport through `gui_input`, so it must not use
  `MOUSE_FILTER_IGNORE`. The class sets `MOUSE_FILTER_PASS` itself. A full-screen
  parent `Control` with `MOUSE_FILTER_STOP` between the HUD and the screen (for
  example a title veil that never hides) will also swallow the motion.
- **The map table is blank.** `level.map_surface` was converted or lost its
  `psx_exclude` meta; restore the `ViewportTexture` material.
- **Photos are blank, flat grey or white.** The still-photo `SubViewport` must
  share the PSX viewport's effective `World3D`. A viewport with
  `own_world_3d = true` has a null `world_3d` property, so use
  `PSXLook.world_3d()` (which calls `find_world_3d()`); assigning
  `psx_screen.viewport.world_3d` leaves the photo camera in an empty world.
- **Materials look stretched.** The source material lost its triplanar flag, or
  the vendored shader's triplanar block was removed.
- **Everything is slow.** Lower or turn off geometry density first, then draw
  distance and texture options. Conversion itself is load-time only.
- **A preset adds fog to the whole bay.** That preset authors fog. Pick `ps1`
  (no fog) or turn PS1 fog off.
