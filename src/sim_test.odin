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
sim_hid, sim_came_out: int // hide cycles seen by the last sim_run

sim_run :: proc(t: ^testing.T, ticks: int, check: bool) -> (trace: u64, variety: int) {
	sim_hid, sim_came_out = 0, 0
	prev_hide := 0
	c := &game.spider
	seen: map[int]bool
	defer delete(seen)
	h: u64 = 14695981039346656037
	prev_seq := -1
	for i in 0 ..< ticks {
		px, py := c.x, c.y // position when this tick's sequence choice is made
		tank_tick()
		state := [6]int{c.x, c.y, c.dir, c.seq, c.frame, game.stats.mood}
		h = hash.fnv64a(transmute([]u8)state[:], h)
		seen[c.seq] = true
		if c.hide == 1 && prev_hide == 0 do sim_hid += 1
		if c.hide == 0 && prev_hide != 0 do sim_came_out += 1
		prev_hide = c.hide
		if !check do continue

		frames := len(c.anim.seqs[c.seq].dirs[c.dir].frames)
		ok := c.x >= WALL_MARGIN && c.x <= TANK_W - WALL_MARGIN &&
			c.y >= (c.no_clamp ? HIDE_Y : FLOOR_TOP) && c.y < VIEW_H &&
			(c.hide == 0) == !c.no_clamp &&
			frames > 0 && c.frame >= 0 && c.frame < frames &&
			c.scale >= 35 && c.scale <= 100
		if !testing.expectf(t, ok, "tick %d: bad state x=%d y=%d seq=%s dir=%d frame=%d/%d scale=%d",
			i, c.x, c.y, c.anim.seqs[c.seq].name, c.dir, c.frame, frames, c.scale) {
			return h, len(seen)
		}
		if c.seq != prev_seq && c.anim.seqs[c.seq].dirs[c.dir].needs_check {
			// deterministic parts of spider_precondition (random ones can't
			// be re-checked after the fact)
			ids := &game.seq
			pre := true
			switch c.seq {
			case ids.glass:      pre = c.size > 49
			case ids.log_hide:   pre = px > 629 && px < 651 && py < 174
			case ids.web_laying: pre = game.stats.food <= 30
			case ids.catch_:     pre = false // needs a cricket: none in the tank yet
			}
			testing.expectf(t, pre, "tick %d: %s started without its precondition (x %d y %d size %d food %d moving %v)",
				i, c.anim.seqs[c.seq].name, c.x, c.y, c.size, game.stats.food, c.moving_x || c.moving_y)
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
	log.infof("hid under the rock %d times, came out %d times", sim_hid, sim_came_out)
	testing.expect(t, sim_hid > 0, "spider hides under the rock")
	testing.expect(t, sim_came_out > 0, "spider comes back out")
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
