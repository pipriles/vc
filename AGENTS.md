# Agent notes

- Run tests with `./test.sh` (not bare `odin test src`): it builds with
  `-o:speed`, runs single-threaded, then builds the wasm and smoke-tests it.
- Only run one test process at a time: the suite is CPU-heavy, and parallel
  runs from several agents slow each other down. `test.sh` waits for a run
  already in progress; don't bypass it with bare `odin test` loops.
- Rendering: only send a frame when it changed (`present_view`); the
  browser calls `step` every display frame, up to 120 Hz.
- In tests, advance the sim with `tank_tick()` or `tank_advance(TICK)`.
  Don't loop over `tank_step()`: it renders a full frame every step.
- See README.md "Tests", and docs/TESTING.md for why (profiling how-to,
  measurements).
