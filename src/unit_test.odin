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
	testing.expect_value(t, c.y, VIEW_H - 100) // bottom clamp: y + h/2 < 480
	testing.expect_value(t, c.scale, 66)       // 380/480*40 + 35 = 66.67, truncated
}

@(test)
wall_bump_marks_directions :: proc(t: ^testing.T) {
	a := Anim{w = 320, h = 200, seqs = make([]Seq, 1)}
	defer delete(a.seqs)
	c: Creature
	creature_init(&c, &a, 10, 300, 5, 3, 40)
	defer delete(c.last_played)
	testing.expect_value(t, c.x, WALL_MARGIN)
	testing.expect(t, c.bumped[5] == BUMP_TICKS && c.bumped[6] == BUMP_TICKS && c.bumped[7] == BUMP_TICKS)
	testing.expect(t, c.bumped[2] == 0)
}
