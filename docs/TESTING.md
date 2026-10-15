# Tests

## Running
```sh
./test.sh                                    # everything
./test.sh -define:ODIN_TEST_NAMES=vc.<name>  # one native test
```
`test.sh` runs the native `odin test` (`-o:speed`: about 3.5 s of tests
after a ~6 s build), then builds the wasm and runs `tools/smoke.mjs` and
`tools/mixer_test.mjs` in Node. The native tests run single-threaded
because they share the simulation's globals. Data tests skip themselves
when `data/` is missing; the Node steps need `data/` and Node.

## What the tests cover
- **Unit:** `rand` vs known MSVC output; x87 rounding vs an exact-fraction
  oracle (`tools/gen_x87_fixture.py`); needs/temperament, depth scale,
  speeds and wall bumps vs values worked out by hand from the disassembly.
- **Data:** every frame of every animation (both variants) decodes to the
  canvas size; frame content matches the boxes stored in the index (and
  not when flipped); plugin merge rules.
- **Simulation:** 100k headless ticks checking invariants (bounds, valid
  frames, sequence preconditions) and determinism for a fixed seed; a run
  with every object placed; a sweep of 3000 start seeds.
- **Fuzz:** random pointer, tool, button, typed-command, object, box,
  save/reload, catch-up and new-spider input on fixed seeds (both
  variants), invariants checked after every tick (`fuzz_test.odin`).
- **Time away and saves:** hidden-page time replays exactly like ticks on
  screen; over an hour the catch-up runs; save round trip; unusable saves
  are reported; `step` lets go of each frame's temp allocations.
- **Browser build:** `tools/smoke.mjs` runs the real `vc.wasm` in Node with
  both variants and both pages, catching wasm-only failures, and checks a
  hidden-time replay is silent. Its clock starts at a fixed time
  (`SMOKE_TIME=<seconds>` or `now` for another), so runs repeat.
  `tools/mixer_test.mjs` checks the sound mixer's rules. Both print `FAIL`
  lines on failure.

Not covered yet: comparison against the original program's behaviour (see
`docs/BEHAVIOR.md` for how each rule was derived).

## Rules for new tests

- Advance the sim with `tank_tick()` or `tank_advance(TICK)`. Never loop
  over `tank_step`: it renders a full 640×480 frame per step, which the
  native build throws away (7,200 renders took ~30 s). Call
  `tank_render()` once where drawing is checked.
- Keep per-call work small in anything called per tick per object
  (`x87_scale_trunc`, collision, `update_render_list`). Avoid `u128`
  division in hot paths; cache what depends only on small inputs.
- Long runs (thousands of ticks) are fine if they don't render; budget
  roughly tens of µs per tick in the optimised build.
- Tests share the sim's globals. A test that changes what `sim_setup`
  doesn't reset (`cmd`, the loaded variant via `assets.loaded` and
  `data_dir`) puts it back before returning, as the fuzz test does.
  `data_dir` must be a literal or persistent string if the test frees
  the temp allocator.
- The fuzz test (~0.9 s) runs a few seeds per variant for 6000 ticks,
  drawing every 50th. To look wider, change the seeds or tick count
  locally; a failure prints the variant, seed and tick to replay. Keep
  seeds that once found a bug.
- Keep `-o:speed`: unoptimised builds (`odin test src`) run the tests
  ~6× slower.
- One test process at a time: parallel runs (e.g. several agents) heat
  the machine and skew timings. `test.sh` enforces it with a lock
  (`build/.test.lock`): a second run waits, and a lock left by a killed
  run is taken over.

## Performance notes

Why the test suite is set up the way it is, and how to check it stays
fast. Measured on an M3 Max (macOS, Odin native tests).

### What happened (2026-10-08)

Fans spun up while tests ran: two `odin test` processes (`src.bin`) at
130–150% CPU each. The suite took **2m01s** of test time unoptimised, a
"lightweight" sim spending minutes of CPU.

Two independent costs, found by profiling (see below):

#### 1. `x87_scale_trunc`: ~60 software 128-bit divisions per call

`x87_scale_trunc` (`src/x87.odin`) reproduces VC.EXE's x87 rounding of
`trunc(a / (100.0 / scale))` exactly with `u128` integer maths. It found
the shift `k` for the 64-bit mantissa with a loop doing one `u128`
division per step, ~60 steps, on every call. ARM64 (and wasm) has no
native 128-bit divide, so each is a call to `runtime::udivmod128`, a
bit-by-bit software loop.

It is called many times per tick, not just when drawing: hit boxes,
positions, floor clamping, shadows (`creature.odin`, `spider.odin`,
`objects.odin`, `floor.odin`, `tank.odin`). In `sim_invariants_hold`,
which never renders, ~95% of samples were in `udivmod128`.

Fix: the quotient `M / 2^k` depends only on `scale`, so it is cached per
scale (`x87_quotient`); a call now does one `u128` division. Results are
bit-identical (`x87_matches_fixture` covers a × scale 1..100).

#### 2. Rendering frames nobody sees

`tank_step(dt)` runs the due ticks *and* renders: copy the 1200×480
background, decode and draw every sprite twice (shadow, body), then
convert 640×480 = 307,200 pixels to RGBA. On native, `present()` is an
empty stub, so the frame is discarded.

Movement tests looped `tank_step(TICK)` thousands of times (7,200 frames
across two tests, ~2.2 billion pixel conversions), and the newer senses
tests repeated the pattern (up to 7,300 more). Their assertions only
read sim state (positions, `game.senses`, `eaten`, `water`).

Fix: `tank_step` was split into `tank_advance(dt)` (timing + ticks, sets
`game.alpha`) followed by `tank_render()`. Tests call `tank_advance`.
Results were unchanged (e.g. the ring test still reports 272 px). No
test loops over `tank_step` now; messages such as the death notice come
from the tick (`death_notice_tick` → `host_message`), not the render.

#### 3. Unoptimised build

`odin test` defaults to no optimisation, with bounds checks on every
pixel access. `test.sh` now passes `-o:speed`: build ~30 s, tests ~2 s.

### Measurements

Test time as reported by the runner ("Finished N tests in ..."),
single-threaded, unoptimised unless noted:

| Step | Movement tests (2) | `sim_*` tests (3) | Whole suite |
|---|---:|---:|---:|
| Original | 35.4 s | 67.8 s | 2m01s |
| + x87 cache | 32.8 s | 5.0 s | 45 s |
| + no render in movement tests | | | 13 s |
| (senses tests added, rendering) | | | 2m08s |
| + no render in senses tests | | | 13.2 s |
| + `-o:speed` | | | 2.0 s |

Each fix looks small or large depending on the workload measured: the x87
cache only saved ~10% on the render-heavy movement tests, but ~13× on the
sim tests. Measure the whole suite, and per test group, before ranking
causes.

### Build time (2026-10-14)

The `-o:speed` build took ~27 s native and ~13 s for wasm, against 0.4 s
with `-o:none`. `-show-timings` put 99% in LLVM; `llc -time-passes` on the
optimised IR put 85% of the backend in instruction scheduling and
selection, and `llvm-extract` per function showed three cold procedures
cost ~14 s of the 16 s backend:

| Procedure | Optimised IR | Backend alone |
|---|---:|---:|
| `box_art_load` | 28k instructions | 7.6 s |
| `apply_save` | 12k | 3.7 s |
| `make_save` | 12k | 2.5 s |
| (next largest, `tank_tick`) | 4.8k | 0.08 s |

Each copies big structs by value (`Bitmap` with its 768-byte palette;
`Save`), and LLVM splits those copies into thousands of scalar loads and
stores in a single basic block, where the schedulers are superlinear. All
three run only at start-up or once a minute, so they're marked
`@(optimization_mode = "none")`: native build ~6 s, wasm ~4.5 s, backend
1.9 s. (`"favor_size"` made it worse, 34 s; not inlining `bmp_load` alone
changed nothing.)

If the build slows down again: emit the IR with
`odin build src -o:speed -build-mode:llvm-ir -out:<dir>`, list the
largest functions, and time them one by one with `llvm-extract --func=...`
and `llc -O3` (Homebrew `llvm@22`, matching `odin report`).

### Browser loop (2026-10-09)

`odin.js` calls `step` on every `requestAnimationFrame`: up to 120 Hz on a
ProMotion display, while the sim ticks every 55-100 ms. Each call ran a
full render, and ~90% of frames came out pixel-identical to the previous
one. Measured with the real `web/main.js` against a stub DOM in Node, 30 s
at 120 Hz, Chile Rose tank:

| Per display frame | Before | After |
|---|---:|---:|
| `putImageData` (640×480 RGBA, 1.2 MB) | 1.00 | 0.17 |
| UI text canvas cleared | 1.00 | 0 |
| JS + wasm time | 0.48 ms | 0.44 ms |
| Viewer page: `putImageData` / status text writes | 1.00 / 1.00 | 0.08 / 0.08 |
| Viewer page: JS + wasm time | 0.115 ms | 0.011 ms |

- `present_view` (`tank.odin`) keeps the last frame sent (palette indices
  and palette) and skips the RGBA conversion and `present` when both are
  unchanged. The canvas already shows that image, so output is identical
  (`identical_frames_are_not_sent_again`).
- `main.js` collects each frame's UI text calls (`ui_begin`, `ui_text`,
  `ui_text_ex`) and repaints the text canvas only when they differ.
- The viewer renders only when animation, sequence, direction or frame
  change (nothing while paused).

Still per display frame: composing the tank in wasm (~0.44 ms, about 5%
of a core at 120 Hz). Skipping it needs to know nothing visible changed
(no tick, no input, no smooth-motion step), which isn't tracked yet.

### How to profile a slow test (macOS)

```sh
odin build src -build-mode:test -debug -define:ODIN_TEST_THREADS=1 \
  -define:ODIN_TEST_TRACK_MEMORY=false \
  -define:ODIN_TEST_NAMES=vc.<test_name> -out:/tmp/t.bin
/tmp/t.bin & sleep 3; sample $! 10 -file /tmp/s.txt
```

Read "Sort by top of stack" in `/tmp/s.txt`; the call graph shows which
test line is responsible. Ignore the main thread's `__semwait_signal`
(the runner waiting). Use bash, not zsh, for scripts that pass several
`-define:` flags in one variable: zsh doesn't word-split `$D`.
