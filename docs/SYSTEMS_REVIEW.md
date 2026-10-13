# Virtual Creatures: systems review (original vs port)

A review of the whole of VC.EXE (Chile Rose / Red Knee builds share the same
code), system by system, against the port. Written 2026-10-13.

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

Status key: **Same** = ported as the original. **Differs** = a known
difference (numbered, see the list at the end). **Port** = deliberately
changed or added for the browser (agreed earlier). **Not ported** = left
out on purpose.

## System map

| # | System | Original functions | Port | Status |
|---|--------|--------------------|------|--------|
| 1 | Start-up and resources | 0x417920 WinMain, 0x417e00 (msg 0x8002), 0x41a790 setup, 0x40b2f0/0x40b9e0 DLL + sequence ids, 0x4169f0/0x412460/0x405fe0 bitmaps, 0x41b590 fonts, 0x41c8e0 palette, 0x41c800 cursors | `main.odin`, `tank.odin` (`tank_init`, `tank_reset`), `vcg.odin`, `bmp.odin`, `tools/extract.py` | Same, except D1, D2, D16 |
| 2 | Main loop and timing | 0x417e00 WM_TIMER / msg 0x8001, 0x40ca70 main update | `tank.odin` (`tank_tick`, `tank_advance`) | Same, except D7, D8, D11 |
| 3 | Animation engine | 0x404600, 0x404830, 0x405900, 0x406680, 0x406780, 0x408120–0x408290, 0x414700, 0x414840, 0x414a30, 0x40ca40 | `creature.odin`, `vcg.odin` | Same (line by line) |
| 4 | Frame events | 0x404b20, 0x4057b0 | `frame_events.odin`, `cricket.odin` | Same (line by line) |
| 5 | Movement, collisions, goals | 0x406df0, 0x407d00, 0x40bdd0, 0x40bf10, 0x40c120, 0x40c6a0, 0x4086b0 | `creature.odin`, `objects.odin`, `path.odin` | Differs: D1, D3, item 14; Port: routing |
| 6 | Spider AI | 0x4010c0, 0x401420, 0x402760, 0x402d60, 0x402f40, 0x403000, 0x403210, 0x403520, 0x403770, 0x403e90, 0x404010, 0x404180, 0x407830 | `spider.odin`, `spider_react.odin`, `cricket.odin`, `objects.odin` | Same (line by line), except D4; Port: senses |
| 7 | Cricket AI | 0x407830 (cricket part), 0x403770, 0x404b20, 0x406780 (webs) | `cricket.odin`, `floor.odin` | Same (line by line) |
| 8 | Needs, growth, life cycle | 0x401000, 0x403ac0, 0x403c90, 0x404230, 0x404490, 0x404580, 0x408350, 0x408630, 0x408b70, 0x408d50, 0x415430, 0x415cc0, 0x41f4d0, 0x41f710, 0x41d0f0/0x41d460/0x41d710 | `spider.odin`, `growth.odin`, `persist.odin`, `floor.odin` | Same (line by line), except D2, D7, D10 |
| 9 | Player input and tools | 0x417e00 (mouse, keys), 0x403a60, 0x416be0, 0x4062d0, 0x41c890, 0x408140 | `tools.odin`, `ui.odin`, `web/main.js` | Differs: D3, D4, D5, D6; Port: touch, pan |
| 10 | Typed commands | 0x409de0 | `commands.odin` | Same (line by line) |
| 11 | Rendering | 0x40ca70, 0x416d20, 0x416e40, 0x417180, 0x417390, 0x412600, 0x4126d0, 0x4127b0, 0x412880, 0x41c160, 0x41c2e0, 0x408c70, 0x408430/0x408550, 0x408880/0x408af0, 0x417600, 0x41c9b0/0x41ca80 | `tank.odin`, `floor.odin`, `objects.odin`, `bmp.odin`, `views.odin` | Same (checked), except D9, D14 |
| 12 | Intro | 0x40ca70 (stage < 3), 0x412940, 0x41c9b0, 0x41ca80 | `intro.odin` | Same (line by line) |
| 13 | Interface: buttons, indicators, tooltips, name | 0x4060b0, 0x4064b0, 0x4065b0, 0x40e990, 0x411fe0, 0x412130, 0x412280, 0x40e2a0, 0x41c4b0 | `ui.odin` | Same (checked), except D10, D15; Port: smooth slide |
| 14 | Views: close-up, whole tank, cricket box | 0x40ca70 (views 1–3), 0x40e360, 0x40e930 | `views.odin`, `cricket.odin`, `tools.odin` | Same (checked) |
| 15 | Options box | 0x40ed40, 0x406350, 0x41da00, 0x4043f0 | `options.odin` | Same (ported whole last session; strings checked now); Port: settings items |
| 16 | Messages | 0x41f7f0, 0x41f8e0 (dialog), 0x417e00 timer (death, low crickets) | `web/main.js` message box, `persist.odin` | Differs: D7, D12 |
| 17 | Sound | 0x415f00, 0x416510, 0x416680, 0x416920 | `web/mixer.js`, `host_sound` callers, `tank.odin` `sound_loops` | Same (mixer tested sample by sample) |
| 18 | Saving | 0x414a60, 0x414df0, 0x415c30 | `persist.odin`, `web/main.js` | Port format; differs: D13 |
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
same table and placements. Differences:

- **D1 (new): object hit boxes aren't trimmed.** After measuring each
  object's bounds, setup shrinks the boxes of the tall objects (0x41a790):
  both cacti and the fountain keep only their lower half (cactus #1 also
  loses its left third), the bell its lower three quarters, the windpump
  its bottom quarter, the yucca is trimmed top, bottom and sides. These boxes
  are what blocks creatures, what the draw order sorts by and what you can
  click. The port uses the full box (less the shadow, a port choice), so
  tall objects block the spider and catch clicks well above where the
  original did.
- **D2 (new): the yucca starts grown.** The original starts it on frame 8
  (a small plant) and grows it one frame a day. The port starts it on
  frame 0, fully grown, so it never grows (it only wilts and recovers).
- **D16 (new, minor):** at a fresh start the original leaves the bowl
  wherever its random spot is (it may overlap the spider); the port finds a
  free spot. The crickets' first sequence comes from the idle chooser in
  the original; the port starts them on LURK. Only the opening seconds of
  a new pet differ.
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
(port) on top. Differences:

- **D7 (new): the minute update runs every 59 s** in the original (a
  per-second counter that resets at 59); the port uses 60 s. Growth, webs,
  the skin and the yucca run about 1.7% slower in the port.
- **D11 (new, minor): update order.** The original ticks everything in
  depth order (so the spider and crickets interleave by y); the port ticks
  objects, then the spider, then the crickets, and does the minute update
  before the second's. Only the order of random draws within a tick and
  of same-tick collision reactions differ.

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
- **D3 (new): the Follow tool's goal doesn't follow.** In the original the
  cursor goal (type 10) takes the pointer's current position every tick,
  so the spider keeps walking after the pointer as you move it; the port
  sends it to where you clicked.
- **Item 14 (open from the last audit): collisions.** The original's object
  rules (an overlap shallower than a quarter of the creature's height only
  blocks sideways; the bell doesn't block while walking to it; the chased
  target never blocks, except the bell) aren't in the port, which uses its
  own body box and one-third threshold so the spider fits narrower gaps.
- Port: route planning, edging round corners, unsticking, detour timeouts.

### 6. Spider AI — Same, except D4

Stats and temperament, idle choice, wants and preconditions, reactions to
every tool, finished hooks, thirst and the bell, noticing crickets. Line
by line.

- **D4 (new): the Follow tool never counts as an interaction.** While the
  spider walks after the cursor with the Follow tool the original sets its
  interaction to 4 (0x40bf10), so it reacts to being followed every 2.5 s:
  mood moves towards calm, and it may give up following, threaten, show
  its hairs or hide. The port has the reaction code but never sets the
  interaction, so none of this happens.
- Port: senses (noticing area, stalking, bowl memory, exploring), cricket
  rescue.

### 7. Cricket AI — Same

Idle choice, fleeing the spider, webs, the box, being dropped. Line by
line.

### 8. Needs, growth and the life cycle — Same, except D2, D7

Needs decay, health, temperament, growth (one point every 6 hours),
moulting, the skin, the yucca, webs ageing, the catch-up after time away,
death and its date, resurrection. Line by line after the last two rounds.

- **D10 (new, minor):** Clear (and resurrection) stops every cricket's
  current play in the original; the port only stops those stuck in webs.
- Port: the spider can starve while you watch (the original only checked
  for death in the start-up catch-up).

### 9. Player input and tools

Mouse, keyboard, cursors, the five tools, carrying, the whole-tank and box
clicks, edge scroll.

- **D3, D4** (above).
- **D5 (new): right-click while carrying a cricket** moves it between the
  tank and the box in the original (it toggles where the cricket is and
  switches the view); the port ignores right-clicks while carrying.
- **D6 (new): picking up a cricket stuck in a web frees it** in the
  original; in the port it stays stuck after you put it down.
- Port: edge scroll only while carrying, pan with a right-drag or two
  fingers, touch input, the right button's click-vs-drag.

### 10. Typed commands — Same

All 19 words, plus the port's CRICKET.

### 11. Rendering — Same (checked)

Decoding RLE frames, the per-frame transparent colour, scaling, the shadow
pass then the body pass, depth order (with the spider in front while on
the glass), the floor surface with prints, web pieces and corner webs, the
rock in front of a hiding spider, the logo skin, palette fades.

- **D9 (new, minor):** when the floor is rebuilt (start-up, Clear) the
  original draws web pieces first and footprints over them; the port draws
  footprints first.
- **D14 (info):** the original only clips sprites at the left/right edges
  when drawn at full size; scaled sprites crossing an edge wrap into the
  next row (a visual glitch). The port clips properly.

### 12. Intro — Same

### 13. Interface

Button row (10 buttons, pressed at 70%, spinning ring), help strings and
right-click help pages, the four indicators with the low-needs blink,
tooltips, the pet's name and its editing, the logo toggling the UI, the
tools button while hidden.

- **D15 (new, minor):** a tooltip that would run off the right edge is
  moved left to fit in the original; the port uses fixed offsets.
- Port: smooth slide animation, no exit button.

### 14. Views — Same (checked)

Close-up, whole tank with the object panel (6 objects at most since the
last fix), the cricket box with its counts.

### 15. Options box — Same

Ported whole last session: pages, wipes, help (161 lines), credits,
prognosis, stats, settings and utilities. All strings match. Port: the
settings show Full Screen where the original had Window Mode, Smooth
Motion in the Freeze Simulation slot, a Screensaver item, and Download
Crickets adds 12 crickets offline.

### 16. Messages

- **D7 / D12 (new, minor): the death message** comes 20 frames after start
  in the original, once per run; the port waits 30 frames (and also shows
  it when the spider dies while you watch, which the original couldn't).
- **D8 (new): the low-crickets warning isn't ported.** When fewer than 6
  crickets are left (box, store and tank together) the original shows,
  once per run, "YOU ONLY HAVE n CRICKETS LEFT!" (or "...ANY CRICKETS
  LEFT!") with "To download extra crickets, click on the 'Download
  Crickets' option in the 'Utilities' menu from the Options dialog box."

### 17. Sound — Same

8-bit 11 kHz mono, double-buffered 2048-sample blocks, four channels
(channel 0 for the crunches 450–456, 1 the fountain loop 465, 2 the drag
loop 403, otherwise the first free of 1–3, no repeats except the bell),
the windpump creak muted in the box view. Port: gritty / smooth / modern
modes and a volume control.

### 18. Saving

The original writes its whole state to vc.dat every 5 minutes and on exit
(the creature structs, objects, crickets, prints, webs, settings, name).
The port saves its own JSON every minute, when hidden and when closed.

- **D13 (new, minor): not everything is kept.** The port doesn't save the
  spider's current animation, goal or eating state, nor which crickets are
  stuck in webs. After a restart under 3 minutes (no catch-up), a spider
  that was eating doesn't leave remains and stuck crickets are free; the
  original would carry on where it left off.

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
overlays.

## Differences found in this review

| # | Difference | Size |
|---|------------|------|
| D1 | Object hit boxes not trimmed (tall objects block and catch clicks too high) — **fixed** | Large |
| D3 | Follow tool: the spider doesn't keep following the pointer — **fixed** | Large |
| D4 | Follow tool: no reactions to being followed — **fixed** | Medium |
| D2 | Yucca starts fully grown and never grows — **fixed** | Medium |
| D5 | Right-click while carrying a cricket doesn't move it to/from the box — **fixed** | Medium |
| D8 | No low-crickets warning | Small |
| D6 | Picking up a web-stuck cricket doesn't free it | Small |
| D7 | Minute update every 60 s instead of 59 s | Small |
| D13 | Save doesn't keep the current animation, eating or web-stuck crickets | Small |
| D12 | Death message after 30 frames instead of 20 | Small |
| D9 | Floor rebuild draws footprints under webs instead of over | Small |
| D10 | Clear stops only stuck crickets | Small |
| D11 | Update order within a tick | Small |
| D15 | Tooltips not moved left to fit | Small |
| D16 | Fresh start: bowl placed in a free spot, crickets start on LURK | Small |
| D14 | Sprite edge clipping (original glitch) | Info |
| 14 | Collision rules (open from the last audit) | Large, conflicts with narrow gaps |
