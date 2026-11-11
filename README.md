# UMBILICAL — vertical slice (M0–M6, east annex + berth + Processor wing)

First-person industrial horror. You survive inside a sealed fabrication bay on
an infested ship; you cannot leave, and the things outside hunt anything that
moves. You pilot remote drones built from salvage to scrounge what you need.

**Current build — radar + stills, then live video after the salvage** (see `docs/v1-plan.md`):
- The fab bay hub (M0): walk it, read it, hear the hull knock.
- **Drones v1 start blind to live video.** The radar is the primary display —
  most of the screen — and the drone's only camera is the **still camera**.
  Primary mouse (or **F**) exposes one crude photograph: heavy grain, crushed
  blacks, violent contrast, hard to read. The print holds ~2.2 s, then the
  mechanism needs a **slow 5 s recharge** (left-edge shutter bar; green pip =
  ready).
- **The salvage in the east spur is the video camera module.** Racking it at
  the fabricator wakes the decoder: later sorties fly on the **live drone
  feed**, with the radar reduced to a compact inset. The feed runs through the
  same grainy emulsion as the still — low-res, scanlined, and deliberately
  dirty — and gets worse while you drive: steering smears and ghosts the
  picture, speed adds grain, tearing and dropped scanlines. At rest it settles,
  but never gets clean. When the primary stalker closes, it poisons the feed:
  heavier grain and tears, a rolling white band, then the picture dissolves
  toward snow until the kill. Lose the module and the feed goes with it — you
  are back to stills until you recover and refit it. Every drone carries the
  still camera as standard kit, even with live video.
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
- **Hosts now escalate instead of beelining, and sight needs motion.** One
  quiet noise makes them curious: they stop, remember roughly where it came
  from, and listen. Keep moving and a second noise starts a slow, imprecise
  hunt. A host only *sees* a drone it has seen move: stop rolling and the
  machine is invisible at any range, even nose-to-nose — it can walk straight
  past you. A stalk ends when you stop (or break the corner); the host searches
  the last place it saw motion, then gives up. Contact still kills if it is
  already on top of you. A single very loud noise (≥ 0.7) skips the listening
  phase. The ship now carries **one** ordinary host; the primary stalker is
  relentless and kills on contact.
- **M4: the primary bad guy.** The first sortie with the recovered video module
  wakes a **second hunting body**: a tall, pale-boned **stalker** that spawns
  far away in the north ring once you enter the junction. It patrols the annex
  by default;
  noise sends it to investigate the *direction* it came from, never the exact
  point. It recognises any player drone on sight, chases immediately, and
  destroys on contact. Break line of sight and it searches the direction it
  last saw. It persists across sorties. Its voice is a long sub-bass hum that
  grows louder and deeper as it closes; on radar it is a broad **moving mass**,
  not a noise blip. When the live feed is up and it is already behind the
  drone, it may choose to **lurk** instead of charging: it shadows you out of
  view and only lunges when you turn the camera toward it — a jumpscare with a
  shriek and a hard red flash. It can also fold itself into a corner as an
  **ambush**: face down at drone height, eyes shut, hum held, waiting for a
  drive-by. Come close and the eyes snap wide and it pounces. The wreck stays
  where it fell, visual-only so it can never block a corridor; the module is
  inside it. Go back for it, if you have the nerve — then refit and fly with
  live eyes again.
- **Low tables are cover.** The junction and cafeteria have low work tables.
  The crawler fits under them; the stalker does not. Under a table you are
  invisible to its sight, but not to its hearing — stop moving too.
- **M5: hull-borne sound and the hand-copy map.** Positional audio routes
  through a lowpass "Hull" bus when a wall occludes the listener; hosts read
  as three-rooms-away. Motor pitch strains with load. **The map fills itself
  in:** every wall a drone's sweep touches is charted permanently (0.5 m
  grid) and hand-dotted onto the deck map — both the fullscreen map and the
  physical paper on the table in the middle of the bay, which redraws live.
- **The galley is a proper hall now** (12 x 10.4 m), and it is empty. The
  pressure door still grinds open when a drone gets close, but nothing waits
  behind it any more: the pantry sits at the far west end as a real traversal,
  not a doorway ambush. With one patroller in the junction, the opening rooms
  are quiet enough to read.
- **The east annex: a donut corridor around a gutted cafeteria.** Past the
  spur, the ship opens into a long service loop — north, east, south and
  west rings wrapped around a 13 x 10.8 m crew mess with four arches, long
  bolted-down tables, a dead serving line and a toppled table for cover. The
  loop has two mouths into the junction, so you can circle it or cut straight
  through the cafeteria. This is the "more ship" the survivors never mapped:
  the patroller walks the whole donut, and the far corner is ~34 m from the
  dock, still inside the 36 m tether.
- **The berth wing: the crew's rooms.** South of the annex ring, a short hall
  opens into three small cabins with **lofted bunks** (drive under one and the
  stalker loses sight of you, exactly like the low tables) and **loud sliding
  doors**: the bang and grind of a door opening posts a hard noise event into
  the annex, so a room is never a quiet place to hide. The wing has two normal
  mouths into the ring and a **1.0 m service crawl** that only the drone fits
  through; the tall bodies route around via the east link. A locker torn off
  its mounts leans across the west link at chest height — another drone-only
  gap. At the east end is the **ossuary**, the Collector's original nest. The
  nest is a single constant (`beyond.COLLECTOR_DEPOSIT`) and a matching node,
  so it can be moved in one edit.
- **The Collector: the third body.** It is not a hunter. A small, hunched
  scavenger with a lantern and a drag sack walks a long authored loop around
  the east annex, the berth wing and the Processor hall, picks up the crew
  remains scattered along it, and carries them to the feeding pile at the end
  of the new east hall. Its circuit deliberately avoids the bay, starting
  corridor and junction, so the opening rooms stay quiet. It never chases the
  drone, never kills, and is deaf to noise; monsters ignore each other. If it
  crosses a chassis it does not break it: it lifts the bot, carries it with the
  link and camera still live (the player can watch the whole ride through the
  feed), and sets it down in front of the Processor. It shows up as work being
  done — evidence that something is cleaning the ship.
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
  hall.

## Run

With Godot 4.4+ installed:

    godot --path .

or open this folder in the Godot editor and press F5.

## Controls

Walking the bay:  WASD move (A/D strafe) · SHIFT hurry · mouse look ·
E inspect · ESC pause · F3 debug

In the pilot chair (sortie):  W/S drive · A/D turn (crawler steer) ·
SHIFT hurry · F / left click — take a photograph · B deploy another bot (one at
a time) · Q cycle bot · 1 / 2 select a bot ·
R reel the whole fleet back in (only near the hatch dock) · E stand up (the
fleet parks where it is; E at the chair resumes the same link, same machines,
same charge) · ESC pause

Once the video module is racked, the pilot view becomes the live drone feed
and the radar moves to a compact inset; F still exposes a still frame.

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

At the fabricator:  E installs a recovered video module; the live feed wakes on the next sortie.

## First loop (radar + stills → video module → live feed)

1. **In the bay:** E at the pilot chair launches a sortie with one chassis.
   Press `B` while piloting to deploy a second at the dock, one at a time.
   Every other station is also usable: fabricator (north-east), map table
   (centre), lockers (east), barricade (west door), drone hatch (north wall).
2. **Radar drone:** before the module there is no live view. The radar fills
   most of the screen and the black lens sits behind it. Primary mouse / F
   exposes one grainy still; the shutter then recharges slowly (5 s).
   Optionally run the rations errand: west through the grinding galley door to
   the cold-room pantry, then home to the hatch dock and press R to reel.
   `B` drops another bot at the dock; `Q` hops the link between deployed bots
   at any time; the parked one waits.
3. **Video module salvage:** from the junction, take the east opening into
   the spur (the west end of the annex's north ring). The dead drone is
   against the north wall; the amber **video camera module** lies on its near
   side. Close to within 1.2 m to take it, drive back to the dock, and press R
   to reel. The rest of the donut and the cafeteria are optional — and the
   patroller uses them.
4. **Install:** walk to the fabricator in the bay's north-east corner and
   press E. The module is racked; the next sortie flies on the **live drone
   feed**, with the radar as an inset. The still camera remains available.
5. **The loss:** the next sortie with the module arms the authored
   interception. The module-carrying chassis is lost; the wreck stays where it
   fell, and a surviving bot can keep flying on stills. Until you recover and
   refit the module, the fleet is back to radar + stills; after the refit,
   live feed and free sorties resume.

## Build gates (from the plan)

- M0 done-when: walking the bay feels heavy and quiet.
- **M1 done-when:** a radar drone sortie through the empty corridors is tense
  with zero monsters. If it isn't, nothing after it matters.
- **M3 done-when:** the black lens between photographs makes you slow down;
  each print reads as evidence from a camera you don't trust, not video.
- **M2 done-when:** the food run is winnable, losable, and scary by audio.
- **M4 done-when:** the first video-module sortie ends in loss, and the player
  immediately wants to go back for the module.
- **M6 (next, and a wall):** fresh-eyes playtest — see `docs/playtest-checklist.md`.
  No Act 2/3 work until the gate passes.

## Headless autotest

    godot --headless --path . res://tests/autotest.tscn
    godot --headless --path . res://tests/camera_loop.tscn
    godot --headless --path . res://tests/patrol_soak.tscn
    godot --headless --path . res://tests/host_ai_rules.tscn
    godot --headless --path . res://tests/stalker_ai.tscn
    godot --headless --path . res://tests/annex_loop.tscn
    godot --headless --path . res://tests/collector_ai.tscn
    godot --headless --path . res://tests/processor_ai.tscn

213 checks in the main autotest: shell, FPS + tank controls, one-at-a-time
fleet deployment (B spawns exactly one chassis, Q/1-2 link transfer, per-bot
charge and cargo persistence, cradles ship-side), sortie lifecycle, chair
suspend/resume persistence, host perception (curious/hunt/stalk, imprecise
hearing, stillness safety, host-vs-host deafness), radar-first stills,
live-feed unlock and motion-stress plumbing after the module salvage, the late
primary-stalker beat (modelled body, patrol/investigate/chase, low-table
cover, moving radar mass, event lamp, proximity feed poisoning, rising hum,
lurk/lunge, corner ambush), the visual-only loss wreck, the authored loss and
recovery, hull bus, and the hand-copy map. The other suites add 19
camera-loop, 29 patrol-soak, 14 host-AI-rule, 22 stalker-AI, 9 annex-loop,
38 collector-AI and 26 processor-AI checks (370 in total).

The **fleet** starts as one crawler on the hatch cradle. `B` deploys another
one at a time (up to `DRONE_FLEET`), placing it on the next clear cradle at the
dock and moving the link to it. Only the linked bot drains battery and takes
player input; parked bots hold position, heading, charge and cargo. `Q` cycles
the link, `1`/`2` select directly, and a caught bot is destroyed where it stood
while a survivor carries the sortie on. `R` recalls the whole fleet and
delivers all cargo.

The **camera loop** test drives the real drone from the hatch dock through
the corridor, bend, junction, and into the spur with tank controls (no
teleports), picks up the video module, reels it home, installs it through the
fabricator's real focus/interact path, and confirms the next sortie comes up
on the live drone camera with the radar inset. It also verifies every hub
station is focusable. Use it after any ship-geometry or interaction change.

The **patrol soak** walks every leg of the patroller's authored loop with
the real host body at 3x time scale and reports the exact waypoint pair if
any segment is not traversable. Use it after any geometry change.

The **annex loop** drives the real drone around the full donut with tank
controls — north ring, east ring, south ring, through the cafeteria's arches,
out the west ring and back into the junction — then into the berth wing,
through the 1.0 m service crawl, down the hall, through a loud cabin door and
back via the east link. It confirms the annex, cafeteria and berth zones ink
onto the hand-copy map. Use it after any annex change.

The **host AI rules** test builds a small walled room and checks the
escalation contract directly: blocked sight decays a stalk into a search, a
still drone is unseen at every range (including 2 m), movement re-acquires it,
stalking keeps its distance, stopping ends the stalk without a catch, and only
a moving drone is killed on contact by the common host brain.

The **stalker AI** test drives the primary enemy directly: modelled body,
default patrol, directional investigation, immediate sight/chase, low-table
cover, last-seen-direction search, the live-feed lurk/lunge (only from behind
and only when the camera turns to it), and the contact kill.

The **collector AI** test builds the ship and checks the berth wing geometry
(drone-height vs body-height clearance, the fallen locker, bunks as hide
spots), loud-door noise, the Collector's pickup/deposit cycle and its
non-hunting nature, the chassis carry (frozen in the hands, delivered to the
Processor's drop mark, never disconnected), and the stalker's physical
way-around through the east link when a target lies beyond the crawl.

The **processor AI** test builds the Processor wing and probes the pinned
body: the hall and chamber are traversable but enclosed, the body never walks,
motion-only sight (still, cone, carried cargo), the telegraph before the
reach, the catch inside arm's reach, the escape beyond it, feeding from the
pile, and release after the fleet absorbs the loss.

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

- The drone-space floor is **one continuous collision slab** under the whole
  ship (`beyond._flat_floor()`, top at y = 0). Per-compartment floor meshes
  are visual-only: edge-to-edge colliders catch box/sled bodies on seams.
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
  clears the host/scanner links and sets the sortie IDLE while every chassis
  stays alive, uncontrolled, at its exact transform. `E` at the chair takes
  the same link back, so positions, headings, charge and cargo persist across
  chair sessions. Only `R` (reel), the loss of the last bot, or battery death
  tears the fleet down.

## Known benign warnings

`ObjectDB instances were leaked at exit` — a few AudioStreamWAV/PlaybackWAV
references held by the mixer at shutdown in headless mode. Engine quirk,
not live state; harmless.
