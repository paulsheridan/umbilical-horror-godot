# M6 — Fresh-eyes playtest gate

Run this after M4+M5+M6b+M6c (current build). The vertical slice covers:

radar + stills sortie → rations run → spur salvage of the **video module** →
install (live feed unlocked) → first live-feed sortie →
**the interception and loss** → recovery without the module (back to stills) →
refit (live feed returns) → free sorties. The ship now includes the **east
annex**: a donut corridor around a large cafeteria, with two mouths back into
the junction, the **berth wing**: three loud-doored cabins, lofted bunks,
a drone-only service crawl, and the Collector's ossuary, and the **Processor
wing**: a long dark hall ending in the feed chamber where a pinned giant mouth
eats what the Collector brings it.

Every drone carries the **still camera** from the first launch. The recovered
video module unlocks the **live drone feed** on later sorties; the radar stays
as a compact inset. Losing the module takes the feed away again, so test both
the radar-first era and the live-feed era.

M6 is a wall, not a polish task: **no Act 2/3 work until a fresh player
proves the slice works.** Everything below is what the slice has to do to a
person who has never seen it.

## How to run

    godot --path /home/paulsheridan/projects/umbilical

Record each session in `docs/playtest-log.md` (session template + aggregate
gate questions).

## Watch silently. Do not explain the controls.

Hand them nothing but "it's a horror game about drones, you're stuck in a
room". Watch for:

1. **First two minutes.** Do they find the chair, the map, the fabricator?
   What do they inspect first? If they wander the bay aimlessly for more
   than ~2 minutes, the chair's call to action is too quiet.
2. **First sortie.** Is the large radar legible? Do they figure out the echo
   map without being told? Where do they get lost? A radar sortie that reads
   "broken" instead of "dreadful" is the #1 tuning signal.
3. **The galley door.** Does the grind read as *cost*? The room behind it is
   empty now; the sound should still make them pause and listen, because the
   patroller is somewhere out in the annex.
4. **Host escalation.** One noise should only make a host stop and listen.
   Does the player notice that distinction? Do they keep driving through it
   and trigger the hunt, or do they freeze? A second noise should produce a
   slow, visibly uncertain search — not a beeline.
5. **Stillness = safety.** Does anyone discover the halt rule organically
   (stop moving, host loses sight at any range)? Note where and how — that's
   the thesis moment. After a stalk, do they try stopping or turning a corner,
   and does the host search the last place they moved and then give up instead
   of camping forever? Watch for players who never realise a stationary drone
   is invisible; the "stop and it walks past" beat is the one to test hardest.
6. **The still camera, then the live feed.** Before the module, there is no
   live video; the radar fills most of the screen. Do they understand the
   shutter? (Bar on the left, LMB/F.) Do they shoot before moving, or drive on
   the radar alone? The stills should make them stop, aim, and commit; if they
   spam the shutter the slow 5 s recharge isn't biting hard enough. The held
   print (~2.2 s) is your blind spot — do they notice the drone keeps moving
   while the frame is up? After the install, the next sortie should visibly
   become a live feed with a radar inset. Does the upgrade land as relief, and
   does the ship still feel dangerous once they can see it? Watch the moving
   picture specifically: is the tearing/ghosting/grain legible enough to drive
   by, or does it cross into unreadable or nauseating? Ask whether they noticed
   the image getting worse when they steer.
7. **The fleet.** One bot deploys at launch; `B` drops another, one at a time,
   and `Q` (or `1`/`2`) moves the link. Watch whether they find deployment and
   the swap without being told: do they park one bot as a lookout or as bait,
   and does the other keep its charge? Do they understand that only the bot
   they are flying drains battery, and that a caught bot is gone but the run
   continues on a survivor? If they never deploy or swap, the control hint or
   the second LED is too quiet.
8. **The primary stalker.** It should only appear after they leave the initial
   hallway and enter the junction, spawning far away in the annex. Do they
   notice the moving radar mass and the rising hum before they see the body?
   Does the body read as a tall skeletal horror, or as another robot? When it
   sees them it should chase immediately; when they break sight, does its
   search head in the direction they were last seen?
   - **Hiding:** do they discover the low tables? Drive under one and stop.
     Does the stalker lose them, search, and move on? If they keep moving under
     the table, does it hear and investigate?
   - **Don't look back:** with the live feed online and the stalker behind
     them, does it lurk? Do the rear radar mass and louder hum make them want
     to turn? When they do, does the lunge land — shriek, red flash, body
     rushing in — or is it too dark/grainy to read?
   - **The trap:** do they notice a shape folded into a corner at drone height?
     When they drive past, do the eyes snapping open and the low face-first
     pounce land, or does it read as a wall prop? If they spot it while it is
     creeping to the corner, does it abandon the trap and chase?
   - **The loss:** the line we want, unprompted: some version of *"wait, can
     I go back for it?"* Watch that losing the module reads as **losing the
     live feed**, not as "now I'm blind" — the still camera and radar remain.
     Confirm the wreck left behind does **not** block the corridor — they
     should be able to drive through/over it on the recovery run.
9. **The recovery.** Is going back for the video module a decision? Fear of
   the known wreck site is the content. Confirm they understand the recovery
   drone still has the still camera, so the run out is not blind — and that
   refitting the module brings the live feed back.
10. **Failure discipline.** Getting caught should cost time and hardware,
    not the run. If a loss makes them quit the game entirely, the failure
    meter is overtuned.

## The east annex (new since the last gate)

The annex is deliberately larger than the old spur. Watch specifically for:

- **Do they find the loop?** From the junction, both east openings are the
  annex. Do they realise the spur is now the west end of a corridor, or do
  they treat it as the same dead end and turn around?
- **Do they cut through the cafeteria or circle it?** Both work. Note whether
  the four arches read as openings at a glance in the dark, or as solid wall.
- **Does the space dilute the dread?** The point of the annex is that hosts
  can be somewhere else — but the player should still hear/see enough to feel
  tracked. If they drive the whole donut without a single sign of a host, log
  where and whether it felt empty rather than safe.
- **Cafeteria landmark.** The one-time line ("The crew mess…") should land as
  a place, not a jump-scare. Do they stop and photograph the tables/serving
  line?
- **Tether.** Does the far annex corner (~34 m) ever read as "I am about to
  be cut off"? The tether warning should bite before the hard stop.
- **Do not expect a new hunter.** There is one ordinary host, the primary
  stalker, the Collector scavenger, and the pinned Processor. The annex is
  room, not another chase; the Processor is a place, not a patrol.

## The berth wing and the Collector (new since the last gate)

South of the annex south ring is the crew's berth wing. Watch specifically for:

- **Do they find the wing?** The south ring now has two normal mouths and a
  low crawl. Do they read the crawl as a drone route or as a wall defect?
- **Loud doors.** Entering a cabin bangs and grinds the door open. Does the
  sound read as a warning/cost, or as an alarm? Do they pause and listen after
  opening one, or drive straight in?
- **Bunks.** Do they discover they can drive under a lofted bunk and hide?
  Does it land like the low tables, or is the clearance too subtle in the dark?
- **The crawl and the locker.** Can they thread the 1.0 m service crawl with
  tank controls without it feeling unfair? Do they try the fallen-locker gap in
  the west link? If the stalker is chasing, can they feel it taking the east
  link instead of wedging at the low header?
- **The Collector.** Do they see the lantern or the drag sack before they
  understand what it is? Does it read as a scavenger at work (evidence), not as
  another hunter? Do they follow it, avoid it, or ignore it? Note whether the
  scattered remains register before they see it pick one up. Its loop stays in
  the annex/berth wing, so a sighting should feel like catching it in the act,
  not like traffic in the opening rooms.
- **The ossuary.** Do they find the nest? Does the growing pile + bone chimes
  read as a place, and does the red lamp make them want to leave? Confirm the
  deposit does not block the cabin door or the drone's path.
- **The Processor hall.** Do they follow the east hall past the berth wing?
  The hall is deliberately empty and almost unlit: does the walk build
  tension, or just feel like a dead end? Does the mouth read from the hall
  mouth before the hand moves? Do they work out that stillness is safe and
  motion is food, or do they read the pinned body as another patroller?
- **The Collector's delivery.** If they see the Collector carrying a bot, do
  they understand the link/camera is still live? Can they watch the ride
  through the feed without it cutting out, and do they realise they can drive
  the bot away after it is set down? If the Processor catches it, did the
  telegraph give them a fair chance to escape the reach?
- **Feeding.** Do they watch it take parts off the pile and put them in its
  mouth? Does the pile make the Collector's route legible as a system rather
  than random scavenging?

## Specific things to log per tester

- Time to first sortie / to first photograph / to first delivery / to first
  loss.
- Where they died and whether they understood *why* (audio cue? radar blip?
  still frame?).
- Any "this is unfair" moment: distinguish *the game lied* (fix the system)
  from *the game is scarce* (keep it).
- Audio balance on their hardware: can they hear the patroller over the
  motor at 50% system volume?
- "Why is the screen black?" between photographs (that's the point; they
  should discover LMB/F from the hint and the shutter bar unprompted). Note
  whether they try to read the black lens as a dead feed rather than "no
  photograph yet".
- Whether the live feed after install lands as an upgrade: do they look around
  more, drive faster, or stop using the radar? Log whether losing it in the
  interception actually stings.
- Whether the radar inset stays legible enough to navigate by after the feed
  comes online.
- Did they hide under a low table or a bunk? Did the stalker lose them, or
  hear them moving? Did the lurk/hum make them turn around, and how did the
  jumpscare land?
- Did they deploy a second bot with B? Did the extra chassis read as a tool
  (lookout, bait, relay) or did they forget it existed? If a bot was caught,
  did they understand the link hopped to the survivor?
- Did they see the Collector? Did it read as a scavenger rather than a hunter,
  and did the remains/nest make the ship feel lived-in (and cleaned)?
- Did they reach the Processor hall? Did the pinned mouth / feeding pile land
  as a place, and did they understand stillness vs motion and the reach?
- Did they watch a Collector bot carry through the live feed, and did the link
  survive the ride?
- Whether the stalker's body reads as horror on their hardware (too dark? too
  grainy? silhouette unclear?).

## Tuning knobs on hand (top of each file)

- Drone speed/turn/accel, `MAX_TETHER` (36), `BATTERY_RATE`, signal bar
  distances (`main._signal_bars`), photo `SHUTTER_TIME` (5.0 s) and
  `PHOTO_SHOW_TIME` (2.2 s). Fleet cap is `main.DRONE_FLEET` (2), deployed one
  at a time with B; the cradle spacing is `main.DRONE_CRADLE_GAP` (1.5 m).
- Radar `RANGE`, `SWEEP_TIME`, `ECHO_LIFE`; scanner scaling is automatic
  (ring = full range). The radar is full-screen before the module and a
  top-right inset after it.
- Host `HEARING_MULT`, `ESCALATE_DELAY`, `HUNT_*`, `SIGHT_*`, `STALK_*`
  speeds/distances, `MOVE_THRESH` (what counts as visible motion),
  `LOSE_SIGHT_TIME`
- Still shader exposure/gamma/grain (frozen — no `TIME` term, so prints do
  not shimmer), vignette; photo viewport 480×270
- Live-feed shader grain/tear/ghost/corruption and the `set_live_stress()`
  drive curve in `main._process` (speed + steering). `LIVE_SHADER_SRC` in
  `hud.gd`; live tube sits on CanvasLayer 4 under the HUD
- Live-feed gate: `VIDEO_FEED_ENABLED` (master) and `_camera_installed`
  (module). `drone.live_view` is set from `_live_feed_active()`.
- Stalker (`src/host/stalker.gd`): `SIGHT_RANGE`, `SIGHT_FOV`,
  `HEARING_MULT`, `W_PATROL` / `W_INVESTIGATE` / `W_CHASE`, `LOSE_SIGHT_TIME`,
  `SEARCH_LEAD`, `LURK_CHANCE`, `LURK_DIST`, `W_LURK`, `LUNGE_DOT`,
  `LUNGE_RANGE`, `W_LUNGE`, `AMBUSH_CHANCE`, `AMBUSH_ROLL`,
  `AMBUSH_COOLDOWN`, `AMBUSH_TRIGGER`, `AMBUSH_WAIT`
- Berth wing (`src/ship/beyond.gd`): `CRAWL_X0/X1` (height is the gate — do
  not widen to "fix" pathing), `BERTH_*`, door trigger radius (1.9 m) and slide
  speed (1.7 m/s), `chokes` routing points
- Collector (`src/host/collector.gd`): `SPEED`, `MAX_CARRY`, `COLLECT_RADIUS`,
  `DEPOSIT_RADIUS`, `BOT_PICKUP_RADIUS`, `BOT_DROP_RADIUS`,
  `BOT_DROP_COOLDOWN`; its loop is `main.COLLECTOR_ROUTE` (annex + berth wing
  + Processor hall); the nest is `beyond.COLLECTOR_DEPOSIT` and the feed pile
  is `beyond.PROCESSOR_PILE`
- Processor (`src/host/processor.gd`): `SIGHT_RANGE`, `SIGHT_FOV`,
  `MOVE_THRESH` (0.30), `TELEGRAPH_TIME`, `REACH_TIME`, `MAX_REACH`,
  `GRAB_RADIUS`, `CATCH_COOLDOWN`, `FEED_INTERVAL`; the body is pinned at
  `beyond.PROCESSOR_POS`, the pile at `beyond.PROCESSOR_PILE`, and a carried
  bot is set down at `beyond.PROCESSOR_DROP`
- Hull knock frequency (42–95 s), bay hum level

## Exit criteria (all of them)

- Radar navigation is *legible but frightening*, not confusing.
- The annex reads as a navigable loop with a recognisable cafeteria, not as
  maze padding; the extra space makes hosts feel elsewhere, not absent.
- The still camera reads as evidence, not a broken video feed: black lens,
  slow recharge, frozen grain.
- The module-loss beat produces the "go back for it" reflex without making
  the player think they have gone blind.
- Nobody describes the game as broken (except the touchpad thing, which
  is documented in the README).
- 3+ of 5 testers voluntarily do a second sortie after the first loss.

## Known benign warnings

`ObjectDB instances were leaked at exit` — a handful of AudioStreamWAV/
PlaybackWAV references held by the audio mixer at shutdown in headless
mode. Engine quirk, not live state; harmless in the editor too.
