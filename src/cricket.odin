package vc

// Crickets and hunting (docs/BEHAVIOR.md, "Crickets and hunting").

CRICKET_COUNT :: 12
MAX_IN_TANK   :: 8  // crickets can only be taken out of the box while fewer are in the tank
REMAINS_COUNT :: 12 // ring of cricket remains on the sand (0x452720)

Cricket_Seq_Ids :: struct {
	circle, walk, lurk, jump, chirp, pickup, drop, web_stuck: int,
}

Remains :: struct {
	x, y, kind: int, // kind picks one of 6 sprites in vcg_4004
	used:       bool,
}

// Startup (0x40f... setup path): 12 crickets wait in the box.
crickets_init :: proc() {
	a := &game.cricket_a
	game.cseq = {
		circle    = seq_find(a, "CIRCLE"),
		walk      = seq_find(a, "WALK"),
		lurk      = seq_find(a, "LURK"),
		jump      = seq_find(a, "JUMP"),
		chirp     = seq_find(a, "CHIRP"),
		pickup    = seq_find(a, "PICKUP"),
		drop      = seq_find(a, "DROP"),
		web_stuck = seq_find(a, "WEB_STUCK"),
	}
	for &c, i in game.crickets {
		y := rand_n(130) + 290
		x := rand_n(440) + 50
		creature_init(&c, a, x, y, 8, 6, 0)
		c.kind = .Cricket
		c.id = i
		c.name = "cricket"
		c.in_box = true
		c.dir = min(rand_n(8), 7) // rand_n(8) is 8 once in 32768; the original would read past its table
		c.idle = cricket_idle
		c.seq = game.cseq.lurk
		start_sequence(&c)
	}
}

crickets_in_tank :: proc() -> (n: int) {
	for &c in game.crickets do if c.active && !c.in_box do n += 1
	return
}

// Takes a cricket out of the box and drops it into the tank at (x, y), like
// releasing it with the feed tool (wnd_proc_main mouse-up).
cricket_drop :: proc(x, y: int) -> bool {
	if crickets_in_tank() >= MAX_IN_TANK do return false
	for &c in game.crickets {
		if !c.active || !c.in_box do continue
		c.in_box = false
		c.x, c.y = x, y
		c.prev_x, c.prev_y = x, y
		c.carried = 2
		clear_queue(&c)
		c.plays = 1 // the current sequence ends now; the idle chooser plays DROP
		creature_update_position(&c)
		next_sequence(&c)
		debug_logf("cricket %d dropped at (%d, %d)", c.id, x, y)
		spider_sees_cricket(&game.spider, &c)
		return true
	}
	return false
}

// Cricket idle (0x407830, cricket branches).
cricket_idle :: proc(c: ^Creature) {
	ids := &game.cseq
	if c.carried == 2 {
		c.seq = ids.drop
		c.dir = 4
		c.web_stuck = false
		if c.prev_seq != ids.drop do return // play DROP first
		c.carried = 0
	}
	if c.web_stuck {
		r := rand_n(10)
		c.seq = r < 3 ? ids.lurk : rand_n(10) < 5 ? ids.chirp : ids.web_stuck
		spider_sees_cricket(&game.spider, c)
		return
	}

	if p := rand_n(3) + 4; rand_n(10) < p && c.prev_seq != ids.circle {
		start_turn_step(c, rand_n(10) >= 5)
		return
	}
	for {
		c.seq = rand_n(len(c.anim.seqs))
		if c.seq == ids.circle || c.seq == c.prev_seq do continue
		if !seq_has_frames(c, c.seq, c.dir) do continue
		d := &c.anim.seqs[c.seq].dirs[c.dir]
		if !d.needs_check do break
		if c.seq == ids.web_stuck && c.web_stuck do break
	}
	spider_sees_cricket(&game.spider, c)
}

// Whether the spider goes after a cricket (0x404010). Called when a cricket
// lands in the tank, and for crickets stuck in a web.
spider_sees_cricket :: proc(s, c: ^Creature) {
	if s.kind != .Spider || c.kind != .Cricket do return
	dx, dy := abs(s.x - c.x), abs(s.y - c.y)
	timeout: int
	if c.carried == 2 {
		if dx > 350 || dy > 175 do return
		if s.hide != 0 && rand_n(10) < 2 {
			s.hide = 2 // come out from under the rock
			debug_logf("spider noticed cricket %d, coming out", c.id)
			return
		}
		food := game.stats.food
		if rand_n(25) + 65 <= food {
			debug_logf("spider ignores cricket %d (food %d)", c.id, food)
			return
		}
		timeout = min(160 - food, 20)
	} else {
		if !c.web_stuck || s.eating do return
		if dx > 200 || dy > 140 do return
		stop_current(s)
		timeout = 45
	}
	debug_logf("spider hunts cricket %d", c.id)
	move_to(s, .Creature_B, -1, -1, -1, game.seq.catch_, timeout, target = c.id)
}

// The spider's lunge (part of 0x404b20): the cricket is pulled in during
// CATCH; on the last frame it is caught (KILL) or escapes (CATCH_RESET).
spider_catch_frame :: proc(s: ^Creature) {
	if s.seq != game.seq.catch_ || s.target_id < 0 do return
	cr := &game.crickets[s.target_id]
	n := len(creature_dir(s).frames)
	slot, centre := s.blocks[s.dir], s.blocks[8]
	in_slot := slot.active && slot.kind == int(Kind.Cricket) && slot.id == cr.id
	in_centre := centre.active && centre.kind == int(Kind.Cricket) && centre.id == cr.id

	if s.frame > 0 && in_slot && n - s.frame > 0 {
		// pull the cricket towards the spider's mouth
		left := n - s.frame
		tx, ty := s.x, s.y + (s.hit.bottom - s.hit.top) / 3
		cr.x += (tx - cr.x) / left
		cr.y += (ty - cr.y) / left
		cr.web_stuck = false
	}
	if s.frame < n - 1 do return

	if in_slot || (in_centre && s.y >= FLOOR_TOP && rand_n(10) > 1) {
		cricket_eaten(cr)
		enqueue_anim(s, game.seq.kill, s.dir, 1, flush = true)
		s.eating = true
		host_sound(450 + rand_n(3))
		debug_logf("spider caught cricket %d", cr.id)
	} else {
		s.prev_seq = game.seq.catch_
		enqueue_anim(s, game.seq.catch_reset, s.dir, 1, flush = true)
		if in_centre || in_slot || centre.id == cr.id || slot.id == cr.id {
			enqueue_anim(cr, game.cseq.jump, rand_n(8), rand_n(3) + 1, flush = true, run = true)
		}
		debug_logf("spider missed cricket %d", cr.id)
	}
}

// Cricket eaten (0x404180): +25 food; its slot is refilled from storage.
cricket_eaten :: proc(cr: ^Creature) {
	s := &game.spider
	game.stats.food = min(game.stats.food + 25, 100)
	game.eaten += 1
	if s.goal.active && s.goal.type == .Creature_B && s.goal.target == cr.id do clear_goal(s)
	cr.active = false
	if game.storage > 0 {
		game.storage -= 1
		cr.active = true
		cr.in_box = true
		cr.web_stuck = false
		stop_current(cr)
	}
}

// Leaves cricket remains at the centre of the spider's hit rect (0x408350).
add_remains :: proc(s: ^Creature) {
	kind := rand_n(6)
	r := &game.remains[game.remains_next]
	r^ = {
		x    = s.hit.left + (s.hit.right - s.hit.left) / 2,
		y    = max(s.hit.top + (s.hit.bottom - s.hit.top) / 2, FLOOR_TOP),
		kind = kind,
		used = true,
	}
	game.remains_next = (game.remains_next + 1) % REMAINS_COUNT
}

// Debug: drop a cricket somewhere on the visible floor on the next tick.
@(export)
tank_drop_cricket :: proc "contextless" () {
	game.pending_drops += 1
}

handle_pending_drops :: proc() {
	for ; game.pending_drops > 0; game.pending_drops -= 1 {
		x := game.scroll_x + 120 + rand_n(VIEW_W - 240)
		y := 200 + rand_n(200)
		if !cricket_drop(x, y) do debug_logf("no cricket to drop (box empty or %d in tank)", MAX_IN_TANK)
	}
}
