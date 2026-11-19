# M7 — Fresh-eyes playtest gate

Run this after M7+M5+M6b+M6c (current build). The vertical slice covers:

radar + stills sortie → flashlight add-on run → spur salvage of the **video module** →
install (live feed unlocked) → first live-feed sortie →
**the Cold Hold crossing** (four watchers wake, the Collector is consumed once,
the crawler arms) → the lit side hall opens into **Deck C**, a dark engine room
with a live Stalker and low machinery hides → a real loss only if a watcher is
driven into (wreck + stills recovery) → refit (live feed returns) → free
sorties. The ship now includes the **east annex**: a donut corridor around a
large cafeteria, with two mouths back into the junction, the **berth wing**:
three loud-doored cabins, lofted bunks, a drone-only service crawl, and the
Collector's ossuary, the **Processor wing**: a long dark hall ending in the
feed chamber where a pinned giant mouth eats what the Collector brings it, and
**Deck B / the Cold Hold**: an 8 m umbilical into a pitch-black 50 x 25 m hold
with a relay and a side hall.

Every drone carries the **still camera** from the first launch. The recovered
video module unlocks the **live drone feed** on later sorties; the radar keeps
its own large window. A real catch takes the module and the feed away again, so
test both the radar-first era and the live-feed era. There is **no scripted
loss**.

This gate is a wall, not a polish task: **no Act 2/3 work until a fresh player
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
2. **First sortie.** Is the small radar legible? Do they figure out the echo
   map without being told? Where do they get lost? A radar sortie that reads
   "broken" instead of "dreadful" is the #1 tuning signal.
3. **The galley door.** Does the grind read as *cost*? The room behind it is
   empty, and Deck A is deliberately threat-free: the sound should still make
   them pause and listen because the ship feels occupied.
4. **Deck B escalation.** One noise should only make a watcher stop and listen.
   Does the player notice that distinction? Do they keep driving through it
   and trigger the hunt, or do they freeze? A second noise should produce a
   slow, visibly uncertain search — not a beeline.
5. **Stillness = safety.** Does anyone discover the halt rule organically
   (stop moving, a watcher loses sight outside its short still radius)? Note
   where and how — that's the thesis moment. After a stalk, do they try
   stopping or turning a corner, and does the watcher search the last place
   they moved and then give up instead of camping forever? Watch for players
   who never realise a stationary drone is invisible; the "stop and it walks
   past" beat is the one to test hardest.
6. **The still camera, then the live feed.** Before the module, there is no
   live video; a large black-lens optics window fills the desktop with a small
   radar beside it. Do they understand the shutter? (Bar in the optics window,
   LMB/F.) Do they shoot before moving, or drive on the radar alone? The stills
   should make them stop, aim, and commit; if they spam the shutter the slow
   5 s recharge isn't biting hard enough. The held print (~2.2 s) is your blind
   spot — do they notice the drone keeps moving while the frame is up? After
   the install, the next sortie should visibly become a large live feed with
   the radar reduced to a small instrument. Does the upgrade land as relief,
   and does the ship still feel dangerous once they can see it? The live tube
   is near-sighted: do they still reach for a print to read distance? Watch the
   moving picture specifically: is the tearing/ghosting/grain legible enough to
   drive by, or does it cross into unreadable or nauseating? Ask whether they
   noticed the image getting worse when they steer. If they fitted the **flashlight
   add-on**, check that its narrow beam reads as a tool (not a room light) and
   that its small start/stop/turn kick feels like a mounted lamp, not a swaying
   camera. Does **L** read as a real trade: the beam opens the dark, but a lit
   bot is spotted farther and cannot hide under low cover?
7. **The fleet.** One bot deploys at launch; `B` drops another, one at a time,
   and `Q` (or `1`/`2`) moves the link. Watch whether they find deployment and
   the swap without being told: do they park one bot as a lookout or as bait,
   and does the other keep its charge? Do they understand that only the bot
   they are flying drains battery, and that a caught bot is gone but the run
   continues on a survivor? If they never deploy or swap, the control hint or
   the second LED is too quiet.
8. **The Cold Hold crossing.** The junction's north airlock opens onto the
   umbilical. On the first active-drone crossing, four watchers wake 20+ m out,
   the Collector feeds itself to the Processor, and the crawler arms in the
   side hall. Do they notice the deck stencil, the light dying behind them, and
   the relay label change? Does the hold read as dark and open without an
   instant threshold kill?
   - **The watchers:** can they read a body in the lamp before it reaches them,
     and do the wet steps/breathing/radar give them a direction? Do they plant
     at the stand-off and hold it, and do they stay planted when the player
     approaches? When they break line of sight or stop outside the short still
     radius, does the watcher search and give up instead of tracking an
     invisible coordinate?
   - **The sacrifice:** do they see or hear the Collector go — lantern
     guttering, sack dragging, wet crunch through the hull? Is the Processor
     visibly inert afterwards, and do the empty lantern/sack on the deck read as
     evidence rather than an unloaded prop?
   - **The crawler:** do they hear the drag before they see the shape? Does the
     voice land on the subtitle channel without being mistaken for a HUD
     instruction? Does the long yank back down the lit hall land, and does the
     smear trail remain? Confirm it cannot kill, be saved, or soft-lock the
     drone.
   - **Deck C:** do the side-hall lights draw them to the far opening? In the
     engine room, does the Stalker's folded lair at the far end read as a
     threat without jumping them at the threshold, and do they find the low
     machinery pockets? Drive under one, stop moving, and check whether it
     loses them and searches. Confirm the `ENGINE` relay label and that the
     room is inside the tether.
   - **Real loss only:** if a watcher takes the module chassis, the line we
     want, unprompted, is some version of *"wait, can I go back for it?"*
     Confirm the wreck left behind does **not** block the corridor, and that
     the still camera and radar remain so the recovery run is not blind.
9. **If a real loss happens.** Is going back for the video module a decision?
   Fear of the known wreck site is the content. Confirm they understand the
   recovery drone still has the still camera, so the run out is not blind — and
   that refitting the module brings the live feed back. If no loss happened,
   note how they read the hold instead.
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
- **Does the space dilute the dread?** The point of the annex is that the ship
  feels larger than the opening rooms — but Deck A is deliberately empty, so
  the tension should come from the space and sound, not a hidden patrol. If
  they drive the whole donut without a single sign of life, log whether it
  felt empty rather than safe.
- **Cafeteria landmark.** The one-time line ("The crew mess…") should land as
  a place, not a jump-scare. Do they stop and photograph the tables/serving
  line?
- **Tether.** Does the far annex corner (~34 m) ever read as "I am about to
  be cut off"? The tether warning should bite before the hard stop.
- **Do not expect a watcher on Deck A.** The Collector scavenger and the pinned
  Processor are the only bodies out here. The annex is room, not another chase
  unless you bring a body close enough to wake the scavenger's attention; the
  Processor is a place, not a patrol. The four watchers are beyond the north
  airlock.

## The berth wing and the Collector (new since the last gate)

South of the annex south ring is the crew's berth wing. Watch specifically for:

- **Do they find the wing?** The south ring now has two normal mouths and a
  low crawl. Do they read the crawl as a drone route or as a wall defect?
- **Loud doors.** Entering a cabin bangs and grinds the door open. Does the
  sound read as a warning/cost, or as an alarm? Do they pause and listen after
  opening one, or drive straight in?
- **Bunks.** Do they discover they can drive under a lofted bunk and hide? Does
  it land like the low tables, or is the clearance too subtle in the dark?
- **The crawl and the locker.** Can they thread the 1.0 m service crawl with
  tank controls without it feeling unfair? Do they try the fallen-locker gap in
  the west link? The height gates are for the drone; the tall bodies route
  around via the east link.
- **The Collector.** Do they see the lantern or the drag sack before they
  understand what it is? Does it read as a scavenger that has noticed them,
  rather than a generic hunter? Note whether the scattered remains register
  before it picks one up, whether the long-range stare lands before it stops to
  spit, whether the gap between the spit and the closer shamble is legible
  (it should watch and spit from farther than it is willing to walk), and
  whether the harmless vomit spray/grab attempt lands as a threat before they
  work out that it will give up when they break away. Its loop stays in the
  annex/berth wing, so a sighting should feel like catching it in the act, not
  like traffic in the opening rooms.
- **The ossuary.** Do they find the nest? Does the growing pile + bone chimes
  read as a place, and does the red lamp make them want to leave? Confirm the
  deposit does not block the cabin door or the drone's path.
- **The Processor hall.** Do they follow the east hall past the berth wing?
  The hall is deliberately empty and almost unlit: does the walk build
  tension, or just feel like a dead end? Does the mouth read from the hall
  mouth before the hand moves? Do they work out that stillness is safe and
  motion is food, or do they read the pinned body as another hunter?
- **The Collector's delivery.** If they see the Collector carrying a bot, do
  they understand the link/camera is still live? Can they watch the ride
  through the feed without it cutting out, and do they realise they can drive
  the bot away after it is set down? If the Processor catches it, did the
  telegraph give them a fair chance to escape the reach?
- **Feeding.** Do they watch it take parts off the pile and put them in its
  mouth? Does the pile make the Collector's route legible as a system rather
  than random scavenging?

## The PSX look (presentation gate)

The shipped build starts with the **PSX Look** on: 240 lines, 15-bit dither, a
thin pixel grid and snapped vertices. The HUD, map, scanner and PSX panel stay
full-resolution. Do not explain F5 before the first run; the title and pause
screens both surface **PSX LOOK**.

- **First movement.** Mouse look must work on foot immediately after starting
  and again after closing the pause or PSX panel. If the view will not turn, the
  `PSXScreen` input path is broken — log it as a blocker, not taste.
- **Does it read as intentional?** A 240-line, dithered ship should look like a
  chosen instrument, not a broken renderer. Check that text and radar stay
  crisp and that the low-resolution edge is square, not smeared.
- **Performance.** Drive the Cold Hold and the annex with the look on. If frame
  time drops, lower density or draw distance before turning the master off.
- **Master off.** In F5, turn the master off: the authored full-colour look must
  return exactly, then come back on without a restart. Ask which one they would
  play and why; note the answer rather than defending the default.
- **Panel legibility.** Buttons, sliders and preset names must stay sharp and
  clickable over the moving world. Escape/close must resume play and recapture
  the mouse.

## Specific things to log per tester

- Time to first sortie / to first photograph / to first delivery / to first
  loss.
- Where they died and whether they understood *why* (audio cue? radar blip?
  still frame?).
- Any "this is unfair" moment: distinguish *the game lied* (fix the system)
  from *the game is scarce* (keep it).
- Audio balance on their hardware: can they hear a Cold Hold watcher over the
  motor at 50% system volume?
- "Why is the screen black?" between photographs (that's the point; they
  should discover LMB/F from the hint and the shutter bar unprompted). Note
  whether they try to read the black lens as a dead feed rather than "no
  photograph yet".
- Whether the live feed after install lands as an upgrade: do they look around
  more, drive faster, or stop using the radar? Log whether losing it in the
  if a real catch takes it actually stings.
- Whether the radar window stays legible enough to navigate by after the feed
  comes online.
- Did they hide under a low table or a bunk? Did a Deck B watcher lose them, or
  hear them moving through the hull? Did the state/audio make them stop?
- Did they deploy a second bot with B? Did the extra chassis read as a tool
  (lookout, bait, relay) or did they forget it existed? If a bot was caught,
  did they understand the link hopped to the survivor?
- Did they see the Collector? Did it read as a scavenger rather than a hunter,
  and did the remains/nest make the ship feel lived-in (and cleaned)?
- Did they reach the Processor hall? Did the pinned mouth / feeding pile land
  as a place, and did they understand stillness vs motion and the reach?
- Did they watch a Collector bot carry through the live feed, and did the link
  survive the ride?
- Whether a hunter's body reads as horror on their hardware (too dark? too
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
- **Cold Hold watchers** (`src/host/watcher.gd`, which also uses
  `configure_aggressive()`): `WATCH_STANDOFF` (6.8), `sight_range` (21),
  `sight_fov` (105°), `move_thresh` (0.12), `still_sight_range` (5),
  `hearing_mult` (28), `loud_escalate` (0.62), `w_patrol/w_hunt/w_stalk`
  (1.4/2.0/2.6), `hunt_patience` (20 s), `hunt_error_*` (0.5–1.4)
- **Crawler** (`src/host/crawler.gd`): `SPEED_MIN/MAX` (0.6–0.9),
  `HOLD_DIST` (2.6), `YANK_DIST` (2.45), `YANK_TIME` (15 s),
  `HOLD_VOICE_TIME`, `YANK_ANIM`, `SCRAPE_INTERVAL`; its marks are the
  `CrawlerSetPiece` / `CrawlerGrab` anchors and the defer radius is
  `main.HOST_CRAWLER_DEFER` (12 m)
- **Relay / Deck B** (`src/ship/beyond.gd`): `ZONE2_DOOR_CLOSED_Y/OPEN_Y`,
  `ZONE2_DOOR_SPEED`; the routes are `main.ZONE2_ROUTES`, the dark targets are
  in `main._set_zone2_dark()` (ambient 0.025, fog 0.055), and the lamp opens to
  7.5 m in the hold
- Still shader exposure/gamma/grain (frozen — no `TIME` term, so prints do
  not shimmer), vignette; photo viewport 480×270
- Live-feed shader grain/tear/ghost/corruption and the `set_live_stress()`
  drive curve in `main._process` (speed + steering). `LIVE_SHADER_SRC` in
  `hud.gd`; live tube sits on CanvasLayer 4 under the HUD
- Live-feed gate: `VIDEO_FEED_ENABLED` (master) and `_camera_installed`
  (module). `drone.live_view` is set from `_live_feed_active()`.
- Engine-room Stalker (`src/host/stalker.gd`): `SIGHT_RANGE`, `SIGHT_FOV`,
  `HEARING_MULT`, `W_PATROL` / `W_INVESTIGATE` / `W_CHASE`, `LOSE_SIGHT_TIME`,
  `SEARCH_LEAD`, `LURK_CHANCE`, `LURK_DIST`, `W_LURK`, `LUNGE_DOT`,
  `LUNGE_RANGE`, `W_LUNGE`, `AMBUSH_CHANCE`, `AMBUSH_ROLL`,
  `AMBUSH_COOLDOWN`, `AMBUSH_TRIGGER`, `AMBUSH_WAIT`
- Berth wing (`src/ship/beyond.gd`): `CRAWL_X0/X1` (height is the gate — do
  not widen to "fix" pathing), `BERTH_*`, door trigger radius (1.9 m) and slide
  speed (1.7 m/s), `chokes` routing points
- Collector (`src/host/collector.gd`): `SPEED`, `MAX_CARRY`, `COLLECT_RADIUS`,
  `DEPOSIT_RADIUS`, `BOT_PICKUP_RADIUS`, `BOT_DROP_RADIUS`,
  `BOT_DROP_COOLDOWN`, `HEAD_TRACK_RANGE`, `CHASE_RANGE`, `LOSE_RANGE`,
  `VOMIT_RANGE`, `GRAB_RANGE`; its loop is `main.COLLECTOR_ROUTE` (annex +
  berth wing + Processor hall); the nest is `beyond.COLLECTOR_DEPOSIT` and the
  feed pile is `beyond.PROCESSOR_PILE`
- Processor (`src/host/processor.gd`): `SIGHT_RANGE`, `SIGHT_FOV`,
  `MOVE_THRESH` (0.30), `TELEGRAPH_TIME`, `REACH_TIME`, `MAX_REACH`,
  `GRAB_RADIUS`, `CATCH_COOLDOWN`, `FEED_INTERVAL`; the body is pinned at
  `beyond.PROCESSOR_POS`, the pile at `beyond.PROCESSOR_PILE`, and a carried
  bot is set down at `beyond.PROCESSOR_DROP`
- Hull knock frequency (42–95 s), bay hum level
- **PSX look** (`src/psx/psx_look.gd`, defaults in `docs/psx-look.md`):
  resolution (`lines`), dither/colour bits, snap, affine, filter, fog, draw
  distance, density (2 m), sprites/waves and the master switch. Scanlines are
  forced off. The `ps1` preset deliberately has no fog, so the authored bay and
  Cold Hold darkness survive. F5 is the live panel; F4 still suspends the look for the
  clean debug feed.

## Exit criteria (all of them)

- Radar navigation is *legible but frightening*, not confusing.
- The annex reads as a navigable loop with a recognisable cafeteria, not as
  maze padding; the extra space makes hosts feel elsewhere, not absent.
- The still camera reads as evidence, not a broken video feed: black lens,
  slow recharge, frozen grain.
- The first Cold Hold crossing produces a dark, open, escapable hold, four
  watchers that do not instantly kill at the threshold, a one-shot Collector
  sacrifice, and a readable crawler beat.
- A real module loss produces the "go back for it" reflex without making the
  player think they have gone blind.
- Nobody describes the game as broken (except the touchpad thing, which
  is documented in the README). A tester who dislikes the PSX look should call
  it a style choice; "the renderer is broken" means the master switch or pixel
  fit needs work.
- Mouse look works on foot, after pause and after closing F5, in every run.
- 3+ of 5 testers voluntarily do a second sortie after the first loss.

## Known benign warnings

`ObjectDB instances were leaked at exit` — a handful of AudioStreamWAV/
PlaybackWAV references held by the audio mixer at shutdown in headless
mode. Engine quirk, not live state; harmless in the editor too.
