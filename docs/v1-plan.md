# UMBILICAL — v1 Plan (Vertical Slice)

First-person industrial horror. You are a silent survivor barricaded in a derelict
ship's fabrication bay after an infestation takes the crew. You can never leave —
the biomass hunts anything organic that moves. You pilot remote drones through the
ship with almost no vision, scrounging salvaged parts and supplies, always on the
limit of what you can do.

Working title: **UMBILICAL** (placeholder).

## What v1 is

A vertical slice covering the **Act 1 authored beat**, end to end:

1. **Radar sortie** — pilot a tetherless-recovery drone using the ship map plus
   a large movement scanner. Retrieve food from the galley cold room. Before
   the upgrade, the drone's only camera is a single still.
2. **Salvage** — discover a wrecked maintenance drone holding an intact **video
   module**. Return it to the fabricator and rack it.
3. **Stills, then live video** — every drone carries a still-image camera from
   the first launch: one grainy black-and-white exposure at a time, slow
   recharge. Racking the recovered video module wakes its decoder, and later
   sorties fly on the live drone feed with the radar reduced to a compact
   inset. Lose the module and the feed goes with it — back to stills until you
   recover and refit it. The ship looks different in fragments, then all at
   once.
4. **The loss** — the first sortie carrying the video module ends with the
   drone destroyed by a host. End of slice. The wreck (and the module) stay
   where they fell; the recovery attempt is the emotional payoff.

**Out of scope for v1** (explicit cuts):
- Fabrication/crafting depth (the fabricator exists, but only racks the video
  module and repairs cosmetics/trivial parts).
- Multiple drone chassis, tool arms, sonar shader, motion sensors, bait drones.
- Acts 2 and 3 (finale, plan board, on-foot escape run).
- Monsters beyond **one host AI** with one behavior family (patrol / curious /
  hunt / stalk). No visual detail — silhouettes and audio only.

## Success criteria (the "is it scary" gate)

- A radar drone sortie through an empty corridor is *tense with zero monsters*.
- The black lens between photographs makes you slow down; you dread the
  exposure gap and the slow shutter recharge. The still reads as a photograph,
  not a stuttering video feed.
- After the salvage, the live feed feels like a hard-won upgrade — not a
  different game — and losing it in the authored interception hurts because
  you remember what it was like to see.
- Losing the video module at the end of the beat hurts **and** makes the player
  want to go back out immediately, without believing they have gone blind.
- Playtesters, unprompted, describe the map and radar as "the ship" — not UI.

If any of those fail, we retune *this slice* before building anything else.

## Engine & structure

Godot **4.4, Forward Plus** (match hallway-demo conventions).

```
umbilical/
  project.godot
  scenes/
    main.tscn            root: holds ship, player, GameState wiring
    ship/                one scene per compartment (graybox)
    drone/drone.tscn
    hosts/host.tscn
    props/               interactables: chair, fabricator, map table, crates
  src/
    autoload/            game_state.gd, noise.gd, sfx.gd
    player/              player.gd, fp_controller.gd
    drone/               drone.gd, drone_camera.gd
    host/                host_ai.gd, perception.gd
    ui/                  map_table.gd, scanner_crt.gd, sortie_hud.gd
    interact/            interactable.gd, interact_ray.gd
  assets/
    audio/kenney/        same pipeline as previous projects
    fonts/
  docs/                  this file, beat script, tuning notes
  tools/                 (reuse infini-burbs conventions for test scripts)
```

Autoloads:
- **`GameState`** — act state, life-support meters (O2/water/food), sortie state
  (IDLE / PILOTING / REVIEW), inventory of salvaged parts, run timer. Single
  source of truth; scenes read from it, never cache it.
- **`NoiseBus`** (event bus) — the whole perception model lives here:
  `emit_noise(position: Vector3, loudness: float, source: Object)`. Player
  footsteps, drone motors, sonar pings (future), door cycling, impacts —
  everything posts here. Hosts subscribe and ignore events whose source is
  another host. No host reads the player's position directly, ever.
  (Named `NoiseBus`, not `Noise`: `Noise` is a native Godot class.)
- **`Sfx`** — reuse the hallway-demo pattern (one-shot helper with 3D variant).

Input map: reuse hallway-demo's first-person set (WASD + interact), add drone
pilot set (`pilot_*` actions bound to the same keys but gated by sortie state).

## The two first-person bodies (core tech)

The player's camera and the drone's camera are the two pillars. Both exist from
M1 onward; every episode alternates which one "you" are.

### Player body (hub only in v1)
- `CharacterBody3D` + capsule + camera, slow walk speed (~2.2 m/s), stiff head
  bob, heavy footstep noise (posts to `Noise`).
- Fab bay is small: pilot chair, fabricator, map table, supply lockers, the
  barricaded exterior door, one interior hatch.

### Drone body (sorties)
- Separate `CharacterBody3D`, heavy: slow accel/decel, wide turn rate, small
  collision shapes for scraping audio triggers.
- **The fleet:** a sortie starts with one chassis on the hatch cradle. `B`
  deploys another at a time (up to `DRONE_FLEET = 2`), on the next clear
  cradle and with the link moved to it. Cradles are on the ship side of the
  sealed bay wall (the bay is the player's safe room); they extend deeper into
  the corridor, never into the bay. `drone` is the linked bot; `drones[]` holds
  the rest. Only the linked chassis drains battery and takes input. `Q` cycles
  the link, `1`/`2` select directly. Parked bots hold position, heading, charge
  and cargo; `main._cargo` mirrors the linked bot's slot and swaps on transfer.
  Each bot has its own LED identity (`configure_bot`).
- **Control handoff:** entering the pilot chair → `GameState.sortie = PILOTING`;
  player controller disabled, linked drone controller enabled. Standing up (E)
  leaves the fleet parked in place; re-entering resumes the same link,
  positions, charge and cargo. R recalls the whole fleet. With the video module
  racked, the main viewport hands off to `drone.cam` (`drone.live_view = true`);
  without it, the player's camera stays current behind the black still-camera
  lens.
- **Loss:** a caught chassis is destroyed where it stands; the link hops to a
  surviving bot and the sortie continues. A dry battery recalls the whole
  fleet. Only an empty fleet ends the sortie. Module loss stays with the
  chassis that carried it.
- **The still-image optic (standard kit, M3):**
  - Drone world rendered in a dedicated `SubViewport` (480×270). Before the
    salvage the main view stays blacked out; the still is the only picture.
  - Update mode `UPDATE_ONCE`: exactly one frame per photograph. Between
    exposures the lens is black. The drone keeps moving while the print holds.
  - Fullscreen post ColorRect shader: grayscale, hard black toe, blown
    highlights, heavy **frozen** grain (no `TIME` term, so it reads as a
    photograph), vignette, signal-scaled static.
  - Slow shutter recharge meter on the left edge; photograph on **LMB / F**.
    The still camera stays available even after live video is online.
- **The video module (salvage, live feed):** the wrecked drone in the east spur
  carries a video camera module. Recovered and racked at the fabricator, its
  decoder wakes and the next sortie flies on the live drone camera; the radar
  shrinks to an inset. `main._live_feed_active()` gates the handoff on
  `VIDEO_FEED_ENABLED and _camera_installed`, so losing the module in the
  authored interception (or to any later loss) puts the drones back on stills
  until it is recovered and refitted.
  - The live picture runs through `LIVE_SHADER_SRC`: the still print's hard
    toe/shoulder curve, quantised to 480×270, with animated grain, scanlines,
    horizontal tearing, ghosting and block corruption. `hud.set_live_stress()`
    feeds it drive speed and signed steering every frame; parked is grainy but
    stable, turning drags the ghost sideways, speed adds noise and roll.
  - The tube lives on its own `CanvasLayer` (layer 4) below the HUD: screen-
    texture shaders render in a separate pass, so this is what keeps the radar
    inset and labels above the picture.
  - Proximity poison: `main` computes `dread` from drone-to-stalker distance
    (zero at 9 m, rising steeply inside it) and calls `hud.set_live_dread()`.
    The shader adds tears, ghosting, a rolling white band and a final wash
    toward snow, so the stalker stays unseen as it closes.
- **Signal integrity:** feed squelch/static scales with distance from the fab
  bay antenna + hull damage. At zero integrity: static-only. This replaces any
  "you can see the whole ship" cheat.

### Movement scanner (primary display, M2)
- 2D CRT-styled control shown large at the pilot station while piloting — it
  takes most of the screen until the video module is fitted, then shrinks to a
  compact top-right inset so it keeps charting beside the live feed.
- Sweep-line radar, north-up and world-anchored: as the drone drives, the ship
  assembled from wall echoes stays put. Echoes decay (~20 s) and each return is
  charted permanently onto the map.
- Noise events (hosts, doors, impacts) appear as short-lived bright blips at
  last-known position. The radar reports *that something moved and roughly
  where*, never *what*.

### Map (M2)
- Diegetic paper map plane on the map table + a `map_table.gd` overlay the
  player can enlarge (tab). Pre-printed ship outline with compartment names;
  the player's *annotations* are earned (objective markers added when sorties
  reveal them). No live player/drone dot beyond last-known scanner data.

## Host AI (one body, one brain — M4)

- `CharacterBody3D`; the current pass uses authored waypoint routes with a
  stuck detector rather than a baked navigation mesh. The single junction
  patroller's route runs the full east-annex donut and cuts through the
  cafeteria. The route is kept legal for straight-line seek and proven by the
  patrol soak. The galley is deliberately empty; two silhouettes in the
  opening rooms made the game a waiting game rather than a scare.
- States: **PATROL** (waypoints, slow), **CURIOUS** (one noise: stop, remember
  roughly where it was, listen — no approach), **HUNT** (a second noise: walk
  slowly toward an imprecise memory of the sound, pausing to listen), **STALK**
  (direct sight: follow at a distance and keep line of sight).
- Perception: `NoiseBus` events plus a 10 m sight cone with a world raycast.
  **Sight requires motion:** a drone that is not rolling is invisible at every
  range — there is no close-range sight exception. Movement re-acquires it
  instantly. A still drone can only be killed by contact if the host was
  already on top of it. Hosts are source-tagged and deaf to each other.
- Escapability rules: a single quiet noise only buys curiosity; freezing ends
  the encounter. Stopping (or breaking line of sight around a corner) makes a
  stalk decay into a short search of the last place the drone was seen moving,
  then patrol. A loud event (≥ 0.7) skips the listening phase and starts a hunt
  immediately.
- The primary stalker is a separate **second hunting body** (`src/host/stalker.gd`).
  `main` spawns it far away in the annex north ring once the drone enters the
  junction, and it persists across sorties. Its AI states are **PATROL** (annex
  route), **INVESTIGATE** (noise: head for the direction, not the exact point),
  **SEARCH**, **CHASE** (any player drone in sight, immediately), **LURK**,
  **LUNGE**, **AMBUSH_SETUP** and **AMBUSH**. It kills on contact. Low tables
  are true cover: a drone inside a `hide_spots` footprint is invisible to sight
  (but still audible). Breaking sight makes it search in the direction it last
  saw. It reads on radar as a broad moving mass (`radar_mass` in `scanner`,
  `radar_blips = false`) and its voice is a single long sub-bass hum
  (`stalker_hum`) with no footsteps.
- The live-feed scare: while `feed_active` (the recovered video module is
  online) and the stalker is already behind the drone, a sight acquisition has
  a `LURK_CHANCE` (25%) of becoming a **LURK** instead of a chase. It shadows
  the drone at `LURK_DIST` (3.2 m), out of the forward camera. Turning the
  camera toward it (dot > `LUNGE_DOT`) emits `lunge_started`, which triggers the
  red flash, static lock and stinger, and the stalker charges at `W_LUNGE`
  (7 m/s) to kill.
- The trap: on a cooldown while patrolling, it may pick an `ambush_spots` corner
  that is outside the drone's current view, near enough (4–14 m) to matter, and
  creep there (`AMBUSH_SETUP`). It folds low in the corner (`AMBUSH`): hips at
  ~0.56 m, head at drone height, eyes shrunk to shut sockets, core hidden,
  hum nearly silent and radar mass at 30%. If the drone drives within
  `AMBUSH_TRIGGER` (3.2 m) in its front hemisphere, it springs with
  `lunge_started`: eyes scale wide, the body stays low and pounces face-first,
  and the red flash/stinger fires. If the drone looks at it during set-up, it
  abandons the trap and chases.
- Visual: the ordinary host is a dark humanoid silhouette. The stalker is
  a fully modelled hunched skeleton in `stalker.gd._build_body`: dark elongated
  trunk, pale bone ribs/spines/skull, black maw, amber eye points and chest
  core, long two-jointed clawed arms and bent legs. It is animated
  procedurally (gait, reach, head tracking, lunge lean) in `_animate`.

## The Collector (third body, scavenger — M6b)

- `src/host/collector.gd` is a scavenger, not another hunter. It walks an
  authored legal loop around the east annex, the berth wing and the Processor
  hall — never the bay, starting corridor or junction — picks up any un-taken
  `ship.remains` within 1.15 m, carries up to four parts in a visible drag
  sack, and deposits them at `beyond.PROCESSOR_PILE` / `ship.processor_pile`.
  Each deposit grows the feeding pile in front of the Processor, and the
  starting rooms stay free of it.
- It has no sight, no hearing, no drone link and no kill signal. It is in the
  `hosts` group only so the other bodies' source filter ignores it. It makes
  no radar blips and is not a radar mass: you find it by seeing the lantern,
  not by tracking it.
- If its loop crosses a live chassis, it picks the bot up instead of killing
  it. `drone.carried` freezes self-movement and battery drain but leaves the
  link and camera live, so the player can watch the whole ride through the
  feed. It sets the bot down at `beyond.PROCESSOR_DROP`, at the edge of the
  Processor's reach, then keeps walking. The nest at `COLLECTOR_DEPOSIT`
  remains its home and first/last route point; only the deposit target moved.
- Its body is graybox primitives like the rest: a small hunched pale figure,
  short bent legs, a low lantern in one hand, and the sack on its back. It is
  animated procedurally; the sack is only visible while it is carrying.

## The Processor (fourth body, pinned — M6c)

- `src/host/processor.gd` is the last body: a giant mouth on two legs, pinned
  to the deck at `beyond.PROCESSOR_POS` at the end of a long, almost unlit
  east hall. It never walks, never patrols, never hears, and makes no radar
  blip. Two telescoping gaunt arms end in cube hands; one picks body parts off
  the pile and feeds them into the maw, the other reaches for the player.
- Perception is motion-only, like the ordinary host's sight rule: range, a
  wide 145° frontal cone, a clear ray, and `MOVE_THRESH = 0.30`. A still
  chassis is invisible even at its feet; a carried chassis is ignored.
- A moving chassis in the chamber starts a ~1.05 s telegraph (mouth opens,
  low thud), then the hand reaches at limited speed with a 3.5 m maximum
  extension. Inside the grab radius the bot is caught and drawn into the
  mouth; `drone_caught` hands it to main's normal fleet-loss path. Beyond the
  reach the same telegraph is survivable: drive west down the hall.
- The feeding pile is the Collector's deposit node: deposit bones are parented
  to it, and the Processor consumes one visible child at a time on a timed
  cycle. It is deliberately not a scanner mass; the chamber is the warning.

## Processor wing (M6c)

East of the berth hall, behind the sealed bay wall, a 7 x 2.6 m service hall
opens into a feed chamber. The hall is empty except for a dead fixture, a low
amber guide line and the Collector's route; the chamber holds the pile, the
drop mark, old feed stains and the pinned body. The floor collider extends to
x = 35 so the wing is drivable, and the pile sits ~32 m from the dock — inside
the 36 m tether, so a dropped bot can drive home.

## Berth wing (M6b)

South of the annex south ring, a short service wing: two normal link mouths,
a 1.0 m-high crawl between them, a hall, three small cabins with lofted bunks
and loud sliding doors, and the Collector's ossuary. The bunks are true
`hide_spots` (drive underneath; the tall bodies cannot). The crawl and the
fallen locker in the west link are **height gates**: the drone fits, a
1.6–1.8 m capsule does not. `beyond.chokes` publishes each gate with two
routing points; the stalker's `_nav_target()` detours through the east link
when pursuit crosses one, then resumes direct pursuit. The doors post a hard
`NoiseBus` event when they open (bang + grind), so entering a cabin is a
decision the annex can hear.

## Ship (one deck, four states)

A single deck: Fab Bay → Workshop Connector → Hydro Junction (hub) → Galley +
Cold Room, the Hydro Spur / salvage site (video-module wreck), and the **east
annex** — a donut service corridor wrapped around a gutted crew cafeteria. The
annex has two mouths into the junction (the old spur opening and a west-ring
opening), so it can be circled or cut through via the cafeteria's four arches.
South of the south ring is the **berth wing**: a hall, three small cabins with
lofted bunks and loud doors, a drone-only service crawl, a fallen locker, and
the Collector's ossuary. East of that hall is the **Processor wing**: a long
dark corridor ending in the feed chamber where the Collector piles crew
remains in front of the pinned mouth. It gives the ship's bodies somewhere to
be other than the room you are in: the patroller owns the whole donut, the
stalker spawns in the far north ring, and the Collector circles the annex,
berth and Processor hall. The opening bay, corridor and junction belong to the
player alone. The far annex corner is ~34 m from the dock, inside the 36 m
tether; the Processor pile is ~32 m. Graybox: CSG/MeshInstance
industrial kit, dark materials, sparse practical lights (most corridors unlit —
which also forgives low detail).

Act state = configuration, not new geometry:
- **Pre-sortie:** doors locked except the sortie target; growth absent.
- **Per sortie:** which hatches the drone can open is data-driven per mission.
- Act-state helper script toggles door locks, prop dressing, host spawn points.

## Milestones (solo pace, ~1–2 weeks each; the slice is ~8–10 weeks)

**M0 — Shell (week 1).** Project skeleton, `project.godot` (4.4/Forward+),
autoloads stubbed, input map, ship graybox deck, player controller + interact
ray (E), pilot chair interactable, walk-around fab bay. Sounds: Kenney assets.
*Done when:* walking the bay feels heavy and quiet.

**M1 — Radar piloting (week 2–3).** Drone body, control handoff at the chair,
heavy physics, tether reel (counter + mild drag), collision scrape audio, map
table + scanner CRT v1, sortie state machine with launch/static-cut/return.
*Done when:* a radar drone sortie through an empty corridor is tense. **This is
the thesis gate — retune here before any monster work.**

**M2 — Sortie structure (week 4).** Objectives (food pickup in the cold room),
supply meters ticking in real time while piloting, return/loss resolution, one
host on the full PATROL/CURIOUS/HUNT/STALK ladder reacting to `Noise` only
(no mesh polish yet).
*Done when:* the food run is winnable, losable, and scary-by-audio alone.

**M3 — Still-image camera (week 5).** SubViewport still capture + post stack +
signal-static rule + slow shutter recharge. The still camera is fitted from the
first launch; there is no optics install gate. Test corridor: something crosses
while the print is held, in a scripted test only, to verify the effect lands
(then remove it).
*Done when:* the black lens between photographs makes you slow down, and the
print reads as a photograph rather than a frozen video frame.

**M4 — Authored beat (week 6–7).** The Act 1 sequence as data/script:
1) radar food sortie (first host heard, not met),
2) east spur reveals the wrecked drone + intact **video module** (carry-back
   mechanic: drone inventory + drag weight),
3) rack the module at the fabricator (short in-fiction sequence; the decoder
   wakes and the next sortie gets the live feed),
4) first sortie carrying the video module; the primary stalker is held back
   until the drone leaves the initial hallway and enters the junction,
5) host contact — drone destroyed; link cut to black; end card. The wreck is
   visual-only (never blocks a lane) and the module stays where it fell;
   recovery is a real decision.
Implement the full patrol / directional-investigate / immediate-chase /
last-seen-direction search, low-table cover and the live-feed lurk/lunge. The
stalker is a modelled skeletal horror and persists after the first spawn. No scripted cutscenes — everything emerges from systems plus a couple of
gated triggers.
*Done when:* a fresh playtester loses the video module and says some version of
"wait, can I go back for it?"

**M5 — Audio + polish pass (week 8).** The real horror budget: hull-borne
transmission (bus with heavy lowpass + distance muffle for all host sounds),
sensor ticks, drone motor loops that change with load, a grain/static revisit
on the photographs, map annotation polish.
*Done when:* sound alone communicates host proximity within ~3 rooms.

**M6 — Playtest gate (week 9–10).** 5 fresh players, watch silently, collect:
where they get lost, where they get bored, whether they try going back for the
video module, and whether the radar + stills read as "dreadful" rather than
"broken". Fix the top 5 issues.
*Done when:* the success-criteria list at the top passes. Ship the slice as the
itch.io "first transmission" build if it holds up.

## Technical risk register

| Risk | Mitigation |
|---|---|
| SubViewport still-capture perf/compat spikes | `UPDATE_ONCE` is cheap (one render per photograph); fallback = one-shot main-camera RT. Decide in M3 spike, not sooner. |
| Navigation mesh through many doors | Navmesh per-act baked with door-link points; hosts re-path via `NavigationAgent3D` only through unlocked doors. |
| Host drifting through graybox gaps | Ship deck is one welded traversal set; run a "host jail" autotest (reuse hallway-demo's autotest pattern) that walks patrol routes nightly. |
| Radar navigation being *unfair* instead of *dreadful* | Radar echoes + noise blips + map annotations + audio landmarks (each compartment gets a signature ambient hum). Test with strangers early (M1 gate). |
| Scope creep (the finale is tempting) | The M6 gate is a wall. Acts 2–3 wait for a passed gate. |

## Reference / tone notes for build sessions

- Camera feel: Iron Lung photography; *Alien: Isolation* (1990s CRT post);
  still prints, not found footage — frame-hold, no smoothing, frozen grain.
- Audio: submarine/hull films — The Abyss, Das Boot distant clangs; wet infested
  ship = Event Horizon galley… mostly: *Things We Heard in the Dark* — keep
  monster sounds organic, non-verbal, and almost always *distant*.
- Rule of thumb on screen: sensors answer "when/where did something move",
  never "what/where is the monster".
