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

## Rendering **confirmed**
- Scene is composed into an 8-bit 1200×480 surface; the 640×480 view is a
  window at `scroll_x` (panning moves 20 px per tick).
- Creatures drawn in render-list order with `blit_creature`: the frame
  canvas scaled to scale% (StretchBlt COLORONCOLOR = nearest), centred on
  the creature's centre; skips the key colour and `key2` (dir header byte,
  0x31 = 49 = shadow colour). Shadows come from another pass (TBD).
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
5. 1/51 chance (≥12 min apart) walk to the log and hide; 30% (≥3 min apart)
   walk to the glass (needs `move_to_then_anim`, TBD).
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
- Shadow pass; `move_to_then_anim` (walk to a point, then play); growth
  and moulting; death and resurrection; hiding under the log.
- Tank objects, crickets and hunting (CATCH/KILL), player tools and UI.
