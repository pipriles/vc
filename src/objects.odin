package vc

// Tank objects (kind 1): water bowl, bell, rocks, cacti, yucca, fountain,
// windpump. Table and behaviour from VC.EXE setup (0x41a790), the object
// part of the main update (0x40ca70) and drinking (0x403e90).

OBJECT_COUNT :: 10 // the 11th table row is the shed skin (kind 6), handled with moulting
BOWL         :: 0  // DAT_00455846: the drinking object
BELL         :: 1  // DAT_00454a38: where a hungry spider waits
YUCCA        :: 7  // DAT_0044def4: grows one frame per day
FOUNTAIN     :: 8  // plays its sound now and then

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
	content:  Rect, // non-key bounds of frame 0 (0x41c2e0)
	anim_left: int, // ticks until the next frame (+0x8a)
	anim_step: int, // (+0x8c)
	swings:   int, // remaining bell swings (+0x90)
}

objects_init :: proc() {
	for &o, i in game.objects {
		def := &OBJECT_DEFS[i]
		ui_add_object(i32(i), def.name, def.in_tank)
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
		o.content = content_bounds(&o)
		o.anim_step = def.step
		o.target_id = -1
		if i == BOWL do o.frame = (def.frames - 1) / 2 // half full
		x := rand_n(TANK_W) - o.fw
		y := rand_n(VIEW_H) - o.fh + FLOOR_TOP
		o.x, o.y = x, y
		o.in_box = !def.in_tank // not placed in the tank
		if def.in_tank do place_free(&o)
	}
}

// Bounds of the non-key pixels of frame 0, in frame coordinates.
content_bounds :: proc(o: ^Object) -> Rect {
	r := Rect{o.fw, o.fh, -1, -1}
	for y in 0 ..< o.fh do for x in 0 ..< o.fw {
		if o.bmp.pixels[y * o.fw + x] == o.key do continue
		r.left, r.top = min(r.left, x), min(r.top, y)
		r.right, r.bottom = max(r.right, x), max(r.bottom, y)
	}
	return r
}

// Position update for objects (the no-animation branch of 0x406df0).
object_update_position :: proc(o: ^Object) {
	if o.x < WALL_MARGIN do o.x = WALL_MARGIN
	if o.x > TANK_W - WALL_MARGIN do o.x = TANK_W - WALL_MARGIN
	div := o.def.depth_class == 1 ? 6 : o.def.depth_class == 2 ? 12 : 3
	if top := FLOOR_TOP + o.fh / div; o.y < top do o.y = top
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
	if o.id == FOUNTAIN && o.frame == 0 {
		game.fountain_wait -= 1
		if game.fountain_wait < 1 {
			if game.input.view != .Box do host_sound(419)
			game.fountain_wait = rand_n(18) + 18
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
	if game.thirst_count == 0 {
		debug_logf("thirsty (water %d): go to the bowl", st.water)
		move_to(s, .Creature_A, -1, -1, -1, game.seq.lurk, 120, target = BOWL)
	}
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
		if p == 1 && o.active && o.in_box {
			o.in_box = false
			place_free(o)
			debug_logf("placed %s at (%d, %d)", o.name, o.x, o.y)
		} else if p == 2 {
			o.in_box = true
		}
		p = 0
	}
}
