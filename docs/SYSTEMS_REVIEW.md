# Virtual Creatures: systems review (original vs port)

A review of the whole of VC.EXE (Chile Rose / Red Knee builds share the same
code), system by system, against the port. Written 2026-10-13; every
difference it found (D1–D16, item 14) has since been fixed or settled, and
the sections below describe the port as it is now.

## Scope and method

The Ghidra decompile (`re/VC_EXE.annotated.c`) has 349 functions:

- **173 game functions** (0x401000–0x41ff90). Every one was read and sorted
  into the systems below.
- **176 C runtime functions** (0x4201a0 up: `rand`, string, maths, heap,
  file I/O, locale, start-up). Of these only `rand` (0x4201a0, the MSVC
  LCG) and the x87 float behaviour matter; the port reproduces both
  (`rng.odin`, `x87.odin`, with fixture tests).

Each system was compared with the port function by function. "Line by
line" means every branch, constant and random draw was checked; "checked"
means the behaviour and constants were checked but not every line.

Status key: **Same** = ported as the original. **Fixed** = a difference
found in this review (numbered, see the list at the end), now ported as
the original. **Port** = deliberately changed or added for the browser
(agreed earlier). **Not ported** = left out on purpose.

## System map

| # | System | Original functions | Port | Status |
|---|--------|--------------------|------|--------|
| 1 | Start-up and resources | 0x417920 WinMain, 0x417e00 (msg 0x8002), 0x41a790 setup, 0x40b2f0/0x40b9e0 DLL + sequence ids, 0x4169f0/0x412460/0x405fe0 bitmaps, 0x41b590 fonts, 0x41c8e0 palette, 0x41c800 cursors | `main.odin`, `tank.odin` (`tank_init`, `tank_reset`), `vcg.odin`, `bmp.odin`, `tools/extract.py` | Same (D1, D2, D16 fixed) |
| 2 | Main loop and timing | 0x417e00 WM_TIMER / msg 0x8001, 0x40ca70 main update | `tank.odin` (`tank_tick`, `tank_advance`) | Same (D7, D8, D11 fixed) |
| 3 | Animation engine | 0x404600, 0x404830, 0x405900, 0x406680, 0x406780, 0x408120–0x408290, 0x414700, 0x414840, 0x414a30, 0x40ca40 | `creature.odin`, `vcg.odin` | Same (line by line) |
| 4 | Frame events | 0x404b20, 0x4057b0 | `frame_events.odin`, `cricket.odin` | Same (line by line) |
| 5 | Movement, collisions, goals | 0x406df0, 0x407d00, 0x40bdd0, 0x40bf10, 0x40c120, 0x40c6a0, 0x4086b0 | `creature.odin`, `objects.odin`, `path.odin` | Same (D1, D3, item 14 fixed); Port: body box, routing |
| 6 | Spider AI | 0x4010c0, 0x401420, 0x402760, 0x402d60, 0x402f40, 0x403000, 0x403210, 0x403520, 0x403770, 0x403e90, 0x404010, 0x404180, 0x407830 | `spider.odin`, `spider_react.odin`, `cricket.odin`, `objects.odin` | Same (line by line, D4 fixed); Port: senses, held spider, glass trips |
| 7 | Cricket AI | 0x407830 (cricket part), 0x403770, 0x404b20, 0x406780 (webs) | `cricket.odin`, `floor.odin` | Same (line by line) |
| 8 | Needs, growth, life cycle | 0x401000, 0x403ac0, 0x403c90, 0x404230, 0x404490, 0x404580, 0x408350, 0x408630, 0x408b70, 0x408d50, 0x415430, 0x415cc0, 0x41f4d0, 0x41f710, 0x41d0f0/0x41d460/0x41d710 | `spider.odin`, `growth.odin`, `persist.odin`, `floor.odin` | Same (line by line; D2, D7, D10 fixed); Port: live starvation |
| 9 | Player input and tools | 0x417e00 (mouse, keys), 0x403a60, 0x416be0, 0x4062d0, 0x41c890, 0x408140 | `tools.odin`, `ui.odin`, `web/main.js` | Same (D3–D6 fixed); Port: touch, pan, edge scroll |
| 10 | Typed commands | 0x409de0 | `commands.odin` | Same (line by line) |
| 11 | Rendering | 0x40ca70, 0x416d20, 0x416e40, 0x417180, 0x417390, 0x412600, 0x4126d0, 0x4127b0, 0x412880, 0x41c160, 0x41c2e0, 0x408c70, 0x408430/0x408550, 0x408880/0x408af0, 0x417600, 0x41c9b0/0x41ca80 | `tank.odin`, `floor.odin`, `objects.odin`, `bmp.odin`, `views.odin` | Same (checked; D9 fixed, D14 left as agreed) |
| 12 | Intro | 0x40ca70 (stage < 3), 0x412940, 0x41c9b0, 0x41ca80 | `intro.odin` | Same (line by line) |
| 13 | Interface: buttons, indicators, tooltips, name | 0x4060b0, 0x4064b0, 0x4065b0, 0x40e990, 0x411fe0, 0x412130, 0x412280, 0x40e2a0, 0x41c4b0 | `ui.odin` | Same (checked; D15 fixed); Port: smooth slide |
| 14 | Views: close-up, whole tank, cricket box | 0x40ca70 (views 1–3), 0x40e360, 0x40e930 | `views.odin`, `cricket.odin`, `tools.odin` | Same (checked) |
| 15 | Options box | 0x40ed40, 0x406350, 0x41da00, 0x4043f0 | `options.odin` | Same (strings checked); Port: settings items |
| 16 | Messages | 0x41f7f0, 0x41f8e0 (dialog), 0x417e00 timer (death, low crickets) | `web/main.js` message box, `persist.odin` | Same (D8, D12 fixed); Port: shown while running |
| 17 | Sound | 0x415f00, 0x416510, 0x416680, 0x416920 | `web/mixer.js`, `host_sound` callers, `tank.odin` `sound_loops` | Same (mixer tested sample by sample) |
| 18 | Saving | 0x414a60, 0x414df0, 0x415c30 | `persist.odin`, `web/main.js` | Port format (D13 fixed) |
| 19 | Registration and time limit | 0x4059f0, 0x405db0, 0x405f50, 0x408f40, 0x409170–0x409db0, 0x41be00 | – | Not ported |
| 20 | Internet and floppy | 0x40a670, 0x40a9a0, 0x40aa10, 0x40add0, 0x4177e0, 0x41f690 | – (website button opens an archive) | Not ported |
| 21 | Floating window and tray icon | 0x41df50, 0x41de60, 0x41dd70, 0x41fe20, 0x41ff70, 0x41dbc0, 0x417e00 (0x800a menu, 0x8014–0x8017) | picture-in-picture panel (`main.js`) | Not ported (replaced) |
| 22 | Screensaver (VC.SCR modes) | 0x412a20, 0x412d50, 0x413300, 0x4133a0, 0x4138a0, 0x413960, 0x413b30, 0x413c00, 0x413ce0, 0x413dc0, 0x414190, 0x414450 | in-page screensaver mode | Not ported (replaced) |
| 23 | Freeze simulation | 0x417e00 (menu), 0x40ed40 item, checks of 0x455d58 everywhere | – | Not ported |
| 24 | Display mode and window | 0x41cbb0, 0x41cd70, 0x41c8c0, 0x413960 | browser full screen | Not ported (replaced) |
| 25 | Usage statistics | 0x4176c0, 0x4176e0, 0x417740, 0x417680 | – | Not ported |

## The systems

### 1. Start-up and resources

The original reads its settings and save, loads VCG.DLL / VCG2.DLL (the
plugin's sequences are appended and looked up by name, last match wins),
builds the object table, places the spider, 12 crickets in the box, the
objects and the shed skin, then runs the intro.

Port: same data (extracted from the installers), same sequence look-up,
same table and placements.

- **D1 (fixed): trimmed object hit boxes.** After measuring each object's
  bounds, setup shrinks the boxes of the tall objects (0x41a790): both
  cacti and the fountain keep only their lower half (cactus #1 also loses
  its left third), the bell its lower three quarters, the windpump its
  bottom quarter, the yucca is trimmed top, bottom and sides. These boxes
  block creatures, sort the draw order and catch clicks. The port trims
  them the same way (`trim_box`), and also leaves out the shadow (port
  choice) except for the draw order, which keeps the original's bottom.
- **D2 (fixed): the yucca starts small** (frame 8) and grows one frame a
  day.
- **D16 (fixed):** at a fresh start the bowl stays at its random spot (it
  may overlap the spider), and the crickets' first sequence comes from the
  idle chooser, as in the original.
- Per-frame draw offsets (tables at +0x608/+0x688 of each direction) aren't
  read by the port: they're zero in every animation, so this changes
  nothing.

### 2. Main loop and timing

A 100 ms Windows timer. Each tick (when the chosen frame time, 100/71/55
ms, has passed): cursor animation, low-needs blink, edge scroll, the main
update (every creature and object updated and drawn in depth order), and
every second the stats update, the cricket count, and every 59 seconds the
"minute" update.

Port: the same steps per tick, with the frame rates and smooth motion
(port) on top.

- **D7 (fixed): the minute update runs every 59 s** (a per-second counter
  that resets after 58).
- **D11 (fixed): update order.** Everything is ticked in last frame's draw
  order (spider, crickets and objects interleaved by depth), then the draw
  order is sorted again; the second's stats update comes before the
  minute's.

### 3. Animation engine — Same

Sequences, play counts, ping-pong and tail bounces, holds, the queue (with
its busy flag), turning with CIRCLE, the start rules, stop/flush, the
per-frame displacement (with the reverse and lock-scale tables). All fixed
in the last two audit rounds and now line by line the same.

### 4. Frame events — Same

Footsteps and prints, sounds on frames, pauses, ringing the bell, laying
webs, the catch pull and kill, creeping under the rock. Line by line.

### 5. Movement, collisions, goals

Clamping, depth scale, speeds, 3×3 collision cells, the touch reactions,
goal types 0/1/2/10/11/12/13, arrival, detours, timeouts.

- **D1** (above): the trimmed object boxes are part of this system.
- **D3 (fixed): the Follow tool's goal follows.** The cursor goal (type 10)
  takes the pointer's current position every frame, so the spider keeps
  walking after the pointer as you move it.
- **Item 14 (fixed): collisions.** The original's object rules are in
  (an overlap shallower than a quarter of the box only blocks sideways;
  walking to a goal, the bell doesn't block while it overlaps at most
  half; the chased target never blocks, except the bell), applied to the
  port's body box (the middle 60 % of the frame box) with a one-third cell
  threshold, so the spider fits narrower gaps.
- Port: route planning, edging round corners, unsticking, detour timeouts.

### 6. Spider AI — Same

Stats and temperament, idle choice, wants and preconditions, reactions to
every tool, finished hooks, thirst and the bell, noticing crickets. Line
by line.

- **D4 (fixed): being followed is an interaction.** While the spider walks
  after the cursor with the Follow tool its interaction is set to 4
  (0x40bf10), so it reacts every 2.5 s: mood moves towards calm, and it may
  give up following, threaten, show its hairs or hide.
- Port: senses (noticing area, stalking, bowl memory, exploring), cricket
  rescue, no reactions queued while held (it stays on PICKUP), glass trips
  counted from the trip.

### 7. Cricket AI — Same

Idle choice, fleeing the spider, webs, the box, being dropped. Line by
line.

### 8. Needs, growth and the life cycle — Same

Needs decay, health, temperament, growth (one point every 6 hours),
moulting, the skin, the yucca, webs ageing, the catch-up after time away,
death and its date, resurrection. Line by line after the last two rounds.

- **D2, D7** (above).
- **D10 (fixed):** Clear (and resurrection) stops every cricket's current
  play, and frees the stuck ones.
- Port: the spider can starve while you watch (the original only checked
  for death in the start-up catch-up). Time with the page hidden is
  replayed tick by tick when it comes back, as the original ran on while
  minimized (silently; over an hour, the catch-up takes the whole minutes).

### 9. Player input and tools

Mouse, keyboard, cursors, the five tools, carrying, the whole-tank and box
clicks, edge scroll.

- **D3, D4** (above).
- **D5 (fixed): right-click while carrying a cricket** moves it between the
  tank and the box, switching the view.
- **D6 (fixed): picking up a cricket stuck in a web frees it.**
- Port: edge scroll only while carrying, pan with a right-drag or two
  fingers, touch input, the right button's click-vs-drag, keys 1–5 pick a
  tool.

### 10. Typed commands — Same

All 19 words, plus the port's CRICKET. Port: its own shortcuts (debug,
full screen) need Shift so typing a command doesn't set them off.

### 11. Rendering — Same (checked)

Decoding RLE frames, the per-frame transparent colour, scaling, the shadow
pass then the body pass, depth order (with the spider in front while on
the glass), the floor surface with prints, web pieces and corner webs, the
rock in front of a hiding spider, the logo skin, palette fades.

- **D9 (fixed):** when the floor is rebuilt (start-up, Clear) web pieces
  are drawn first and footprints over them.
- **D14 (left as agreed):** the original only clips sprites at the
  left/right edges when drawn at full size; scaled sprites crossing an edge
  wrap into the next row (a visual glitch). The port clips properly.

### 12. Intro — Same

### 13. Interface

Button row (10 buttons, pressed at 70%, spinning ring), help strings and
right-click help pages, the four indicators with the low-needs blink,
tooltips, the pet's name and its editing, the logo toggling the UI, the
tools button while hidden.

- **D15 (fixed):** a tooltip that would run off the right edge is moved
  left so it ends 20 px short of it.
- Port: smooth slide animation (the buttons slide in rather than appearing
  at the end), no exit button, the original's GDI fonts regenerated as
  1-bit bitmaps (`web/gdifont.js`), tooltips drawn regular as in footage.

### 14. Views — Same (checked)

Close-up, whole tank with the object panel, the cricket box with its
counts (board in Arial bold, the tank count blinking when full, the total
when zero). Port: the original allowed at most 6 objects in the tank (3
when unregistered); the port lets all 10 in.

### 15. Options box — Same

Pages, wipes, help (161 lines), credits, prognosis, stats, settings and
utilities. All strings match, except the help's website entry and its
closing link, which point at the port's GitHub page. Port: the settings show Full Screen where
the original had Window Mode, Smooth Motion in the Freeze Simulation slot,
a Screensaver item with its idle time in Utilities, a Browser Port section
(with a support link) at the start of the credits, and Download Crickets adds 12 crickets
offline.

### 16. Messages

- **D12 (fixed): the death message** comes 20 frames into a dead spider,
  once per run. Port: it also shows when the spider dies while you watch,
  which the original couldn't.
- **D8 (fixed): the low-crickets warning.** When fewer than 6 crickets are
  left (box, store and tank together, counted each second) the port shows,
  once per run and 20 frames later, "YOU ONLY HAVE n CRICKETS LEFT!" (or
  "...CRICKET LEFT!" / "YOU DON'T HAVE ANY CRICKETS LEFT!") with "To
  download extra crickets, click on the 'Download Crickets' option in the
  'Utilities' menu from the Options dialog box." Neither shows in the
  screensaver.
- Port: messages from New Spider, Resurrect Creature (when refused),
  Download Crickets and the floating panel.

### 17. Sound — Same

8-bit 11 kHz mono, double-buffered 2048-sample blocks, four channels
(channel 0 for the crunches 450–456, 1 the fountain loop 465, 2 the drag
loop 403, otherwise the first free of 1–3, no repeats except the bell),
the windpump creak muted in the box view. Port: gritty / smooth / modern
modes and a volume control.

### 18. Saving

The original writes its whole state to vc.dat every 5 minutes and on exit
(the creature structs, objects, crickets, prints, webs, settings, name).
The port saves its own JSON (`localStorage`, one save per variant) every
minute, when the page is hidden and when it's closed. A save the game
can't use (unreadable, or another save version) gives way to a new pet; the
page warns in the console and keeps a copy as `vc-save-<variant>-unusable`.

- **D13 (fixed): what each creature is doing is kept**: sequence, frame,
  plays, bounces, holds, pause, goal (with its elapsed time), eating, the
  target, which crickets are stuck in webs, and (port) the queue: the
  original didn't keep it, but only loaded at start-up, where its catch-up
  put a spider up on the back wall under the rock again. The port loads on
  every page load; without the queue, a spider saved while coming out from
  under the rock lost its walk down and was stuck up there, unpickable. A
  spider coming out with nothing queued now walks down anyway.

## Systems not ported

| System | What it did | Why |
|--------|-------------|-----|
| Registration and time limit | Serial checks against the disk and Windows install, a hidden file (Hptxc.dat) and registry keys counting days; the unregistered version allowed 3 of the first 5 objects, no typed commands, no freeze, and showed "TIME UP!" | Agreed out of scope |
| Internet and floppy | Download Crickets and the website through the browser with registration data in the URL; copying crickets to a floppy disk | Agreed out of scope; Download Crickets adds 12 offline, the website button opens an archive |
| Floating window and tray icon | A shaped mini-window showing the spider, with feed/water/close buttons, "Interrupts" (pops up when the spider is hungry or thirsty) and a tray menu (Interrupts, Sound, Restore, Exit) | Replaced by the picture-in-picture panel |
| Screensaver modes | VC.SCR: non-interactive VC, and Cricket Swarm (crickets swarming over the desktop), with its settings dialog | Replaced by the in-page screensaver mode; Cricket Swarm left out |
| Freeze simulation | Stopped time for the pet (frozen time subtracted from its age) | Agreed out of scope |
| Display mode | Switching the screen resolution for full screen, window mode at 800×600 or more | The browser's full screen |
| Usage statistics | Counters of time run, times starved or dehydrated | Not shown anywhere in the game |
| Exit button | Top-right "Click here to exit" | Not needed in a page |

## Port additions (agreed)

Senses and hunting, route planning, unsticking, cricket rescue, the
CRICKET command, live starvation, smooth motion and higher frame rates,
the mixer modes and volume, the in-page screensaver, picture-in-picture,
the mobile layout and touch input, panning, a New Spider button, the debug
overlays, and no limit on objects in the tank (the original's was 6).

## Differences found in this review

| # | Difference | Size |
|---|------------|------|
| D1 | Object hit boxes not trimmed (tall objects block and catch clicks too high) — **fixed** | Large |
| D3 | Follow tool: the spider doesn't keep following the pointer — **fixed** | Large |
| D4 | Follow tool: no reactions to being followed — **fixed** | Medium |
| D2 | Yucca starts fully grown and never grows — **fixed** | Medium |
| D5 | Right-click while carrying a cricket doesn't move it to/from the box — **fixed** | Medium |
| D8 | No low-crickets warning — **fixed** | Small |
| D6 | Picking up a web-stuck cricket doesn't free it — **fixed** | Small |
| D7 | Minute update every 60 s instead of 59 s — **fixed** | Small |
| D13 | Save doesn't keep the current animation, eating or web-stuck crickets — **fixed** | Small |
| D12 | Death message after 30 frames instead of 20 — **fixed** | Small |
| D9 | Floor rebuild draws footprints under webs instead of over — **fixed** | Small |
| D10 | Clear stops only stuck crickets — **fixed** | Small |
| D11 | Update order within a tick — **fixed** | Small |
| D15 | Tooltips not moved left to fit — **fixed** | Small |
| D16 | Fresh start: bowl placed in a free spot, crickets start on LURK — **fixed** | Small |
| D14 | Sprite edge clipping (original glitch) — **addressed**: left as is (agreed), the port clips properly | Info |
| 14 | Collision rules (open from the last audit) — **fixed** (the three missing rules added on top of the port's body box) | Large |
