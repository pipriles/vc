# VC.EXE behaviour notes

Living document. Source: Ghidra decompile of `VC.EXE` (Chile Rose, built
1999-08-05) with `re/symbols.txt` applied (`tools/decompile.sh`).
Status markers: **confirmed** = read from code, *tentative* = inferred.

## What the program is

Not a desktop crawler: a **virtual pet terrarium** game, 640×480 window
(`CreateWindowExA(..., 0x280, 0x1e0)`), with an optional full-screen mode
(changes display resolution) and a "floating panel" window mode.

Screens / assets (VCG.DLL bitmaps):
- `4500` 1200×480 desert tank panorama, scrolled by a viewfinder
  ("Scan mode" = free pan, "Follow mode" = spider stays centred).
- `4501`, `4502` 640×480 cricket box (wicker room, apple slices, water bottle).
- `5000` 640×480 splash screen.
- Smaller bitmaps: tank objects, UI panels, icons, indicator bars (TBD).

Gameplay (from UI strings, **confirmed** text, mechanics TBD):
- Stats: food (hunger), water (thirst), health, mood. Death + "Resurrect".
- Real time: birth date, time alive, death date, "Freeze simulation".
- Food: crickets (tank / box / storage counts). "Out of food" when none left.
- Tank objects (unregistered: any 3): Waterbowl, Bell, Rock #1–3, Cactus
  #1–2, Yucca Plant, Water Fountain, Windpump, Skin (shed skin), log (plugin).
- Player tools: water, feed, follow cursor, stroke, prod, pick up & move,
  tap on the glass. "Remove all debris" (skins, cricket remains, footprints?).
- Name your pet. Sound on/off. Frame-rate display (`FPS:%02d`).

Port decision: needs keep changing in real time while the page is closed
(like the original, which stored timestamps), so state will be saved with
wall-clock timestamps and caught up on load.

Out of scope for the port: registration / trial limits, registry storage,
internet/website links, floppy-disk cricket "download", screensaver config.

## Timing **confirmed**
- Main tick: `SetTimer(hwnd, 1, 100)` → 10 Hz simulation and animation.
- `now_ms` = `GetTickCount()` sampled per tick; cooldowns compare against it.

## Randomness **confirmed**
- `rand` = MSVC LCG: `seed = seed*0x343FD + 0x269EC3; return (seed>>16)&0x7FFF`.
- Seeded once at startup with `srand(time(NULL))`.
- Idiom everywhere: `rand()*N / 0x7FFF` → integer in `[0, N]` (N only when
  rand() == 0x7FFF). Port must use the same integer maths.

## Animation system **confirmed**
- Sequence ids resolved by name at load (`map_sequence_ids`) into globals
  `seq_spider_*` / `seq_cricket_*`.
- Each creature has a 16-entry **animation queue**: entries of
  `{seq: i16, dir: i16, p4: i16, p6: i16}` at creature `+0x1f4`, count
  `+0x1f0`, dirty flag `+0x1ec`. `enqueue_anim(c, seq, dir, p4, p5, p6)`:
  - `dir == 8` → keep current facing (`+0x9a`).
  - `p5 != 0` (and creature not busy) → flush queue first (*tentative*).
  - Rejected while creature not active (`+0x92 == 0`) or anim not loaded.
  - p4 looks like a repeat count (walk uses `rand()*4/0x7fff + 4`).

## Playback: repeats and ping-pong **confirmed** (0x404830, 0x404600, 0x403210)
- A play counts its frames (`+0xb6`); when they run out:
  - tail bounces left (`+0xca`) → reverse and play the last `loop_len`
    frames (direction header +0x14);
  - else a pending back pass (`+0xb8` = 2) → reverse and play the whole
    thing back (n − 1 frames);
  - else plays (`+0xba`) − 1: another play restarts the sequence
    (re-rolling everything), none left → the sequence is done.
- At start, per direction: back pass always (+0x08) or 50 % (+0x04);
  tail bounces always (+0x10) or 50 % (+0x0c): K = loop_count rounded up
  to even, bounces = K + 1 + 2·rand_n(K) (K + 2 + … with a back pass, so
  it ends facing forward).
- Start rules (t = temperament): CRUSH one play, bounces (rand_n(t)+t)·8+8;
  LURK plays (rand_n(t)+t)/3; LURK_D rand_n(t)+t; THREAT rand_n(2)+1 plays,
  bounces rand_n(2)·2+2; GLASS one play, bounces (rand_n(t)+4+2t)·2; HAIR
  rand_n(2)+1; CLEAN rand_n(3)+2; KILL_RESET sound 457. Play counts only
  when not already given.
- Stopping early keeps the bounce parity (1 or 0 left).

## Creature tick (`creature_tick`, every 100 ms) **confirmed**
1. Bump counters tick down.
2. Frame hold: if the frame has a hold flag, hold for `hold` ticks
   (negative = `rand()*hold/0x7fff`).
3. Advance `frame += step`; past the end → one play done; after all plays
   pop the queue (turning first with CIRCLE steps if the queued direction
   differs) or run the idle chooser, then `start_sequence`.
4. Move if the sequence moves (`move_x` 60% per play, `move_y` always) or
   the frame has dx/dy: dirs 0/1/7 up, 3/4/5 down, 5/6/7 left, 1/2/3 right.
   x step = `sx`; y step = `sx` straight up/down, `sy` on diagonals.
   Running doubles speeds while walking.
5. `creature_update_position`: clamp x to [130, 1070] (walls) and y to
   [170 + h/3, 480 - h/2]; hitting a side marks the 3 directions into it as
   bumped for 5 ticks. Then
   `scale% = min(100, trunc(y/480 * size + 35))`,
   `sx = trunc(base_sx / (100/scale))`, `sy` likewise.
   Spider: base 5×3, size 40 when new (grows; SKIN = moult, TBD).

## Goals: walk somewhere, then play **confirmed**
`move_to_then_anim(c, target, type, x, y, dir, seq, timeout)` only stores a
goal (refused while hiding or above the floor line); it lets the current
play finish.
- Types: 1/2 chase a creature (crickets, TBD), 10 cursor, 11 point,
  12 only y matters (front glass), 13 only x matters.
- Arrival, checked every frame (`goal_check`): tolerance `9·sx` by `7·sy`
  around the target (bands for 12/13). On arrival the queue is flushed and
  `seq` queued facing `dir`; the current sequence ends at once. Not yet
  arrived but already level in x or y → end the current play early to
  re-steer. Goals expire after `timeout` seconds; target x is clamped to
  the wall margins.
- At each sequence end (`goal_step`): pick the heading from the offsets
  (x beyond ±4·sx, y beyond ±3·sy), 8 directions; queue WALK ×6 that way.
  If that direction is blocked, start a detour: remember the blocked
  direction ±1, rotate (cw or ccw depending on which side is blocked) to
  the first free direction and walk ×4; resume once the three directions
  around the original heading are free and the creature has moved. Facing
  a wall while detouring: back off sideways ×10 and drop the goal.
- Blocks: per-direction slots `+0xfa + 8d` {active, kind, id, ticks}.
  Walls set kind 5 only; every position update first ages all slots and
  clears those whose ticks run out, so a wall mark lasts one update.

## Hiding under the rock **confirmed** (except where noted)
- Idle: 1 in 51 picks, ≥ 12 min since the last LOG_HIDE: goal to
  (640, 170), then LOG_HIDE facing 7 (up-left), timeout 120 s. LOG_HIDE
  only plays at x 630–650, y < 174, size > 24.
- While LOG_HIDE plays (`spider_post_draw`, every frame) the spider is
  marked hidden and creeps left (frames > 8: −sx, > 17: a further
  −((100−size)/30 + 1)) and up (−1 − (100−size)/65 on frames
  (100−size)/25+4 .. 15), footsteps on odd frames, sound 411 on frames 23
  and 29. When it finishes the spider is moved to (422, 114) and lurks.
- Hidden: stays at (422 − (100−size)/2, 114) facing left, no turning.
  Each idle pick, ≥ 2 min after hiding: `rand_n(50) < temperament` and 20%
  → come out: walk left ×14 (flush), then down or down-left ×12.
- While hiding and above y 170 the floor clamp is off (y ≥ 114); back on
  the floor the hiding state resets (`creature_post_frame`).
- The rock overlay (vcg_4005, keyed) is drawn at (330, 84) after the
  spider whenever its y < 170.

## Glass **confirmed**
30% of idle picks, ≥ 3 min since GLASS last finished: goal type 12 (y only)
to y = 375 + (100−size)/2, then GLASS facing 4. GLASS is re-validated when
it comes off the queue and needs size > 49, so a young spider walks to the
front and lurks instead; since GLASS never finishes, its cooldown never
starts and it keeps going back (faithful to the original logic).

## Crickets and hunting **confirmed**
- 12 crickets (kind 2) start in the cricket box at x 50–490, y 290–420
  (box coordinates), base speed 8×6. In the tank: wall margin 80, floor
  y ≥ 180. Their depth scale uses the *spider's* size.
- Feeding: in the box view click a cricket (only while < 8 are in the
  tank), it is carried (PICKUP) and released into the tank (DROP). On
  release the spider decides (`spider_sees_cricket`): within 350×175 px,
  if hiding 20% chance it comes out instead; ignores it if
  food ≥ 65 + rand_n(25); else chases it (goal type 2, CATCH, timeout
  min(160 − food, 20) s). Web-stuck crickets within 200×140 are always
  chased (45 s).
- Cricket idle: turn with probability (rand_n(3)+4)/10, else a random
  sequence with frames (WEB_STUCK only when stuck). Web-stuck crickets
  lurk/chirp/struggle and keep calling `spider_sees_cricket`.
- Collision (`collide_mark`): each creature's hit rect is the frame box,
  scaled, at the drawn position, split into 3×3 cells mapped to directions
  `7 0 1 / 6 8 2 / 5 4 3`. Cells overlapping another creature (≥ 1/20 of a
  cell for crickets) mark that direction slot {active, kind, id}; the
  creature being chased is marked inactive (never blocks). Spiders and
  crickets don't block each other; other kinds do (move undone). Walking
  into anything marked in the facing direction ends the walk after this
  play.
- Response (`collide_respond`): spider touching a cricket (not hiding, not
  eating) drops its goal and queues CATCH towards it (flush, run) — again
  on every tick of contact. Cricket touching the spider: 50% if idle, flee
  with JUMP or WALK ×6–8, facing the same way or 2–4 steps round (wraps
  by 7, sic; the walk uses the spider's WALK id, sic).
- Chase arrival: when the target shows up in a direction slot → CATCH that
  way (run). Target gone back to the box → goal ends.
- CATCH: each frame the cricket is pulled 1/(frames left) of the way to
  (spider x, spider y + hit height/3). Last frame: cricket in the facing
  slot, or in the centre slot with the spider on the floor and 80% →
  eaten: +25 food, crickets-eaten +1, cricket removed (refilled into the
  box from storage), KILL queued, eating flag, crunch sound 450–452.
  Otherwise CATCH_RESET and the cricket jumps away (×1–3).
- KILL finished: eating cleared, cricket remains (vcg_4004, 1 of 6) left at
  the hit-rect centre (ring of 12), KILL_RESET then CLEAN ×2–3.

## Tank objects **confirmed**
Table built on the stack at startup (recovered by tracing the stores):

| # | object | bitmap | frames | depth | in tank | animation |
|---|--------|--------|--------|-------|---------|-----------|
| 0 | Waterbowl | 3000 | 5 (dry..full) | 0 | yes | fill level |
| 1 | Bell | 3008 | 11 | 0 | no | swing ×N, rest on 4, 2 ticks/frame |
| 2 | Rock #1 | 3002 | 1 | 0 | no | |
| 3 | Rock #2 | 3003 | 1 | 0 | no | |
| 4 | Cactus #1 | 3005 | 2 | 1 | no | |
| 5 | Cactus #2 | 3004 | 2 | 0 | no | |
| 6 | Rock #3 | 3001 | 1 | 0 | no | |
| 7 | Yucca Plant | 3006 | 10 | 2 | no | 1 frame per day (slow anim) |
| 8 | Water Fountain | 3007 | 8 | 1 | no | loop, sound 419 every 18–36 ticks |
| 9 | Windpump | 3009 | 4 | 2 | no | loop, every tick |
| 10 | Skin (kind 6) | – | 6 | – | – | crumbles, then gone |

- Objects are creature structs of kind 1 without animation data. Depth
  class sets the floor clamp: y ≥ 170 + h/3, h/6 or h/12; bottom
  y + h/2 < 480; x margin 130. Scale `min(100, 35 + 100·y/480)`.
- Hit rect: non-key bounds of frame 0 (`object_content_bounds`), scaled.
  Shadows are colour 49 in the object bitmaps, drawn in the shadow pass.
- Start: random x = rand_n(1200) − w, y = rand_n(480) − h + 170 (then
  clamped); the bowl starts half full (frame 2).
- Objects block creatures: a creature whose facing cell overlaps one is
  put back where it was and its walk ends; the goal steering detours.
- New spider: random facing, then the free-spot search (`place_free`:
  random point, step 50 px right / down until the position update leaves
  it unchanged), then faces the first free direction.

## Water **confirmed**
`spider_thirst`, once a minute and whenever the spider touches the bowl
(facing it): only if water < 81. A counter cycles 0..4.
- Bowl in the tank, spider facing and touching it, level > 0: drink,
  +20 water, level −1, sound 457.
- Otherwise every 5th call: go to the bowl (goal type 1, arrive on touch),
  then LURK.
- No bowl: every 5th call with water < 51, go and wait at the bell.
- Hungry (food < 26) with the bell in the tank: every 5th minute go and
  wait at the bell (in front of or behind it, by where the spider is).

## Player tools **confirmed**
Hand tools (cycled by the hand button, icon strip vc_304): 0 tap on the
glass, 1 pick up and move, 2 prod, 3 stroke, 4 follow the cursor.
- Cursor sets (RT_GROUP_CURSOR 200 + 10·set, frames 240/241 …): 0 pointer,
  1 open hand, 2 hand over something grabbable, 3 grabbing, 4 prod ×2,
  5 knock ×2, 6 tap hover, 7 stroke ×2. A cursor frame lasts 4 ticks.
  Each time the knock / prod / stroke cursor loops back to frame 0 it plays
  its sound (404 / 410 / 411) and sets the spider's interaction to tap (2)
  / prod (1) / stroke (3).
- Tap: holding the button anywhere in the tank. Prod / stroke: holding it
  on the spider (if it could be picked up). Pick up: the spider (PICKUP,
  sound 405; carried it plays PICKUP and counts as interaction 5, released
  it plays DROP), a cricket in the tank (sound 407) or an object (dragged;
  dropped below the tank it is put away). Follow: the spider walks after
  the pointer (goal type 10, LURK_D on arrival, interaction 4).
- The spider can be picked up unless something is carried, it is eating,
  hiding, above the floor line or dead. Hit test: hit rect shrunk by 1/8.
- Pointer within 20 px of the left/right edge scrolls the viewfinder 20 px
  a tick for 8 ticks; follow mode re-centres on the spider every frame.
- Buttons: feed opens the cricket box (click a cricket, < 8 in the tank,
  to carry it into the tank); water raises the bowl one level (sound 402;
  water < 35 sends the spider to the bowl); clear removes remains,
  footprints and webs. Every button click plays 400.

## Reactions to the tools **confirmed**
`spider_react_tool` (every tick while an interaction is pending):
- Ignored (except tap) while eating or above the floor; at most every
  2.5 s; not while heading for the rock.
- Mood step on a new kind of interaction: prod, tap, carry push mood
  away from 0 by 3, stroke and follow pull it back by 3; repeated
  interactions keep the step. Mood clamped to ±100.
- Hiding: a tap may bring it out (temperament > 2, rand_n(8) < temperament).
- Then a decision tree by interaction and temperament (ported line by line
  in `src/spider_react.odin`): grumpy spiders walk off and crush, threaten
  or flick hairs (from the glass if far back) or flee under the rock;
  calm ones lurk, come to the glass where it was tapped, or crush (stroke
  with temperament ≥ 6).

## UI and views **confirmed**
- Button row at y 420 from x 20, each button 4 px after the previous one:
  tools, feed, water, scan/follow, close-up, whole tank, clear, options,
  website, floating panel (command = icon resource id − 300). Hovered
  button: ring animation (vc_320, 14 frames) and its tooltip 16 px above;
  pressed: drawn at 70 %.
- Indicators at y 13: mood gauge (1000, 8 frames = temperament) at x 342,
  then health (1003), water (1002), food (1001), 10 frames each
  ((value−1)/10); below 31 they blink on frame 0, below 10 they vanish on
  alternate blinks. Pet name at (10, 10) in the bitmap font vcg_2008
  (white glyphs on black, A–Z 0–9, offsets at 0x431248). The logo (bottom
  right) cycles three states: all shown → indicators only (the buttons
  slide down 10 px a tick) → nothing (the indicators slide up 14 px a
  tick) → all (the indicators slide down, the buttons appear at the end).
  Each slide lasts 7 ticks; buttons stay clickable until it ends.
- Close-up (button 0): the spider's 320×200 canvas box, clamped to the
  tank, stretched to the view; any click returns.
- Whole tank (button 1, switches to the pick-up tool): the tank scaled to
  640×256; below it a panel of 96×96 cells (5 per row from x 60, y 260)
  with the objects not in the tank (dithered background, colour 1, 2 when
  hovered; corners vcg_2009; names). Drag objects between the panel and
  the tank; a click elsewhere returns and restores the tool. (The
  unregistered original allowed 3 objects in the tank.)

## Pauses and frame events **confirmed** (`creature_post_frame`)
Run on every frame advance. A pause (`+0xf8`) freezes the creature
(no frames, no movement) for that many ticks.
- WALK frames 0 and 3: unless following the cursor or chasing,
  `rand_n(14) < temperament/2` → pause `rand()*temperament*2/0x7fff + 5`;
  health < 16 and `rand_n(6) == 2` → pause `rand()*(8−temperament)*2/0x7fff
  + 11`. While following/chasing: `rand_n(10) == health/10` → pause
  `rand_n(10) + 8`.
- THREAT: frame 9 hiss (459); last frame pause 8–16. CRUSH: last two
  frames pause 15–30 (cut short if a tool interaction is pending).
- LURK ending facing up/down against the bell (within 29 px / 0–49 px):
  the bell swings 60 times — the spider rings it.
- Sequence start (`0x403210`): no running while turning if health < 30,
  or walking if health < 15 or blocked; a running walk plays at double
  frame step; a cricket chirps (401) when CHIRP starts in the visible view.

## Sound **confirmed**
`play_sound` (0x415f00) is a 4-channel software mixer: channel 0 for the
eating crunches 450–456 (they cut it off); everything else takes the first
free channel of 1–3 and is skipped if all are busy or the same sound is
already playing (the bell 466 excepted). Two loops: running water 465 while
the fountain is in the tank (not in the box view, channel 1) and scraping
403 while an object is dragged and moving (channel 2). The fountain splash
419 is muted in the box view.

| id | sound | id | sound |
|----|-------|----|-------|
| 400 | button click | 450–452 | crunch on catching |
| 401 | cricket chirp | 453–456 | eating |
| 402 | water poured | 457 | drinking |
| 403 | object dragged (loop) | 458 | hair flick |
| 404 | knock on the glass | 459 | threat hiss |
| 405 | spider picked up | 460 | footstep |
| 406 | spider dropped | 461, 462 | cleaning |
| 407 | cricket picked up | 463, 464 | at the glass |
| 408 | cricket dropped | 465 | fountain water (loop) |
| 409 | cricket lands a jump | 466 | bell |
| 410 | prod | 411 | stroke / crawling under the rock |
| 412, 413 | laying a web | 419 | fountain splash |

## Time away, death and resurrection **confirmed**
`offline_catch_up` (0x415430) runs when the program starts and replays the
minutes M since it was closed (the port also runs it when a hidden page
comes back after ≥ 3 minutes):
- M < 3: nothing, except a hidden spider is put back under the rock.
- M ≥ 60: mood becomes rand_n(200) − 100. Crickets in the tank are
  moved to free spots.
- Steps of 1, 2, 3 or 90 minutes (M < 30, < 60, < 90, else). Each step:
  water −(acc/75) per 150 min, food −(acc/60) per 120 min; water < 80 →
  drink from the bowl (+20, level −1); food < 26 → 50 % per tank cricket to
  eat one (once per step), else wander and maybe lay webs (≤ 3 a day);
  then the needs are recomputed and **health < 1 kills the spider**
  (temperament 0, date of death recorded).
- Afterwards the remainders carry into the live decay timers; a dead
  spider leaves the yucca wilted; otherwise 50 % (more if grumpy) the
  spider is found hiding under the rock.
- Health is min(food, water) + 1 once either is below 41, and 0 below 2,
  so the spider dies when food or water reaches 0. From 30/30 untended:
  about 28–30 hours. The original only checks this in the catch-up, so a
  spider starving while the program runs dies at the next start.
- Dead: lies on its DEAD frame (the first direction after 0 that has
  frames), no needs, no tools, no hunting; "YOUR CREATURE HAS DIED!" after
  a few seconds.
- Resurrect Creature (0x404230): refused while alive or with no crickets
  left anywhere; otherwise clears debris, revives as a newborn (size 40,
  food/water 30, mood 0, birth date now, DROP), resurrections +1, yucca
  frame 8.

## Growth and moulting **confirmed** (`spider_growth` 0x403ac0, 0x408d50)
- Size = min(100, 40 + minutes alive / 360): one point every 6 hours,
  full grown after 15 days. Recomputed every game minute.
- Moults are only checked while starting up (after time away): days 5–15,
  and from day 28 in every 28-day cycle on its first 5 days. At most one a
  day, and only when no shed skin is lying in the tank.
- The skin lies at x 200–999, y 170–389, facing 0 or 1, the spider's size;
  it crumbles one frame per 1920 minutes and is gone after 3.
- Yucca grows back one frame per 1440 minutes (wilted while dead).

## Webs and footprints **confirmed** (0x408430, 0x408880, 0x408b70)
- Decals are drawn into the 1200×480 floor surface once; they stay drawn
  until the floor is rebuilt (start-up or Clear).
- Footprints: walk frame 3 and circle frames 0/6 (±2 px jitter) on the
  floor; ring of 500.
- Web pieces: WEB_LAYING frame 3 lays a piece behind the spider, frame
  chosen by facing and play number; ring of 100, 2880-minute lifetime.
  The catch-up also lays them (≤ 3 times a day). Crickets overlapping
  half their hit box get stuck (the spider notices); otherwise 70 % turn
  away.
- Corner webs (bitmaps 4000–4003) appear only during the catch-up;
  stages grow every day (4 stages; the big fourth web needs the other
  three and lasts 3 days).
- Clear removes remains, footprints and web pieces and frees crickets.

## Rendering **confirmed**
- Scene is composed into an 8-bit 1200×480 surface; the 640×480 view is a
  window at `scroll_x` (panning moves 20 px per tick).
- Creatures drawn in render-list order with `blit_creature`: the frame
  canvas scaled to scale% (StretchBlt COLORONCOLOR = nearest), centred on
  the creature's centre; skips the key colour and `key2` (dir header byte,
  0x31 = 49 = shadow colour).
- Shadows: before any bodies, `blit_shadow` copies only the key2 pixels of
  every creature, as solid colour 49 (#2c2418). No blending.
- Clamps for animated creatures: y ≥ 170 (180 for crickets), and
  y + drawn_h/3 < 480 using the previous frame's drawn height.
- Tank and creature buffer share a palette (bitmaps 4500/9100); the other
  bitmaps differ only at index 71.

## Idle behaviour **confirmed**
`creature_idle` (queue empty): spider turns one step (random cw/ccw) with
probability (rand_n(5)+4)/10 unless it just turned; otherwise `spider_idle`:
1. food ≤ rand_n(10)+25 and 50%: queue WALK random dir, 4–8 plays.
2. food ≤ rand_n(10)+25 and 20%: queue LURK, 2–4 plays.
3. temperament < 4 and `rand()*temperament*10/0x7fff < 2`: queue CRUSH.
4. Else pick: WALK with prob temperament/20, else a random sequence; must
   pass `spider_wants_seq` (WALK by temperament, CRUSH ≥30 s apart, THREAT/
   HAIR only after interaction, CLEAN `rand_n(15) < 2*temperament`,
   WEB_LAYING when food < 36), not repeat, not CIRCLE, have frames, and its
   precondition if flagged (GLASS near the front glass, LOG_HIDE at the log
   x 630–650 y < 174). Gives up after 8 tries → LURK 60% / WALK.
5. 1/51 chance (≥12 min apart) go hide under the rock; 30% (≥3 min apart)
   go to the front glass (see below).
Crickets: random sequence with frames in the current direction.

## Needs **confirmed** (`spider_stats_tick`, every second)
- health = (food+water)/2, or min+1 when either < 41; below 50 each pulls
  it down; mood adds +10 (|mood|<30), 0, −10 (≥50), −20 (≥80). Clamp ≤100.
- temperament = floor(((100−|mood|)/2 + health/2) × 0.07), +1 if the
  fraction ≥ 0.7 → 0..7.
- water −2 every 2.5 h, food −2 every 2 h (real time), mood −1 per minute
  (wraps −101 → 100, a bug in the original), interaction flag cleared.
- Hungry (food < 26) with a cricket in the tank: every 5th minute stalk it.

## Creature struct (partial)
| off | type | meaning |
|-----|------|---------|
| 0x40  | ptr | animation index blob |
| 0x48  | i16 | hiding state (log) 0 = out, 1..3 |
| 0x4c  | i16 | current player tool / interaction (1..5) |
| 0x4e  | i16 | previous interaction |
| 0x50  | i16 | mood step for current interaction (±3) |
| 0x54  | u32 | last reaction time (ms) |
| 0x92  | i16 | active / alive flag |
| 0x98  | i16 | current sequence |
| 0x9a  | i16 | facing direction 0..7 (0 = up, clockwise) |
| 0x9c  | i16 | scale percent |
| 0x9e, 0xa0 | i16 | base speed x, y |
| 0xa2, 0xa4 | i16 | current speed x, y |
| 0xa6, 0xa8 | i16 | centre x, y in the tank |
| 0xae, 0xb0 | i16 | draw x, y (centre − canvas/2) |
| 0xb2, 0xb4 | i16 | frame, frame step |
| 0xba  | i16 | plays left |
| 0xbc  | i16 | previous sequence |
| 0xc4, 0xc6 | i16 | moving x/y this play |
| 0xf4  | i16 | creature kind / location (0 spider floor, 2 cricket, 4, 6) |
| 0xfa + 8d | i16 | bumped-wall counter for direction d |
| 0x152 | i16 | run (double speed) |
| 0x158 | i16 | mood −100..100 |
| 0x15a | i16 | temperament 0..7 |
| 0x15c, 0x15e, 0x160 | i16 | health, food, water |
| 0x174 + 4s | u32 | time sequence s last played |
| 0x1e6 | i16 | size / growth (40 new) |
| 0x1ec..| | animation queue (above) |

## Spider reaction to tools (`spider_react_tool`) — partial
- Ignored within 2500 ms of the previous reaction, or while hiding under the log.
- Repeated same tool keeps the mood step; a new tool sets it:
  tools 1, 2, 5 → +3 if mood ≥ 0 else −3; tools 3, 4 → −3 if mood ≥ 0 else +3
  (*tentative* sign reading). Mood clamped to ±100.
- Tool 1 at low irritation: 40% walk off (random dir, 4–5 steps), else
  threat or hair-flick (`THREAT` / `HAIR`), or retreat under the log
  (`move_to_then_anim(…, 0x280, 0xaa, …, LOG_HIDE, 0x78)`).
- Remaining cases (2..5) to be decoded.

## Open questions
- Remaining tool cases, idle behaviour loop, hunting (CATCH/KILL/cricket AI).
- Growth and moulting; death and resurrection; footprints and footstep
  sound (`creature_post_frame`).
- Tank objects (kind 1), webs, player tools and UI, the cricket box view.
- Bell ringing (what sets the swing count), yucca growth start state,
  fountain as a water source.
- The UI sliding in/out when toggled (the port toggles instantly).
