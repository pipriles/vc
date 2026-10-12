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
	settings = {frame_rate = 0} // the tests count 100 ms steps
	saved_json = "" // no save carried over between tests
	if !testing.expect(t, tank_init(), "tank_init") do return false
	mode, running = .Tank, true
	rng.seed = seed
	return true
}

// Runs the sim and returns a hash of every tick's observable state.
sim_hid, sim_came_out: int // hide cycles seen by the last sim_run
sim_drank: int              // water increases seen by the last sim_run
sim_min_x, sim_max_x: int   // horizontal range the spider covered
sim_max_queue: int          // longest animation queue seen

sim_run :: proc(t: ^testing.T, ticks: int, check: bool) -> (trace: u64, variety: int) {
	sim_hid, sim_came_out, sim_drank, sim_max_queue = 0, 0, 0, 0
	sim_min_x, sim_max_x = TANK_W, 0
	prev_hide := 0
	prev_water := game.stats.water
	c := &game.spider
	seen: map[int]bool
	defer delete(seen)
	h: u64 = 14695981039346656037
	prev_seq := -1
	for i in 0 ..< ticks {
		px, py := c.x, c.y // position when this tick's sequence choice is made
		if i % 600 == 300 do game.pending_drops += 1 // feed once a simulated minute
		tank_tick()
		if check {
			for &cr in game.crickets {
				if !cr.active || cr.in_box do continue
				frames := len(cr.anim.seqs[cr.seq].dirs[cr.dir].frames)
				ok := cr.x >= 80 && cr.x <= TANK_W - 80 && cr.y >= 180 && cr.y < VIEW_H &&
					frames > 0 && cr.frame >= 0 && cr.frame < frames
				if !testing.expectf(t, ok, "tick %d: cricket %d bad state x=%d y=%d seq=%s frame=%d/%d",
					i, cr.id, cr.x, cr.y, seq_name(&cr, cr.seq), cr.frame, frames) {
					return h, len(seen)
				}
			}
		}
		state := [7]int{c.x, c.y, c.dir, c.seq, c.frame, game.stats.mood, game.eaten}
		h = hash.fnv64a(transmute([]u8)state[:], h)
		seen[c.seq] = true
		if game.stats.water > prev_water do sim_drank += 1
		prev_water = game.stats.water
		sim_min_x, sim_max_x = min(sim_min_x, c.x), max(sim_max_x, c.x)
		if c.hide == 1 && prev_hide == 0 do sim_hid += 1
		if c.hide == 0 && prev_hide != 0 do sim_came_out += 1
		prev_hide = c.hide
		if !check do continue

		frames := len(c.anim.seqs[c.seq].dirs[c.dir].frames)
		ok := c.x >= WALL_MARGIN && c.x <= TANK_W - WALL_MARGIN &&
			// while crawling under the rock it rises above the floor line a
			// tick before the clamp is lifted (crawl runs after the update)
			c.y >= (c.no_clamp ? HIDE_Y : c.seq == game.seq.log_hide ? FLOOR_TOP - 10 : FLOOR_TOP) && c.y < VIEW_H &&
			(!c.no_clamp || c.hide != 0) && // the floor clamp is only lifted while hiding
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
			case ids.catch_:     pre = c.target_id >= 0
			}
			testing.expectf(t, pre, "tick %d: %s started without its precondition (x %d y %d size %d food %d moving %v)",
				i, c.anim.seqs[c.seq].name, c.x, c.y, c.size, game.stats.food, c.moving_x || c.moving_y)
		}
		prev_seq = c.seq
		sim_max_queue = max(sim_max_queue, c.queue_len)
	}
	return h, len(seen)
}

@(test)
sim_invariants_hold :: proc(t: ^testing.T) {
	if !sim_setup(t, 12345) do return
	_, variety := sim_run(t, SIM_TICKS, true)
	log.infof("%d distinct sequences played", variety)
	testing.expect(t, variety >= 5, "spider shows varied behaviour")
	log.infof("hid under the rock %d times, came out %d times, x range %d..%d", sim_hid, sim_came_out, sim_min_x, sim_max_x)
	testing.expect(t, sim_hid > 0, "spider hides under the rock")
	testing.expect(t, sim_came_out > 0, "spider comes back out")
	log.infof("ate %d crickets, %d in the tank at the end, food %d", game.eaten, crickets_in_tank(), game.stats.food)
	testing.expect(t, game.eaten > 0, "spider catches and eats crickets")
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

@(test)
sim_with_all_objects :: proc(t: ^testing.T) {
	if !sim_setup(t, 4242) do return
	for i in 0 ..< OBJECT_COUNT do game.pending_objects[i] = 1
	game.stats.water = 30
	_, variety := sim_run(t, SIM_TICKS / 2, true)
	placed := 0
	for &o in game.objects do if o.active && !o.in_box do placed += 1
	log.infof("objects placed %d, sequences %d, drank %d times, water %d, bowl level %d, x range %d..%d, ate %d",
		placed, variety, sim_drank, game.stats.water, game.objects[BOWL].frame, sim_min_x, sim_max_x, game.eaten)
	testing.expect_value(t, placed, MAX_OBJECTS_IN_TANK)
	// (randomly placed objects can wall the spider in, as in the original,
	// so roaming and drinking aren't guaranteed here)
	// (touching crickets re-queue CATCH every tick, and while turning the
	// queue isn't flushed, so it can fill up, as in the original)
	log.infof("longest queue %d", sim_max_queue)
	testing.expect(t, variety >= 5, "varied behaviour with objects in the way")
}

@(test)
spider_gets_out_of_a_ring_of_objects :: proc(t: ^testing.T) {
	if !sim_setup(t, 77) do return
	s := &game.spider
	s.x, s.y = 600, 320
	s.prev_x, s.prev_y = s.x, s.y
	clear_queue(s)
	creature_update_position(s)
	// rocks and cacti close round it on four sides
	ring := [?]struct {id, x, y: int}{{2, 470, 320}, {3, 730, 320}, {6, 600, 230}, {5, 600, 420}, {4, 480, 230}}
	for r in ring {
		o := &game.objects[r.id]
		o.active, o.in_box = true, false
		o.x, o.y = r.x, r.y
		object_update_position(o)
	}
	max_d := 0
	for _ in 0 ..< 6000 { // ten minutes
		tank_advance(TICK)
		max_d = max(max_d, abs(s.x - 600) + abs(s.y - 320))
	}
	log.infof("got %d px from the start", max_d)
	testing.expectf(t, max_d > 150, "still boxed in (%d px at most)", max_d)
}

@(test)
spider_gets_away_from_the_glass_when_boxed_in :: proc(t: ^testing.T) {
	if !sim_setup(t, 21) do return
	s := &game.spider
	s.size = 80
	s.x, s.y = 600, 470 // clamped onto the front glass
	s.prev_x, s.prev_y = s.x, s.y
	clear_queue(s)
	creature_update_position(s)
	y0 := s.y
	ring := [?]struct {id, x, y: int}{{BOWL, 600, y0 - 70}, {2, 470, y0}, {3, 730, y0}}
	for r in ring {
		o := &game.objects[r.id]
		o.active, o.in_box = true, false
		o.x, o.y = r.x, r.y
		object_update_position(o)
	}
	moved := 0
	for _ in 0 ..< 1200 { // two minutes
		tank_advance(TICK)
		moved = max(moved, abs(s.x - 600) + abs(s.y - y0))
	}
	// (once out it may well come back: the bowl it was boxed in by is right there)
	testing.expectf(t, moved > 60, "still stuck at the glass (%d px at most)", moved)
}

@(test)
catch_reach_is_half_the_drawn_frame :: proc(t: ^testing.T) {
	if !sim_setup(t, 22) do return
	s := &game.spider
	s.x, s.y = 600, 330
	creature_update_position(s)
	cr := &game.crickets[0]
	cr.in_box, cr.active = false, true
	s.target_id = 0
	dw, dh := x87_scale_trunc(s.anim.w, s.scale), x87_scale_trunc(s.anim.h, s.scale)
	cr.x, cr.y = s.x - dw / 2 + 2, s.y + dh / 2 - 2
	creature_update_position(cr)
	testing.expect(t, abs(s.x - cr.x) > (s.hit.right - s.hit.left) / 2, "beyond the hit box")
	testing.expect(t, spider_precondition(s, game.seq.catch_), "but within half the drawn frame")
	cr.x = s.x - dw / 2 - 4
	creature_update_position(cr)
	testing.expect(t, !spider_precondition(s, game.seq.catch_), "out of reach further away")
}
