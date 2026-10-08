package vc

// Creature animation and movement, following VC.EXE (docs/BEHAVIOR.md).
// Original addresses and struct offsets are noted for cross-reference.

QUEUE_LEN    :: 16
TANK_W       :: 1200
VIEW_W       :: 640
VIEW_H       :: 480
FLOOR_TOP    :: 170 // 0xaa: tank floor starts at this y, above is the back wall
WALL_MARGIN  :: 130 // 0x82: closest a creature's centre gets to the side walls
BUMP_TICKS   :: 5

Queued :: struct {
	seq, dir, plays: int,
	run:             bool,
}

Creature :: struct {
	anim:               ^Anim,
	x, y:               int,  // centre in tank coordinates (+0xa6, +0xa8)
	dir:                int,  // facing 0..7: 0 = up, clockwise (+0x9a)
	seq, prev_seq:      int,  // (+0x98, +0xbc)
	frame, step:        int,  // (+0xb2, +0xb4)
	plays:              int,  // remaining plays of seq (+0xba)
	hold:               int,  // frame hold countdown, -1 = none (+0xf6)
	moving_x, moving_y: bool, // (+0xc4, +0xc6)
	run:                bool, // double speed while walking (+0x152)
	turn_target:        int,  // facing to reach before the next queued seq, -1 = none
	turn_dir:           int,  // +1 clockwise, -1 counter-clockwise, 0 = not turning
	base_sx, base_sy:   int,  // (+0x9e, +0xa0)
	size:               int,  // growth factor (+0x1e6), 40 for a new spider
	scale:              int,  // percent (+0x9c)
	sx, sy:             int,  // (+0xa2, +0xa4)
	bumped:             [8]int, // ticks left on "just hit a wall in this direction"
	queue:              [QUEUE_LEN]Queued,
	queue_len:          int,
	last_played:        []u32, // now_ms when each seq last started (+0x174 + seq*4)
	idle:               proc(c: ^Creature), // picks a sequence when the queue is empty
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
	creature_update_position(c)
}

creature_dir :: proc "contextless" (c: ^Creature) -> ^Dir {
	return &c.anim.seqs[c.seq].dirs[c.dir]
}

seq_has_frames :: proc "contextless" (c: ^Creature, seq, dir: int) -> bool {
	return seq >= 0 && len(c.anim.seqs[seq].dirs[dir].frames) > 0
}

// enqueue_anim at 0x414700. dir 8 (or -1) keeps the current facing.
enqueue_anim :: proc(c: ^Creature, seq, dir, plays: int, run := false) {
	if seq < 0 || c.queue_len >= QUEUE_LEN do return
	c.queue[c.queue_len] = {seq, dir, plays, run}
	c.queue_len += 1
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
	c.hold = -1
	c.last_played[c.seq] = now_ms
}

// One CIRCLE play rotates the creature by one direction (0x4081c0):
// clockwise plays forward then faces dir+1, counter-clockwise first faces
// dir-1 and plays backward.
start_turn_step :: proc(c: ^Creature, cw: bool) {
	circle := game.seq.circle
	c.prev_seq = c.seq
	c.seq = circle
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

	if c.turn_target >= 0 && c.turn_target != c.dir {
		// turn the shorter way round, one CIRCLE play per step (0x408170)
		cw := (c.turn_target - c.dir + 8) % 8 <= 4
		start_turn_step(c, cw)
		return
	}
	c.turn_target = -1

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
		if !seq_has_frames(c, c.seq, c.dir) do c.seq = game.seq.lurk
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
	for &b in c.bumped do if b > 0 do b -= 1

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
		if c.frame < 0 || c.frame >= len(d.frames) {
			c.plays -= 1
			if c.plays > 0 {
				c.frame = c.step < 0 ? len(d.frames) - 1 : 0
			} else {
				next_sequence(c)
			}
		}
	}

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

// Clamps to the tank and derives depth scale and speeds (0x406df0).
creature_update_position :: proc(c: ^Creature) {
	if c.x < WALL_MARGIN {
		c.x = WALL_MARGIN
		c.bumped[5], c.bumped[6], c.bumped[7] = BUMP_TICKS, BUMP_TICKS, BUMP_TICKS
	}
	if c.x > TANK_W - WALL_MARGIN {
		c.x = TANK_W - WALL_MARGIN
		c.bumped[1], c.bumped[2], c.bumped[3] = BUMP_TICKS, BUMP_TICKS, BUMP_TICKS
	}
	if top := FLOOR_TOP + c.anim.h / 3; c.y < top {
		c.y = top
		c.bumped[7], c.bumped[0], c.bumped[1] = BUMP_TICKS, BUMP_TICKS, BUMP_TICKS
	}
	if c.y + c.anim.h / 2 >= VIEW_H {
		c.y = VIEW_H - c.anim.h / 2
		c.bumped[3], c.bumped[4], c.bumped[5] = BUMP_TICKS, BUMP_TICKS, BUMP_TICKS
	}

	// scale% = min(100, y/480 * size + 35), truncated (x87 + _ftol)
	v := f64(c.y) / f64(VIEW_H) * f64(c.size) + 35
	c.scale = int(min(v, 100))
	// speeds shrink with distance: base / (100 / scale), truncated
	c.sx = int(f64(c.base_sx) / (100 / f64(c.scale)))
	c.sy = int(f64(c.base_sy) / (100 / f64(c.scale)))
}
