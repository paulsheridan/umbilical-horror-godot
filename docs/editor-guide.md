# Editing UMBILICAL in the Godot editor

The level is now authored content, not code. `scenes/level/ship.tscn` and
`scenes/level/rooms/fab_bay.tscn` are the source of truth. Nothing rebuilds
geometry at runtime; if you change the scene, the game changes.

Requires **Godot 4.7+**.

---

## 1. Open and run

```sh
godot --editor --path /home/paulsheridan/projects/umbilical
```

- **F5** runs the whole game from `scenes/main.tscn`.
- **F6** on `scenes/level/ship.tscn` loads the level alone (no player or HUD;
  useful for checking geometry and lighting).
- **F6** on `scenes/level/rooms/fab_bay.tscn` loads the bay alone.
- **F6** on any `scenes/actors/*.tscn` previews that body.
- **F4** in game toggles developer debug vision: clean full-colour feed from
  any chassis (no video module needed), low-light ambient/exposure, a wide lamp,
  and hostile bodies that ignore the fleet. It is a debug switch, not content.
- **F5** in game opens the crisp **PSX LOOK** panel. Every presentation feature
  is live there; the master switch restores the authored look. See
  `docs/psx-look.md`.

`scenes/main.tscn` now holds the `WorldEnvironment` under the PSX viewport and
instances the level and the actor prefabs. The HUD is still built in code; that
is the remaining conversion work.

---

## 2. Scene map

```
scenes/
  main.tscn                      # entry point: WorldLayer/PSXScreen/Viewport/World
  level/
    ship.tscn                    # the ship, grouped by room
    rooms/
      fab_bay.tscn               # the safe room
  actors/
    player.tscn                  # body, capsule, camera, eye fill
    drone.tscn                   # chassis, tracks, camera, status lamp
    host.tscn                    # attacking zombie body (tests/dev placement)
    watcher.tscn                 # Cold Hold watcher body (watches, then hunts)
    stalker.tscn                 # body + collision only; the centipede rig
                                 # is runtime-built (engine tenant)
    collector.tscn               # animated scavenger (Kenney), lantern, sack
    vomit.tscn                   # stand-in Collector vomit projectile
    processor.tscn               # pinned maw, jaw, gaunt arms
    crawler.tscn                 # legless survivor set piece
assets/
  environment.tres               # fog / ambient / background, inspector-editable
  materials/*.tres               # shared palette
  characters/collector/          # Kenney model, skin, idle/walk/run/jump clips
addons/psx_look/                 # vendored PSX presentation pack
src/psx/                         # PSXLook manager: conversion, density, settings
```

`scenes/main.tscn` is deliberately shallow:

```
Main (Node3D)                    # src/main.gd
└── WorldLayer (CanvasLayer)
    └── PSXScreen (SubViewportContainer)
        └── Viewport (SubViewport, own_world_3d)
            └── World (Node3D)   # every gameplay Node3D, and WorldEnvironment
```

The HUD, map, scanner and still-photo `SubViewport` are created by `main.gd`
outside the PSX viewport, so their text and overlays stay sharp at full
resolution.

### `ship.tscn` tree

```
Ship (Node3D)                    # beyond.gd controller
├── Corridor                     # vestibule, legs, bend
├── Junction                     # junction + spur mouth
├── Spur                         # salvage wreck + module
├── Galley                       # mess, cold room, flashlight add-on
├── Annex                        # donut ring
├── BerthWing                    # hall, cabins, crawl, ossuary
├── ProcessorWing                # hall + feed chamber
├── Zone2
│   └── ColdHold                 # umbilical + 50 x 25 m dark hold + side hall
├── EngineRoom                   # Deck C: core, machinery, low-cover hides
├── World                        # the single flat floor collider (all decks)
└── Data
    ├── Anchors                  # placement markers (see §4)
    ├── HideSpot0..5             # Deck A low-table / bunk sight hides
    ├── HideSpotEngine0..2       # engine-room low-cover hides
    ├── AmbushSpot0..10          # Deck A corners (the engine Stalker has none)
    └── Choke0..1                # body-height barriers
```

Named gameplay nodes stay findable regardless of their room container:
`GalleyDoor`, `Zone2Door`, `CameraModule`, `CollectorPile`, `ProcessorPile`,
`FlickerLight`, `DoorLamp`, and `LoudDoor0..3`.

### `fab_bay.tscn` tree

```
FabBay (Node3D)                  # fab_bay.gd controller
├── PilotChair, Fabricator, MapTable    # Interactable bodies
├── MapSurface                   # live paper-map quad
├── MapFlicker, EmergencyLight   # animated practicals
├── PlayerStart                  # Marker3D
└── ... graybox geometry
```

---

## 3. Editing geometry

- Geometry is `CSGBox3D` / `CSGCylinder3D` / `CSGSphere3D`. Select and move them
  like any node. The transforms are world-space at the scene root, so room
  containers are at the origin and moving a container moves the room.
- `use_collision = true` makes a CSG node solid to the player, drone and hosts.
  Floor cables, stains, guide strips and other decoration should stay
  `use_collision = false` — a 12 cm cable is an invisible wall to a capsule.
- Walls, ceilings and floors are butt-jointed. If you move a wall, move the
  pieces that share its plane or you will open a gap the drone can drive
  through.
- The ship has **one flat floor collider** in `World`, sized to cover Deck A and
  the Cold Hold. Keep its top at `y = 0`; every body assumes that plane. Do not
  add a second floor slab under Zone 2.
- Materials come from `assets/materials/*.tres`. Assign one from the FileSystem
  dock; edit the `.tres` once and every surface using it updates. Do not create
  per-node material copies unless the surface is genuinely unique.
- Everything 3D must be under `WorldLayer/PSXScreen/Viewport/World`. A node
  parented to `Main` lands in the empty root `World3D` and is invisible in game.
  Runtime spawns use `main._add_world()` or `PSXLook.world`.
- The PSX converter copies source material values into shared shader materials;
  it never edits the authored `.tres`. Turn the master switch off (F5) to see
  the authored look and confirm a new surface reads as intended.

### Adding a prop

1. Add a `CSGBox3D` (or cylinder/sphere) under the room container.
2. Set `size`, transform and `material` (drag a palette `.tres` in).
3. Leave `use_collision = true` only if the player/drone should collide.
4. If it is a low table or bunk a tall host must respect as cover, add a
   `HideSpot` marker (see below). The Cold Hold intentionally has none: its
   cover is hard cover you route around.

---

## 4. Moving gameplay without touching code

All placement is editor-owned. The controller reads these on load:

| Marker (`Data/Anchors/…`) | Drives |
|---|---|
| `Dock` | drone launch point, tether origin, fleet cradles |
| `CameraSite` | salvage-module pickup distance |
| `Flashlight` | flashlight add-on pickup distance |
| `GalleyDoorApproach` | when the galley door starts opening |
| `CollectorDeposit` | the Collector's home/nest |
| `ProcessorPos` | where the Processor stands |
| `ProcessorPile` | what the Processor feeds from |
| `ProcessorDrop` | where the Collector sets a carried bot down |
| `Zone2Threshold` | where Deck B begins and the first-entry beat fires |
| `Zone2Relay` | the Cold Hold tether origin and radar label |
| `Zone2Spawn0..3` | the four watcher spawn points (keep 20+ m out) |
| `CrawlerSetPiece` | the side-hall entrance / set-piece trigger |
| `CrawlerGrab` | the crawl origin and its abandon mark |
| `CollectorSacrifice` | legacy first-crossing mark, retained but no longer used (the Collector is never consumed) |
| `EngineEntry` | the engine-room threshold / first Deck C mark |
| `EngineRelay` | the engine-room tether origin and radar label |
| `EngineStalkerSpawn` | where the engine-room Stalker starts |

- **Hide spots** (`Data/HideSpot*`): `Marker3D` with metadata
  `kind = "hide_spot"` and `half = Vector2(x, z)`. The half-extents are the
  tall host's sight-hide footprint.
- **Ambush spots** (`Data/AmbushSpot*`): `Marker3D` with
  `kind = "ambush_spot"`. Retained Deck A corners; the engine Stalker is given
  an empty ambush list by `main`.
- **Chokes** (`Data/Choke*`): `kind = "choke"`, plus `half`, `north`, `south`.
  `north`/`south` are the waypoints a tall body routes through instead.
- **Loud doors** (`LoudDoor0..3`): panel metadata `door_open` (closed + slide
  offset) and `door_trigger` (where a body opens it). The controller rebuilds
  the runtime door list from these.
- **Remains** (`Remains0..11`): `kind = "remains"`. The Collector picks these
  up and carries them to the Processor pile.

If you move a marker, run the game once and check the effect. The
`level_scene` suite verifies the anchors exist and that moving one updates the
runtime value.

### Deck B authoring notes

- The hold is one open room (`Zone2/ColdHold`) with an 8 m umbilical and an
  8.5 m ceiling. Keep it sparse: hard cover is the only cover and the room is
  deliberately pitch black while the active drone is inside.
- The four watcher loops live in `main.ZONE2_ROUTES`. Every leg must stay out of
  the crawler side hall (`x > 19.2, z < -47`) and clear of the cover blocks.
  The watchers arrive passive: the first sighting by any of them arms one shared
  clock (`main.WATCHER_PATIENCE_MIN` 120 s plus `WATCHER_PATIENCE_EXTRA` 0–120 s),
  and when it expires all four hunt like the plain host for the rest of the
  session. Keep the spawn marks 20+ m from the threshold so the hold does not
  start already hunting.
- The crawler hall is the east-edge corridor (`CrawlerWestWall`,
  `CrawlerCeiling`, `CrawlerFloor`) plus the throat that opens north into
  `EngineRoom`. Trigger and end marks are the `CrawlerSetPiece` /
  `CrawlerGrab` anchors; the actor itself is collision-free and never blocks
  the lane. The hall lamps are `CrawlerLampA..C`; `beyond.gd` breathes them.
- The relay must stay within 36 m of the dock, every hold point within 36 m of
  the Cold Hold relay, and `EngineRelay` within 36 m of that relay with every
  engine-room point inside its own drum. Never solve a range problem by raising
  `MAX_TETHER`.
- `EngineRoom` is an open machinery hall around `EngineCore`: pipes, tanks,
  gantry beams and three low covers (`EngineLowCover0..2`). The low covers are
  the drone's true sight-hides (`HideSpotEngine0..2`); keep a metre of
  clearance under them for the chassis and leave them too low for a Stalker.
  The engine Stalker's loop is `main.ENGINE_ROUTE`, but it opens folded in
  ambush at `EngineStalkerSpawn` (far from the entry) and is tuned in `main` for
  a long wait and a high re-fold chance; recheck these by playing after moving
  the room, the core, the cover or the ambush marks.

---

## 5. Materials

`src/mats.gd` is a thin loader over `assets/materials/*.tres`, and
`assets/environment.tres` owns fog, ambient and background. Edit the `.tres`
files directly; they are the source of truth. The PSX look is applied on top at
runtime by `src/psx/psx_convert.gd`, which records every original override and
Environment value so master-off restores them exactly. Author as if the pack
were not installed.

All actor bodies are authored scenes. Their scripts only reference named
children (`$Head/Cam`, `$Chassis/LED`, `$Rig/Hips/Torso`, …), so move or
restyle a body in the editor without touching behaviour. The audio player for
the Stalker's hum is created at runtime, not saved in the scene.

---

## 6. Tests

```sh
tools/run_tests.sh                 # all suites, fails on any FAIL
tools/run_tests.sh level_scene     # one suite
```

The suite set is:

```
autotest camera_loop host_ai_rules watcher_ai stalker_ai zombie_reach
catch_face collector_ai processor_ai level_scene crawler_setpiece debug_vision
psx_look
```

`level_scene` is the editor contract: it loads the baked scenes and checks the
controllers, anchors, pickups, doors, shared materials and actor prefabs. It
does not pin terrain, walls, floors, ramps, walkways or walkable routes, so the
level layout can be edited freely.

---

## 7. What not to do

- Do not reintroduce a runtime geometry builder. Scene files are the source of
  truth.
- Do not rename gameplay nodes (`GalleyDoor`, `ProcessorPile`, `FlickerLight`,
  …) without updating `src/ship/beyond.gd`.
- Do not move `Data/Anchors` markers out of `Data/Anchors`; the controller
  resolves them by that path.
- Do not set `PSXScreen.mouse_filter = MOUSE_FILTER_IGNORE`. The
  `SubViewportContainer` forwards mouse motion to the gameplay viewport through
  `gui_input`; `IGNORE` silently breaks mouse look. It is set to `PASS` in
  `addons/psx_look/psx_screen.gd`, and `psx_look` tests the forwarding path.
- Do not commit `.godot/`. Commit `.uid` files.
