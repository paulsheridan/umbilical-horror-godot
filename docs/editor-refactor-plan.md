# Editor-first refactor plan

Status: **proposed — not started**
Goal: make UMBILICAL a project you can open and build in the Godot editor, and
leave the code clean and DRY without changing gameplay.

---

## 1. Audit — where the project actually is

### Scenes
| File | Lines | Contents |
|---|---:|---|
| `scenes/main.tscn` | 6 | One `Node3D` with `src/main.gd`. Nothing else. |
| `tests/*.tscn` | 6 each | One `Node3D` with a test script. |

There is **no level scene, no room scene, no actor prefab, and no UI scene**.

### Everything is built in `_ready()`
`src/main.gd` (1301 lines) does all of this at runtime:

```gdscript
level = FAB_BAY.new(); add_child(level); level.build()
ship  = BEYOND.new();  add_child(ship);  ship.build()
hud   = CanvasLayer.new(); hud.set_script(load("res://src/ui/hud.gd"))
player = CharacterBody3D.new(); player.set_script(load("res://src/player/player.gd"))
scanner = SCANNER.new()
hosts/collector/processor/drones = CharacterBody3D.new() + set_script(...)
```

### Generated geometry (measured)
| Builder | Lines | Runtime nodes |
|---|---:|---|
| `src/hub/fab_bay.gd` | 287 | 69 — 38 CSGBox, 13 CSGCylinder, 6 StaticBody, 4 lights |
| `src/ship/beyond.gd` | 956 | 334 — 268 CSGBox, 16 CSGCylinder, 14 CSGSphere, 1 StaticBody (floor), 19 lights |
| **Total** | | **403 nodes, 0 editable in the editor** |

### Other code-built content
- `src/ui/hud.gd` (871) — every panel, label, vignette and feed built in code.
- `src/ui/scanner.gd` (178), `src/ui/map_view.gd` (146) — code-built.
- `src/drone/drone.gd` (244), `src/host/*.gd` (610 + 1019 + 529 + 515) — bodies
  built from primitives in `_ready()`.
- Materials: `src/mats.gd` (163) caches `StandardMaterial3D` in-process, but
  they are not project assets and cannot be edited in the inspector.

### Facts that affect the plan
- Ship geometry shares **one flat collision floor** at `y = 0`; walls and props
  are CSG nodes with `use_collision = true`, decorative slabs have it off.
- Gameplay data lives in plain arrays/consts on the builder:
  `hide_spots`, `ambush_spots`, `chokes`, `loud_doors`, `remains`,
  `collector_pile`, `processor_pile`, `dock_pos`, `PROCESSOR_*`, `CAMERA_POS`,
  `GALLEY_DOOR_POS`, `FOOD_POS`.
- `main.gd` wires interactables with `Callable(self, "_start_sortie")` etc.
- Two suites build the ship directly (`collector_ai`, `processor_ai`:
  `BEYOND.new(); ship.build()`); the rest use `main.tscn`.
- `project.godot` declares `config/features=("4.4", "Forward Plus")` while the
  installed engine is **4.7.2**.
- Git: one commit (`first commit`) on `main`; `.uid` files exist and are
  tracked; `.godot/` is ignored.
- Test baseline: **370 checks, 0 failures** across 8 suites.

### The actual problem
1. The level cannot be opened, selected, moved or visually authored.
2. Geometry changes require editing GDScript and re-running the game.
3. No F6/F5 workflow per room; no inspector tuning.
4. Two builders duplicate `_box`, `_cyl`, `_light`, and run-splitting logic.
5. `main.gd` is a 1301-line God object that owns fleet, objectives, feed,
   lighting, hosts, UI and level construction.
6. Hosts, HUD and vehicles are similarly opaque to the editor.

---

## 2. Target architecture

```
scenes/
  main.tscn                      # orchestration only: Level + Player + HUD + systems
  level/
    level.tscn                   # composition root; instances the rooms
    rooms/
      fab_bay.tscn
      vestibule_legs.tscn        # vestibule, leg A, bend, leg C
      junction_spur.tscn         # junction + spur + galley stub
      galley.tscn
      annex_ring.tscn            # donut corridor
      cafeteria.tscn
      berth_wing.tscn            # hall, cabins, crawl, ossuary
      processor_wing.tscn        # hall + feed chamber
  actors/
    player.tscn
    drone.tscn
    host.tscn
    stalker.tscn
    collector.tscn
    processor.tscn
  ui/
    hud.tscn
    scanner.tscn
    map_view.tscn
assets/
  materials/*.tres               # shared palette, inspector-editable
src/
  level/
    level.gd                     # composition root controller
    ship_refs.gd                 # resolves anchors/groups, exposes the old API
    hide_spot.gd, ambush_spot.gd, choke.gd, loud_door.gd, interactable.gd
  build/
    geo.gd                       # only for runtime props after the bake
tools/
  bake_level.gd                  # one-time migration: builder -> .tscn
  dump_level.gd                  # parity snapshot before/after bake
  run_tests.sh
tests/
  util.gd                        # check / wait / drive_to / load helpers
  scene_integrity.gd             # new suite
```

### Principles
- **Static geometry is authored data, not code.** Runtime code never creates
  walls, floors, lights or dressing.
- **One source of truth per datum.** Positions live in `Marker3D` nodes; lists
  live in groups; tuning lives in `@export` vars. No mirrored constants.
- **Controllers stay thin.** `level.gd` and `ship_refs.gd` expose the same
  property names `main.gd` already uses (`dock_pos`, `PROCESSOR_PILE`, ...), so
  the migration does not ripple through gameplay code.
- **Gameplay-created nodes stay runtime**: loss wrecks, collected remains,
  Collector deposits, Processor feeding, sliding doors, flicker, drone spawns,
  live feed.
- **No gameplay changes during the refactor.** Every phase must keep the 370
  checks green and the visual result identical.

### Why bake first, not hand-author
Re-authoring 403 nodes by hand is slower, error-prone, and has no upside: the
existing builder already encodes exact positions, openings and collision. A
one-time bake produces an editable baseline that is guaranteed to match, then
the scene is split into rooms. The builders are deleted only after parity is
proven.

### Why not `@tool` scripts
A `@tool` builder shows geometry in the editor but still cannot be dragged or
inspected; it keeps code as the source of truth. It is useful as a temporary
bridge, not the destination.

---

## 3. Phases

Each phase is a branch and a self-contained PR-sized change. Order matters:
never start a phase with a red suite.

### Phase 0 — Baseline and guardrails (0.5 day)
- Branch `refactor/editor-level`; tag `pre-editor-refactor`.
- Add `tools/run_tests.sh` that runs all eight suites headless and prints
  per-suite and total counts, failing on any `FAIL:`.
- Fix `project.godot` features `4.4` → `4.7`; open once in the 4.7 editor and
  confirm no import errors. Commit `.uid` files.
- Add this plan; record the baseline counts in it.
- **Acceptance:** clean clone → `tools/run_tests.sh` → 370/370; project opens
  in the 4.7 editor without dialogs or parse errors.

### Phase 1 — Materials and shared geometry helpers (1 day)
- Convert `src/mats.gd` from cached runtime objects to a small static accessor
  over `assets/materials/*.tres` (deck, wall, ceil, hull, machine, cable,
  bone, flesh, screen_off, amber, ...). Keep the public function names.
- Extract `_box`, `_cyl`, `_light`, `_run` into `src/build/geo.gd` and have
  both builders call it.
- **Acceptance:** 370/370; node counts and screenshots unchanged; each
  material exists once as a `.tres` file.

### Phase 2 — Bake the static level into scenes (1–2 days)
- `tools/bake_level.gd` (EditorScript) instantiates each builder, recursively
  sets `owner`, externalises materials, names nodes by function where cheap,
  and saves:
  - `scenes/level/rooms/fab_bay.tscn`
  - `scenes/level/ship.tscn` (temporary single scene; split in Phase 4)
- `tools/dump_level.gd` writes a JSON parity snapshot (node path, class,
  position, rotation, size/radius, material key, collision flag) from the
  builder *before* the bake and from the packed scene *after*.
- Turn `src/hub/fab_bay.gd` and `src/ship/beyond.gd` into thin controllers:
  constants, `@export` `NodePath` refs, `_process` flicker, door state,
  wreck/remains/deposit nodes, and the anchors API. No geometry creation.
- `main.gd` preloads and instances the scenes; `ship.build()` disappears.
- Tests `collector_ai` and `processor_ai` load the scene instead of building.
- **Acceptance:** parity diff empty; 370/370; headless boot clean; F5 runs;
  the level is visible, selectable and editable in the editor; no builder call
  remains in `main.gd`.

### Phase 3 — Anchors and data out of code (1–2 days)
Replace every gameplay constant/array with editor-owned data:

| Old | New |
|---|---|
| `ship.dock_pos` | `Anchors/Dock` Marker3D; `ship_refs.dock_pos` |
| `FabBay.player_start` | `Anchors/PlayerStart` |
| `CAMERA_POS` | `Anchors/CameraSite` |
| `GALLEY_DOOR_POS`, `FOOD_POS` | `Anchors/GalleyDoor`, `Anchors/Food` |
| `PROCESSOR_POS / _PILE / _DROP` | `Anchors/Processor*` |
| `COLLECTOR_DEPOSIT` | `Anchors/CollectorDeposit` |
| `hide_spots` | group `hide_spot`, `hide_spot.gd` with `@export half: Vector3` |
| `ambush_spots` | group `ambush_spot` |
| `chokes` | `choke.gd` with exported footprint |
| `remains` | group `remains` (scene nodes, `taken` state runtime) |
| `loud_doors` | `loud_door.gd` nodes with exported span/speed/noise |
| `Callable` interactables | `interactable.gd` with `@export id`, signal `interacted(id)` |

`ship_refs.gd` resolves the anchors in `_ready()` and exposes the **same
property names** as the old builder, so `main.gd`, `collector.gd`,
`processor.gd` and the tests change minimally.
- **Acceptance:** 370/370; moving a marker in the editor moves the gameplay
  effect; no duplicate coordinate literal remains in `src/`.

### Phase 4 — Split the ship into room scenes (2–3 days)
- Cut the baked ship along room seams into the eight room scenes in §2.
- `level.tscn` instances them at identity (they are already world-space) or
  re-bases each room to a local origin — choose identity first; it keeps the
  parity diff trivial. Re-basing is a later cosmetic pass.
- Replace the single global floor collider with one floor collider per room
  (flush at `y = 0`, non-overlapping) or keep a `Level/Floor` static body.
  Recommendation: per-room, so rooms are self-contained prefabs.
- **Acceptance:** parity diff empty; 370/370 including `annex_loop` (real
  driving); each room scene opens and F6-runs in isolation.

### Phase 5 — Actors and UI as scenes (3–5 days)
- `player.tscn` (body, shape, camera, script), `drone.tscn`,
  `host.tscn`, `stalker.tscn`, `collector.tscn`, `processor.tscn`.
- Move model construction out of `_ready()` into scene children; move tuning
  that a designer would touch into `@export` (speeds, ranges, timings).
- `ui/hud.tscn`, `ui/scanner.tscn`, `ui/map_view.tscn` with scripts driving
  state. Keep the same public methods so `main.gd` is unchanged where possible.
- **Acceptance:** 370/370; every actor and the HUD can be opened, previewed
  and tuned in the editor; no visual regression.

### Phase 6 — `main.gd` decomposition and host DRY (2–3 days)
- Split `main.gd` into focused nodes/scripts:
  - `fleet.gd` — drones, deploy/swap/reel, cradles, link transfer
  - `sortie.gd` — piloting lifecycle, leave/teardown/reel
  - `objectives.gd` — act stages, cargo, module recovery
  - `feed.gd` — live feed viewport, grain/static, photography
  - `main.gd` — orchestration and wiring only (target < 400 lines)
- Extract shared host code into `host_base.gd` (sight ray, cone/FOV test, stuck
  detection, drone binding, noise filter). Keep Stalker/Collector/Processor
  behaviour in their own scripts; no forced shared state machine.
- Move tuning constants to `@export` or a single `src/config.gd`; delete dead
  constants.
- **Acceptance:** 370/370; no behaviour change; `main.gd` under 400 lines.

### Phase 7 — Test and quality infrastructure (1–2 days)
- `tests/util.gd`: `check`, `wait`, `drive_to`, `load_level`, `spawn_bot`.
- Split `tests/autotest.gd` (934 lines) into domain suites or at least helpers
  plus section files, keeping the same coverage.
- New `tests/scene_integrity.gd`: every anchor exists, node names unique,
  collision layers/masks match the contract, no missing scripts, floor is
  continuous, interactables have ids, groups non-empty.
- Optional: `gdtoolkit` (`gdformat` + `gdlint`) via `tools/lint.sh`.
- **Acceptance:** ≥370 checks (old + new) green; a broken scene fails with a
  clear message before gameplay tests run.

### Phase 8 — Docs and handoff (0.5 day)
- `docs/editor-guide.md`: open project, open `level.tscn`, room map, how to add
  a room/prop, how to move an anchor, how to run tests, how to bake.
- Update `README.md` architecture section and test counts.
- **Acceptance:** a new contributor can add a prop and a marker without
  reading `main.gd`.

---

## 4. What stays in code (explicit non-goals)

Do **not** move these into scenes as static data:

- Drone spawn/deploy, fleet link transfer, battery, tether.
- Loss wreck spawn and module recovery.
- Collector deposits, Processor feeding, caught-bot handling.
- Runtime door sliding, flicker, emergency pulse.
- Remains disappearing when collected (scene node, runtime `visible`).
- Live feed `SubViewport`, still camera, grain/static.
- Act/objective state, HUD meters, map inking.

Also out of scope: gameplay changes, new art, Act 2/3 content, renderer
changes, engine upgrade beyond the 4.7 metadata fix, and netcode.

---

## 5. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| CSG editor becomes slow with 403 nodes | Medium | Split per room; keep decorative slabs `use_collision=false`; later bake CSG to `MeshInstance3D` if needed |
| Material subresources duplicate in packed scenes | High if skipped | Phase 1 externalises all materials to `.tres` before baking |
| Behaviour drift from data moving to markers | Medium | JSON parity dump + existing 370 checks + new integrity suite |
| Test paths break when `build()` is removed | Certain if unplanned | Phase 2 updates `collector_ai`/`processor_ai` and adds `load_level` helper |
| Refactor breaks the M6 playtest baseline | Medium | Branch + tag; no gameplay edits in refactor commits; playtest after Phase 4 |
| `4.4` → `4.7` metadata change triggers reimport issues | Low | Do it in Phase 0, commit `.uid`, run suites before anything else |
| HUD/scene conversion scope creep | Medium | Phase 5 is explicitly last-before-DRY and can ship alone |
| Node paths in tests become brittle | Medium | Tests use groups/anchors and unique names, not deep paths |

---

## 6. Definition of done

- [ ] Opening the project shows a real, navigable level tree.
- [ ] `scenes/level/level.tscn` and every room open in the editor; F6 works.
- [ ] F5 runs the game with no runtime geometry construction.
- [ ] Level positions, prop placement, lighting and collision are editable.
- [ ] Gameplay references resolve through markers/groups, not mirrored consts.
- [ ] Materials are shared `.tres` assets.
- [ ] Actors and HUD are scenes; tuning is inspector-editable.
- [ ] `main.gd` is orchestration only (< 400 lines).
- [ ] All original checks still pass, plus scene-integrity checks.
- [ ] `docs/editor-guide.md` explains the workflow.

---

## 7. Recommended first slice

1. **Phase 0 + 1** — branch, test runner, version fix, material palette, shared
   geo helpers. One session; no visible change.
2. **Phase 2** — bake and switch `main.gd`/tests to scenes. One to two sessions.
3. **Stop and validate in the editor**: open the level, move a light, F5, run
   the suites. This is the moment the project becomes editor-first.
4. Then Phase 3 (anchors), Phase 4 (room split), and continue.

The earliest point at which the level is genuinely editable is the end of
Phase 2. The earliest point at which it is *pleasant* to edit is the end of
Phase 4.

---

## 8. Verification commands

```sh
# all suites
tools/run_tests.sh

# one suite
godot --headless --path . res://tests/autotest.tscn

# editor
godot --editor --path .

# parity snapshot
godot --headless --path . --script res://tools/dump_level.gd
```
