#+build !js
package vc

import "core:hash"
import "core:log"
import "core:testing"

// Headless simulation runs on the real data: invariants and determinism.

SIM_TICKS :: 100_000 // ~2.8 hours of simulated time

sim_setup :: proc(t: ^testing.T, seed: u32) -> bool {
	if !have_data(t, "cr") do return false
	now_ms = 0
	if !testing.expect(t, tank_init(), "tank_init") do return false
	rng.seed = seed
	return true
}

// Runs the sim and returns a hash of every tick's observable state.
sim_run :: proc(t: ^testing.T, ticks: int, check: bool) -> (trace: u64, variety: int) {
	c := &game.spider
	seen: map[int]bool
	defer delete(seen)
	h: u64 = 14695981039346656037
	prev_seq := -1
	for i in 0 ..< ticks {
		tank_tick()
		state := [6]int{c.x, c.y, c.dir, c.seq, c.frame, game.stats.mood}
		h = hash.fnv64a(transmute([]u8)state[:], h)
		seen[c.seq] = true
		if !check do continue

		frames := len(c.anim.seqs[c.seq].dirs[c.dir].frames)
		ok := c.x >= WALL_MARGIN && c.x <= TANK_W - WALL_MARGIN &&
			c.y >= FLOOR_TOP + c.anim.h / 3 && c.y + c.anim.h / 2 <= VIEW_H &&
			frames > 0 && c.frame >= 0 && c.frame < frames &&
			c.scale >= 35 && c.scale <= 100
		if !testing.expectf(t, ok, "tick %d: bad state x=%d y=%d seq=%s dir=%d frame=%d/%d scale=%d",
			i, c.x, c.y, c.anim.seqs[c.seq].name, c.dir, c.frame, frames, c.scale) {
			return
		}
		if c.seq != prev_seq && c.anim.seqs[c.seq].dirs[c.dir].needs_check {
			// deterministic parts of spider_precondition (random ones can't
			// be re-checked after the fact)
			ids := &game.seq
			pre := true
			switch c.seq {
			case ids.glass:      pre = c.size > 49
			case ids.log_hide:   pre = c.x > 629 && c.x < 651
			case ids.web_laying: pre = game.stats.food <= 30
			case ids.catch_:     pre = false // needs a cricket: none in the tank yet
			}
			testing.expectf(t, pre, "tick %d: %s started without its precondition",
				i, c.anim.seqs[c.seq].name)
		}
		prev_seq = c.seq
	}
	return h, len(seen)
}

@(test)
sim_invariants_hold :: proc(t: ^testing.T) {
	if !sim_setup(t, 12345) do return
	_, variety := sim_run(t, SIM_TICKS, true)
	log.infof("%d distinct sequences played", variety)
	testing.expect(t, variety >= 5, "spider shows varied behaviour")
}

@(test)
sim_is_deterministic :: proc(t: ^testing.T) {
	if !sim_setup(t, 777) do return
	a, _ := sim_run(t, 20_000, false)
	if !sim_setup(t, 777) do return
	b, _ := sim_run(t, 20_000, false)
	testing.expect_value(t, a, b)
	if !sim_setup(t, 778) do return
	c, _ := sim_run(t, 20_000, false)
	testing.expect(t, a != c, "different seeds diverge")
}
