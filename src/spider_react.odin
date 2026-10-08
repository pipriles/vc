package vc

// The spider's reaction to the player's tools (spider_react_tool, 0x401420).
// The original is one function with shared goto targets; those became the
// small helpers below, named after the original labels where useful.
//
// Interactions (+0x4c): 1 prod, 2 tap on the glass, 3 stroke, 4 being
// followed with the cursor, 5 being carried.

Interaction :: enum {
	None   = 0,
	Prod   = 1,
	Tap    = 2,
	Stroke = 3,
	Follow = 4,
	Carry  = 5,
}

REACT_COOLDOWN_MS :: 2500 // 0x9c4

// `(5 - rand() * t) / 0x7fff + k` with the original's unsigned wraparound.
@(private = "file")
neg_rand_term :: proc(base, t: int) -> int {
	return int(i32(u32(base) - u32(rand()) * u32(t))) / 0x7FFF
}

spider_react_tool :: proc(c: ^Creature) {
	ids := &game.seq
	s := &game.stats
	tool := c.tool

	end :: proc(c: ^Creature) {
		c.prev_tool = c.tool
		c.tool = .None
	}
	// enqueue then end (the common tail)
	E :: proc(c: ^Creature, seq, dir, plays: int, flush: bool, run: int) {
		enqueue_anim(c, seq, dir, plays, flush = flush, run = run != 0)
		end(c)
	}
	// walk off in a random direction, then crush (LAB_00401bc8)
	walk_then_crush :: proc(c: ^Creature, plays: int, flush: bool, run: int) {
		enqueue_anim(c, game.seq.walk, rand_n(8), plays, flush = flush, run = run != 0)
		E(c, game.seq.crush, -1, 1, false, 0)
	}
	// walk to the front glass band, then play (LAB_004023f9 / LAB_00401cce)
	to_glass :: proc(c: ^Creature, x, y, dir, seq: int) {
		move_to(c, .Y_Band, x, y, dir, seq, 60)
		end(c)
	}
	// retreat under the rock if on the floor (joined_r0x004025d9)
	hide_or_nothing :: proc(c: ^Creature) {
		if c.y > 169 {
			move_to(c, .Point, LOG_X, FLOOR_TOP, 7, game.seq.log_hide, 120)
		}
		end(c)
	}

	// can't react while eating or off the floor, except to the tap
	if tool != .Tap && (c.eating || c.y < FLOOR_TOP) {
		s.interacted = false
		c.tool = .None
		game.release_mouse = true
		return
	}
	if now_ms < c.last_react + REACT_COOLDOWN_MS do return
	if c.goal.active && c.goal.seq == ids.log_hide do return
	c.last_react = now_ms
	s.interacted = true

	// mood: agitating interactions push it away from 0, calming ones back
	if tool != c.prev_tool {
		c.mood_step = 0
		#partial switch tool {
		case .Prod, .Tap, .Carry:
			c.mood_step = s.mood >= 0 ? 3 : -3
		case .Stroke, .Follow:
			c.mood_step = s.mood >= 0 ? -3 : 3
		}
	}
	s.mood = clamp(s.mood + c.mood_step, -100, 100)
	t := s.temperament
	run := rand_n(2)
	y := c.y

	if c.hide != 0 {
		// a tap may coax it out from under the rock
		if tool == .Tap && c.hide == 1 && t > 2 && rand_n(8) < t {
			c.hide = 2
		}
		end(c)
		return
	}
	debug_logf("spider reacts to %v (temperament %d, mood %d)", tool, t, s.mood)

	switch tool {
	case .None:
	case .Prod:
		if t < 4 {
			if rand_n(10) < 4 {
				walk_then_crush(c, rand_n(2) + 4, true, 1)
			} else if rand_n(10) < 5 {
				if rand_n(10) > 4 {
					E(c, ids.threat, 4, rand_n(2) + 2, true, 1)
				} else if y < 325 {
					to_glass(c, c.x, GLASS_Y, 4, ids.threat)
				} else {
					E(c, ids.threat, 4, 2, true, 1)
				}
			} else {
				if rand_n(10) > 4 {
					if t > 2 || rand_n(10) >= 7 {end(c); return}
					hide_or_nothing(c)
				} else if y < 325 {
					to_glass(c, c.x, GLASS_Y, 4, ids.hair)
				} else {
					E(c, ids.hair, 4, 2, true, 1)
				}
			}
		} else {
			if rand_n(10) < 5 {
				plays := rand_n(4) + 4
				enqueue_anim(c, ids.walk, rand_n(8), plays, flush = true, run = true)
				E(c, ids.lurk, -1, rand_n(2) + 2, false, 0)
			} else if rand_n(10) < 5 {
				E(c, ids.lurk, 4, rand_n(2) + 2, true, 1)
			} else if rand_n(10) > 4 {
				plays := rand_n(2) + 2
				E(c, ids.lurk_d, rand_n(3) + 3, plays, true, 1)
			} else {
				E(c, ids.walk, -1, rand_n(4) + 4, true, 1)
			}
		}

	case .Tap:
		if t < rand_n(2) + 3 {
			if rand_n(10) < 4 && c.seq != ids.crush {
				E(c, ids.crush, rand_n(2), 1, true, 0)
			} else if rand_n(10) < 5 {
				plays := neg_rand_term(5, t) + 8
				enqueue_anim(c, ids.walk, rand_n(2), plays, flush = true, run = run != 0)
				E(c, ids.crush, -1, 1, false, 0)
			} else if t < 3 {
				if rand_n(10) < 5 && c.seq != ids.threat {
					E(c, ids.threat, 4, rand_n(2) + 2, true, run)
				} else if rand_n(10) > 4 || c.seq == ids.hair {
					if rand_n(10) >= 4 {end(c); return}
					hide_or_nothing(c)
				} else if y < 325 {
					to_glass(c, c.x, GLASS_Y, 4, ids.hair)
				} else {
					E(c, ids.hair, 4, 2, true, run)
				}
			} else {
				if rand_n(10) > 5 {end(c); return}
				plays := neg_rand_term(5, t) + 3
				E(c, ids.walk, rand_n(2), plays, true, 0)
			}
		} else {
			if rand_n(10) < 5 {
				// come to the front, where the glass was tapped
				if y < 325 do to_glass(c, game.cursor_x, GLASS_Y - rand_n(30), -1, -1)
				else do end(c)
			} else if rand_n(10) < 6 && c.seq != ids.glass {
				lim := (100 - c.size) / 2 + GLASS_Y
				if y < lim do to_glass(c, game.cursor_x, lim, 4, ids.glass)
				else do E(c, ids.glass, 4, 1, true, run)
			} else if rand_n(10) < 5 {
				E(c, ids.walk, 4, rand() * (t / 2) / 0x7FFF + 2, true, run)
			} else {
				if rand_n(10) > 3 {end(c); return}
				plays := rand() * (t / 2) / 0x7FFF + 4
				E(c, ids.lurk_d, rand_n(3) + 3, plays, true, 0)
			}
		}

	case .Stroke:
		if t < 6 {
			if t < 4 {
				if rand_n(10) < 6 {
					walk_then_crush(c, neg_rand_term(7, t) + 8, true, run)
				} else if t < 3 {
					if rand_n(10) < 5 && c.seq != ids.threat {
						E(c, ids.threat, 4, rand_n(2) + 2, true, run)
					} else if rand_n(10) > 5 {
						if rand_n(10) > 3 {end(c); return}
						hide_or_nothing(c)
					} else if y < 325 {
						to_glass(c, c.x, GLASS_Y - rand_n(100), 4, ids.hair)
					} else {
						E(c, ids.hair, 4, 2, true, run)
					}
				} else {
					plays := neg_rand_term(7, t) + 8
					E(c, ids.walk, rand_n(8), plays, true, 1)
				}
			} else {
				if rand_n(10) > 5 || c.seq == ids.crush {
					if rand_n(10) < 5 && c.seq != ids.glass {
						to_glass(c, c.x, (100 - c.size) / 2 + GLASS_Y, 4, ids.glass)
					} else if rand_n(10) > 3 {
						end(c)
					} else if y < 325 {
						to_glass(c, c.x, GLASS_Y - rand_n(100), -1, -1)
					} else {
						E(c, ids.lurk, rand_n(3) + 3, 1, true, run)
					}
				} else {
					E(c, ids.crush, -1, rand() * t / 0x7FFF + 4, true, 0)
				}
			}
		} else {
			if c.seq == ids.glass || (c.seq == ids.crush && c.mood_step > 0) {end(c); return}
			if rand_n(10) < 7 && c.seq != ids.crush {
				E(c, ids.crush, -1, rand() * t / 0x7FFF + 4, true, run)
			} else if rand_n(10) < 7 && c.seq != ids.glass {
				lim := (100 - c.size) / 2 + GLASS_Y
				if y < lim do to_glass(c, c.x, lim, 4, ids.glass)
				else do E(c, ids.glass, 4, 1, true, run)
			} else {
				plays := rand() * t / 0x7FFF + 4
				E(c, ids.lurk_d, rand_n(3) + 3, plays, true, 0)
			}
		}

	case .Follow:
		if rand() / 0x7FFF + 3 < t {end(c); return}
		if rand_n(10) < 3 {
			clear_goal(c)
			end(c)
			return
		}
		if t > 2 {end(c); return}
		if rand_n(10) < 5 && c.seq != ids.threat {
			E(c, ids.threat, 4, rand_n(2) + 2, true, 1)
		} else if rand_n(10) > 4 || c.seq == ids.hair {
			if rand_n(10) > 2 {end(c); return}
			hide_or_nothing(c)
		} else if y < 325 {
			to_glass(c, c.x, GLASS_Y - rand_n(80), 4, ids.hair)
		} else {
			E(c, ids.hair, 4, rand_n(2) + 1, true, run)
		}

	case .Carry:
		if t < 4 {
			if rand_n(10) < 3 && c.seq != ids.threat {
				E(c, ids.threat, 4, rand_n(2) + 1, true, run)
			} else if rand_n(10) < 3 && c.seq != ids.hair {
				E(c, ids.hair, 4, neg_rand_term(5, t) + 3, true, 1)
			} else if rand_n(10) > 4 || c.seq == ids.crush {
				if t > 2 || rand_n(10) != 3 {end(c); return}
				hide_or_nothing(c)
			} else {
				E(c, ids.crush, rand_n(2), 1, true, run)
			}
		} else {
			if rand_n(10) > 2 || c.seq == ids.lurk_d {
				if rand_n(10) > 4 || c.seq == ids.lurk {end(c); return}
				plays := rand_n(3) + 3
				E(c, ids.lurk, rand_n(3) + 3, plays, true, run)
			} else {
				plays := rand_n(3) + 3
				E(c, ids.lurk_d, rand_n(3) + 3, plays, true, 0)
			}
		}
	}
	if c.tool != .None do end(c)
}
