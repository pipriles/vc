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
	timeout_s:            int, // abandon after this many seconds (+0x60), 0 = never
	start_ms:             u32,
	detouring:            bool, // walking round an obstacle (+0x6e)
	cand:                 [3]int, // directions around the blocked one (+0x78..)
	detour_x, detour_y:   int, // where the detour started (+0x74, +0x76)
	resume_dir, walk_dir: int, // (+0x72, +0x70)
}

Creature :: struct {
	anim:               ^Anim,
	name:               string,
	x, y:               int,  // centre in tank coordinates (+0xa6, +0xa8)
	dir:                int,  // facing 0..7: 0 = up, clockwise (+0x9a)
	seq, prev_seq:      int,  // (+0x98, +0xbc)
	frame, step:        int,  // (+0xb2, +0xb4)
	plays:              int,  // remaining plays of seq (+0xba)
	hold:               int,  // frame hold countdown, -1 = none (+0xf6)
	moving_x, moving_y: bool, // (+0xc4, +0xc6)
	no_clamp:           bool, // floor clamp off: hiding behind the rock (+0xc2)
	run:                bool, // double speed while walking (+0x152)
	turn_target:        int,  // facing to reach before the next queued seq, -1 = none
	turn_dir:           int,  // +1 clockwise, -1 counter-clockwise, 0 = not turning
	base_sx, base_sy:   int,  // (+0x9e, +0xa0)
	size:               int,  // growth factor (+0x1e6), 40 for a new spider
	scale:              int,  // percent (+0x9c)
	sx, sy:             int,  // (+0xa2, +0xa4)
	blocks:             [9]Block,
	queue:              [QUEUE_LEN]Queued,
	queue_len:          int,
	goal:               Goal,
	hide:               int, // hiding state (+0x48): 0 out, 1 hidden, 2..3 coming out
	last_played:        []u32, // now_ms when each seq last finished (+0x174 + seq*4)
	idle:               proc(c: ^Creature), // picks a sequence when the queue is empty
	finished:           proc(c: ^Creature), // sequence-finished hook (0x403520 for the spider)
	can_play:           proc(c: ^Creature, seq: int) -> bool, // validity on pop (0x402f40)
}

// creature_init at 0x406680: (c, x, y, base_sx, base_sy, ...)
creature_init :: proc(c: ^Creature, a: ^Anim, x, y, base_sx, base_sy, size: int) {
	c^ = {}
	c.anim = a
	c.x, c.y = x, y
	c.base_sx, c.base_sy = base_sx, base_sy
	c.size = size
	c.dir = 4
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
	return seq >= 0 && len(c.anim.seqs[seq].dirs[dir].frames) > 0
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
	if flush && c.turn_target < 0 {
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
}

// Starts c.seq in the current direction (0x404830).
start_sequence :: proc(c: ^Creature) {
	d := creature_dir(c)
	n := len(d.frames)
	c.frame = c.step < 0 ? n - 1 : 0
	s := &c.anim.seqs[c.seq]
	if c.plays < 1 && s.rand_repeat do c.plays = rand_n(s.max_repeat) + 1
	if c.plays < 1 do c.plays = 1
	c.moving_x = d.move_x && rand_n(10) < 6
	c.moving_y = d.move_y
	c.no_clamp = d.no_clamp
	c.hold = -1
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
	c.last_played[c.seq] = now_ms
	if c.finished != nil do c.finished(c)

	if c.turn_target >= 0 && c.turn_target != c.dir {
		// turn the shorter way round, one CIRCLE play per step (0x408170)
		cw := (c.turn_target - c.dir + 8) % 8 <= 4
		start_turn_step(c, cw)
		return
	}
	c.turn_target = -1

	if c.goal.active do goal_step(c)

	if c.queue_len > 0 {
		// pop (0x414840)
		q := c.queue[0]
		dir := q.dir
		if dir < 0 || dir > 7 do dir = c.dir
		if dir != c.dir {
			c.turn_target = dir
			c.run = q.run
			cw := (dir - c.dir + 8) % 8 <= 4
			start_turn_step(c, cw)
			return
		}
		copy(c.queue[:], c.queue[1:c.queue_len])
		c.queue_len -= 1
		c.prev_seq = c.seq
		c.seq = q.seq
		c.plays = q.plays
		c.run = q.run
		if !seq_has_frames(c, c.seq, c.dir) || (c.can_play != nil && !c.can_play(c, c.seq)) {
			debug_logf("%s can't play %s now, lurking instead", c.name, seq_name(c, c.seq))
			c.seq = game.seq.lurk
			c.plays = 1
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
	d := creature_dir(c)
	if len(d.frames) == 0 {
		next_sequence(c)
		d = creature_dir(c)
	}
	f := d.frames[c.frame]

	if c.hold < 0 && f.hold_flag != 0 {
		c.hold = f.hold < 0 ? rand() * int(f.hold) / 0x7FFF : int(f.hold)
	}
	c.hold -= 1
	if c.hold < 0 {
		c.hold = -1
		c.frame += c.step
		ended := c.frame < 0 || c.frame >= len(d.frames)
		if c.goal.active && goal_check(c) do ended, c.plays = true, 1 // arrived: cut short
		if ended {
			c.plays -= 1
			if c.plays > 0 {
				c.frame = c.step < 0 ? len(d.frames) - 1 : 0
			} else {
				next_sequence(c)
			}
		}
	}
	creature_post_frame(c)

	// movement for the frame now showing
	d = creature_dir(c)
	f = d.frames[clamp(c.frame, 0, len(d.frames) - 1)]
	dx, dy := int(f.dx), int(f.dy)
	if c.moving_x || c.moving_y || dx != 0 || dy != 0 {
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

// Clamps to the tank and derives depth scale and speeds (0x406df0).
creature_update_position :: proc(c: ^Creature) {
	for &b in c.blocks {
		b.ticks -= 1
		if b.ticks < 1 do b = {}
	}

	if c.no_clamp {
		c.y = max(c.y, HIDE_Y)
		c.x = clamp(c.x, WALL_MARGIN, TANK_W - WALL_MARGIN)
	} else {
		if c.x < WALL_MARGIN {
			c.x = WALL_MARGIN
			for d in ([?]int{5, 6, 7}) do c.blocks[d].kind = BLOCK_WALL
		}
		if c.x > TANK_W - WALL_MARGIN {
			c.x = TANK_W - WALL_MARGIN
			for d in ([?]int{1, 2, 3}) do c.blocks[d].kind = BLOCK_WALL
		}
		if c.y < FLOOR_TOP {
			c.y = FLOOR_TOP
			for d in ([?]int{7, 0, 1}) do c.blocks[d].kind = BLOCK_WALL
		}
		// bottom: a third of the drawn height may hang below the view
		if dh := x87_scale_trunc(c.anim.h, c.scale); c.y + dh / 3 >= VIEW_H {
			c.y = VIEW_H - dh / 3
			for d in ([?]int{3, 4, 5}) do c.blocks[d].kind = BLOCK_WALL
		}
	}

	// scale% = min(100, y/480 * size + 35), truncated (x87 + _ftol)
	v := f64(c.y) / f64(VIEW_H) * f64(c.size) + 35
	c.scale = int(min(v, 100))
	// speeds shrink with distance: base / (100 / scale), truncated
	c.sx = x87_scale_trunc(c.base_sx, c.scale)
	c.sy = x87_scale_trunc(c.base_sy, c.scale)
}

// --- goals: walk to a target, then play a sequence ---------------------

// move_to_then_anim (0x40bdd0). x/y < 0 keep the current draw position.
move_to :: proc(c: ^Creature, type: Goal_Type, x, y, dir, seq, timeout_s: int) {
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
	if g.detouring do return false
	g.x = clamp(g.x, WALL_MARGIN, TANK_W - WALL_MARGIN) // (0x40bf10)
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
	if g.seq >= 0 do enqueue_anim(c, g.seq, g.dir, 1, flush = true)
	clear_goal(c)
	return true
}

// Chooses the next walking leg towards the goal, detouring round blocked
// directions (0x40c120). Runs when a sequence ends.
goal_step :: proc(c: ^Creature) {
	if goal_check(c) do return
	g := &c.goal
	if !g.active do return

	right := g.type != .Y_Band && c.x < g.x - 4 * c.sx
	left := g.type != .Y_Band && c.x > g.x + 4 * c.sx
	down := g.type != .X_Band && c.y < g.y - 3 * c.sy
	up := g.type != .X_Band && c.y > g.y + 3 * c.sy
	if g.type == .Y_Band && !g.detouring &&
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

	if !dir_blocked(c, dir) {
		if !g.detouring {
			enqueue(c, dir, 6)
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
