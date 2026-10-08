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
	if game.life.dead do return
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
		spider := &game.spider
		bell := &game.objects[BELL]
		if s.food < 26 && bell.active && !bell.in_box {
			game.hunger_count = (game.hunger_count + 1) % 5
			if game.hunger_count == 0 {
				debug_logf("hungry (food %d): wait at the bell", s.food)
				move_to(spider, .Creature_A, -1, -1, 4, game.seq.lurk, 120, target = BELL)
			}
		}
		spider_thirst(spider)
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
	case ids.kill_reset:
		return c.prev_seq == ids.kill
	case ids.catch_reset:
		return c.prev_seq == ids.catch_
	case ids.catch_:
		// the target cricket must be within half the spider's hit rect
		if c.target_id < 0 do return false
		cr := &game.crickets[c.target_id]
		return abs(c.x - cr.x) <= (c.hit.right - c.hit.left) / 2 &&
			abs(c.y - cr.y) <= (c.hit.bottom - c.hit.top) / 2
	}
	return false
}

// Sequence validity for the idle pick (0x402f40).
spider_can_play :: proc(c: ^Creature, seq: int) -> bool {
	if c.hide != 0 && seq != game.seq.walk do return false
	d := &c.anim.seqs[seq].dirs[c.dir]
	if d.needs_check do return spider_precondition(c, seq)
	if seq != game.seq.walk do return len(d.frames) > 0
	b := c.blocks[c.dir]
	return !b.active && b.kind != BLOCK_WALL
}

ROCK_X      :: 0x1a6 // 422: hiding spot behind the rock (minus a size margin)
LOG_X       :: 640   // 0x280: where LOG_HIDE starts, in front of the rock
GLASS_Y     :: 0x177 // 375: front glass line (plus a size margin)

// Idle chooser (0x407830 for the spider, falling through to 0x402760).
spider_idle :: proc(c: ^Creature) {
	ids := &game.seq
	s := &game.stats

	// being carried / just dropped (0x407830)
	if c.carried == 1 {
		c.seq = ids.pickup
		c.dir = 4
		c.tool = .Carry
		return
	}
	if c.carried == 2 {
		c.dir = 4
		c.seq = ids.drop
		if c.prev_seq != ids.drop do return
		c.carried = 0
	}

	if c.hide != 0 {
		spider_idle_hidden(c)
		return
	}

	// Usually turn on the spot first.
	if p := rand_n(5) + 4; rand_n(10) < p && c.prev_seq != ids.circle {
		start_turn_step(c, rand_n(10) >= 5)
		return
	}

	if s.food <= rand_n(10) + 25 && rand_n(10) < 5 {
		plays := rand_n(4) + 4
		enqueue_anim(c, ids.walk, rand_n(8), plays, flush = true)
		c.seq = ids.walk
		debug_logf("idle: peckish (food %d), wander", s.food)
		return
	}
	if s.food <= rand_n(10) + 25 && rand_n(10) < 2 {
		enqueue_anim(c, ids.lurk, -1, rand_n(2) + 2, flush = true)
		c.seq = ids.lurk
		debug_logf("idle: peckish (food %d), lurk", s.food)
		return
	}
	if s.temperament < 4 && rand() * s.temperament * 10 / 0x7FFF < 2 {
		dir := rand_n(10) < 4 ? 7 : rand_n(2)
		enqueue_anim(c, ids.crush, dir, 1, flush = true)
		c.seq = ids.lurk
		debug_logf("idle: grumpy (temperament %d), crush", s.temperament)
		return
	}

	tries := 0
	for {
		tries += 1
		if tries > 8 {
			c.seq = rand_n(10) < 6 ? ids.lurk : ids.walk
			debug_logf("idle: nothing fits, %s", seq_name(c, c.seq))
			break
		}
		if rand_n(10) < s.temperament / 2 {
			c.seq = ids.walk
		} else {
			c.seq = rand_n(len(c.anim.seqs))
		}
		if c.seq == c.prev_seq || c.seq == ids.circle do continue
		if !seq_has_frames(c, c.seq, c.dir) do continue
		if spider_wants(c, c.seq) && spider_can_play(c, c.seq) {
			debug_logf("idle: pick %s (try %d)", seq_name(c, c.seq), tries)
			break
		}
	}

	if rand_n(50) == 25 && now_ms > c.last_played[ids.log_hide] + 720_000 {
		debug_logf("idle: go hide under the rock")
		move_to(c, .Point, LOG_X, FLOOR_TOP, 7, ids.log_hide, 120)
		return
	}
	if rand_n(10) > 6 && now_ms > c.last_played[ids.glass] + 180_000 {
		debug_logf("idle: go to the glass")
		move_to(c, .Y_Band, c.x, (100 - c.size) / 2 + GLASS_Y, 4, ids.glass, 60)
	}
}

// Behind the rock: stay put, now and then come out (0x402760, else branch).
spider_idle_hidden :: proc(c: ^Creature) {
	ids := &game.seq
	hidden_x := ROCK_X - (100 - c.size) / 2
	if c.hide == 2 ||
	   (now_ms > c.last_played[ids.log_hide] + 120_000 &&
		   rand_n(50) < game.stats.temperament && rand_n(10) < 2) {
		c.hide = 2
		c.x, c.y = hidden_x, HIDE_Y
		enqueue_anim(c, ids.walk, 6, 14, flush = true)
		enqueue_anim(c, ids.walk, rand_n(10) > 4 ? 4 : 5, 12)
		c.hide = 3
		c.seq = ids.lurk
		debug_logf("hidden: coming out")
		return
	}
	if c.hide == 1 {
		clear_queue(c)
		clear_goal(c)
		c.seq = ids.lurk
		c.x, c.y = hidden_x, HIDE_Y
		c.dir = 6
	}
}

// Sequence-finished hook for the spider (0x403520).
spider_finished :: proc(c: ^Creature) {
	ids := &game.seq
	switch c.seq {
	case ids.kill:
		// finished eating: remains, then reset and groom (0x403520)
		c.eating = false
		add_remains(c)
		c.prev_seq = ids.kill
		enqueue_anim(c, ids.kill_reset, -1, 1, flush = true)
		plays := rand_n(2) + 2
		enqueue_anim(c, ids.clean, rand_n(5) + 3, plays)
		c.target_id = -1
	case ids.log_hide:
		// crawled under the rock: teleport behind it
		clear_goal(c)
		clear_queue(c)
		c.x, c.y = ROCK_X, HIDE_Y
		c.seq = ids.lurk
		debug_logf("hidden under the rock") // hide was set while crawling (0x4057b0)
	case ids.clean:
		if rand_n(15) < game.stats.temperament * 2 {
			dir := rand_n(5) + 3
			enqueue_anim(c, ids.clean, dir, rand_n(2) + 2, flush = true)
		}
	case ids.web_laying:
		if rand_n(10) < 6 && c.queue_len == 0 {
			dir := c.dir + 2
			if dir > 7 do dir = 0
			run := rand_n(2) != 0
			enqueue_anim(c, ids.web_laying, dir, rand_n(2) + 8, flush = true, run = run)
		}
	}
}
