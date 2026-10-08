package vc

// The floor layer: a copy of the tank background with decals drawn into
// it once — footprints, web pieces and the big corner webs — like the
// original's 1200x480 surface (0x451760). It is rebuilt from the lists on
// load and when debris is cleared; until then expired decals stay drawn,
// as in the original.

FOOTPRINT_COUNT :: 500 // ring (0x44dfa0)
WEB_PIECES      :: 100 // ring (0x454bc0)
WEB_PIECE_LIFE  :: 2880 // minutes (0x42a050)

Footprint :: struct {
	x, y:        int, // canvas top-left, like the spider's draw position
	dir, kind:   int, // kind 0 = while turning, 1 = while walking (sequence index)
	scale, foot: int,
}

Web_Piece :: struct {
	x, y:       int,
	dir, frame: int,
	scale:      int, // 0 = unused
	age:        int, // minutes
	rect:       Rect, // crickets touching it get stuck
}

Corner_Web :: struct {
	active:     bool,
	stage, age: int, // stage grows every day (3 days for the big one)
}

// bitmap, frames, position (0x408c70)
CORNER_WEBS := [4]struct {
	bitmap, frames, x, y: int,
} {{4000, 4, 56, 15}, {4001, 4, 373, 0}, {4002, 4, 692, 0}, {4003, 1, 856, 0}}

floor_buf: [TANK_W * VIEW_H]u8

// Draws an animation frame into the floor at (x, y) top-left, scaled to
// scale% within its canvas (0x416e40 onto 0x451760).
floor_decal :: proc(a: ^Anim, seq, dir, frame, x, y, scale: int) {
	if seq < 0 || seq >= len(a.seqs) || dir < 0 || dir > 7 do return
	s := &a.seqs[seq]
	d := &s.dirs[dir]
	if frame < 0 || frame >= len(d.frames) do return
	buf := frame_buf[:a.w * a.h]
	if !frame_decode(a, s, d.frames[frame], buf) do return
	dw, dh := x87_scale_trunc(a.w, scale), x87_scale_trunc(a.h, scale)
	if dw <= 0 || dh <= 0 do return
	ox, oy := x + (a.w - dw) / 2, y + (a.h - dh) / 2
	for j in 0 ..< dh {
		fy := oy + j
		if fy < 0 || fy >= VIEW_H do continue
		row := (j * a.h / dh) * a.w
		for i in 0 ..< dw {
			fx := ox + i
			if fx < 0 || fx >= TANK_W do continue
			p := buf[row + i * a.w / dw]
			if p != a.key do floor_buf[fy * TANK_W + fx] = p
		}
	}
}

floor_rebuild :: proc() {
	copy(floor_buf[:], assets.tank.pixels[:TANK_W * VIEW_H])
	for w, i in game.corner_webs {
		if !w.active do continue
		b := &assets.corner_webs[i]
		def := CORNER_WEBS[i]
		if b.w == 0 do continue
		fh := b.h / def.frames
		stage := min(w.stage, def.frames - 1)
		for j in 0 ..< fh {
			fy := def.y + j
			if fy >= VIEW_H do break
			for k in 0 ..< b.w {
				fx := def.x + k
				if fx < TANK_W do floor_buf[fy * TANK_W + fx] = b.pixels[(stage * fh + j) * b.w + k]
			}
		}
	}
	for f in game.footprints do if f.scale > 0 {
		floor_decal(&assets.footprints, f.kind, f.dir, f.foot, f.x, f.y, f.scale)
	}
	for w in game.webs do if w.scale > 0 {
		floor_decal(&assets.web, 0, w.dir, w.frame, w.x, w.y, w.scale)
	}
}

// A footprint at the spider's feet (0x408430).
add_footprint :: proc(s: ^Creature, dx, dy, foot: int) {
	dw, dh := x87_scale_trunc(s.anim.w, s.scale), x87_scale_trunc(s.anim.h, s.scale)
	_ = dw
	_ = dh
	f := Footprint {
		x     = s.x - s.anim.w / 2 + dx,
		y     = s.y - s.anim.h / 2 + dy,
		dir   = s.dir,
		kind  = s.seq == game.seq.circle ? 0 : 1,
		scale = s.scale,
		foot  = foot,
	}
	game.footprints[game.footprint_next] = f
	game.footprint_next = (game.footprint_next + 1) % FOOTPRINT_COUNT
	floor_decal(&assets.footprints, f.kind, f.dir, f.foot, f.x, f.y, f.scale)
}

// A piece of web behind the spider (0x408880).
add_web_piece :: proc(s: ^Creature, dir, frame: int) {
	if s.y < FLOOR_TOP do return
	a := &assets.web
	w := Web_Piece {
		x     = s.x - s.anim.w / 2 + rand_n(4) - 2,
		dir   = dir,
		frame = frame,
		scale = s.scale,
	}
	w.y = s.y - s.anim.h / 2 + 19 + rand_n(2)
	d := &a.seqs[0].dirs[dir]
	if frame < len(d.frames) {
		b := d.frames[frame].box
		dw, dh := x87_scale_trunc(a.w, w.scale), x87_scale_trunc(a.h, w.scale)
		ox, oy := w.x + (a.w - dw) / 2, w.y + (a.h - dh) / 2
		w.rect = {
			x87_scale_trunc(int(b[0]), w.scale) + ox, x87_scale_trunc(int(b[1]), w.scale) + oy,
			x87_scale_trunc(int(b[2]), w.scale) + ox, x87_scale_trunc(int(b[3]), w.scale) + oy,
		}
		if dir == 2 || dir == 6 {
			w.rect.right -= (w.rect.right - w.rect.left) / 8
		} else if dir == 4 {
			h := w.rect.bottom - w.rect.top
			w.rect.bottom -= h / 8
			w.rect.top -= (w.rect.bottom - w.rect.top) / 8
		}
	}
	game.webs[game.web_next] = w
	game.web_next = (game.web_next + 1) % WEB_PIECES
	floor_decal(a, 0, dir, frame, w.x, w.y, w.scale)
}

// WEB_LAYING frame 3: which piece to lay depends on the facing and on
// which play this is (creature_post_frame, web branch).
spider_lay_web :: proc(s: ^Creature) {
	wdir := s.dir + 4
	if wdir > 7 do wdir = s.dir - 4
	frame := game.web_frame
	lay := false
	if s.step > 0 {
		if s.plays == 2 || s.plays == 4 {
			switch wdir {
			case 4, 6: frame = 1
			case 0, 2: frame = 0
			}
			lay = true
		} else if s.plays == 1 || s.plays == 3 {
			switch wdir {
			case 4, 6: frame = 0
			case 0, 2: frame = 1
			}
			lay = true
		}
	}
	game.web_frame = frame
	if lay do add_web_piece(s, wdir, frame)
}

// A big corner web appears (0x408b70); the fourth only once the three
// corners are taken.
add_corner_web :: proc(starting: bool) {
	webs := &game.corner_webs
	if starting {
		for w in webs[:4] do if w.active && w.stage == 0 && w.age < 90 do return
	}
	tries := 0
	slot := (4 - rand()) / 0x7FFF // 0
	for webs[slot].active {
		slot = (slot + 1) % 3
		tries += 1
		if tries > 2 do break
	}
	if tries <= 2 {
		webs[slot] = {active = true}
		return
	}
	n := 0
	for w in webs[:3] do if w.active do n += 1
	if n > 2 && !webs[3].active do webs[3] = {active = true}
}

// Minutes passing for the floor decals (0x404490, 0x404580).
age_webs :: proc(minutes: int) {
	for &w, i in game.corner_webs {
		if !w.active do continue
		w.age += minutes
		stages, per := 4, 1440
		if i == 3 do stages, per = 1, 4320
		for w.age >= per {
			w.stage += 1
			if w.stage < stages {
				w.age -= per
			} else {
				w = {}
				break
			}
		}
	}
	for &p in game.webs {
		if p.scale == 0 do continue
		p.age += minutes
		if p.age >= WEB_PIECE_LIFE do p = {}
	}
}

// Crickets walking into a web get stuck (creature_tick, cricket branch).
cricket_web_check :: proc(c: ^Creature) {
	if c.web_stuck || c.carried != 0 || c.in_box do return
	if c.seq == game.cseq.jump && (c.moving_x || c.moving_y) do return
	for &w in game.webs {
		if w.scale == 0 || !rects_intersect(c.hit, w.rect) do continue
		ix := min(c.hit.right, w.rect.right) - max(c.hit.left, w.rect.left)
		iy := min(c.hit.bottom, w.rect.bottom) - max(c.hit.top, w.rect.top)
		if iy >= (c.hit.bottom - c.hit.top) / 2 && ix >= (c.hit.right - c.hit.left) / 2 {
			enqueue_anim(c, game.cseq.web_stuck, -1, 4, flush = true)
			c.moving_x, c.moving_y = false, false
			c.web_stuck = true
			debug_logf("cricket %d stuck in a web", c.id)
			spider_sees_cricket(&game.spider, c)
			return
		}
		if rand_n(10) < 7 && c.queue_len == 0 {
			d := c.dir - 4
			if d < 0 do d = 7 - d // sic: out of range, so it keeps its facing
			enqueue_anim(c, game.seq.walk, d, rand_n(3) + 3, flush = true)
			return
		}
	}
}

clear_debris :: proc() {
	game.remains = {}
	game.footprints = {}
	game.webs = {}
	for &c in game.crickets {
		if c.web_stuck do stop_current(&c)
		c.web_stuck = false
	}
	floor_rebuild()
}
