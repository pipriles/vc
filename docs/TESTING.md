# Test performance notes

Why the test suite is set up the way it is, and how to check it stays
fast. Measured on an M3 Max (macOS, Odin native tests).

## What happened (2026-10-08)

Fans spun up while tests ran: two `odin test` processes (`src.bin`) at
130–150% CPU each. The suite took **2m01s** of test time unoptimised, a
"lightweight" sim spending minutes of CPU.

Two independent costs, found by profiling (see below):

### 1. `x87_scale_trunc`: ~60 software 128-bit divisions per call

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

### 2. Rendering frames nobody sees

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
Results were unchanged (e.g. the ring test still reports 272 px).
`starving_while_running_dies` keeps `tank_step` (70 frames; it checks the
death message, which goes through the drawn UI).

### 3. Unoptimised build

`odin test` defaults to no optimisation, with bounds checks on every
pixel access. `test.sh` now passes `-o:speed`: build ~30 s, tests ~2 s.

## Measurements

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

## Rules for new tests

- Advance the sim with `tank_tick()` or `tank_advance(TICK)`. Never loop
  over `tank_step`. Call `tank_render()` once where drawing is checked.
- Keep per-call work small in anything called per tick per object
  (`x87_scale_trunc`, collision, `update_render_list`). Avoid `u128`
  division in hot paths; cache what depends only on small inputs.
- Long runs (thousands of ticks) are fine if they don't render; budget
  roughly tens of µs per tick in the optimised build.
- One test process at a time: parallel runs (e.g. several agents) heat
  the machine and skew timings.

## How to profile a slow test (macOS)

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
