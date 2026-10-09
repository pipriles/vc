# Agent notes

- Run tests with `./test.sh` (not bare `odin test src`): it builds with
  `-o:speed`, runs single-threaded, then builds the wasm and smoke-tests it.
- Only run one test process at a time: the suite is CPU-heavy, and parallel
  runs from several agents slow each other down.
- In tests, advance the sim with `tank_tick()` or `tank_advance(TICK)`.
  Don't loop over `tank_step()`: it renders a full frame every step.
- See README.md "Tests" for the rest.
