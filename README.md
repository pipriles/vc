# vc_port

Browser port of *Virtual Creatures — Pet Spider* (Global Beach / Virtual
Creatures Ltd., 1999): Chile Rose and Red Knee tarantulas plus the plugin
animation packs. Written in Odin, compiled to WebAssembly, drawn on a canvas.

The original game data is not included. Extract it from your own copies of
the installers (`setup_cr.exe`, `setup_rk.exe`, `plugin_cr.exe`,
`plugin_rk.exe`); nothing from them is executed.

## Requirements
- Odin (`brew install odin`) and `wasm-ld` (`brew install lld`)
- Python 3 (extraction only)
- Ghidra + JDK 21 (reverse engineering only)

## Build and run
```sh
python3 -I tools/extract.py "/path/to/installers" data
./build.sh
python3 -I tools/serve.py   # no-cache dev server on :8081
```
Open http://127.0.0.1:8081/ for the tank (`?v=rk` for Red Knee), `viewer.html` for the animation viewer.
`C` / "Drop cricket" releases a cricket from the box into the tank (until
the feed tool exists). The Objects bar places or removes objects (only the bowl starts in the tank)
and "Fill bowl" refills the water. Press `D` (or tick Debug) for the overlay: tank limits, drawn box, facing,
blocked directions, goal target and tolerance, a state panel and a log of
the spider's decisions. Sim speed runs the clock up to 20× faster.

## Tests
```sh
./test.sh
```
Native `odin test` (about 2 s), single-threaded because tests share the
simulation's globals. Data tests skip themselves when `data/` is missing.
- **Unit:** `rand` vs known MSVC output; x87 rounding vs an exact-fraction
  oracle (`tools/gen_x87_fixture.py`); needs/temperament, depth scale,
  speeds and wall bumps vs values worked out by hand from the disassembly.
- **Data:** every frame of every animation (both variants) decodes to the
  canvas size; frame content matches the boxes stored in the index (and
  not when flipped); plugin merge rules.
- **Simulation:** 100k headless ticks checking invariants (bounds, valid
  frames, sequence preconditions) and determinism for a fixed seed.

Not covered yet: comparison against the original program's behaviour
(see docs/BEHAVIOR.md for how each rule was derived).

## Layout
| path | contents |
|------|----------|
| `src/`   | Odin: format (`vcg.odin`, `bmp.odin`), `rng.odin`, `creature.odin`, `spider.odin`, `tank.odin`, `viewer.odin` |
| `web/`   | HTML + JS host (file prefetch, canvas blit) |
| `tools/` | extractor, Ghidra scripts (`decompile.sh`), dev server, fixture generator |
| `re/`    | `symbols.txt`: names for addresses in `VC.EXE` |
| `docs/`  | `FORMAT.md` (animation format), `BEHAVIOR.md` (game logic notes) |

## Status
- [x] Installer + resource extraction
- [x] Animation format decoded; viewer for all sequences/directions
- [ ] Game logic reverse engineering (in progress, see `docs/BEHAVIOR.md`)
- [x] Tank scene: spider idle AI, movement, depth scale, needs
- [x] Walk-to-goal steering with detours; hiding under the rock; glass; shadows
- [x] Debug overlay
- [x] Crickets: collisions, chase, catch, eat, remains (debug "Drop cricket")
- [x] Tank objects: rendering, animation, blocking, drinking at the bowl
- [ ] Crickets, hunting, tank objects, tools, UI, sound, persistence
