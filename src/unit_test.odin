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
