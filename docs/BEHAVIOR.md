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

## Creature struct (partial)
| off | type | meaning |
|-----|------|---------|
| 0x40  | ptr | animation index blob |
| 0x48  | i16 | *tentative* state (`2` = special) |
| 0x4c  | i16 | current player tool / interaction (1..5) |
| 0x4e  | i16 | previous interaction |
| 0x50  | i16 | mood step for current interaction (±3) |
| 0x54  | u32 | last reaction time (ms) |
| 0x92  | i16 | active / alive flag |
| 0x9a  | i16 | facing direction 0..7 |
| 0xa6  | i16 | *tentative* x position |
| 0xa8  | i16 | *tentative* y position (thresholds 170 = 0xaa, 325 = 0x145) |
| 0x158 | i16 | mood, clamped −100..100 |
| 0x15a | i16 | *tentative* irritation / agitation level (compared to 2, 4) |
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
- Movement: per-direction speed, tank bounds, walls, depth scaling (StretchBlt).
- Stat decay rates; death conditions; what the real-time clock affects.
- Shadow rendering (dark palette range — darken blend?).
- Seq record fields `u32@0x24` (1 = ambient behaviour?) and `u32@0x28`.
- Meaning of per-direction flag bytes and `u16` at record `+0x46 + dir*0x924`
  (checked by `enqueue_anim` when `DAT_0044dc5a` is set).
