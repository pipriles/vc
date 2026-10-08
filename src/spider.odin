package vc

import "core:math"

// Spider needs, temperament and idle behaviour (docs/BEHAVIOR.md).

Spider_Stats :: struct {
	food, water: int, // 0..100 (+0x15e, +0x160)
	health:      int, // 0..100 (+0x15c)
	mood:        int, // -100..100 (+0x158)
	temperament: int, // 0..7, higher = calmer (+0x15a)
	interacted:  bool, // recently touched by a tool (+0x4a)
	last_minute: u32, // (+0x170)
	last_food:   u32, // (+0x1bc)
	last_water:  u32, // (+0x1c0)
}

// Per-second stats update (0x4010c0).
spider_stats_tick :: proc(s: ^Spider_Stats) {
	water, food := s.water, s.food
	avg := (water + food) / 2
	s.health = avg
	if food < 41 || water < 41 {
		s.health = min(water, food) + 1
	} else {
		adj := 0
		if food < 50 {
			s.health = food - 50 + avg
			adj += (50 - food) / 2
		} else if water < 50 {
			s.health = water - 50 + avg
			adj += (50 - water) / 2
		}
		m := abs(s.mood)
		adj += m >= 80 ? -20 : m >= 50 ? -10 : m >= 30 ? 0 : 10
		s.health += adj
	}
	s.health = min(s.health, 100)
	if s.health < 2 {
		s.health = 0
	} else {
		// temperament = floor(v * 0.07), rounded up when the fraction >= 0.7
		v := (100 - abs(s.mood)) / 2 + s.health / 2
		ip, frac := math.modf(f64(f32(v) * 0.01 * 7.0))
		if frac >= 0.7 do ip += 1
		s.temperament = int(ip)
	}

	if now_ms > s.last_water + 9_000_000 { // every 2.5 h
		s.last_water = now_ms
		s.water = max(s.water - 2, 0)
	}
	if now_ms > s.last_food + 7_200_000 { // every 2 h
		s.last_food = now_ms
		s.food = max(s.food - 2, 0)
	}
	if now_ms >= s.last_minute + 60_000 {
		s.last_minute = now_ms
		s.interacted = false
		s.mood -= 1
		if s.mood < -100 do s.mood = 100 // sic: the original wraps here
	}
}

// Whether the spider wants to play seq right now (0x402d60).
spider_wants :: proc(c: ^Creature, seq: int) -> bool {
	s := &game.stats
	t := s.temperament
	ids := &game.seq
	switch seq {
	case ids.walk:
		if t < 3 && rand_n(10) < 4 do return false
		return t > 4 || rand_n(10) > 3
	case ids.crush:
		return now_ms >= c.last_played[seq] + 30_000
	case ids.lurk, ids.glass, ids.log_hide:
		return true
	case ids.lurk_d:
		return t > 5 || rand_n(10) > 5
	case ids.threat, ids.hair:
		return s.interacted
	case ids.clean:
		return rand_n(15) < t * 2
	case ids.web_laying:
		return s.food < 36 && rand_n(10) < 8
	}
	return false
}

// Precondition for sequences flagged needs_check (0x403000).
spider_precondition :: proc(c: ^Creature, seq: int) -> bool {
	ids := &game.seq
	switch seq {
	case ids.glass:
		return c.size > 49 && c.y >= (60 - c.size) / 2 + 375
	case ids.log_hide:
		return c.y < 174 && c.x > 629 && c.x < 651 && c.size > 24
	case ids.web_laying:
		return game.stats.food <= rand_n(10) + 20 && rand_n(10) < 7
	case ids.hair, ids.threat, ids.kill:
		return true
	}
	return false // CATCH etc. need a cricket target
}

// Sequence validity for the idle pick (0x402f40).
spider_can_play :: proc(c: ^Creature, seq: int) -> bool {
	d := &c.anim.seqs[seq].dirs[c.dir]
	if d.needs_check do return spider_precondition(c, seq)
	if seq != game.seq.walk do return len(d.frames) > 0
	return c.bumped[c.dir] != BUMP_TICKS
}

// Idle chooser (0x407830 for the spider, falling through to 0x402760).
spider_idle :: proc(c: ^Creature) {
	ids := &game.seq
	s := &game.stats

	// Usually turn on the spot first.
	if p := rand_n(5) + 4; rand_n(10) < p && c.prev_seq != ids.circle {
		start_turn_step(c, rand_n(10) >= 5)
		return
	}

	if s.food <= rand_n(10) + 25 && rand_n(10) < 5 {
		plays := rand_n(4) + 4
		enqueue_anim(c, ids.walk, rand_n(8), plays)
		c.seq = ids.walk
		return
	}
	if s.food <= rand_n(10) + 25 && rand_n(10) < 2 {
		enqueue_anim(c, ids.lurk, -1, rand_n(2) + 2)
		c.seq = ids.lurk
		return
	}
	if s.temperament < 4 && rand() * s.temperament * 10 / 0x7FFF < 2 {
		dir := rand_n(10) < 4 ? 7 : rand_n(2)
		enqueue_anim(c, ids.crush, dir, 1)
		c.seq = ids.lurk
		return
	}

	tries := 0
	for {
		tries += 1
		if tries > 8 {
			c.seq = rand_n(10) < 6 ? ids.lurk : ids.walk
			break
		}
		if rand_n(10) < s.temperament / 2 {
			c.seq = ids.walk
		} else {
			c.seq = rand_n(len(c.anim.seqs))
		}
		if c.seq == c.prev_seq || c.seq == ids.circle do continue
		if !seq_has_frames(c, c.seq, c.dir) do continue
		if spider_wants(c, c.seq) && spider_can_play(c, c.seq) do break
	}

	// TODO: walk to the log (1 in 51, every 12 min) or the glass (30%, every
	// 3 min) via move_to_then_anim (0x40bdd0), not decoded yet.
}
