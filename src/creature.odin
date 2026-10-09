package vc

import "core:fmt"

// Creature animation and movement, following VC.EXE (docs/BEHAVIOR.md).
// Original addresses and struct offsets are noted for cross-reference.

QUEUE_LEN   :: 16
TANK_W      :: 1200
VIEW_W      :: 640
VIEW_H      :: 480
FLOOR_TOP   :: 170 // 0xaa: tank floor starts at this y, above is the back wall
HIDE_Y      :: 114 // 0x72: lowest y while hiding behind the rock
WALL_MARGIN :: 130 // 0x82: closest a creature's centre gets to the side walls
BLOCK_WALL  :: 5   // block kind for a wall (the other kinds are creatures)

Queued :: struct {
	seq, dir, plays: int,
	run:             bool,
}

// Per-direction obstacle slot (+0xfa + 8*dir). Walls set only kind, which
// lasts until the next position update.
Block :: struct {
	active:    bool,
	kind, id:  int,
	ticks:     int,
}

Goal_Type :: enum {
	Creature_A = 1, // chase a creature (types 1/2, crickets: TBD)
	Creature_B = 2,
	Cursor     = 10,
	Point      = 11,
	Y_Band     = 12, // only y matters (the front glass)
	X_Band     = 13, // only x matters
}

// Walk-to-target goal set by move_to (0x40bdd0, +0x58..+0x7c).
Goal :: struct {
	active:               bool,
	type:                 Goal_Type,
	x, y:                 int, // target (+0x66, +0x68)
	seq, dir:             int, // played on arrival (+0x6c, +0x6a)
	target:               int, // creature id for chase goals (+0x64)
	timeout_s:            int, // abandon after this many seconds (+0x60), 0 = never
	start_ms:             u32,
	detouring:            bool, // walking round an obstacle (+0x6e)
	cand:                 [3]int, // directions around the blocked one (+0x78..)
	detour_x, detour_y:   int, // where the detour started (+0x74, +0x76)
	resume_dir, walk_dir: int, // (+0x72, +0x70)
	detour_cw:            bool, // port: which way round the detour turns
}

Kind :: enum {
	Spider  = 0,
	Object  = 1, // tank objects (TBD)
	Cricket = 2,
	Skin    = 6, // the shed skin
}

Rect :: struct {
	left, top, right, bottom: int,
}

Creature :: struct {
	anim:               ^Anim,
	name:               string,
	kind:               Kind, // (+0xf4)
	id:                 int,  // index within its kind (+0xf2)
	active:             bool, // exists (+0x92)
	in_box:             bool, // cricket still in the cricket box (+0x96)
	carried:            int,  // 0, 1 = being carried, 2 = just dropped (+0xc8)
	eating:             bool, // spider eating a cricket (+0x164)
	target_id:          int,  // cricket being caught (+0x144)
	hit:                Rect, // current frame box in tank coordinates (+0xd0)
	prev_x, prev_y:     int,  // position before this tick's move (+0xaa, +0xac)
	x, y:               int,  // centre in tank coordinates (+0xa6, +0xa8)
	from_x, from_y:     int,  // smooth drawing: position at the start of the last step
	dir:                int,  // facing 0..7: 0 = up, clockwise (+0x9a)
	seq, prev_seq:      int,  // (+0x98, +0xbc)
	frame, step:        int,  // (+0xb2, +0xb4)
	plays:              int,  // remaining plays of seq (+0xba)
	left:               int,  // frames left in this pass (+0xb6)
	bounces:            int,  // tail reversals left (+0xca)
	back_pass:          int,  // 2 = play the whole thing backward at the end (+0xb8)
	hold:               int,  // frame hold countdown, -1 = none (+0xf6)
	moving_x, moving_y: bool, // (+0xc4, +0xc6)
	no_clamp:           bool, // floor clamp off: hiding behind the rock (+0xc2)
	run:                bool, // double speed while walking (+0x152)
	turn_target:        int,  // facing to reach before the next queued seq, -1 = none
	turn_dir:           int,  // +1 clockwise, -1 counter-clockwise, 0 = not turning
	pop_turning:        bool, // turning for a queued sequence: no goal step meanwhile (+0x5a)
	base_sx, base_sy:   int,  // (+0x9e, +0xa0)
	size:               int,  // growth factor (+0x1e6), 40 for a new spider
	scale:              int,  // percent (+0x9c)
	sx, sy:             int,  // (+0xa2, +0xa4)
	blocks:             [9]Block,
	queue:              [QUEUE_LEN]Queued,
	queue_len:          int,
	goal:               Goal,
	hide:               int, // hiding state (+0x48): 0 out, 1 hidden, 2..3 coming out
	web_stuck:          bool, // cricket caught in a web (+0x166)
	// port: escaping when boxed in by objects (see spider_unstick)
	anchor_x, anchor_y: int,
	anchor_ms:          u32,
	squeeze_until:      u32,
	waiting_for:        int, // cricket the spider is waiting to come within reach, -1 none
	pause:              int,         // ticks frozen (+0xf8)
	tool:               Interaction, // pending player interaction (+0x4c)
	prev_tool:          Interaction, // (+0x4e)
	mood_step:          int,         // (+0x50)
	last_react:         u32,         // (+0x54)
	last_played:        []u32, // now_ms when each seq last finished (+0x174 + seq*4)
	idle:               proc(c: ^Creature), // picks a sequence when the queue is empty
	finished:           proc(c: ^Creature), // sequence-finished hook (0x403520 for the spider)
	can_play:           proc(c: ^Creature, seq: int) -> bool, // validity on pop (0x402f40)
}

// creature_init at 0x406680: (c, x, y, base_sx, base_sy, ...)
creature_init :: proc(c: ^Creature, a: ^Anim, x, y, base_sx, base_sy, size: int) {
	c^ = {}
	c.anim = a
	c.active = true
	c.target_id = -1
	c.waiting_for = -1
	c.x, c.y = x, y
	c.prev_x, c.prev_y = x, y
	c.base_sx, c.base_sy = base_sx, base_sy
	c.size = size
	c.dir = min(rand_n(8), 7) // creature_init picks a random facing
	c.step = 1
	c.hold = -1
	c.turn_target = -1
	c.seq = 0
	c.prev_seq = -1
	c.last_played = make([]u32, len(a.seqs))
	c.scale = 100
	creature_update_position(c)
}

creature_dir :: proc "contextless" (c: ^Creature) -> ^Dir {
	return &c.anim.seqs[c.seq].dirs[c.dir]
}

seq_name :: proc "contextless" (c: ^Creature, seq: int) -> string {
	return seq >= 0 && seq < len(c.anim.seqs) ? c.anim.seqs[seq].name : "-"
}

seq_has_frames :: proc "contextless" (c: ^Creature, seq, dir: int) -> bool {
	if seq < 0 || seq >= len(c.anim.seqs) || dir < 0 || dir > 7 do return false
	return len(c.anim.seqs[seq].dirs[dir].frames) > 0
}

// Walking that way is refused right after hitting something there.
dir_blocked :: proc "contextless" (c: ^Creature, d: int) -> bool {
	b := c.blocks[d]
	return (b.active && b.kind == 1) || b.kind == BLOCK_WALL
}

// enqueue_anim at 0x414700. dir 8 (or -1) keeps the current facing; flush
// first empties the queue and lets the current play finish. Refused behind
// the rock unless coming out (hide == 2), and for CIRCLE (turns are implicit).
enqueue_anim :: proc(c: ^Creature, seq, dir, plays: int, flush := false, run := false) {
	if seq < 0 || seq >= len(c.anim.seqs) || seq == game.seq.circle do return
	if c.y < FLOOR_TOP && c.hide != 2 do return
	if flush && c.turn_target < 0 && !c.eating {
		clear_queue(c)
		stop_current(c)
	}
	if c.queue_len >= QUEUE_LEN do return
	c.queue[c.queue_len] = {seq, dir, plays, run}
	c.queue_len += 1
}

clear_queue :: proc(c: ^Creature) {
	c.queue_len = 0
	c.run = false
}

// Lets the current sequence finish its current play, then stop (0x405900).
stop_current :: proc(c: ^Creature) {
	if c.y < FLOOR_TOP do return
	if c.seq == game.seq.glass do return
	c.plays = 1
	c.turn_target = -1
	c.run = false
	// keep the bounce parity so the play still ends the right way round
	c.bounces = c.bounces % 2 != 0 ? 1 : 0
}

// Starts c.seq in the current direction (0x404830).
start_sequence :: proc(c: ^Creature) {
	d := creature_dir(c)
	n := len(d.frames)
	if c.seq != game.seq.circle do c.step = 1
	c.frame = c.step < 0 ? n - 1 : 0
	s := &c.anim.seqs[c.seq]
	if c.plays < 1 && s.rand_repeat do c.plays = rand_n(s.max_repeat) + 1
	if c.seq != game.seq.circle {
		if d.pp_always || (d.pp_rand && rand_n(10) < 5) do c.back_pass = 2
		if d.tail_always || (d.tail_rand && rand_n(10) < 5) {
			k := max(d.loop_count, 1)
			if k % 2 != 0 do k += 1
			c.bounces = k + (c.back_pass < 1 ? 1 : 2) + rand_n(k) * 2
		} else {
			c.bounces = 0
		}
	}
	c.moving_x = d.move_x && rand_n(10) < 6
	c.moving_y = d.move_y
	c.no_clamp = d.no_clamp
	c.hold = -1
	sequence_start_rules(c)
	if c.plays < 1 do c.plays = 1
	c.left = n
	if c.run && abs(c.step) > 1 do c.left = n / abs(c.step)
}

// The current pass has run out of frames (0x404600): bounce over the tail,
// play backward, repeat, or report the sequence done.
sequence_play_done :: proc(c: ^Creature) -> bool {
	d := creature_dir(c)
	n := len(d.frames)
	c.bounces -= 1
	if c.bounces >= 0 {
		c.step = -c.step
		c.left = d.loop_len
		// (a direction without a tail would show frame n: stay on the last)
		c.frame = clamp(c.step < 0 ? n - 1 : n - d.loop_len, 0, n - 1)
		return false
	}
	c.back_pass -= 1
	if c.back_pass < 1 {
		c.plays -= 1
		c.bounces, c.back_pass = 0, 0
		if c.plays > 0 {
			start_sequence(c)
			return false
		}
		c.plays = 0
		return true
	}
	c.bounces = 0
	c.step = -c.step
	c.left = n - 1
	c.frame = c.step < 0 ? n - 1 : 0
	return false
}

// Per-sequence start rules (0x403210): cricket chirps; a weak spider
// doesn't run; a running walk also plays at double frame speed; play and
// bounce counts for the spider's moods (t = temperament).
sequence_start_rules :: proc(c: ^Creature) {
	if c.kind == .Cricket {
		if c.seq == game.cseq.chirp && c.in_box == (game.input.view == .Box) do host_sound(401)
		return
	}
	if c.kind != .Spider do return
	ids := &game.seq
	health := game.stats.health
	t := game.stats.temperament
	switch c.seq {
	case ids.circle:
		if health < 30 do c.run = false
	case ids.walk:
		if health < 15 || c.blocks[c.dir].active do c.run = false
		if c.run do c.step *= 2
	case ids.crush:
		c.plays = 0
		c.bounces = (rand_n(t) + t) * 8 + 8
	case ids.lurk:
		if c.plays < 1 do c.plays = (rand_n(t) + t) / 3
	case ids.lurk_d:
		if c.plays < 1 do c.plays = rand_n(t) + t
	case ids.threat:
		if c.plays < 1 do c.plays = rand_n(2) + 1
		c.bounces = rand_n(2) * 2 + 2
	case ids.glass:
		c.plays = 0
		c.bounces = (rand_n(t) + 4 + t * 2) * 2
	case ids.hair:
		if c.plays < 1 do c.plays = rand_n(2) + 1
	case ids.clean:
		if c.plays < 1 do c.plays = rand_n(3) + 2
	case ids.kill_reset:
		host_sound(457)
	}
}

// One CIRCLE play rotates the creature by one direction (0x4081c0):
// clockwise plays forward then faces dir+1, counter-clockwise first faces
// dir-1 and plays backward.
start_turn_step :: proc(c: ^Creature, cw: bool) {
	c.prev_seq = c.seq
	c.seq = game.seq.circle
	c.turn_dir = cw ? 1 : -1
	if cw {
		c.step = 1
	} else {
		c.dir = (c.dir + 7) % 8
		c.step = -1
	}
	if c.run do c.step *= 2
	c.plays = 1
	start_sequence(c)
}

// Called when the current sequence has finished all its plays.
next_sequence :: proc(c: ^Creature) {
	if c.turn_dir > 0 do c.dir = (c.dir + 1) % 8
	c.turn_dir = 0
	c.step = 1
	c.bounces, c.back_pass = 0, 0
	c.last_played[c.seq] = now_ms
	if c.finished != nil do c.finished(c)

	if c.turn_target >= 0 && c.turn_target != c.dir {
		// turn the shorter way round, one CIRCLE play per step (0x408170)
		cw := (c.turn_target - c.dir + 8) % 8 <= 4
		start_turn_step(c, cw)
		return
	}
	c.turn_target = -1

	if c.goal.active && !c.pop_turning do goal_step(c)

	if c.queue_len > 0 {
		// pop (0x414840)
		q := c.queue[0]
		dir := q.dir
		if dir < 0 || dir > 7 do dir = c.dir
		if dir != c.dir {
			c.turn_target = dir
			c.run = q.run
			c.pop_turning = true
			cw := (dir - c.dir + 8) % 8 <= 4
			start_turn_step(c, cw)
			return
		}
		c.pop_turning = false
		copy(c.queue[:], c.queue[1:c.queue_len])
		c.queue_len -= 1
		c.prev_seq = c.seq
		c.seq = q.seq
		c.plays = q.plays
		c.run = q.run
		if !seq_has_frames(c, c.seq, c.dir) || (c.can_play != nil && !c.can_play(c, c.seq)) {
			if c.kind == .Spider && c.seq == game.seq.catch_ {
				// out of reach: wait (lurking, facing it) for it to come closer
				if c.waiting_for != c.target_id {
					debug_logf("%s waits for cricket %d to come within reach", c.name, c.target_id)
				}
				c.waiting_for = c.target_id
			} else {
				debug_logf("%s can't play %s now, lurking instead", c.name, seq_name(c, c.seq))
			}
			c.seq = game.seq.lurk
			c.plays = 1
		} else if c.seq == game.seq.catch_ {
			c.waiting_for = -1
		}
	} else {
		c.run = false
		c.prev_seq = c.seq
		c.plays = 0
		c.idle(c)
		if c.turn_dir != 0 do return // idle chose to turn
		if !seq_has_frames(c, c.seq, c.dir) do c.seq = game.seq.lurk
	}
	start_sequence(c)
}

// Per-tick creature step (0x406780): frame advance, then movement.
creature_tick :: proc(c: ^Creature) {
	if !c.active do return
	// crickets in the box only move while the box is on screen
	if c.in_box && !(c.kind == .Cricket && game.input.view == .Box) do return
	if c.kind == .Spider && game.life.dead {
		spider_dead_tick(c)
		return
	}
	if c.kind == .Spider && c.tool != .None do spider_react_tool(c)
	d := creature_dir(c)
	if len(d.frames) == 0 {
		next_sequence(c)
		d = creature_dir(c)
	}
	f := d.frames[c.frame]

	// a pause (+0xf8) freezes the creature: no frames, no movement
	c.pause -= 1
	paused := c.pause >= 0
	if !paused {
		c.pause = 0
		if c.hold < 0 && f.hold_flag != 0 {
			c.hold = f.hold < 0 ? rand() * int(f.hold) / 0x7FFF : int(f.hold)
		}
		c.hold -= 1
		if c.hold < 0 {
			c.hold = -1
			c.frame += c.step
			if c.frame < 0 || c.frame >= len(d.frames) do c.left = 0
			c.left -= 1
			if c.goal.active && goal_check(c) {
				// arrived: cut short
				c.left, c.plays, c.bounces, c.back_pass = 0, 1, 0, 0
			}
			if c.left < 1 && sequence_play_done(c) do next_sequence(c)
			creature_post_frame(c)
		}
	}

	// movement for the frame now showing
	d = creature_dir(c)
	f = d.frames[clamp(c.frame, 0, len(d.frames) - 1)]
	dx, dy := int(f.dx), int(f.dy)
	if c.kind == .Cricket && !paused do cricket_web_check(c)
	if c.kind == .Cricket && c.web_stuck do paused = true // stuck crickets don't move
	if !paused && (c.moving_x || c.moving_y || dx != 0 || dy != 0) {
		sx, sy := c.sx, c.sy
		if c.run && c.seq == game.seq.walk {
			sx *= 2
			sy *= 2
		}
		vy := sx
		dir := c.dir
		if dir != 0 && dir != 4 && (dy == 0 || dx != 0) do vy = sy
		if dx != 0 || dy != 0 do dir = 99
		if dir == 0 || dir == 1 || dir == 7 || dy < 0 do c.y -= vy
		if dir == 3 || dir == 4 || dir == 5 || dy > 0 do c.y += vy
		if dir == 5 || dir == 6 || dir == 7 || dx < 0 do c.x -= sx
		if dir == 1 || dir == 2 || dir == 3 || dx > 0 do c.x += sx
	}
	creature_update_position(c)
}

// Tail of 0x404b20: hiding behind the rock lifts the floor clamp until the
// creature is back on the floor.
creature_post_frame :: proc(c: ^Creature) {
	if c.kind == .Cricket {
		cricket_frame_sounds(c)
		return
	}
	if c.kind == .Spider {
		spider_frame_events(c)
		spider_catch_frame(c)
	}
	if c.hide == 0 {
		if c.y < FLOOR_TOP do return
	} else if c.y < FLOOR_TOP {
		c.no_clamp = true
		return
	}
	if c.hide != 0 do debug_logf("%s back out on the floor", c.name)
	c.no_clamp = false
	c.hide = 0
}

// Clamps to the tank, derives depth scale and speeds, then checks
// collisions with the other creatures (0x406df0).
creature_update_position :: proc(c: ^Creature) {
	for &b in c.blocks {
		b.ticks -= 1
		if b.ticks < 1 do b = {}
	}

	margin, floor := WALL_MARGIN, FLOOR_TOP
	if c.kind == .Cricket do margin, floor = 80, 180
	if c.kind == .Cricket && c.in_box {
		// the cricket box has its own bounds and depth scale (0x406df0)
		c.x = clamp(c.x, 50, 590)
		c.y = clamp(c.y, 286, 460)
		c.scale = int(min(25 + f64(c.y) / 460 * 100, 100))
		c.sx = x87_scale_trunc(c.base_sx, c.scale)
		c.sy = x87_scale_trunc(c.base_sy, c.scale)
		creature_hit_rect(c)
		return
	}
	if c.no_clamp {
		c.y = max(c.y, HIDE_Y)
		c.x = clamp(c.x, margin, TANK_W - margin)
	} else {
		if c.x < margin {
			c.x = margin
			for d in ([?]int{5, 6, 7}) do c.blocks[d].kind = BLOCK_WALL
		}
		if c.x > TANK_W - margin {
			c.x = TANK_W - margin
			for d in ([?]int{1, 2, 3}) do c.blocks[d].kind = BLOCK_WALL
		}
		if c.y < floor {
			c.y = floor
			for d in ([?]int{7, 0, 1}) do c.blocks[d].kind = BLOCK_WALL
		}
		// bottom: a third of the drawn height may hang below the view
		if dh := x87_scale_trunc(c.anim.h, c.scale); c.y + dh / 3 >= VIEW_H {
			c.y = VIEW_H - dh / 3
			for d in ([?]int{3, 4, 5}) do c.blocks[d].kind = BLOCK_WALL
		}
	}

	// scale% = min(100, y/480 * size + 35), truncated (x87 + _ftol); spiders
	// and crickets both use the spider's size
	size := c.kind == .Cricket ? game.spider.size : c.size
	v := f64(c.y) / f64(VIEW_H) * f64(size) + 35
	c.scale = int(min(v, 100))
	// speeds shrink with distance: base / (100 / scale), truncated
	c.sx = x87_scale_trunc(c.base_sx, c.scale)
	c.sy = x87_scale_trunc(c.base_sy, c.scale)

	creature_hit_rect(c)

	if c.in_box || c.kind == .Skin do return
	may_move := true
	if c.kind != .Cricket || !c.web_stuck {
		for o in game.render_list {
			if o == c || !o.active || o.in_box do continue
			if c.kind == .Spider && c.hide != 0 do continue
			if !rects_intersect(c.hit, o.hit) do continue
			if collide_mark(c, o) && collide_respond(c, o) do break
			// only obstacles stop movement; spiders and crickets react instead
			passable := o.kind == .Cricket || o.kind == .Spider || (o.kind == .Object && now_ms < c.squeeze_until)
			if !passable && c.carried == 0 && c.blocks[c.dir].active do may_move = false
		}
	}
	if !may_move {
		c.x, c.y = c.prev_x, c.prev_y
	} else {
		c.prev_x, c.prev_y = c.x, c.y
	}

	// walking into something ends the walk after this play
	fb := c.blocks[c.dir]
	if (fb.active || (fb.kind != 0 && fb.kind != int(Kind.Cricket))) && (c.moving_x || c.moving_y) {
		c.plays = min(c.plays, 1)
	}
}

// Hit rect: the frame's stored box, scaled, at the drawn position.
creature_hit_rect :: proc(c: ^Creature) {
	dw, dh := x87_scale_trunc(c.anim.w, c.scale), x87_scale_trunc(c.anim.h, c.scale)
	d := creature_dir(c)
	if len(d.frames) == 0 do return
	b := d.frames[clamp(c.frame, 0, len(d.frames) - 1)].box
	ox, oy := c.x - dw / 2, c.y - dh / 2
	c.hit = {
		x87_scale_trunc(int(b[0]), c.scale) + ox, x87_scale_trunc(int(b[1]), c.scale) + oy,
		x87_scale_trunc(int(b[2]), c.scale) + ox, x87_scale_trunc(int(b[3]), c.scale) + oy,
	}
}

rects_intersect :: proc "contextless" (a, b: Rect) -> bool {
	return a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom
}

// Marks which of a's 3x3 hit-rect cells overlap b (0x407d00). Cells map to
// directions 7 0 1 / 6 8 2 / 5 4 3. Returns whether anything was marked.
collide_mark :: proc(a, b: ^Creature) -> bool {
	CELL_DIR := [9]int{7, 0, 1, 6, 8, 2, 5, 4, 3}
	box := a.hit
	if a.kind == .Spider && b.kind == .Object {
		// port: against objects only the body counts (the middle 60 % of the
		// frame box), so the legs may reach over a rock
		w, h := box.right - box.left, box.bottom - box.top
		box = {box.left + w / 5, box.top + h / 5, box.right - w / 5, box.bottom - h / 5}
		if !rects_intersect(box, b.hit) do return false
	}
	cw, ch := (box.right - box.left) / 3, (box.bottom - box.top) / 3
	minw, minh: int
	switch {
	case a.kind == .Spider && b.kind == .Object:
		// a third of a cell, as the original only allows while walking to a
		// goal (port: always, so narrow gaps are passable)
		minw, minh = cw / 3, ch / 3
	case b.kind == .Cricket:
		minw, minh = cw / 20, ch / 20
	case:
		minw, minh = cw / 8, ch / 8
	}
	hit := false
	for row in 0 ..< 3 {
		for col in 0 ..< 3 {
			cell := Rect{box.left + col * cw, box.top + row * ch, 0, 0}
			cell.right, cell.bottom = cell.left + cw, cell.top + ch
			ix := min(cell.right, b.hit.right) - max(cell.left, b.hit.left)
			iy := min(cell.bottom, b.hit.bottom) - max(cell.top, b.hit.top)
			if ix <= 0 || iy <= 0 || ix < minw || iy < minh do continue
			d := CELL_DIR[row * 3 + col]
			is_target := a.goal.active && int(a.goal.type) == int(b.kind) && a.goal.target == b.id
			if is_target {
				// the creature being chased never blocks the chaser
				a.blocks[d] = {active = false, kind = int(b.kind), id = b.id}
			} else {
				a.blocks[d] = {active = true, kind = int(b.kind), id = b.id}
				hit = true
			}
			if b.kind == .Cricket && a.kind == .Spider do return hit
		}
	}
	return hit
}

// What happens when two creatures touch (0x403770): the spider lunges at
// crickets, crickets may flee from the spider.
collide_respond :: proc(a, b: ^Creature) -> bool {
	if a.carried != 0 || b.carried != 0 do return false
	s := -1
	for blk, d in a.blocks do if blk.active && blk.id == b.id && blk.kind == int(b.kind) {s = d; break}
	if s < 0 do return false

	if a.kind == .Spider {
		if a.hide != 0 || game.life.dead do return false
		if b.kind == .Object && b.id == BOWL {
			f := a.blocks[a.dir]
			if f.active && f.kind == int(Kind.Object) && f.id == BOWL do spider_thirst(a)
			return false
		}
		if b.kind == .Cricket && !a.eating {
			if a.goal.active do clear_goal(a)
			if s == 8 do s = a.dir
			// re-queued on every tick of contact, as in the original
			already := a.queue_len > 0 && a.queue[0].seq == game.seq.catch_ && a.queue[0].dir == s
			enqueue_anim(a, game.seq.catch_, s, 1, flush = true, run = true)
			a.target_id = b.id
			if !already && a.waiting_for != b.id do debug_logf("%s touched cricket %d: catch facing %d", a.name, b.id, s)
			return true
		}
	} else if a.kind == .Cricket && b.kind == .Spider && rand_n(10) < 5 && a.queue_len == 0 {
		dir := a.dir
		if rand_n(10) >= 5 do dir = a.dir - rand_n(3) - 2
		if dir < 0 do dir += 7 // sic: the original wraps by 7
		ids := &game.cseq
		if rand_n(10) < 5 {
			enqueue_anim(a, ids.jump, dir, rand_n(3) + 6, flush = true, run = true)
		} else {
			// sic: the original queues the spider's WALK id (1), which is also
			// the cricket's WALK
			enqueue_anim(a, game.seq.walk, dir, rand_n(3) + 6, flush = true, run = true)
		}
	}
	return false
}

// --- goals: walk to a target, then play a sequence ---------------------

// move_to_then_anim (0x40bdd0). x/y < 0 keep the current draw position;
// target is a creature id for chase goals.
move_to :: proc(c: ^Creature, type: Goal_Type, x, y, dir, seq, timeout_s: int, target := -1) {
	if c.hide != 0 || c.y < FLOOR_TOP do return
	if c.goal.active && c.goal.seq == game.seq.log_hide do return
	w, h := x87_scale_trunc(c.anim.w, c.scale), x87_scale_trunc(c.anim.h, c.scale)
	c.goal = {
		active    = true,
		type      = type,
		x         = x >= 0 ? x : c.x - w / 2,
		y         = y >= 0 ? y : c.y - h / 2,
		seq       = seq,
		dir       = dir,
		timeout_s = timeout_s,
		start_ms  = now_ms,
		target    = target,
	}
	if seq != game.seq.kill do stop_current(c)
	debug_logf("%s goal: %v to (%d, %d) then %s", c.name, type, c.goal.x, c.goal.y, seq_name(c, seq))
}

clear_goal :: proc(c: ^Creature) {
	c.goal = {}
}

// Arrival test, run every frame while a goal is active (0x40c6a0).
goal_check :: proc(c: ^Creature) -> bool {
	g := &c.goal
	// port: time out while detouring too (the original only checks after
	// the detour test, so a detour that gets nowhere never ends)
	if g.detouring && g.timeout_s != 0 && now_ms > g.start_ms + u32(g.timeout_s) * 1000 {
		debug_logf("%s goal timed out while detouring", c.name)
		clear_goal(c)
		return false
	}
	if g.detouring do return false
	run := false
	// follow the target (0x40bf10)
	if g.type == .Creature_B && g.target >= 0 {
		cr := &game.crickets[g.target]
		g.x, g.y = cr.x, cr.y
	}
	if g.type == .Creature_A && g.target >= 0 {
		t := &game.objects[g.target]
		if !t.active || t.in_box {
			// port: it's been taken away
			debug_logf("%s: %s is gone, giving up", c.name, t.name)
			clear_goal(c)
			return false
		}
		g.x, g.y = t.x, t.y
		if g.target == BELL {
			// wait in front of or behind the bell
			if t.y < c.y {
				g.dir = 0
				g.y = t.hit.bottom - (t.hit.bottom - t.y) / 5
			} else {
				g.y = t.hit.top - 20
				g.dir = 4
				g.x += (t.hit.right - t.hit.left) / 4
			}
		}
	}
	g.x = clamp(g.x, WALL_MARGIN, TANK_W - WALL_MARGIN)
	if g.timeout_s != 0 && now_ms > g.start_ms + u32(g.timeout_s) * 1000 {
		debug_logf("%s goal timed out", c.name)
		clear_goal(c)
		return false
	}

	tx, ty := c.sx * 9, c.sy * 7
	gx := g.type == .Y_Band ? c.x : g.x
	gy := g.type == .X_Band ? c.y : g.y
	arrived := false
	#partial switch g.type {
	case .Creature_B:
		// arrives when collision marks the chased cricket in a direction slot
		cr := &game.crickets[g.target]
		if !cr.active || cr.in_box {
			arrived = true
			g.seq = -1
		} else {
			for b, d in c.blocks[:8] {
				if b.kind == int(Kind.Cricket) && b.id == g.target {
					g.dir = d
					run = true
					arrived = true
					break
				}
			}
		}
	case .Creature_A:
		// objects: touching it, except the bell which has a waiting spot
		if g.target == BELL {
			if abs(c.x - gx) <= tx / 2 && abs(c.y - gy) <= ty / 2 {
				arrived = true
				c.blocks[g.dir] = {active = true, kind = int(Kind.Object), id = BELL, ticks = 80}
			}
		} else {
			for b in c.blocks[:8] do if b.kind == int(Kind.Object) && b.id == g.target {arrived = true; break}
		}
	case .Point, .Cursor:
		arrived = abs(c.x - gx) <= tx / 2 && abs(c.y - gy) <= ty / 2
	case .Y_Band:
		arrived = (c.y >= gy && c.y <= gy + ty) || (c.y + ty >= gy && c.y + ty <= gy + ty)
	case .X_Band:
		arrived = (c.x >= gx && c.x <= gx + tx) || (c.x + tx >= gx && c.x + tx <= gx + tx)
	}

	if !arrived {
		near := (c.x >= gx && c.x <= gx + tx) || (c.y >= gy && c.y <= gy + ty)
		if near && c.turn_target < 0 do stop_current(c) // re-steer sooner
		return false
	}
	debug_logf("%s arrived at goal", c.name)
	if g.seq >= 0 do enqueue_anim(c, g.seq, g.dir, 1, flush = true, run = run)
	clear_goal(c)
	return true
}

// Chooses the next walking leg towards the goal, detouring round blocked
// directions (0x40c120). Runs when a sequence ends.
goal_step :: proc(c: ^Creature) {
	if goal_check(c) do return
	g := &c.goal
	if !g.active do return

	// port: head for the next point of a planned route rather than straight
	// at the target (the bands and detours work as before)
	tx, ty := g.x, g.y
	routed := false
	if c.kind == .Spider && !g.detouring && g.type != .X_Band {
		if g.type == .Y_Band {
			// the glass: the nearest reachable spot at that height
			band := c.sy * 7
			if wx, wy, _, _, ok := plan_route_band(c, g.y - band / 2, g.y + band, c.x, g.y); ok {
				tx, ty, routed = wx, wy, true
			}
		} else if wx, wy, _, _, ok := plan_route(c, g.x, g.y); ok {
			tx, ty, routed = wx, wy, true
		}
	}
	bands := g.type == .Y_Band && !routed
	right := !bands && c.x < tx - 4 * c.sx
	left := !bands && c.x > tx + 4 * c.sx
	down := g.type != .X_Band && c.y < ty - 3 * c.sy
	up := g.type != .X_Band && c.y > ty + 3 * c.sy
	if bands && !g.detouring &&
	   ((up && c.blocks[0].active) || (down && c.blocks[4].active)) {
		if c.x < TANK_W / 2 do right = true
		else do left = true
	}

	dir := -1
	switch {
	case up && left:    dir = 7
	case up && right:   dir = 1
	case down && left:  dir = 5
	case down && right: dir = 3
	case up:            dir = 0
	case down:          dir = 4
	case left:          dir = 6
	case right:         dir = 2
	}
	steps := 4

	enqueue :: proc(c: ^Creature, dir, steps: int) {
		run := c.goal.type == .Creature_B || (c.goal.type == .Cursor && rand_n(10) < 5)
		enqueue_anim(c, game.seq.walk, dir, steps, run = run)
	}
	if dir < 0 {
		enqueue(c, dir, steps)
		return
	}

	if routed && dir_blocked(c, dir) && !g.detouring {
		// port: on a planned route, edge round the corner (the neighbouring
		// directions) before falling back to the original's detour
		for off in ([?]int{1, 7, 2, 6}) {
			d := (dir + off) % 8
			if !dir_blocked(c, d) && !c.blocks[d].active {
				enqueue(c, d, 3)
				return
			}
		}
	}
	if !dir_blocked(c, dir) {
		if !g.detouring {
			enqueue(c, dir, routed ? 4 : 6)
			return
		}
	} else if !g.detouring {
		g.cand = {-1, -1, -1}
	}

	if g.detouring {
		lo, mid, hi := g.cand[0], g.cand[1], g.cand[2]
		moved := g.detour_x != c.x || g.detour_y != c.y
		resolved := false
		if !c.blocks[lo].active {
			if !c.blocks[mid].active && !c.blocks[hi].active && moved {
				// the way round is clear: resume the original heading
				g.detouring = false
				g.cand = {-1, -1, -1}
				dir = g.resume_dir
				resolved = true
			}
		} else if c.blocks[mid].active && c.blocks[hi].active {
			enqueue(c, g.walk_dir, 6)
			return
		}
		if !resolved {
			if !moved {
				// port: that way got nowhere either: try the next one round
				// (the original repeats it)
				g.walk_dir = (g.walk_dir + (g.detour_cw ? 1 : 7)) % 8
				enqueue(c, g.walk_dir, 6)
				return
			}
			if !c.blocks[lo].active {
				dir = lo
			} else {
				dir = c.blocks[mid].active ? hi : mid
			}
			g.detouring = false
		}
	}

	if c.blocks[dir].active || c.blocks[dir].kind == BLOCK_WALL {
		if !g.detouring {
			// start a detour: try the neighbouring directions in turn
			g.detouring = true
			g.cand = {(dir + 7) % 8, dir, (dir + 1) % 8}
			g.detour_x, g.detour_y = c.x, c.y
			g.resume_dir = (dir + 1) % 8
			b := &c.blocks
			cw := (!left || b[6].active || b[7].active || b[5].active) &&
				(!down || b[4].active || b[5].active || b[3].active)
			d := dir
			for _ in 0 ..< 8 {
				d = (d + (cw ? 1 : 7)) % 8
				if !c.blocks[d].active do break
			}
			g.walk_dir = d
			g.detour_cw = cw
			debug_logf("%s detour: %d blocked, going %d", c.name, dir, d)
			enqueue(c, d, steps)
			return
		}
		if c.blocks[dir].kind == BLOCK_WALL {
			// already detouring and facing a wall: back off sideways, give up
			enqueue_anim(c, game.seq.walk, (dir + 7) % 8, 10)
			clear_goal(c)
			enqueue(c, dir, 10)
			return
		}
	}
	if c.blocks[dir].active do g.detouring = false
	enqueue(c, dir, steps)
}

// Decision log for the debug overlay.
debug_logf :: proc(format: string, args: ..any) {
	if !debug_enabled do return
	debug_log(fmt.tprintf("%.1fs  %s", f64(now_ms) / 1000, fmt.tprintf(format, ..args)))
}
