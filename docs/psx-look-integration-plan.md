# PSX Look integration plan

Status: **plan only, not implemented**
Source pack: `/home/paulsheridan/Downloads/psx-look` (PSX Look by heyheythere, see `LICENSE.txt`)
Target: UMBILICAL, Godot 4.7.2, Forward+

## 1. Goal

Add PSX Look as a first-class, live-toggleable presentation mode for UMBILICAL:

- The full look (low-res screen, vertex snap, affine mapping, fog, draw distance,
  texture depth, presets, sprites/glow/waves) can be turned on and off from the
  game's own settings UI.
- Every part of the look has its own switch or slider, as in the pack's demo.
- The original authored look remains exactly recoverable with the master switch.
- UI outside the PSX screen stays sharp.
- Nothing about gameplay, AI, physics, audio, the drone feed, the photo camera or
  the hand-copy map regresses.

Recommended defaults:

| Setting | Default |
|---|---|
| Master | **On** |
| Preset | `ps1` (the one preset with no fog) |
| Lines | 240 |
| Dither / colour bits | On / 5 |
| Scanlines | 0 |
| Snap | 1 px |
| Affine | 1.0 |
| Three-point filter | Off |
| Vertex colours | On |
| Texture bits | 8 |
| Texture size / palette | Off / Off |
| Fog | Off (PS1 preset) |
| Draw distance | Off (toggle uses 24 m) |

This keeps the existing lighting, ambient fog and colour direction until the
player deliberately picks a fog/draw-distance preset.

## 2. Why this is not a drop-in

Three facts from the current project determine the implementation:

1. **The level is CSG.** `scenes/level/ship.tscn` has ~450 CSG nodes and
   `fab_bay.tscn` has ~70; there is one gameplay `MeshInstance3D` (the map
   surface). `PSX.convert()` only finds `MeshInstance3D`, so it would convert
   almost nothing. We need a CSG-aware converter that sets
   `GeometryInstance3D.material_override` on `CSGShape3D` nodes. This was
   verified against Godot 4.7: `CSGShape3D` has `material_override`, and hiding
   a CSG shape does **not** remove its generated collision.
2. **The 3D must live inside `PSXScreen`'s SubViewport.** Today `main.gd` adds
   the level, ship, player, drones and enemies directly to the root `Node3D`.
   All 3D adds must go through one world node under the PSX viewport. The
   `WorldEnvironment` must move with them.
3. **The camera is no longer the root viewport camera.** The still-photo
   SubViewport, the Sfx occlusion ray, the audio listener and several tests
   currently assume `get_viewport().get_camera_3d()` sees the world. They need
   to use the PSX world viewport instead.

The CSG geometry is also coarse: large floors/walls are single boxes with four
vertices per face. Vertex snap and per-vertex lighting will work, but affine
warping and lighting on a 50 m floor will be extremely coarse unless the
geometry is densified. Densification is part of this plan, not an optional
polish item.

## 3. Target architecture

```
Main (Node3D, src/main.gd)
├── WorldLayer (CanvasLayer, layer 0)
│   └── PSXScreen (SubViewportContainer, full rect, mouse_filter = PASS)
│       └── Viewport (SubViewport, own_world_3d = true)
│           └── World (Node3D)
│               ├── WorldEnvironment
│               ├── Level (fab_bay.tscn)
│               ├── Ship (ship.tscn)
│               ├── Player
│               └── drones / hosts / collector / processor / crawler / stalker
├── FeedViewport (SubViewport, 480×270, world_3d = find_world_3d())
│   └── FeedCamera (still-photo camera)
├── TableMapViewport (SubViewport, 512×256, 2D map render)
└── HUD (CanvasLayer, layer 5; built in code as today)
    ├── live tube (CanvasLayer layer 4, screen-texture shader)
    └── PSX options (CanvasLayer layer 6, crisp UI)
```

- `PSXScreen.look` is the screen half of the master switch. It is always the
  same SubViewport; `look = false` sets `material = null` and `stretch_shrink = 1`,
  so the world renders natively.
- The HUD, scanner, map overlay, live-tube shader and PSX options all stay
  outside the SubViewport and remain crisp.
- The still-photo viewport shares the PSX viewport's effective `World3D`; it renders the same PSX
  materials but not the screen post-process. That gives the still photo its
  existing distinct "raw optical" look. The live feed is the drone camera inside
  the PSX viewport, so it gets both the PSX look and the existing tube shader.
- The table-map viewport stays a 2D SubViewport. `MapSurface` is excluded from
  PSX conversion so its `ViewportTexture` keeps working. It still benefits from
  the low-resolution screen and dither, which is appropriate for an in-world
  paper map.

## 4. Files

### Vendored addon

Copy:

```
/tmp/.../psx-look/addons/psx_look/  ->  addons/psx_look/
```

Keep the original `LICENSE.txt` at `addons/psx_look/LICENSE.txt` and add a short
`docs/third-party.md` entry. The licence permits use in games and modification;
it forbids redistributing the shaders/scripts/textures as an asset pack.

Copy the demo folder as well. It is both documentation and the source of the
licensed stand-in textures/sprites for the lab and optional art pass. The demo
scene itself is not the game's main scene.

### New project files

| File | Purpose |
|---|---|
| `src/psx/psx_look.gd` | Autoload `PSXLook`: settings, conversion registry, master switch, presets, environment composition, persistence |
| `src/psx/psx_convert.gd` | CSG- and mesh-aware material conversion, restore, re-texture |
| `src/psx/psx_density.gd` | Optional CSG bake + subdivision for vertex density |
| `src/psx/psx_settings.gd` | Serializable settings resource / ConfigFile helpers |
| `src/ui/psx_panel.gd` | Crisp PSX options panel |
| `scenes/dev/psx_lab.tscn`, `src/dev/psx_lab.gd` | Standalone showcase for all six materials, sprites, glow, waves, presets and toggles |
| `tests/psx_look.gd`, `tests/psx_look.tscn` | Headless integration suite |

### Modified project files

| File | Change |
|---|---|
| `project.godot` | Add `PSXLook` autoload; add `psx_menu` action (F5) |
| `scenes/main.tscn` | Add `WorldLayer` → `PSXScreen` → `Viewport` → `World`; move `WorldEnvironment` into `World` |
| `src/main.gd` | Add all 3D nodes under `world`; set up `PSXLook`; feed viewport shares world; delegate environment/zone darkness/debug vision to `PSXLook` |
| `src/autoload/sfx.gd` | Use the PSX world for positional players, occlusion ray and listener |
| `src/ui/hud.gd` | Add PSX panel entry/overlay, proper pause UI with a resume button, F5 handling |
| `tests/*` | Camera assertions use `PSXLook.viewport.get_camera_3d()`; add PSX suite |
| `docs/` / `README.md` | Feature docs, controls, integration notes, licence entry |

## 5. Conversion design

### 5.1 A CSG-aware converter

Do not call `PSX.convert()` on the world directly for the main conversion.
`PSX.from_material()` is still used for each source material, but the traversal
must cover `GeometryInstance3D`:

```
for node in world.find_children("*", "GeometryInstance3D", true, false):
    if node.has_meta("psx_exclude"): continue
    if node is CSGPrimitive3D:                    # CSGBox/Cylinder/Sphere
        source = node.material if node.material is BaseMaterial3D else null
        psx = cache(source)                       # PSX.from_material(source)
        record(node, original_material_override = node.material_override, psx)
        node.material_override = psx if enabled else original
    elif node is MeshInstance3D:
        record material_override and per-surface overrides, same as PSX.convert
```

(`CSGShape3D` also has `material_override`; only the primitive subclasses have a
base `material`. The project uses primitives, not `CSGCombiner3D`.)

Cache key: source material + texture-mode + triplanar mode. Share one PSX
material per source, as the addon does.

Store every entry in the manager:

```
{
  "node": GeometryInstance3D,
  "kind": "csg" | "mesh_override" | "mesh_surface",
  "surface": int,                 # mesh only
  "source": BaseMaterial3D,
  "psx": ShaderMaterial,
  "original": Material,           # original override, or null for default surface
  "original_csg_visible": bool,
  "original_cast_shadow": int,
  "baked": MeshInstance3D,        # densification only
}
```

`apply()` swaps PSX materials in; `restore()` puts originals back. This makes the
master/conversion toggles instant and lossless.

### 5.2 Dynamic content

Drones, hosts, the Collector, Processor, Stalker, crawler, wreck pieces and
smears are built at runtime. Do not rely on a one-time conversion at boot.

- `main.gd` calls `PSXLook.convert_subtree(node)` after every gameplay spawn.
- The manager also listens for new nodes under `World` and converts any new
  `GeometryInstance3D` on the next idle frame. A 0.25 s sweep is a cheap fallback
  for geometry built inside another node's `_ready()`.
- Entries are keyed by instance ID; repeated sweeps are idempotent.

### 5.3 Exclusions

- `MapSurface`: `set_meta("psx_exclude", true)` and keep its unshaded
  `StandardMaterial3D` plus the live `ViewportTexture`.
- Any future viewport-textured or UI-in-world surface gets the same metadata.
- Do not shrink `ViewportTexture`s.

### 5.4 Triplanar / UV fidelity

Every game material uses `uv1_triplanar` + `uv1_world_triplanar` with scale
0.35. The PSX shaders use normal mesh UVs, so a converted material would stretch
the noise texture once per CSG face instead of tiling it per metre.

Recommended fix: add an optional triplanar block to
`addons/psx_look/shaders/psx.gdshaderinc` (and pass the source's
`uv1_scale` as `triplanar_scale` from the converter):

- `uniform bool triplanar = false;`
- world-position planar UVs, blended by the absolute normal;
- computed in the vertex stage with the same affine `w` treatment, so affine
  warping still applies;
- off for sprites, glow, transparent and any material that does not set
  `uv1_triplanar`; existing behaviour is unchanged when false.

Fallback if the shader change is rejected: bake world-space UVs into the
densified CSG mesh. That requires separate PSX material variants for CSG vs.
actor meshes because the same `Mats` resource is shared. The shader block is
less invasive and handles cylinders/spheres better.

### 5.5 CSG densification

`src/psx/psx_density.gd`:

- For each CSG node with a material and enough size, call
  `csg.bake_static_mesh()`, subdivide each triangle to a target edge length
  (default 1.5–2.0 m, user-selectable: Off / 2 m / 1 m / 0.5 m), and put the
  result on a `MeshInstance3D` child of the CSG node.
- Interpolate position, normal, UV and colour during subdivision; keep flat
  normals for CSG faces.
- Set the CSG node's `material_override` to a `discard` shader and turn off its
  shadow casting. The CSG shape stays in the tree, so its collision remains;
  the child MeshInstance renders the dense geometry and follows the parent
  if the parent moves (doors, wreck pieces).
- Record the original override, `visible` and `cast_shadow` for restore.
- Skip small props, dynamic projectiles and anything below the target size.
- Cap subdivisions per node to avoid pathological triangle counts.
- This is a one-time load cost, done before the start card is dismissed. If it
  exceeds ~500 ms, show a short "baking ship…" line; otherwise do it silently.

Densification is what makes vertex snap, affine warp, per-vertex lighting and
per-vertex fog read correctly on the 50 m hold floor and long walls.

### 5.6 Texture depth / shrink

- `texture_bits` is a live shader parameter (4/5/8 bits per channel) and needs no
  rebuild.
- `PSXTexture.shrink` is bake-time. Offer:
  - texture size: Off / 256 / 128 / 64 / 32
  - palette: Off / 256 / 16
- Cache by source texture. Re-run only when the size/palette option changes;
  show a brief pause if needed. Skip `ViewportTexture`, `NoiseTexture2D` if
  `get_image()` is not ready, and the map surface.
- When re-baking, update every PSX material that came from that source.

## 6. Feature matrix and controls

| Feature | Control | Implemented by | Default |
|---|---|---|---|
| Master look | CheckButton | `PSXScreen.look` + conversion apply/restore + environment restore | On |
| Preset | OptionButton / cycle button | `PSXPreset.PRESETS`, 13 entries | `ps1` |
| Resolution | OptionButton: 160 / 192 / 240 / 480 / Native | `PSXScreen.lines` | 240 |
| Dither | CheckButton | `PSXScreen.dither` | On |
| 15-bit colour | CheckButton | `PSXScreen.color_bits` 5/8 | On |
| Saturation | Slider 0–2 | `PSXScreen.saturation` | 1.0 |
| Tint | ColorPickerButton | `PSXScreen.tint` | White |
| Scanlines | CheckButton + slider 0–1 | `PSXScreen.scanlines` | Off |
| Vertex snap | CheckButton + slider 0–4 px | material `snap_pixels` | 1.0 |
| Affine textures | CheckButton + blend slider 0–1 | material `affine` | 1.0 |
| Nearest / three-point | CheckButton | material `three_point` | Nearest |
| Vertex colours | CheckButton | material `vertex_colors` | On |
| Texture colour depth | OptionButton: 4 / 5 / 8 bits | material `texture_bits` | 8 |
| PS1 texture size | OptionButton | `PSXTexture.shrink` size | Off |
| PS1 palette | OptionButton: 16 / 256 | `PSXTexture.shrink` colours | Off |
| Fog | CheckButton + colour + begin/end sliders | material `fog_color/begin/end` + Environment | Off |
| Draw distance | CheckButton + 8–120 m slider | material `draw_distance` | Off (24 m when on) |
| Sprites / billboards | CheckButton | material `billboard` on tagged sprite materials | On |
| Flipbook animation | CheckButton | material `fps` / `frame` on tagged materials | On |
| Waves | CheckButton + height/length/speed | material `wave_*` on tagged materials | On |
| Material conversion | CheckButton | converter apply/restore | On |
| Geometry density | OptionButton: Off / 2 m / 1 m / 0.5 m | `psx_density.gd` | 2 m |
| Custom preset | Save button | `ResourceSaver.save` a `.tres` | — |

All material-wide controls go through one manager call and update every unique
PSX material once, not once per CSG node. This matters on slider drags with
~450 CSG nodes.

## 7. Environment, fog and darkness

The current `main.gd` writes `_env.ambient_light_energy`, `_env.fog_density` and
`_env.tonemap_exposure` directly. That will fight PSX depth fog / preset fog.

Move environment control into `PSXLook`:

- Duplicate `assets/environment.tres` at runtime so the authored resource is
  never mutated.
- Snapshot authored fog/ambient/exposure/background values.
- `set_zone_dark(on)` replaces `_set_zone2_dark`; the manager lerps a darkness
  factor and composes:
  - master off or PSX fog off: authored fog/ambient behaviour exactly as today;
  - PSX fog on: set Environment depth fog to start at the materials' `fog_end`
    and end just after it, set `fog_sky_affect = 1.0`, and set the background
    colour to the fog colour so draw-distance pop-in happens against matching
    fog;
  - zone darkness multiplies ambient energy and the fog colour; it must not
    write `fog_density` while depth fog is active.
- `set_debug_vision(on)` suspends the PSX look (screen + materials + fog + draw
  distance) while debug vision is active, then restores the user's settings.
  This preserves the intent of F4: a clean colour picture, low light and
  ghosted enemies. The existing debug tests that inspect `_env` still pass.
- If a preset has `fog = false`, leave the authored Environment alone and set
  material `fog_end = 0`.

The 50 m rooms and the 36 m tether mean a 24 m default draw distance is a good
"on" value; the `fog_wall` (10 m) and `dark_fog` (8 m) presets remain dramatic
and stay opt-in.

## 8. UI and input

### Pause screen

Replace the "click anywhere to resume" pause surface with a proper pause panel:

- `PAUSED`
- `RESUME`
- `PSX LOOK` (opens the panel)
- existing `ESC or click to resume` hint retained below the panel
- clicking the dark background outside the panel still resumes; clicking the
  panel does not.

### PSX panel (crisp, in HUD layer 6)

A `PanelContainer` styled to match the HUD (near-black panel, amber title, green
values, thin border), with a scrollable column:

1. `PSX LOOK` master switch + preset selector/cycle.
2. Screen group: resolution, dither, 15-bit, scanlines, saturation, tint.
3. Geometry group: vertex snap, affine, three-point, vertex colours, density.
4. Texture group: colour depth, PS1 size, palette.
5. Depth group: fog switch, colour, begin, end, draw distance.
6. Animation group: sprites, flipbooks, waves.
7. Buttons: `Reset to preset`, `Save custom`, `Close`.

Every control is two-way bound to `PSXLook`; changing a preset refreshes all
controls; changing a control marks the selector `Custom`. The panel is not
inside the PSX screen, so labels stay sharp.

### Input

- Add `psx_menu` = F5 to `project.godot`.
- F5 opens the pause screen with the PSX panel; F5/Escape/Close closes it.
- Mouse is released while open and recaptured on close, matching the map.
- While the panel is open, player/drone input, photo/shutter, reel, map and
  deploy keys are suppressed.
- Existing F3 (debug counters), F4 (debug vision) and Escape (pause) keep their
  meanings.
- The panel should also be reachable from the title screen, so a player can set
  the look before starting.

### Persistence

`user://psx_look.cfg` via `ConfigFile`:

- master, preset name, every toggle/slider, fog/draw distance, density,
  texture size/palette, custom preset name.
- Load after the world is converted; if absent, use the defaults above.
- `Reset` restores defaults and saves.
- Headless tests call `PSXLook.reset_to_defaults(false)` first so a developer's
  saved settings never make CI flaky.
- Custom presets save as `.tres` under `user://psx_presets/` and appear in the
  preset list.

## 9. Audio, feed, map and tests

### Audio

`Sfx.play()` currently parents 3D players to `get_tree().current_scene` and
raycasts against that node's world. After the viewport move, that world is empty.

- Give `PSXLook` a `world: Node3D` and `world_viewport: SubViewport`.
- Parent positional `AudioStreamPlayer3D` nodes to `PSXLook.world`.
- Use `PSXLook.current_camera()` (the player or drone camera) for the occlusion
  ray and listener.
- Verify that positional audio pans correctly inside the SubViewport. If Godot
  does not pick up the SubViewport camera as the listener, add an
  `AudioListener3D` in `World` and update its transform to the active camera
  each frame. This is a verification item, not an assumed behaviour.

### Still photo

`_setup_feed()` must set:

```gdscript
_feed_vp.world_3d = psx.viewport.find_world_3d()
```

and keep its update mode `UPDATE_DISABLED` / `UPDATE_ONCE`. A viewport with
`own_world_3d = true` has a null `world_3d` property, so use `find_world_3d()`
(the `PSXLook.world_3d()` helper does this). The feed camera is
still positioned from the drone camera each exposure. The HUD feed shader is
unchanged.

### Table map

- Keep `_setup_table_map()` before conversion.
- Mark `level.map_surface` with `psx_exclude`.
- Keep the live viewport texture on its StandardMaterial3D.
- Optionally add a small `PSXLook` helper that re-applies the texture if the map
  surface is ever replaced.

### Tests

New `tests/psx_look.gd` covers:

- World/viewport setup: `World` under `Viewport`, `own_world_3d`, environment
  inside, player/drone cameras current in that viewport.
- CSG conversion: a known ship CSG node and a known actor CSG node have PSX
  shader overrides.
- Master off/on: CSG overrides restore to `null`, screen `look` toggles, then
  reapply.
- All 13 presets: screen values and representative material values match.
- Every feature toggle: material or screen parameter changes; state restores.
- Dynamic spawn: start a sortie, assert the drone CSG is converted.
- Feed: `_feed_vp.world_3d != null`, equal to `psx.viewport.find_world_3d()`, size 480×270, feed camera current.
- Map surface is excluded and still has a `ViewportTexture`.
- Debug F4: PSX look suspends and restores.
- Settings save/load round-trip in a temporary `user://` path.
- Pause panel opens/closes and a control changes the manager.

Update existing suites:

- `tests/debug_vision.gd`: assert against
  `PSXLook.world_viewport.get_camera_3d()`.
- `tests/autotest.gd`: same for the camera handoff checks.
- Any test that instantiates `main.tscn` should call
  `PSXLook.reset_to_defaults(false)` first.

Add `psx_look` to `tools/run_tests.sh`.

## 10. Showcase / art pass

The pack's demo uses all six materials, sprites, glow and waves. The current game
materials are all opaque lit/unlit CSG, so cutout, transparent, chrome, glow,
sprites and waves would otherwise be dead code.

Required:

- A standalone `scenes/dev/psx_lab.tscn` using the pack's demo art and a simple
  room/mesh set. It should exercise:
  - lit, unlit, cutout (foliage/banner), transparent (water/glass with UV
    scroll), chrome (gem), glow (flame/halo/beam);
  - a flipbook sprite, an upright billboard, a wave banner and a wave puddle;
  - preset stepping and every switch, matching the demo's panel.
  This is the reference scene for "does this feature still work".

Optional but recommended in-game art pass (tasteful, lore-appropriate):

- Amber practical lights get a small additive glow halo sprite.
- A hanging torn strip/tarp in the fab bay or hold gets a pinned wave.
- A puddle or wet deck patch in the galley/hold gets transparent + UV scroll.
- A hanging cable/grate cutout in the corridor or hold.
- A couple of chrome machine accents on the fabricator/Processor.
- A flipbook flame/weld spark on the fabricator or a work lamp.

Each category gets a manager-level toggle (`Sprites`, `Glow`, `Waves`,
`Cutout`, `Transparent`, `Chrome`) so the whole category can be disabled in the
options menu. Tag sprite/wave materials at creation so global toggles only
affect those materials, not walls.

## 11. Performance and budget

- 240-line internal render is cheaper than native; the main added cost is the
  CSG densification triangle count and per-material draw calls.
- Target: < 100k triangles after densification and no more than ~600 draw calls
  in the heaviest room. Measure with `RenderingServer.get_rendering_info`.
- Bake/shrink once at load; never per frame.
- Apply slider changes to unique PSX materials, not per node.
- Throttle texture re-bakes and density rebuilds; they are explicit option
  changes, not live sliders.
- Keep the PSX viewport `mesh_lod_threshold = 0` (PSXScreen already sets this)
  so LOD does not thin vertex-lit geometry.

## 12. Risks and verification items

| Risk | Mitigation |
|---|---|
| CSG `material_override` renders incorrectly with PSX shaders | Verify visually in the lab and bay first; fall back to baking CSG to MeshInstance + discard shader |
| Coarse CSG makes snap/affine/lighting ugly | Densify with `psx_density.gd`; default 2 m, tune in lab |
| Triplanar textures stretch per face | Add optional triplanar block to the PSX include; fallback to baked world UVs |
| Audio listener not picked up inside SubViewport | Verify; add `AudioListener3D` following the active camera if needed |
| HUD screen-texture shaders sample the wrong layer | Already split across CanvasLayers 0/4/5; verify the live tube samples the PSX image |
| Still camera shares the wrong world | Explicitly assign `_feed_vp.world_3d`; test |
| Debug vision and preset fog fight | Debug suspends PSX and restores; tests |
| Test camera assertions break | Update `debug_vision`/`autotest`; add PSX suite |
| Runtime geometry escapes conversion | `convert_subtree` on spawn + node-added + 0.25 s sweep |
| Shared `Mats` resources mutated | Never mutate source materials; only create PSX materials; duplicate Environment |
| Saved settings make tests flaky | `reset_to_defaults(false)` at test start; temp `user://` path in round-trip test |
| Addon licence misuse | Keep licence; do not redistribute pack contents as a pack |

## 13. Phased implementation

### Phase 0 — vendor and prove the pack

1. Copy `addons/psx_look`.
2. Add the licence note.
3. Run the pack's `demo.tscn` under Godot 4.7.2 to confirm shaders compile.
4. Build the minimal `psx_lab` scene and verify CSG `material_override` with a
   PSX lit shader.

### Phase 1 — world under the screen

1. Restructure `main.tscn` (`WorldLayer`/`PSXScreen`/`Viewport`/`World`).
2. Change `main.gd` 3D adds to `_add_world`.
3. Move `WorldEnvironment`.
4. Wire `PSXScreen.look` master switch.
5. Fix feed world and Sfx world/camera.
6. Update camera tests.
7. Acceptance: world renders through PSXScreen, master off looks like today,
   all tests green.

### Phase 2 — CSG conversion and master toggle

1. Implement `psx_convert.gd`.
2. Register static and dynamic geometry.
3. Implement apply/restore.
4. Exclude map surface.
5. Acceptance: CSG materials visibly change; master off restores originals;
   dynamic drones/hosts convert.

### Phase 3 — manager, presets and persistence

1. Implement `PSXLook` settings and preset application.
2. Add all 13 presets.
3. Add save/load to `user://psx_look.cfg`.
4. Acceptance: preset switching changes screen + materials + fog; settings
   survive restart.

### Phase 4 — UI

1. Build `psx_panel.gd`.
2. Wire pause screen, title screen and F5.
3. Add proper pause resume button.
4. Acceptance: all controls live-update; UI crisp; input suppressed while open.

### Phase 5 — environment, fog, draw distance, debug

1. Move environment composition into `PSXLook`.
2. Delegate zone darkness.
3. Compose PSX fog + authored fog.
4. Suspend/restore on debug vision.
5. Acceptance: Cold Hold darkness still works; fog presets match; draw distance
   pops against matching fog; F4 clean and restores.

### Phase 6 — fidelity: triplanar, density, texture depth

1. Add optional triplanar support or baked world UVs.
2. Implement CSG densification with settings.
3. Implement texture size/palette re-bake.
4. Tune defaults on the 50 m hold floor and long walls.
5. Acceptance: snap/affine/lighting/fog read correctly at 240 lines; textures
   tile per metre; no obvious cracks.

### Phase 7 — materials, sprites, glow, waves

1. Build the full `psx_lab`.
2. Add the optional in-game art pass.
3. Add category toggles.
4. Acceptance: all six material kinds visible in the lab; sprite/glow/wave
   toggles work; game still reads as UMBILICAL.

### Phase 8 — tests, docs, QA

1. Add `tests/psx_look`.
2. Update existing tests.
3. Run `tools/run_tests.sh`.
4. Visual QA: master off vs on, every preset, pause panel, title screen, map,
   photo, live feed, debug F4, Cold Hold fog/darkness, full fleet sortie.
5. Update README, `docs/editor-guide.md`, `docs/playtest-checklist.md` and a new
   `docs/psx-look.md`.

## 14. Acceptance criteria

- Master off is visually indistinguishable from the current build (same
  materials, environment, resolution and HUD).
- Master on with `ps1` shows low-res 15-bit dithered pixels, vertex snap and
  affine warping, while HUD text stays crisp.
- All 13 presets apply correctly and can be cycled without leaving the game.
- Every feature in the pack's list has a working toggle or slider:
  snap, affine, screen resolution/dither/colour/scanlines, fog, draw distance,
  texture depth/size/palette, presets, sprites/glow/waves, six materials,
  conversion, three-point filter, vertex colours, master on/off.
- Settings persist and can be reset.
- CSG geometry (ship and bay), actor CSG and runtime-spawned geometry all
  convert.
- The map surface, still photo, live feed, scanner, audio occlusion and all
  gameplay systems behave as before.
- Debug F4 suspends the look and restores it exactly.
- `tools/run_tests.sh` is green, including the new suite.
- No per-frame texture or geometry rebuild cost; load-time bake only.

## 15. Open decisions

1. **Default look on or off.** This plan recommends on with `ps1` (fog off).
   Starting off is also valid and is one line of default settings; the
   architecture supports it either way.
2. **In-game art pass scope.** The lab is required; the optional prop pass
   (halos, tarp, puddle, cutout, chrome) should be reviewed against the game's
   art direction before shipping.
3. **Vendor shader modification.** The triplanar block is the recommended
   approach; if the addon must stay byte-identical, use baked world UVs
   instead.
