# UMBILICAL — vertical slice (M0–M8, east annex + berth + Processor wing + Cold Hold + engine room)

First-person industrial horror. You survive inside a sealed fabrication bay on
an infested ship; you cannot leave, and the things outside hunt anything that
moves. You pilot remote drones built from salvage to scrounge what you need.

**PSX Look is on by default.** The 3D world is drawn at 240 lines with 15-bit
dithered colour, vertex snap and affine textures, while the HUD, map and
options stay crisp. Press **F5** (or use the title/pause screen's **PSX LOOK**
button) to change resolution, dither, snap, affine, fog, draw distance,
texture depth, density and all thirteen presets live. Scanlines are off and not
exposed. The master switch restores the authored look exactly. See
`docs/psx-look.md`; the material showcase lab is
`godot --path . res://scenes/dev/psx_lab.tscn`.

**Current build — radar + stills, then live video after the salvage** (see `docs/v1-plan.md`):
- The fab bay hub (M0): walk it, read it, hear the hull knock.
- **Drones v1 start blind to live video.** The pilot screen is a small desktop
  built around one large **optics** window — a black still-camera lens until
  the video module — with a small **radar** instrument beside it. Primary mouse
  (or **F**) exposes one crude photograph in the optics window only: heavy
  grain, crushed blacks, violent contrast, hard to read. The print holds
  ~2.2 s, then the mechanism needs a **slow 5 s recharge** (shutter bar; green
  pip = ready). The radar stays up and keeps charting through every exposure.
- **The salvage in the east spur is the video camera module.** Racking it at
  the fabricator wakes the decoder: later sorties fly on the **live drone
  feed** in the large optics window, while the small radar keeps its own
  window and is never covered. The feed runs through the
  same grainy emulsion as the still — low-res, scanlined, and deliberately
  dirty; it is a little grainier than the print and **near-sighted**: the lens
  loses focus a few metres out, so distance and fine detail still want a still
  exposure. The drive distortion is deliberately restrained: steering smears
  and ghosts lightly, speed adds grain and a little tear, and a nearby hostile
  body adds a rolling band. It never gets fully clean, but distance from the
  winch no longer degrades it — only real story beats drop the signal into
  snow.
  Lose the module and the feed goes with it — you are back to stills until you
  recover and refit it. Every drone carries the still camera as standard kit,
  even with live video.
- **One link, a fleet of crawlers.** A sortie starts with one bot on the
  hatch cradle. Press `B` while piloting to deploy another, one at a time —
  it appears on the next clear cradle at the dock, and the link moves to it.
  Leave it in the field, deploy another, or `Q` cycle the link / `1` `2` select
  directly. The one you are flying is the only one that drains its battery and
  takes input; parked bots keep their own position, heading, charge and cargo.
  A caught bot is destroyed where it stands and the link hops to a survivor,
  so the sortie continues; a dry battery winches the whole fleet home blind.
  The winch (`R`) recalls the whole fleet and delivers every cargo slot at
  once.
- **Sight needs motion, and the ship starts empty.** The opening decks carry no
  hunters at all: the bay, corridor, junction, galley and annex are for
  learning the ship. A host only *sees* a drone it has seen move: stop rolling
  and the machine is invisible outside a short nose-to-nose radius. A quiet
  noise makes a host curious — it stops, remembers roughly where the sound came
  from, and listens; a second noise (or one very loud event) starts a slow,
  imprecise hunt. Break the ray or stop rolling and it searches the last place
  it saw motion, then gives up. Contact still kills. Hosts are deaf to each
  other. The zombie that runs you down and kills on contact is the plain
  **host**; the Cold Hold's bodies are **watchers** — the same brain, but on
  direct sight a watcher closes only to its ~7 m stand-off, plants and watches.
  A watcher never attacks: it takes a chassis only when the player drives into
  it, and it holds its ground when approached.
- **M7: Deck B — the Cold Hold.** Through the junction's north airlock, an
  eight-metre umbilical opens into a pitch-black hold that has roughly doubled
  in size: the original open floor still reads as one room, with a west hall
  and two side bays, plus a north hall and two small rooms beyond it. Two more
  relays chain off the entry relay so every new bay stays inside the 36 m
  tether drum — `MAX_TETHER` never changes. The first time the active
  drone crosses, four aggressive watchers wake at authored points 20+ m out:
  wider eyes (~21 m, 105°), a real memory, faster patrol/hunt/stalk speeds, and
  a long patience. They are watchers, not hunters: each closes to its ~7 m
  stand-off, plants and watches, and never attacks — the fail state is a
  contact the player drives into. They stay escapable: break line of sight,
  stop rolling outside the short still radius, and they search rather than
  track. Each owns a separate rectangular loop that avoids the west side of the
  room and the crawler hallway. The hold is genuinely dark (ambient and fog drop
  only while the active drone is inside), sparse hard cover is the only cover,
  and the lamp opens up just enough to read a body at the edge of its reach.
- **The Collector feeds itself, once.** The same first crossing sends the
  Collector to the Processor. It sets down anything it is carrying first, walks
  itself to the maw, and is consumed over ~3.6 s: the lantern gutters out, the
  sack drags, the wet crunch carries through the hull, and the Processor goes
  dormant for the rest of the session. The empty lantern and sack remain on the
  deck. Deck A is threat-free from then on.
- **The crawler in the side hall.** Off the Cold Hold's east edge, a dark
  3 x 17 m side corridor is now lit by a few weak amber practicals — just
  enough to draw you in and let you watch. A human survivor with no legs drags
  itself toward the lamp at 0.6–0.9 m/s, talking in a filtered, half-broken
  voice on the subtitle channel (and posting drag noise, so radar and stills
  both carry it). It never comes closer than ~2.6 m: a long alien arm yanks it
  back, fast, down the hall the way it came, through the opening at the far end,
  and the scream cuts off. A long smear trail and handprints remain. It cannot
  kill, be saved, or soft-lock the drone; if the drone leaves, it resolves at
  the authored grab mark. One shot per session.
- **Deck C — the engine room.** The far end of the crawler hall opens into a
  tall engine deck that has tripled in size: the core hall, two side wings with
  machine rooms, a north hall with two bays, and a second-floor gangway reached
  by a ramp at each side so a drone can cross the room above the core. A relay
  in the throat and a far relay in the north hall keep every wing inside the
  36 m drum; the scanner label changes to `ENGINE`. Unreliable practicals gutter
  through the new halls — the dark room and its connecting corridor now carry
  more of them too. The room's tenant is the **Stalker**: it starts folded into
  one wall niche, hunts slowly for a while, folds into a *different* corner,
  then hunts again. It stays near walls while hunting rather than cutting
  across the open floor. Low machinery pockets are still the counterplay — a
  still drone under a machine is invisible to its sight.
- **M5: hull-borne sound and the hand-copy map.** Positional audio routes
  through a lowpass "Hull" bus when a wall occludes the listener; hosts read
  as three-rooms-away. Motor pitch strains with load. **The map fills itself
  in:** every wall a drone's sweep touches is charted permanently (0.5 m
  grid) and hand-dotted onto the deck map — both the fullscreen map and the
  physical paper on the table in the middle of the bay, which redraws live.
- **The galley is a proper hall now** (12 x 10.4 m), and it is empty. The
  pressure door still grinds open when a drone gets close, but nothing waits
  behind it any more: the pantry sits at the far west end as a real traversal,
  not a doorway ambush. With the junction left threat-free, the opening rooms
  are quiet enough to read.
- **The east annex: a donut corridor around a gutted cafeteria.** Past the
  spur, the ship opens into a long service loop — north, east, south and
  west rings wrapped around a 13 x 10.8 m crew mess with four arches, long
  bolted-down tables, a dead serving line and a toppled table for cover. The
  loop has two mouths into the junction, so you can circle it or cut straight
  through the cafeteria. This is the "more ship" the survivors never mapped:
  the far corner is ~34 m from the dock, still inside the 36 m tether.
- **The berth wing: the crew's rooms.** South of the annex ring, a short hall
  opens into three small cabins with **lofted bunks** (drive under one and the
  tall bodies lose sight of you, exactly like the low tables) and **loud sliding
  doors**: the bang and grind of a door opening posts a hard noise event into
  the annex, so a room is never a quiet place to hide. The wing has two normal
  mouths into the ring and a **1.0 m service crawl** that only the drone fits
  through; the tall bodies route around via the east link. A locker torn off
  its mounts leans across the west link at chest height — another drone-only
  gap. At the east end is the **ossuary**, the Collector's original nest. The
  nest is a single constant (`beyond.COLLECTOR_DEPOSIT`) and a matching node,
  so it can be moved in one edit.
- **The Collector: the third body.** It is a scavenger, not a killer: a
  plodding figure in a work shirt with a lantern and a drag sack. It walks a
  long authored loop around the east annex, the berth wing and the Processor
  hall, picks up the crew remains scattered along it, and carries them to the
  feeding pile at the end of the new east hall. Its circuit deliberately avoids
  the bay, starting corridor and junction, so the opening rooms stay quiet. It
  never kills, is deaf to noise, and monsters ignore each other. If the player
  brings the walking body or the active chassis into view, it notices: its head
  turns to follow them from a long way out. Inside its spray range it stops,
  squares up and throws a harmless stand-in vomit; only if the player comes
  closer still does it leave the loop and shamble in to try the lift, and it
  only grabs at arm's length. The vomit never slows or stops the player and
  leaves nothing on the deck. Break away far enough and it gives up and
  returns to its route. A lifted chassis
  is not broken: it carries the bot with the link and camera still live (the
  player can watch the whole ride through the feed) and sets it down in front
  of the Processor. It shows up as work being done — evidence that something is
  cleaning the ship. On the first Deck B crossing it walks itself into the maw
  and is gone (see above).
- **The Processor: the last body.** East of the berth hall, a long, almost
  unlit service hall ends in a chamber where a **giant mouth on two legs** is
  pinned to the deck. It never walks. Two telescoping gaunt arms with cube
  hands reach down to the pile the Collector has built, pick up a body part,
  and feed it into the maw; the jaw works while it chews. It has no hearing,
  no patrol and no radar blip. It watches motion only: a still chassis is
  furniture, even at its feet. Drive inside the chamber and the mouth opens in
  a slow telegraph before the hand comes down; a bot caught by the hand is
  eaten, and the fleet link hops to a survivor. Drive clear of the hand's reach
  and the same telegraph is survivable. The Collector's drop mark sits at the
  edge of that reach, so a delivered bot has one chance to drive west down the
  hall. After the Deck B sacrifice the Processor is dormant for the rest of the
  session: the jaw hangs, the hands stop, and the wing is inert.

## Run

With **Godot 4.7+** installed:

	godot --path .

or open this folder in the Godot editor and press F5.

## Editing the level

The ship and the bay are real scenes, not runtime-generated geometry:

- `scenes/level/ship.tscn` — the ship, grouped into `Corridor`, `Junction`,
  `Spur`, `Galley`, `Annex`, `BerthWing`, `ProcessorWing`, `Zone2`,
  `EngineRoom`, `World` and `Data`.
- `scenes/level/rooms/fab_bay.tscn` — the safe room.
- `scenes/actors/*.tscn` — player, drone, host, watcher, collector, Processor,
  crawler and Stalker prefabs.
- `scenes/main.tscn` — entry point with the `WorldEnvironment`; the HUD and
  monster bodies are wired in code.

Open a level scene, move geometry and lights, and press F5. Placement that
gameplay depends on lives in `Data/Anchors` markers (dock, camera site,
flashlight, Processor pile, Collector deposit, …) and in `Data/HideSpot*`,
`AmbushSpot*`, `Choke*` markers. See `docs/editor-guide.md` for the node map,
the collision rules and how to add props or move gameplay.

## Controls

Walking the bay:  WASD move (A/D strafe) · SHIFT hurry · mouse look ·
E inspect · ESC pause · F3 debug · F4 debug vision · F5 PSX Look

In the pilot chair (sortie):  W/S drive · A/D turn (crawler steer) ·
SHIFT hurry · F / left click — take a photograph · L — toggle the fitted
flashlight · B deploy another bot (one at a time) · Q cycle bot · 1 / 2 select
a bot ·
R reel the whole fleet back in (only near the hatch dock) · E stand up (the
fleet parks where it is; E at the chair resumes the same link, same machines,
same charge) · ESC pause · F4 debug vision · F5 PSX Look

**F4 debug vision** is a developer toggle, not a progression unlock: any
chassis gets a clean full-colour live feed even without the video module, the
ship is lit for low-light reading (and the hold stops being pitch black), and
hostile bodies ignore the fleet. Press F4 again to restore the normal stills /
live-feed rules, lighting, and enemy perception.

Once the video module is racked, the large optics window carries the live
drone feed and the small radar keeps its own instrument window; F still
exposes a still frame in the optics window only.

If the Collector lifts the bot you are flying, the link and camera stay live:
watch the ride, then drive west down the hall as soon as it sets you down in
front of the Processor.

**Touchpad note (Linux laptops):** if mouse-look and clicks die while a key
is held, that's libinput's *disable-while-typing* palm rejection, not the
game. USB mice are unaffected. Fix per session/desktop:
`gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing false`
(GNOME) or `xinput set-prop <touchpad-id> "libinput Disable While Typing Enabled" 0`
(X11). F3 shows a live motion counter + capture state for quick checks, and
`UMBILICAL_INPUT_DEBUG=1` logs every mouse-motion event with its delta.

At the map table:  E opens the hand-copy map; E / ESC / click closes it.

At the fabricator:  E installs a recovered video module and/or the flashlight
add-on; the live feed wakes on the next sortie, and the fitted drones get a
narrow, sprung beam.

## First loop (radar + stills → video module → live feed)

1. **In the bay:** E at the pilot chair launches a sortie with one chassis.
   Press `B` while piloting to deploy a second at the dock, one at a time.
   Every other station is also usable: fabricator (north-east), map table
   (centre), lockers (east), barricade (west door), drone hatch (north wall).
2. **Radar drone:** before the module there is no live view. A large
   black-lens optics window fills the pilot desktop, with a small radar
   instrument beside it. Primary mouse / F exposes one grainy still in the
   optics window; the shutter then recharges slowly (5 s). The radar is never
   covered.
   Optionally retrieve the **flashlight add-on** from the cold-room shelf:
   west through the grinding galley door, then home to the hatch dock and press
   R to reel. Fit it at the fabricator to replace the weak omni glow with a
   narrow, spring-mounted beam that kicks as the bot starts, stops and turns.
   Press **L** to switch the beam off/on. The beam is real light: while it is
   on, watchers and the Stalker see the bot farther and even a parked drone is
   a beacon, so running dark is how you hide.
   `B` drops another bot at the dock; `Q` hops the link between deployed bots
   at any time; the parked one waits.
3. **Video module salvage:** from the junction, take the east opening into
   the spur (the west end of the annex's north ring). The dead drone is
   against the north wall; the amber **video camera module** lies on its near
   side. Close to within 1.2 m to take it, drive back to the dock, and press R
   to reel. The rest of the donut, the cafeteria, the berth wing and the
   Processor hall are optional exploration.
4. **Install:** walk to the fabricator in the bay's north-east corner and
   press E. The module is racked; the next sortie flies on the **live drone
   feed**, with the small radar still in its own window. The feed is
   near-sighted and a little grainier than a print. The still camera remains
   available, and a print replaces only the video window.
5. **Cross into Deck B.** With the module aboard, the junction's north airlock
   opens onto the umbilical and the Cold Hold. The first active-drone crossing
   wakes four aggressive watchers at the far side, consumes the Collector, and
   arms the crawler in the east side hall. The relay takes over the tether,
   the radar labels it `RELAY`, and Deck B gets its own inset on the map. There
   is no authored loss: a watcher will plant and watch rather than chase you
   down, but never drive into one — and remember it can see a parked chassis
   inside its short still radius. Come home if the feed starts to tear.
6. **Follow the amber lights into Deck C.** At the far end of the crawler side
   hall the wall is gone. The engine room's relay takes over (`ENGINE` on the
   scanner), the room is dark around a red-lit core, and the Stalker waits
   folded in a far corner. Use the low machinery pockets: drive under, stop
   moving, and let it search the last place it saw you. The engine relay is the
   new tether home.

## Build gates (from the plan)

- M0 done-when: walking the bay feels heavy and quiet.
- **M1 done-when:** a radar drone sortie through the empty corridors is tense
  with zero monsters. If it isn't, nothing after it matters.
- **M3 done-when:** the black lens between photographs makes you slow down;
  each print reads as evidence from a camera you don't trust, not video.
- **M2 done-when:** the flashlight run is a quiet, tense traversal — the grind
  of the galley door and the empty galley do the work; no junction ambush.
- **M7 done-when:** the first Cold Hold crossing spawns four watchers without an
  instant threshold kill, the Collector is visibly eaten exactly once, Deck A
  is thereafter threat-free and the Processor inert, and the relay/HUD/map
  carry the player through a dark, escapable hold. The module is never taken
  from the player by script.
- **Deck C done-when:** the crawler is visibly yanked back down a lit side hall
  into the engine-room opening, the engine relay keeps the room inside the
  tether, and its Stalker is a real, escapable threat with low cover to hide
  under.
- **M6 (next, and a wall):** fresh-eyes playtest — see `docs/playtest-checklist.md`.
  No Act 2/3 work until the gate passes.

## Headless autotest

	godot --headless --path . res://tests/autotest.tscn
	godot --headless --path . res://tests/camera_loop.tscn
	godot --headless --path . res://tests/host_ai_rules.tscn
	godot --headless --path . res://tests/watcher_ai.tscn
	godot --headless --path . res://tests/stalker_ai.tscn
	godot --headless --path . res://tests/zombie_reach.tscn
	godot --headless --path . res://tests/catch_face.tscn
	godot --headless --path . res://tests/collector_ai.tscn
	godot --headless --path . res://tests/processor_ai.tscn
	godot --headless --path . res://tests/level_scene.tscn
	godot --headless --path . res://tests/crawler_setpiece.tscn
	godot --headless --path . res://tests/debug_vision.tscn
	godot --headless --path . res://tests/psx_look.tscn

	# or: tools/run_tests.sh

The main autotest covers the shell, FPS + tank controls, one-at-a-time fleet
deployment (B spawns exactly one chassis, Q/1-2 link transfer, per-bot charge
and cargo persistence), sortie lifecycle, chair
suspend/resume persistence, the common host rules (curious/hunt/stalk, imprecise
hearing, stillness safety, host-vs-host deafness), radar-first stills, live-feed
unlock and motion-stress plumbing after the module salvage, the Deck B
crossing (airlock, four aggressive watchers, no instant threshold kill, relay
anchor and radar label, darkness, the one-shot Collector sacrifice and dormant
Processor, the crawler trigger/deferral/resolution, F3 roster, no authored
loss), the hull bus, and the hand-copy map with its Deck B/engine inset. The
other suites add camera-loop hub/install checks, host-AI rules, watcher-AI
rules, Stalker AI, the chase-reach pose probe (host arms, Stalker forelegs,
toward the drone only while pursuing), the catch-face feed probe
(a random close-up of the catcher's face for the last live frames before snow
and destruction), Collector-AI, Processor-AI, level-scene and crawler
set-piece checks. Run `tools/run_tests.sh` for the live totals.

The **level scene** test is the editor contract: it loads the baked scenes,
checks the controller wiring and anchors, confirms geometry references shared
palette resources, verifies the pickups and doors resolve, and proves that
moving an anchor marker changes the runtime value. It deliberately does not
pin terrain, walls, floors, ramps or walkable routes, so the layout can be
edited freely.

The **fleet** starts as one crawler on the hatch cradle. `B` deploys another
one at a time (up to `DRONE_FLEET`), placing it on the next clear cradle at the
dock and moving the link to it. Only the linked bot drains battery and takes
player input; parked bots hold position, heading, charge and cargo. `Q` cycles
the link, `1`/`2` select directly, and a caught bot is destroyed where it stood
while a survivor carries the sortie on. `R` recalls the whole fleet and
delivers all cargo.

The **camera loop** test verifies every hub station is focusable, picks up the
video module at its anchor, reels it home, installs it through the fabricator's
real focus/interact path, and confirms the next sortie comes up on the live
drone camera with the radar in its own window. It does not assert a drive route,
so level geometry is free to change.

The **host AI rules** test builds a small walled room and checks the
escalation contract directly: blocked sight decays a stalk into a search, a
still drone is unseen at every range (including 2 m), movement re-acquires it,
the stalk closes and runs the drone down, stopping out of reach ends the stalk
without a catch, and a moving drone in the open is killed on contact by the
common host brain.

The **watcher AI** test drives the Watcher prefab directly: it walks its route
unprovoked, closes to its ~6.8 m stand-off and plants instead of attacking,
holds the stand-off and its ground when the player approaches, kills only on
contact the player drives into, gives the drone up when it loses sight, and —
in the aggressive Zone 2 profile — still sees a parked chassis inside its
short still radius, so stopping at arm's length is not safety.

The **stalker AI** test drives the Stalker prefab directly: the thirty-leg
centipede body with exact two-bone IK and a planted-foot gait, default patrol,
directional investigation, sight-into-prowl, low-table cover,
last-seen-direction search, the cat-and-mouse spook (a cut-off ahead of the
prey that never catches), the patience clock, the semi-circular kill approach,
the lunge contact kill, wall climbing with the ceiling vault, and the
folded-lair drive-by spring. In the shipped level it is the engine-room tenant
on Deck C.

The **collector AI** test checks loud-door noise, the Collector's pickup/deposit
cycle, long-range head tracking with line of sight, the mid-range spit at a
player it will not chase, close pursuit of a nearby player body, the harmless
grab stand-in, the give-up ring, and the chassis carry (frozen in the hands,
delivered to the Processor's drop mark, never disconnected).

The **processor AI** test probes the pinned body: the body never walks,
motion-only sight (still, cone, carried cargo), the telegraph before the
reach, the catch inside arm's reach, the escape beyond it, feeding from the
pile, and release after the fleet absorbs the loss.

The **crawler set-piece** test drives the survivor directly: it is not a physics
body, has no legs, crawls at 0.6–0.9 m/s, never closes inside its hold
distance, speaks and posts drag noise, is yanked away on its hold beat, leaves
a long visual-only smear trail, cannot be replayed, and resolves at the
authored mark when abandoned.

The **debug vision** test proves the F4 developer toggle: a module-less chassis
gets the clean colour feed, low-light ambient/exposure and a wide lamp, hostile
bodies are ghosted against sight and noise, and pressing F4 again restores the
stills/live-feed rules and normal lighting. It also checks that a second
chassis inherits the same rules.

## Radar charting (knowledge layer)

- Every scanner wall return is recorded into `main._charted` on a 0.5 m
  world grid (deduped, capped at 900 cells — one playthrough's worth).
- Charted cells draw as faint ink dots on the deck map and mark their zone
  as visited: the sweep *is* reconnaissance.
- The physical paper map on the table is a `SubViewport` rendering the same
  map drawing into a textured quad (`fab_bay.map_surface`), refreshed at
  ~1.2 Hz while you play. The overlay (E at the table) uses the same code at
  full screen size via `map_view.fit_to()`.
- Charting persists across sorties and is never cleared — it is the player's
  accumulated knowledge, the only progression the slice grants for free.

## Floor / collision discipline (important for new level geometry)

- The drone-space floor is **one continuous collision slab** under both decks
  (`World` in `ship.tscn`, top at y = 0). Per-compartment floor meshes are
  visual-only: edge-to-edge colliders catch box/sled bodies on seams. The
  Cold Hold does not add a second slab.
- **Ankle-height dressing must never collide** (cables, debris plates,
  threshold trim). A 12 cm cable is an invisible wall to a capsule whose
  bottom sits at y = 0.05. Collision belongs to walls, tall props, and
  things you must actually route around.
- The host watchdog re-routes on "commanded but not traveling"; it measures
  the *commanded* velocity, because `move_and_slide` zeroes the real one
  against a wall.
- **Hosts do not hear each other.** Footfalls post to `NoiseBus` with
  `source = self`; `_on_noise()` ignores any event whose source is a host.
  Two silhouettes in one room otherwise lock into an endless mutual
  investigate loop. Player, drone, door and hull noise stay audible.
- **Drone-only gaps are height gates, not width gates.** The 1.0 m service
  crawl and the fallen locker block a 1.6–1.8 m capsule regardless of its
  radius. `beyond.chokes` publishes each barrier plus two routing points; the
  stalker's `_nav_target()` takes that way around when pursuit would cross one.
  Do not "fix" the crawl by widening it — the height is the gate.
- **Standing up parks the fleet, it does not destroy it.** `E` in the chair
  clears the monster/scanner links and sets the sortie IDLE while every chassis
  stays alive, uncontrolled, at its exact transform. `E` at the chair takes
  the same link back, so positions, headings, charge and cargo persist across
  chair sessions. Only `R` (reel), the loss of the last bot, or battery death
  tears the fleet down.

## Known benign warnings

`ObjectDB instances were leaked at exit` — a few AudioStreamWAV/PlaybackWAV
references held by the mixer at shutdown in headless mode. Engine quirk,
not live state; harmless.
