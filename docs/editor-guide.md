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
- **F6** on `scenes/actors/player.tscn` or `drone.tscn` previews the prefabs.

`scenes/main.tscn` now holds the `WorldEnvironment` and instances the level and
the player/drone prefabs. The HUD and the four host bodies are still built in
code; that is the remaining conversion work.

---

## 2. Scene map

```
scenes/
  main.tscn                      # entry point + WorldEnvironment
  level/
    ship.tscn                    # the ship, grouped by room
    rooms/
      fab_bay.tscn               # the safe room
  actors/
    player.tscn                  # body, capsule, camera, eye fill
    drone.tscn                   # chassis, tracks, camera, status lamp
assets/
  environment.tres               # fog / ambient / background, inspector-editable
  materials/*.tres               # shared palette
```

### `ship.tscn` tree

```
Ship (Node3D)                    # beyond.gd controller
├── Corridor                     # vestibule, legs, bend
├── Junction                     # junction + spur mouth
├── Spur                         # salvage wreck + module
├── Galley                       # mess, cold room, rations
├── Annex                        # donut ring
├── BerthWing                    # hall, cabins, crawl, ossuary
├── ProcessorWing                # hall + feed chamber
├── World                        # the single flat floor collider
└── Data
    ├── Anchors                  # placement markers (see §4)
    ├── HideSpot0..5             # low-table / bunk sight hides
    ├── AmbushSpot0..10          # stalker corner spots
    └── Choke0..1                # body-height barriers
```

Named gameplay nodes stay findable regardless of their room container:
`GalleyDoor`, `CameraModule`, `CollectorPile`, `ProcessorPile`, `FlickerLight`,
`DoorLamp`, and `LoudDoor0..3`.

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
- The ship has **one flat floor collider** in `World`. Keep its top at `y = 0`;
  every body assumes that plane.
- Materials come from `assets/materials/*.tres`. Assign one from the FileSystem
  dock; edit the `.tres` once and every surface using it updates. Do not create
  per-node material copies unless the surface is genuinely unique.

### Adding a prop

1. Add a `CSGBox3D` (or cylinder/sphere) under the room container.
2. Set `size`, transform and `material` (drag a palette `.tres` in).
3. Leave `use_collision = true` only if the player/drone should collide.
4. If it is a low table or bunk the stalker must respect as cover, add a
   `HideSpot` marker (see below).

---

## 4. Moving gameplay without touching code

All placement is editor-owned. The controller reads these on load:

| Marker (`Data/Anchors/…`) | Drives |
|---|---|
| `Dock` | drone launch point, tether origin, fleet cradles |
| `CameraSite` | salvage-module pickup distance |
| `Food` | ration pickup distance |
| `GalleyDoorApproach` | when the galley door starts opening |
| `CollectorDeposit` | the Collector's home/nest |
| `ProcessorPos` | where the Processor stands |
| `ProcessorPile` | what the Processor feeds from |
| `ProcessorDrop` | where the Collector sets a carried bot down |

- **Hide spots** (`Data/HideSpot*`): `Marker3D` with metadata
  `kind = "hide_spot"` and `half = Vector2(x, z)`. The half-extents are the
  stalker's sight-hide footprint.
- **Ambush spots** (`Data/AmbushSpot*`): `Marker3D` with
  `kind = "ambush_spot"`. Corners where the stalker can fold up and wait.
- **Chokes** (`Data/Choke*`): `kind = "choke"`, plus `half`, `north`, `south`.
  `north`/`south` are the waypoints the stalker routes through instead.
- **Loud doors** (`LoudDoor0..3`): panel metadata `door_open` (closed + slide
  offset) and `door_trigger` (where a body opens it). The controller rebuilds
  the runtime door list from these.
- **Remains** (`Remains0..11`): `kind = "remains"`. The Collector picks these
  up and carries them to the Processor pile.

If you move a marker, run the game once and check the effect. The
`level_scene` suite verifies the anchors exist and that moving one updates the
runtime value.

---

## 5. Materials

`src/mats.gd` is a thin loader over `assets/materials/*.tres`, and
`assets/environment.tres` owns fog, ambient and background. Edit the `.tres`
files directly; they are the source of truth.

The player and drone bodies are authored scenes. Their scripts only reference
named children (`$Head/Cam`, `$Chassis/LED`, …), so move or restyle the body in
the editor without touching behaviour.

---

## 6. Tests

```sh
tools/run_tests.sh                 # all suites, fails on any FAIL
tools/run_tests.sh level_scene     # one suite
```

The suite set is:

```
autotest camera_loop patrol_soak host_ai_rules stalker_ai annex_loop
collector_ai processor_ai level_scene
```

`level_scene` is the editor contract: it loads the baked scenes and checks the
controllers, anchors, baked data lists, room containers, shared materials and
floor collider. A broken scene fails there before the gameplay suites.

---

## 7. What not to do

- Do not reintroduce a runtime geometry builder. Scene files are the source of
  truth.
- Do not rename gameplay nodes (`GalleyDoor`, `ProcessorPile`, `FlickerLight`,
  …) without updating `src/ship/beyond.gd`.
- Do not move `Data/Anchors` markers out of `Data/Anchors`; the controller
  resolves them by that path.
- Do not commit `.godot/`. Commit `.uid` files.
