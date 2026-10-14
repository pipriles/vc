package vc

// Tank objects (kind 1): water bowl, bell, rocks, cacti, yucca, fountain,
// windpump. Table and behaviour from VC.EXE setup (0x41a790), the object
// part of the main update (0x40ca70) and drinking (0x403e90).

OBJECT_COUNT :: 10
// Port: every object may be in the tank at once. The original's panel
// only gave one out while fewer than 6 were in (3 unregistered; 0x40e360,
// 0x40e930), most likely to keep room for the spider on 1999 hardware;
// the port's route planning and unsticking cope with a crowded tank.
MAX_OBJECTS_IN_TANK :: OBJECT_COUNT // the 11th table row is the shed skin (kind 6), handled with moulting
BOWL         :: 0  // DAT_00455846: the drinking object
BELL         :: 1  // DAT_00454a38: where a hungry spider waits
CACTUS1      :: 4  // DAT_00451ef8: wilted (frame 1) while the spider is dead
CACTUS2      :: 5  // DAT_00451ed8: likewise
YUCCA        :: 7  // DAT_0044def4: grows one frame per day
FOUNTAIN     :: 8  // running water while in the tank (loop 465)
WINDPUMP     :: 9  // DAT_00451f2a: creaks now and then (419)

Anim_Mode :: enum {
	None      = 0,
	Loop      = 1, // windpump, fountain
	Ping_Pong = 2,
	Swing     = 3, // bell: a number of swings, then rest on a frame
}

Object_Def :: struct {
	name:        string,
	bitmap:      int, // VCG resource id
	frames:      int, // stacked vertically
	depth_class: int, // floor clamp: 0 -> h/3, 1 -> h/6, 2 -> h/12 (+0x154)
	in_tank:     bool, // placed at startup (+0x94)
	mode:        Anim_Mode, // (+0x86), animated if != None (+0x84)
	ticks:       int, // per frame (+0x88)
	step:        int, // (+0x8c)
	rest:        int, // frame to rest on after swinging (+0x8e)
}

// Rows recovered from the stack table built at 0x41a7b0.
OBJECT_DEFS := [OBJECT_COUNT]Object_Def {
	{"Waterbowl",      3000,  5, 0, true,  .None,  0, 0, 0},
	{"Bell",           3008, 11, 0, false, .Swing, 2, 1, 4},
	{"Rock #1",        3002,  1, 0, false, .None,  0, 0, 0},
	{"Rock #2",        3003,  1, 0, false, .None,  0, 0, 0},
	{"Cactus #1",      3005,  2, 1, false, .None,  0, 0, 0},
	{"Cactus #2",      3004,  2, 0, false, .None,  0, 0, 0},
	{"Rock #3",        3001,  1, 0, false, .None,  0, 0, 0},
	{"Yucca Plant",    3006, 10, 2, false, .None,  0, 0, 0},
	{"Water Fountain", 3007,  8, 1, false, .Loop,  1, 0, 0},
	{"Windpump",       3009,  4, 2, false, .Loop,  0, 0, 0},
}

Object :: struct {
	using c:  Creature, // position, scale, hit rect, collision slots
	def:      ^Object_Def,
	bmp:      Bitmap,
	fw, fh:   int, // frame size
	key:      u8,
	content:  Rect, // hit box in frame coordinates: the original's (trimmed) box, less the shadow (port)
	shadow_bottom: int, // bottom of the original's trimmed box (shadow included), in frame coordinates
	sort_bottom:   int, // the original's hit-box bottom (shadow included), for the draw order
	anim_left: int, // ticks until the next frame (+0x8a)
	anim_step: int, // (+0x8c)
	swings:   int, // remaining bell swings (+0x90)
}

objects_init :: proc() {
	for &o, i in game.objects {
		def := &OBJECT_DEFS[i]
		bmp, ok := assets.objects[i], assets.objects_ok[i]
		o = {}
		o.def = def
		o.name = def.name
		o.kind = .Object
		o.id = i
		o.active = ok
		if !ok do continue
		o.bmp = bmp
		o.fw, o.fh = bmp.w, bmp.h / def.frames
		o.key = bmp.pixels[0]
		box := trim_box(&o, full_bounds(&o))
		o.content = rect_and(box, content_bounds(&o))
		o.shadow_bottom = box.bottom
		o.anim_step = def.step
		o.target_id = -1
		if i == BOWL do o.frame = (def.frames - 1) / 2 // half full
		if i == YUCCA do o.frame = 8 // a small plant that grows (0x41a790)
		// a random spot (and a previous one, drawn but not used here); the
		// bowl, the one object in the tank at first, isn't moved to a free
		// spot, so it may start against the spider (0x41a790)
		o.x = rand_n(TANK_W) - o.fw
		o.y = rand_n(VIEW_H) - o.fh + FLOOR_TOP
		o.prev_x = rand_n(TANK_W) - o.fw
		o.prev_y = rand_n(VIEW_H) - o.fh + FLOOR_TOP
		o.in_box = !def.in_tank // not placed in the tank
		object_update_position(&o)
	}
}

// The plants wilt when the spider dies (catch-up 0x415430: the yucca to its
// last frame, both cacti to frame 1) and recover when it's resurrected
// (0x404230: yucca frame 8, cacti frame 0).
plants_wilt :: proc(dead: bool) {
	y := &game.objects[YUCCA]
	y.frame = dead ? y.def.frames - 1 : min(8, y.def.frames - 1)
	for id in ([?]int{CACTUS1, CACTUS2}) do game.objects[id].frame = dead ? 1 : 0
}

// Bounds of the non-key pixels of frame 0, in frame coordinates. Port:
// the shadow (colour 49) is left out, so objects block where they're seen
// (the original counts it).
content_bounds :: proc(o: ^Object) -> Rect {
	r := Rect{o.fw, o.fh, -1, -1}
	for y in 0 ..< o.fh do for x in 0 ..< o.fw {
		p := o.bmp.pixels[y * o.fw + x]
		if p == o.key || p == 49 do continue
		r.left, r.top = min(r.left, x), min(r.top, y)
		r.right, r.bottom = max(r.right, x), max(r.bottom, y)
	}
	return r
}

// Bounds of frame 0's non-key pixels, shadow included (0x41c2e0).
full_bounds :: proc(o: ^Object) -> Rect {
	r := Rect{o.fw, o.fh, -1, -1}
	for y in 0 ..< o.fh do for x in 0 ..< o.fw {
		if o.bmp.pixels[y * o.fw + x] == o.key do continue
		r.left, r.top = min(r.left, x), min(r.top, y)
		r.right, r.bottom = max(r.right, x), max(r.bottom, y)
	}
	if r.right < 0 do r = {0, 0, o.fw - 1, o.fh - 1}
	return r
}

// Setup (0x41a790) shrinks the boxes of the tall objects so only their
// lower parts block and can be grabbed: the cacti and the fountain keep
// their lower half (cactus #1 also loses its left third), the bell its
// lower three quarters, the windpump its bottom quarter, and the yucca is
// trimmed all round.
trim_box :: proc(o: ^Object, r: Rect) -> Rect {
	r := r
	switch o.def.bitmap {
	case 3004, 3005, 3007: // cactus #2, cactus #1, fountain
		r.top += (r.bottom - r.top) / 2
		if o.def.bitmap == 3005 do r.left += (r.right - r.left) / 3
	case 3006: // yucca
		q := (r.bottom - r.top) / 4
		r.top += q / 2 + q
		v := int((i64(q) * 0x6db6db6d) >> 32) - q // (as compiled)
		r.bottom += v / 4
		w := (r.right - r.left) / 16
		r.left += w
		r.right -= w
	case 3008: // bell
		r.top += (r.bottom - r.top) / 4
	case 3009: // windpump
		r.top = r.bottom - (r.bottom - r.top) / 4
	}
	return r
}

// The overlap of two boxes (the first if they don't overlap).
rect_and :: proc(a, b: Rect) -> Rect {
	r := Rect{max(a.left, b.left), max(a.top, b.top), min(a.right, b.right), min(a.bottom, b.bottom)}
	if r.left > r.right || r.top > r.bottom do return a
	return r
}

OBJECT_MARGIN :: 180 // 0xb4: closest an object's centre gets to the side walls
SPIDER_BMP_H  :: 200 // height of the spider's bitmap (vcg_9100), which the back limit uses (sic)

// Position update for objects (the no-animation branch of 0x406df0). The
// back limit divides the spider's bitmap height, not the object's own.
object_update_position :: proc(o: ^Object) {
	if o.x < OBJECT_MARGIN do o.x = OBJECT_MARGIN
	if o.x > TANK_W - OBJECT_MARGIN do o.x = TANK_W - OBJECT_MARGIN
	div := o.def.depth_class == 1 ? 6 : o.def.depth_class == 2 ? 12 : 3
	if top := FLOOR_TOP + SPIDER_BMP_H / div; o.y < top do o.y = top
	if o.y + o.fh / 2 >= VIEW_H do o.y = VIEW_H - o.fh / 2

	// objects: scale% = min(100, 35 + 100 * y/480)
	o.scale = int(min(35 + f64(o.y) / f64(VIEW_H) * 100, 100))
	dw, dh := x87_scale_trunc(o.fw, o.scale), x87_scale_trunc(o.fh, o.scale)
	ox, oy := o.x - dw / 2, o.y - dh / 2
	b := o.content
	o.hit = {
		x87_scale_trunc(b.left, o.scale) + ox, x87_scale_trunc(b.top, o.scale) + oy,
		x87_scale_trunc(b.right, o.scale) + ox, x87_scale_trunc(b.bottom, o.scale) + oy,
	}
	o.sort_bottom = x87_scale_trunc(o.shadow_bottom, o.scale) + oy
}

// Frame animation and sounds (main update, 0x40ca70).
object_tick :: proc(o: ^Object) {
	def := o.def
	if def.mode != .None {
		switch def.mode {
		case .None:
		case .Loop:
			o.anim_left -= 1
			if o.anim_left < 1 {
				o.anim_left = def.ticks
				o.frame += 1
				if o.frame >= def.frames do o.frame = 0
			}
		case .Ping_Pong, .Swing:
			if def.mode == .Swing && o.swings < 1 {
				o.swings = 0
				o.frame = def.rest
			} else {
				o.anim_left -= 1
				if o.anim_left < 1 {
					o.anim_left = def.ticks
					o.frame += o.anim_step
					if o.frame < 1 || o.frame >= def.frames - 1 do o.anim_step = -o.anim_step
					if def.mode == .Swing do o.swings -= 1
				}
			}
		}
		// bell: ding at either end of a swing
		if o.id == BELL && o.anim_left == def.ticks && (o.frame == 0 || o.frame == def.frames - 1) {
			host_sound(466)
		}
	}
	// the windpump creaks every 18-35 turns of its wheel
	if o.id == WINDPUMP && o.frame == 0 {
		game.windpump_wait -= 1
		if game.windpump_wait < 1 {
			if game.input.view != .Box do host_sound(419)
			game.windpump_wait = rand_n(18) + 18
		}
	}
	object_update_position(o)
}

// Finds a free spot by stepping 50 px at a time from a random position
// (0x4086b0): free means the position update leaves it where it was and
// nothing overlaps.
place_free :: proc(o: ^Object) {
	x, y := rand_n(TANK_W), rand_n(VIEW_H)
	for _ in 0 ..< 1000 {
		o.x, o.y = x, y
		object_update_position(o)
		if o.x == x && o.y == y && !overlaps_anything(o) do return
		x += 50
		if x > TANK_W - o.fw {
			x = rand_n(TANK_W)
			y += 50
			if y > VIEW_H - o.fh do y = rand_n(VIEW_H)
		}
	}
}

// The same search for a creature, then face the first free direction.
place_free_creature :: proc(c: ^Creature) {
	x, y := rand_n(TANK_W), rand_n(VIEW_H)
	for _ in 0 ..< 1000 {
		c.x, c.y = x, y
		c.prev_x, c.prev_y = x, y
		creature_update_position(c)
		if c.x == x && c.y == y do break
		x += 50
		if x > TANK_W - c.anim.w {
			x = rand_n(TANK_W)
			y += 50
			if y > VIEW_H - c.anim.h do y = rand_n(VIEW_H)
		}
	}
	d := c.dir
	for _ in 0 ..< 8 {
		d = (d + 1) % 8
		if !c.blocks[d].active do break
	}
	c.dir = d
	// facing another way, the current play stops and the idle chooser runs
	// (0x405900, 0x407830); the frame must exist in the new direction
	n := len(creature_dir(c).frames)
	if n == 0 || c.frame >= n do c.frame = 0
}

overlaps_anything :: proc(o: ^Object) -> bool {
	for &p in game.objects do if &p != o && p.active && !p.in_box && rects_intersect(o.hit, p.hit) do return true
	return rects_intersect(o.hit, game.spider.hit)
}

// Drinking and the trip to the bowl (0x403e90). Called once a minute and
// whenever the spider touches an object.
spider_thirst :: proc(s: ^Creature) {
	st := &game.stats
	if st.water >= 81 do return
	game.thirst_count = (game.thirst_count + 1) % 5
	bowl := &game.objects[BOWL]
	if !bowl.active || bowl.in_box {
		bell := &game.objects[BELL]
		if bell.active && !bell.in_box && game.thirst_count == 0 && st.water < 51 {
			debug_logf("thirsty and no bowl: wait at the bell")
			move_to(s, .Creature_A, -1, -1, 4, game.seq.lurk, 120, target = BELL)
		}
		return
	}
	f := s.blocks[s.dir]
	touching := f.active && f.kind == int(Kind.Object) && f.id == BOWL
	if bowl.frame < 1 {
		if s.blocks[s.dir].kind != 0 do return
	} else if touching {
		bowl.frame -= 1
		st.water = min(st.water + 20, 100)
		host_sound(457)
		debug_logf("spider drinks (water %d, bowl level %d)", st.water, bowl.frame)
		return
	}
	// port: only to a bowl it has seen, and not in the middle of a hunt
	if game.thirst_count == 0 && game.senses.bowl_known && !hunting() {
		debug_logf("thirsty (water %d): go to the bowl", st.water)
		move_to(s, .Creature_A, -1, -1, -1, game.seq.lurk, 120, target = BOWL)
	}
}

objects_in_tank :: proc() -> (n: int) {
	for &o in game.objects do if o.active && !o.in_box do n += 1
	return
}

@(export)
tank_set_object :: proc "contextless" (id, on: i32) {
	if id < 0 || id >= OBJECT_COUNT do return
	game.pending_objects[id] = on != 0 ? 1 : 2
}

@(export)
tank_fill_bowl :: proc "contextless" () {
	game.objects[BOWL].frame = OBJECT_DEFS[BOWL].frames - 1
}

handle_pending_objects :: proc() {
	for &p, i in game.pending_objects {
		if p == 0 do continue
		o := &game.objects[i]
		if p == 1 && o.active && o.in_box && objects_in_tank() < MAX_OBJECTS_IN_TANK {
			o.in_box = false
			place_free(o)
			debug_logf("placed %s at (%d, %d)", o.name, o.x, o.y)
		} else if p == 2 {
			o.in_box = true
		}
		p = 0
	}
}
