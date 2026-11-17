# PSX Look

PS1-style 3D for Godot 4.3+ (Forward+, Mobile, Compatibility).

## Use

```gdscript
var psx := PSXScreen.new()          # the low-res, 15-bit, dithered picture
add_child(psx)
psx.viewport.add_child(level)       # your 3D scene goes in its SubViewport
PSX.convert(level)                  # StandardMaterial3Ds become PSX materials
```

In the editor: add a PSXScreen, give it a SubViewport child, and put your 3D scene under that.
Keep UI outside the PSXScreen to keep it sharp.

To start with the look off, as a game with a PS1 option might: set the PSXScreen's `look` off and
leave the level's materials as they are. Then one call turns it all on:

```gdscript
PSX.turn_on(psx, level, world_env.environment, &"horror")   # the preset is optional, PS1 by default
```

The addon needs nothing outside this folder; `demo/` is its demo alone, and can go.

## PSXScreen

- `lines`: the picture's height at least (240 is the PS1's usual, 480 its high mode). It is the
  screen divided by a whole number, so 1080p at 240 lines draws 270.
- `dither`: the PS1's 4x4 ordered dither.
- `color_bits`: bits per channel, 5 for the PS1's 15-bit colour, 8 for none.
- `saturation` (0 grey, 1 as drawn) and `tint`, applied before the colour reduction.
- `scanlines`: how dark a CRT's gaps between the picture's lines are, 0 for none. They show where
  a line is two screen pixels tall or more.

## Presets

```gdscript
PSXPreset.named(&"horror").apply(psx, level, world_env.environment)
```

sets the screen, the PSX materials already under `level` (their fog and draw distance among them)
and the Environment's fog in one go. `PSXPreset.PRESETS` holds the 13: `ps1`, `ps1_480`, `subtle`,
`crunchy` (4-bit textures), `64_bit` (three-point filtered, no snap or warp), `handheld`, `crt`
(scanlines), `horror`, `fog_town`, `night`, `flashback`, `fog_wall` and `dark_fog` (both drawing
nothing past the fog). A preset is a Resource: save your own as a `.tres`. One without `fog` turns
the materials' fog off and leaves the Environment as it is.

## Materials

`PSX.make(kind, texture, color)` makes one; `kind` is `lit`, `unlit`, `cutout`, `transparent` or
`chrome`, each a `shaders/psx_<kind>.gdshader` you can also put on a ShaderMaterial yourself.
`PSX.convert(root)` maps unshaded to unlit, alpha scissor to cutout, alpha to transparent and
metallic to chrome, and returns how many materials it made. `PSX.convert(root, 64, 16)` also
makes each texture over once as the PS1 kept it, at most 64 pixels a side and cut to 16 colours
(`PSXTexture.shrink(texture, size, colors)` does one). `PSX.set_param(root, name, value)` sets a
parameter on every PSX material under `root`.

Parameters on every kind: `albedo`, `albedo_texture`, `uv_scale`, `uv_offset`, `uv_scroll` (UV
per second), `snap_pixels` (the vertex grid in screen pixels, 0 = off), `affine` (1 = PS1
warping, 0 = perspective-correct), `vertex_colors`, `three_point` (a 3-point texture filter);
and in the full pack, not the free sampler, `texture_bits` (bits a channel the texture keeps,
8 = as it is, 5 the PS1's 15-bit texels), `draw_distance` (metres past which polygons aren't
drawn, 0 = all) and `fog_color`, `fog_begin` and `fog_end` (the fog per vertex, off while
`fog_end` is 0). Cutout adds `alpha_cut`, chrome `reflection_texture` (a sphere map,
`chrome.png` by default) and `reflection`.

Affine mapping warps more the bigger a polygon is on screen: cut large floors and walls into
smaller quads, as PS1 games did. Lit materials light per vertex, so the same goes for lights.

Fog is the PS1's depth cue: each vertex goes toward `fog_color` from `fog_begin` to `fog_end`
metres, and glow takes none. A preset with `fog` sets the Environment's depth fog to start where
the materials' ends, so the sky and any non-PSX material go the fog's colour behind them. A
`draw_distance` just past `fog_end` makes polygons pop in out of the fog, a whole triangle at a
time, as on the PS1.

Conversion preserves cutout and transparent alpha on unshaded source materials. The shared `unlit`
setting keeps those materials independent of the scene lighting.
