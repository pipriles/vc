#+build !js
package vc

import "core:testing"

// Expected values here are derived by hand from the VC.EXE disassembly
// (see docs/BEHAVIOR.md), not from this port's code.

@(test)
rand_matches_msvc :: proc(t: ^testing.T) {
	// MSVC CRT: srand(1) then rand() x 10
	rng.seed = 1
	want := [?]int{41, 18467, 6334, 26500, 19169, 15724, 11478, 29358, 26962, 24464}
	for w in want do testing.expect_value(t, rand(), w)
}

@(test)
rand_n_is_original_idiom :: proc(t: ^testing.T) {
	rng.seed = 1
	testing.expect_value(t, rand_n(10), 41 * 10 / 0x7FFF)
	testing.expect_value(t, rand_n(10), 18467 * 10 / 0x7FFF) // = 5
}

@(test)
x87_matches_fixture :: proc(t: ^testing.T) {
	for row in X87_FIXTURE {
		for want, i in row.out {
			testing.expectf(t, x87_scale_trunc(row.a, i + 1) == want,
				"a=%d scale=%d: got %d want %d", row.a, i + 1, x87_scale_trunc(row.a, i + 1), want)
		}
	}
}

@(test)
stats_health_and_temperament :: proc(t: ^testing.T) {
	Case :: struct {
		food, water, mood:   int,
		health, temperament: int,
	}
	cases := [?]Case {
		{30, 30, 0, 31, 4},    // either < 41: min + 1; v = 50 + 15 = 65 -> 4.55 -> 4
		{80, 90, 0, 95, 7},    // avg 85 + 10 (calm); v = 50 + 47 = 97 -> 6.79 -> rounds up to 7
		{45, 70, -60, 44, 3},  // 45-50+57, +(50-45)/2, -10; v = 20 + 22 = 42 -> 2.94 -> 3
		{100, 100, 90, 80, 3}, // 100 - 20; v = 5 + 40 = 45 -> 3.15 -> 3
		{1, 50, 0, 2, 3},      // min + 1 = 2; v = 50 + 1 = 51 -> 3.57 -> 3
	}
	for c in cases {
		now_ms = 0
		s := Spider_Stats{food = c.food, water = c.water, mood = c.mood}
		spider_stats_tick(&s)
		testing.expectf(t, s.health == c.health, "%v: health %d", c, s.health)
		testing.expectf(t, s.temperament == c.temperament, "%v: temperament %d", c, s.temperament)
	}
}

@(test)
stats_decay_timers :: proc(t: ^testing.T) {
	s := Spider_Stats{food = 50, water = 50}
	now_ms = 0
	spider_stats_tick(&s)
	now_ms = 7_200_001 // > 2 h: food -2, water not yet (2.5 h)
	spider_stats_tick(&s)
	testing.expect_value(t, s.food, 48)
	testing.expect_value(t, s.water, 50)
	now_ms = 9_000_001
	spider_stats_tick(&s)
	testing.expect_value(t, s.water, 48)
	testing.expect(t, s.mood < 0, "mood drops once a minute")
}

@(test)
stats_mood_wraps_like_original :: proc(t: ^testing.T) {
	s := Spider_Stats{food = 50, water = 50, mood = -100}
	now_ms = 60_000
	spider_stats_tick(&s)
	testing.expect_value(t, s.mood, 100) // sic: -101 wraps to 100 in VC.EXE
}

@(test)
depth_scale_and_speed :: proc(t: ^testing.T) {
	a := Anim{w = 320, h = 200, seqs = make([]Seq, 1)}
	defer delete(a.seqs)
	c: Creature
	creature_init(&c, &a, 600, 300, 5, 3, 40)
	defer delete(c.last_played)
	testing.expect_value(t, c.scale, 60) // 300/480*40 + 35
	testing.expect_value(t, c.sx, 3)
	testing.expect_value(t, c.sy, 1)
	c.y = 470
	creature_update_position(&c)
	// bottom clamp: y + drawn_h/3 < 480, drawn_h = 200 at the previous 60% = 120
	testing.expect_value(t, c.y, 440)
	testing.expect_value(t, c.scale, 71) // 440/480*40 + 35 = 71.67, truncated
	testing.expect(t, c.blocks[4].kind == BLOCK_WALL, "bottom marks dir 4 as wall")
	c.y = 100
	creature_update_position(&c)
	testing.expect_value(t, c.y, FLOOR_TOP) // creatures with animation: y >= 170
}

@(test)
wall_bump_marks_directions :: proc(t: ^testing.T) {
	a := Anim{w = 320, h = 200, seqs = make([]Seq, 1)}
	defer delete(a.seqs)
	c: Creature
	creature_init(&c, &a, 10, 300, 5, 3, 40)
	defer delete(c.last_played)
	testing.expect_value(t, c.x, WALL_MARGIN)
	for d in ([?]int{5, 6, 7}) do testing.expect(t, c.blocks[d].kind == BLOCK_WALL)
	testing.expect(t, c.blocks[2].kind == 0)
	// a wall mark only lasts until the next position update
	c.x = 600
	creature_update_position(&c)
	testing.expect(t, c.blocks[6].kind == 0)
}

@(test)
hidden_spider_skips_floor_clamp :: proc(t: ^testing.T) {
	a := Anim{w = 320, h = 200, seqs = make([]Seq, 1)}
	defer delete(a.seqs)
	c: Creature
	creature_init(&c, &a, 422, 300, 5, 3, 40)
	defer delete(c.last_played)
	c.hide, c.no_clamp, c.y = 1, true, 50
	creature_update_position(&c)
	testing.expect_value(t, c.y, HIDE_Y) // 0x72
	creature_post_frame(&c)
	testing.expect(t, c.no_clamp && c.hide == 1, "still hidden above the floor line")
	c.y = 200
	creature_post_frame(&c)
	testing.expect(t, !c.no_clamp && c.hide == 0, "back on the floor resets hiding")
}

@(test)
goal_times_out_while_detouring :: proc(t: ^testing.T) {
	if !sim_setup(t, 3) do return
	s := &game.spider
	move_to(s, .Point, 1000, 400, -1, game.seq.lurk, 10)
	s.goal.detouring = true
	now_ms += 11_000
	goal_check(s)
	testing.expect(t, !s.goal.active, "a detour that gets nowhere still times out")
}

@(test)
small_spider_waits_between_glass_trips :: proc(t: ^testing.T) {
	if !sim_setup(t, 6) do return
	s := &game.spider
	s.size = 40 // too small to climb
	trips := 0
	for _ in 0 ..< 1800 { // three minutes
		g := s.goal
		tank_advance(TICK)
		if s.goal.active && s.goal.seq == game.seq.glass && !(g.active && g.seq == game.seq.glass) do trips += 1
	}
	testing.expectf(t, trips <= 2, "%d glass trips in three minutes", trips)
}

@(test)
climbing_spider_is_drawn_in_front :: proc(t: ^testing.T) {
	if !sim_setup(t, 7) do return
	s := &game.spider
	s.x, s.y = 600, 300
	creature_update_position(s)
	rock := &game.objects[2]
	rock.active, rock.in_box = true, false
	rock.x, rock.y = s.x, 470 // in front of it
	object_update_position(rock)
	s.seq, s.frame = game.seq.lurk, 0
	update_render_list()
	si, ri := -1, -1
	for c, i in game.render_list {
		if c == s do si = i
		if c == &rock.c do ri = i
	}
	testing.expectf(t, ri > si, "normally the rock in front is drawn after the spider (%d, %d)", si, ri)
	s.seq, s.frame = game.seq.glass, 21
	update_render_list()
	testing.expect(t, game.render_list[len(game.render_list) - 1] == s, "climbing the glass: the spider last")
}

@(test)
at_most_eight_crickets_and_six_objects_in_the_tank :: proc(t: ^testing.T) {
	if !sim_setup(t, 8) do return
	for _ in 0 ..< 10 do cricket_drop(400, 300)
	testing.expect_value(t, crickets_in_tank(), 8)
	for i in 0 ..< OBJECT_COUNT do tank_set_object(i32(i), 1)
	handle_pending_objects()
	testing.expect_value(t, objects_in_tank(), MAX_OBJECTS_IN_TANK)
}

@(test)
catch_up_resets_the_cooldowns :: proc(t: ^testing.T) {
	if !sim_setup(t, 9) do return
	s := &game.spider
	now_ms = CLOCK_START
	for &v in s.last_played do v = now_ms
	move_to(s, .Point, 900, 400, -1, game.seq.lurk, 60)
	catch_up(10, host_time() - 600)
	testing.expect(t, !s.goal.active, "no goal after time away")
	testing.expect_value(t, s.last_played[game.seq.glass], now_ms - 300_000)
}

@(test)
turn_direction_follows_the_original :: proc(t: ^testing.T) {
	// (from, to) -> clockwise
	cases := [?]struct {from, to: int, cw: bool}{
		{0, 1, true}, {0, 2, true}, {0, 3, true}, {1, 4, false}, {0, 4, false}, {0, 7, false},
		{6, 1, true}, {5, 0, true}, {4, 0, false}, {2, 6, false}, {6, 2, false},
	}
	for c in cases do testing.expectf(t, turn_clockwise(c.from, c.to) == c.cw, "%d -> %d", c.from, c.to)
}

@(test)
mood_rule_play_count_beats_the_queued_one :: proc(t: ^testing.T) {
	if !sim_setup(t, 41) do return
	s := &game.spider
	game.stats.temperament = 6
	clear_queue(s)
	clear_goal(s)
	enqueue_anim(s, game.seq.lurk, s.dir, 9)
	s.plays = 1
	next_sequence(s)
	testing.expect_value(t, s.seq, game.seq.lurk)
	testing.expectf(t, s.plays >= 2 && s.plays <= 3, "LURK plays (rand(t)+t)/3, not the queued 9 (got %d)", s.plays)
}

@(test)
web_laying_continues_at_most_once :: proc(t: ^testing.T) {
	if !sim_setup(t, 42) do return
	s := &game.spider
	clear_queue(s)
	s.seq = game.seq.web_laying
	s.queue_busy = true // it came from the queue: the flag is still on
	for _ in 0 ..< 50 do spider_finished(s)
	testing.expect_value(t, s.queue_len, 0)
	s.queue_busy = false
	for _ in 0 ..< 50 {
		spider_finished(s)
		if s.queue_len > 0 do break
	}
	testing.expect(t, s.queue_len > 0, "picked by the idle chooser, it may lay on")
}

@(test)
no_walking_goals_while_eating :: proc(t: ^testing.T) {
	if !sim_setup(t, 43) do return
	s := &game.spider
	clear_goal(s)
	s.eating = true
	move_to(s, .Creature_A, -1, -1, -1, game.seq.lurk, 120, target = BOWL)
	testing.expect(t, !s.goal.active, "no goal while eating")
	s.eating = false
	move_to(s, .Creature_A, -1, -1, -1, game.seq.lurk, 120, target = BOWL)
	start := s.goal.start_ms
	now_ms += 5000
	move_to(s, .Creature_A, -1, -1, -1, game.seq.lurk, 120, target = BOWL)
	testing.expect_value(t, s.goal.start_ms, start) // the same chase carries on
}

@(test)
catch_up_frees_crickets_from_webs :: proc(t: ^testing.T) {
	if !sim_setup(t, 44) do return
	cr := &game.crickets[0]
	cr.in_box, cr.web_stuck = false, true
	enqueue_anim(&game.spider, game.seq.clean, -1, 2)
	catch_up(10, host_time() - 600)
	testing.expect(t, !cr.web_stuck, "free again")
}

@(test)
tall_objects_only_block_low_down :: proc(t: ^testing.T) {
	if !sim_setup(t, 47) do return
	for id in ([?]int{CACTUS1, CACTUS2, FOUNTAIN, WINDPUMP, BELL, YUCCA}) {
		o := &game.objects[id]
		o.in_box = false
		o.x, o.y = 600, 400
		object_update_position(o)
		dh := x87_scale_trunc(o.fh, o.scale)
		// the untrimmed box's top, where the picture starts
		top := x87_scale_trunc(full_bounds(o).top, o.scale) + o.y - dh / 2
		// at least the top eighth is cut off the box (0x41a790)
		testing.expectf(t, o.hit.top >= top + dh / 8, "%s: box top %d, picture top %d", o.name, o.hit.top, top)
		testing.expectf(t, !hit_test(&o.c, o.x, top + 4), "%s can't be grabbed by its top", o.name)
	}
}
