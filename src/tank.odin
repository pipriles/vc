package vc

import "base:runtime"
import "core:fmt"
import "core:slice"
import "core:strings"

// The terrarium: 1200x480 tank seen through a 640x480 viewfinder.

SCROLL_STEP :: 20 // px per tick when panning (wnd_proc_main)

Seq_Ids :: struct {
	circle, walk, lurk, lurk_d, crush, threat, glass, hair, clean: int,
	pickup, drop, catch_, catch_reset, kill, kill_reset, log_hide, web_laying, dead: int,
}

ROCK_DRAW_X :: 0x14a // 330: rock overlay position in the tank (0x4057b0)
ROCK_DRAW_Y :: 0x54  // 84

Game :: struct {
	tank:     Bitmap,
	rock:     Bitmap, // vcg_4005: cutout of the big rock, drawn over a hiding spider
	spider_a: Anim,
	spider:   Creature,
	cricket_a: Anim,
	crickets: [CRICKET_COUNT]Creature,
	cseq:     Cricket_Seq_Ids,
	render_list: [dynamic]^Creature, // creatures in the tank, drawn back to front
	remains:  [REMAINS_COUNT]Remains,
	remains_next: int,
	remains_bmp: Bitmap, // vcg_4004: 6 cricket remains sprites stacked
	storage:  int, // crickets in storage, refill the box
	eaten:    int,
	pending_drops: int,
	objects:  [OBJECT_COUNT]Object,
	pending_objects: [OBJECT_COUNT]int, // 1 = place, 2 = remove (from the UI)
	thirst_count, hunger_count: int, // cycle 0..4: act on every 5th check
	windpump_wait: int,
	input:    Input,
	cursor_x: int, // tank x of the pointer (DAT_004526fc)
	release_mouse: bool,
	pending_pointer: [32]Pending_Pointer,
	pending_pointer_len: int,
	pending_buttons: [8]Button,
	pending_buttons_len: int,
	box_bg:   Bitmap, // vcg_4501: the cricket box
	ui:       UI,
	life:     Life,
	skin:     Skin,
	skin_a:   Anim,
	footprints:     [FOOTPRINT_COUNT]Footprint,
	footprint_next: int,
	webs:           [WEB_PIECES]Web_Piece,
	web_next:       int,
	web_frame:      int,
	corner_webs:    [4]Corner_Web,
	yucca_age:      int,
	minute_ms:      u32,
	pending_resurrect, pending_new: bool,
	saved_tool: Tool, // restored when leaving the whole-tank view
	scroll_left, scroll_right: int, // edge scrolling ticks left
	loop_fountain, loop_drag: bool, // looping sounds on (465, 403)
	drag_x, drag_y: int,
	stats:    Spider_Stats,
	seq:      Seq_Ids,
	scroll_x: int,
	from_scroll: int, // smooth drawing: scroll_x at the start of the last step
	alpha:       f64, // how far into the next step the display is (0..1)
	follow:   bool,
	accum:    f64,
	speed:    f64,
	sec_ms:   u32,
	senses:   Senses, // port: what the spider notices (senses.odin)
}

game: Game
now_ms: u32 // simulation clock, advanced one frame (100, 71 or 55 ms) per tick
debug_enabled: bool

frame_buf: [MAX_W * MAX_H]u8
view: [VIEW_W * VIEW_H]u8 // palette indices
view_rgba: [VIEW_W * VIEW_H * 4]u8

// The last frame sent to the host. The browser calls step every display
// frame (up to 120 Hz) but the sim ticks every 55-100 ms, so most frames
// come out identical: those aren't converted or sent again.
shown_view:    [VIEW_W * VIEW_H]u8
shown_palette: [256][3]u8
shown_valid:   bool

present_view :: proc(palette: ^[256][3]u8) {
	if shown_valid && shown_palette == palette^ && slice.equal(view[:], shown_view[:]) do return
	for i in 0 ..< VIEW_W * VIEW_H {
		col := palette[view[i]]
		view_rgba[4 * i + 0] = col[0]
		view_rgba[4 * i + 1] = col[1]
		view_rgba[4 * i + 2] = col[2]
		view_rgba[4 * i + 3] = 255
	}
	present(&view_rgba[0], VIEW_W, VIEW_H)
	copy(shown_view[:], view[:])
	shown_palette = palette^
	shown_valid = true
}
tank_buf: [TANK_W * VIEW_H]u8 // the whole scene, like the original's tank surface

// Draw target for the blitters.
Surface :: struct {
	px:   []u8,
	w, h: int,
}
dst: Surface

view_surface :: proc() -> Surface {return {view[:], VIEW_W, VIEW_H}}
tank_surface :: proc() -> Surface {return {tank_buf[:], TANK_W, VIEW_H}}

// Allocator for data that lives for the whole program. The heap allocator
// doesn't exist on js_wasm32, where the default allocator is never reset.
persistent_allocator :: proc() -> runtime.Allocator {
	when ODIN_OS == .JS {
		return context.allocator
	} else {
		return runtime.heap_allocator()
	}
}

// Game data loaded once; game state is rebuilt from it by tank_reset.
Assets :: struct {
	loaded:      bool,
	tank, rock:  Bitmap,
	box:         Bitmap,
	ui:          [10]Bitmap, // button icons, in row order
	ring:        Bitmap,
	gauges:      [4]Bitmap,
	corners:     Bitmap,
	corner_webs: [4]Bitmap,
	footprints, web, skin: Anim,
	font:        Bitmap,
	logo:        Anim,
	remains:     Bitmap,
	spider:      Anim,
	cricket:     Anim,
	objects:     [OBJECT_COUNT]Bitmap,
	objects_ok:  [OBJECT_COUNT]bool,
	options_box: Box_Art, // the Options box
}

assets: Assets

load_assets :: proc() -> bool {
	if assets.loaded do return true
	// assets outlive whatever allocator the caller runs with (tests use
	// per-test allocators)
	context.allocator = persistent_allocator()
	tank, ok := bmp_load(load_file("bitmaps/vcg_4500.bmp"))
	if !ok {
		fmt.eprintln("missing tank bitmap")
		return false
	}
	assets.tank = tank
	assets.rock, _ = bmp_load(load_file("bitmaps/vcg_4005.bmp"))
	assets.box, _ = bmp_load(load_file("bitmaps/vcg_4501.bmp"))
	for def, i in BUTTON_DEFS {
		assets.ui[i], _ = bmp_load(load_file(fmt.tprintf("bitmaps/vc_%d.bmp", def.bitmap)))
	}
	assets.ring, _ = bmp_load(load_file("bitmaps/vc_320.bmp"))
	box_art_load(&assets.options_box)
	for id, i in ([4]int{1000, 1003, 1002, 1001}) {
		assets.gauges[i], _ = bmp_load(load_file(fmt.tprintf("bitmaps/vcg_%d.bmp", id)))
	}
	assets.corners, _ = bmp_load(load_file("bitmaps/vcg_2009.bmp"))
	for def, i in CORNER_WEBS {
		assets.corner_webs[i], _ = bmp_load(load_file(fmt.tprintf("bitmaps/vcg_%d.bmp", def.bitmap)))
	}
	assets.footprints, _ = anim_parse(load_file("footprints.idx"), load_file("footprints.pix"))
	assets.web, _ = anim_parse(load_file("web.idx"), load_file("web.pix"))
	assets.skin, _ = anim_parse(load_file("skin.idx"), load_file("skin.pix"))
	assets.font, _ = bmp_load(load_file("bitmaps/vcg_2008.bmp"))
	assets.logo, _ = anim_parse(load_file("logo.idx"), load_file("logo.pix"))
	assets.remains, _ = bmp_load(load_file("bitmaps/vcg_4004.bmp"))
	base, ok1 := anim_parse(load_file("spider.idx"), load_file("spider.pix"))
	if !ok1 do return false
	assets.spider = base
	if plug, ok2 := anim_parse(load_file("plugin_spider.idx"), load_file("plugin_spider.pix")); ok2 {
		assets.spider = anim_merge(base, plug)
	}
	cricket, ok3 := anim_parse(load_file("cricket.idx"), load_file("cricket.pix"))
	if !ok3 do return false
	assets.cricket = cricket
	for def, i in OBJECT_DEFS {
		assets.objects[i], assets.objects_ok[i] = bmp_load(load_file(fmt.tprintf("bitmaps/vcg_%d.bmp", def.bitmap)))
	}
	assets.loaded = true
	return true
}

tank_init :: proc() -> bool {
	if !load_assets() do return false
	rng.seed = u32(host_time())
	tank_reset()
	if load_game() {
		if game.life.dead do game.life.death_notice = 30
	}
	spider_growth(true) // starting up: growth and the moult check (0x403ac0)
	floor_rebuild()
	return true
}

// A brand new spider (Options: New spider).
@(export)
tank_new_spider :: proc "contextless" () {
	game.pending_new = true
}

// Fresh tank with a new spider (keeps the random seed going).
tank_reset :: proc() {
	game = {}
	game.render_list = make([dynamic]^Creature, 0, 32, persistent_allocator())
	game.tank = assets.tank
	state.palette = assets.tank.palette
	game.rock = assets.rock
	game.box_bg = assets.box
	game.remains_bmp = assets.remains
	game.spider_a = assets.spider
	a := &game.spider_a
	game.seq = {
		circle      = seq_find(a, "CIRCLE"),
		walk        = seq_find(a, "WALK"),
		lurk        = seq_find(a, "LURK"),
		lurk_d      = seq_find(a, "LURK_D"),
		crush       = seq_find(a, "CRUSH"),
		threat      = seq_find(a, "THREAT"),
		glass       = seq_find(a, "GLASS"),
		hair        = seq_find(a, "HAIR"),
		clean       = seq_find(a, "CLEAN"),
		pickup      = seq_find(a, "PICKUP"),
		drop        = seq_find(a, "DROP"),
		catch_      = seq_find(a, "CATCH"),
		catch_reset = seq_find(a, "CATCH_RESET"),
		kill        = seq_find(a, "KILL"),
		kill_reset  = seq_find(a, "KILL_RESET"),
		log_hide    = seq_find(a, "LOG_HIDE"),
		web_laying  = seq_find(a, "WEB_LAYING"),
		dead        = seq_find(a, "DEAD"),
	}

	// new spider (0x406680 call in the setup path): x 100, y 300, speed 5x3, size 40
	creature_init(&game.spider, a, 100, 300, 5, 3, 40)
	game.spider.idle = spider_idle
	game.spider.finished = spider_finished
	game.spider.can_play = spider_can_play
	game.spider.name = "spider"
	game.spider.seq = game.seq.lurk
	place_free_creature(&game.spider) // 0x4086b0 right after creation
	start_sequence(&game.spider)
	game.stats = {food = 30, water = 30}
	spider_stats_tick(&game.stats)

	game.cricket_a = assets.cricket
	crickets_init()
	senses_init()
	// registering added 25 crickets to the store (0x4514b2); the port counts
	// as registered
	game.storage = 25
	objects_init()
	game.skin_a = assets.skin
	skin_init()
	floor_rebuild()
	update_render_list()

	ui_init()
	game.life.born_at = host_time()
	game.follow = true
	game.speed = 1
	game.scroll_x = clamp(game.spider.x - VIEW_W / 2, 0, TANK_W - VIEW_W)
}

// Creatures in the tank, back to front.
update_render_list :: proc() {
	clear(&game.render_list)
	append(&game.render_list, &game.spider)
	for &c in game.crickets do if c.active && !c.in_box do append(&game.render_list, &c)
	for &o in game.objects do if o.active && !o.in_box do append(&game.render_list, &o.c)
	if game.skin.active do append(&game.render_list, &game.skin.c)
	slice.sort_by(game.render_list[:], proc(a, b: ^Creature) -> bool {return a.y < b.y})
}

// Frame rate setting (Options > Settings): the original runs the whole
// game step once per frame, every 100, 71 or 55 ms (10, 14 or 18 fps,
// table at 0x4525e0, default 14). Smooth draws every display frame and
// slides creatures and the viewfinder between steps (port only).
FRAME_MS := [3]int{100, 71, 55}
settings := struct {
	frame_rate: int,
	smooth:     bool,
	sound:      bool, // (kept by the host)
	fullscreen: bool, // (kept by the host)
	help_text:  bool, // flyover help (tooltips)
	saver_idle: int,  // port: index into SAVER_IDLE, 0 = never
} {
	frame_rate = 1,
	smooth     = true,
	sound      = true,
	help_text  = true,
}

data_variant := "cr"

@(export)
tank_set_variant :: proc "contextless" (rk: i32) {data_variant = rk != 0 ? "rk" : "cr"}

@(export)
tank_set_host_state :: proc "contextless" (sound, fullscreen, help_text: i32) {
	settings.sound = sound != 0
	settings.fullscreen = fullscreen != 0
	settings.help_text = help_text != 0
}

tick_ms :: proc() -> int {return FRAME_MS[clamp(settings.frame_rate, 0, 2)]}

@(export)
tank_set_frame_rate :: proc "contextless" (rate, smooth: i32) {
	settings.frame_rate = int(clamp(rate, 0, 2))
	settings.smooth = smooth != 0
}

@(export)
tank_set_saver_idle :: proc "contextless" (minutes: i32) {
	settings.saver_idle = 0
	for m, i in SAVER_IDLE do if int(minutes) == m do settings.saver_idle = i
}

// Where things were at the start of the last step, for smooth drawing.
remember_positions :: proc() {
	game.from_scroll = game.scroll_x
	game.spider.from_x, game.spider.from_y = game.spider.x, game.spider.y
	for &c in game.crickets do c.from_x, c.from_y = c.x, c.y
	game.skin.from_x, game.skin.from_y = game.skin.x, game.skin.y
	game.ui.from_ind, game.ui.from_btn = game.ui.ind_y, game.ui.btn_y
	box_remember()
}

// Position to draw at: between the last two steps when smooth, unless it
// jumped (teleports, drops, a new view).
lerp_pos :: proc(from, to: int, limit: int) -> int {
	if !settings.smooth || abs(to - from) > limit do return to
	return from + int(f64(to - from) * game.alpha)
}

tank_tick :: proc() {
	remember_positions()
	now_ms += u32(tick_ms())
	if game.pending_new {
		tank_reset()
		host_message("NEW SPIDER", "A new spider has hatched.")
		return
	}
	if game.pending_resurrect {
		game.pending_resurrect = false
		spider_resurrect()
	}
	handle_input()
	cursor_tick()
	ui_tick()
	box_tick()
	if game.ui.box.state != .Closed do stats_mood()
	death_notice_tick()
	handle_pending_drops()
	handle_pending_objects()
	for &o in game.objects do if o.active && !o.in_box do object_tick(&o)
	update_render_list()
	creature_tick(&game.spider)
	if !game.life.dead do spider_unstick(&game.spider)
	senses_tick()
	for &c in game.crickets do creature_tick(&c)
	spider_hide_crawl(&game.spider)
	sound_loops()
	if now_ms >= game.minute_ms + 60_000 {
		game.minute_ms = now_ms
		minute_tick()
	}
	if now_ms >= game.sec_ms + 1000 {
		game.sec_ms = now_ms
		spider_stats_tick(&game.stats)
		// The original only checks this in the start-up catch-up, so a
		// spider starving while the program runs lingered at health 0 until
		// the next start; here it dies when it happens.
		if game.stats.health < 1 && !game.life.dead {
			spider_dies(&game.spider, host_time()) // (the yucca wilts at the next minute)
		}
	}
	// edge scrolling, 20 px a tick (wnd_proc_main timer)
	if game.scroll_left > 0 {
		game.scroll_left -= 1
		game.scroll_x = max(game.scroll_x - SCROLL_STEP, 0)
	}
	if game.scroll_right > 0 {
		game.scroll_right -= 1
		game.scroll_x = min(game.scroll_x + SCROLL_STEP, TANK_W - VIEW_W)
	}
	// follow mode keeps the spider centred
	if game.follow && game.input.carry == .None {
		game.scroll_x = clamp(game.spider.x - VIEW_W / 2, 0, TANK_W - VIEW_W)
	}
}

tank_step :: proc(dt: f64) {
	tank_advance(dt)
	tank_render()
}

// Runs the ticks due after dt seconds without drawing (tests that only
// watch the sim skip the render).
tank_advance :: proc(dt: f64) {
	tick := f64(tick_ms()) / 1000
	game.accum += dt * game.speed
	if game.accum > 1 do game.accum = tick
	for game.accum >= tick {
		game.accum -= tick
		tank_tick()
	}
	game.alpha = clamp(game.accum / tick, 0, 1)
}

@(export)
tank_scroll :: proc "contextless" (dx: i32) {
	game.follow = false
	game.scroll_x = clamp(game.scroll_x + int(dx), 0, TANK_W - VIEW_W)
}

@(export)
tank_set_follow :: proc "contextless" (on: i32) {
	game.follow = on != 0
}

@(export)
tank_set_speed :: proc "contextless" (speed: f64) {
	game.speed = speed
}

@(export)
tank_set_debug :: proc "contextless" (on: i32) {
	debug_enabled = on != 0
}

tank_render :: proc() {
	if game.input.view == .Box {
		box_render()
		return
	}

	// compose the whole tank, then show part of it
	dst = tank_surface()
	copy(tank_buf[:], floor_buf[:]) // background plus footprints and webs

	// cricket remains on the sand (0x40ca70)
	rb := &game.remains_bmp
	for r in game.remains do if r.used && rb.w > 0 {
		draw_keyed_part(rb, r.x - rb.w / 2, r.y, r.kind * rb.h / 6, rb.h / 6)
	}
	// shadows of every creature first, then bodies (0x417390, 0x417180)
	update_render_list()
	for c in game.render_list do draw_creature(c, .Shadow, 0)
	for c in game.render_list do draw_creature(c, .Body, 0)
	if game.spider.y < FLOOR_TOP && game.rock.w > 0 {
		draw_keyed(&game.rock, ROCK_DRAW_X, ROCK_DRAW_Y)
	}

	dst = view_surface()
	#partial switch game.input.view {
	case .Tank:
		sx := clamp(lerp_pos(game.from_scroll, game.scroll_x, 40), 0, TANK_W - VIEW_W)
		for y in 0 ..< VIEW_H {
			copy(view[y * VIEW_W:][:VIEW_W], tank_buf[y * TANK_W + sx:][:VIEW_W])
		}
		ui_draw()
		if !game.ui.saver do box_draw()
	case .Whole:
		whole_render()
	case .Close:
		close_render()
	}

	present_view(&state.palette)
	if debug_enabled {
		if game.input.view == .Tank do draw_debug()
		else do debug_begin() // the overlay is in tank-view coordinates: clear it
	}
	s := &game.stats
	tank_status(
		i32(s.food), i32(s.water), i32(s.health), i32(s.mood), i32(s.temperament),
		game.spider.anim.seqs[game.spider.seq].name, i32(game.spider.dir),
	)
}

Draw_Pass :: enum {
	Shadow, // only the shadow colour (key2), drawn solid
	Body,   // everything except the key and the shadow colour
}

// Draws the frame scaled to scale% (StretchBlt, nearest) with its canvas
// centred on the creature (0x417390 shadow pass, 0x417180 body pass).
draw_creature :: proc(c: ^Creature, pass: Draw_Pass, scroll: int) {
	if c.kind == .Object {
		draw_object((^Object)(c), pass)
		return
	}
	a := c.anim
	s := &a.seqs[c.seq]
	d := &s.dirs[c.dir]
	if len(d.frames) == 0 do return
	f := d.frames[clamp(c.frame, 0, len(d.frames) - 1)]
	n := a.w * a.h
	if !frame_decode(a, s, f, frame_buf[:n]) do return

	dw := x87_scale_trunc(a.w, c.scale)
	dh := x87_scale_trunc(a.h, c.scale)
	if dw <= 0 || dh <= 0 do return
	x0 := lerp_pos(c.from_x, c.x, 30) - scroll - dw / 2
	y0 := lerp_pos(c.from_y, c.y, 30) - dh / 2
	for j in 0 ..< dh {
		vy := y0 + j
		if vy < 0 || vy >= dst.h do continue
		sy := j * a.h / dh
		for i in 0 ..< dw {
			vx := x0 + i
			if vx < 0 || vx >= dst.w do continue
			p := frame_buf[sy * a.w + i * a.w / dw]
			if p == a.key || (p == d.key2) != (pass == .Shadow) do continue
			dst.px[vy * dst.w + vx] = p
		}
	}
}

// Objects: frame scaled to scale% centred on the object (0x416e40), shadow
// colour (49) in the shadow pass.
draw_object :: proc(o: ^Object, pass: Draw_Pass, cx := min(int), cy := 0, scale := 0) {
	sc := scale > 0 ? scale : o.scale
	dw, dh := x87_scale_trunc(o.fw, sc), x87_scale_trunc(o.fh, sc)
	if dw <= 0 || dh <= 0 do return
	x0, y0 := o.x - dw / 2, o.y - dh / 2
	if cx != min(int) do x0, y0 = cx - dw / 2, cy - dh / 2
	base := o.frame * o.fh * o.fw
	for j in 0 ..< dh {
		vy := y0 + j
		if vy < 0 || vy >= dst.h do continue
		row := base + (j * o.fh / dh) * o.fw
		for i in 0 ..< dw {
			vx := x0 + i
			if vx < 0 || vx >= dst.w do continue
			p := o.bmp.pixels[row + i * o.fw / dw]
			if p == o.key || (p == 49) != (pass == .Shadow) do continue
			dst.px[vy * dst.w + vx] = p
		}
	}
}

// The cricket box view: wicker room with the crickets still in the box.
box_render :: proc() {
	b := &game.box_bg
	dst = view_surface()
	copy(view[:], b.pixels[:VIEW_W * VIEW_H])
	in_box: [CRICKET_COUNT]^Creature
	n := 0
	for &c in game.crickets do if c.active && c.in_box {in_box[n] = &c; n += 1}
	list := in_box[:n]
	slice.sort_by(list, proc(a, b: ^Creature) -> bool {return a.y < b.y})
	for c in list do draw_creature(c, .Shadow, 0)
	for c in list do draw_creature(c, .Body, 0)
	present_view(&b.palette)
}

// Blits a bitmap, skipping its top-left colour (0x412600).
draw_keyed :: proc(b: ^Bitmap, x0, y0: int) {
	draw_keyed_part(b, x0, y0, 0, b.h)
}

// Blits rows [sy, sy+h) of a bitmap, skipping its top-left colour.
draw_keyed_part :: proc(b: ^Bitmap, x0, y0, sy, h: int) {
	key := b.pixels[0]
	for y in 0 ..< h {
		vy := y0 + y
		if vy < 0 || vy >= dst.h do continue
		for x in 0 ..< b.w {
			vx := x0 + x
			if vx < 0 || vx >= dst.w do continue
			if p := b.pixels[(sy + y) * b.w + x]; p != key do dst.px[vy * dst.w + vx] = p
		}
	}
}

// Debug overlay: geometry on the view plus a text panel (drawn by JS).
draw_debug :: proc() {
	DIR_DX := [8]int{0, 1, 1, 1, 0, -1, -1, -1}
	DIR_DY := [8]int{-1, -1, 0, 1, 1, 1, 0, -1}
	sx := -game.scroll_x
	c := &game.spider
	debug_begin()

	// tank limits: side walls, floor line, hiding line
	debug_line(i32(WALL_MARGIN + sx), 0, i32(WALL_MARGIN + sx), VIEW_H, 0x4060ff)
	debug_line(i32(TANK_W - WALL_MARGIN + sx), 0, i32(TANK_W - WALL_MARGIN + sx), VIEW_H, 0x4060ff)
	debug_line(0, FLOOR_TOP, VIEW_W, FLOOR_TOP, 0x4060ff)
	debug_line(0, HIDE_Y, VIEW_W, HIDE_Y, 0x305090)

	// creature: drawn box, centre, facing, blocked directions
	dw, dh := x87_scale_trunc(c.anim.w, c.scale), x87_scale_trunc(c.anim.h, c.scale)
	cx, cy := c.x + sx, c.y
	debug_rect(i32(cx - dw / 2), i32(cy - dh / 2), i32(dw), i32(dh), 0x808080)
	debug_line(i32(cx - 6), i32(cy), i32(cx + 6), i32(cy), 0xffff00)
	debug_line(i32(cx), i32(cy - 6), i32(cx), i32(cy + 6), 0xffff00)
	debug_line(i32(cx), i32(cy), i32(cx + DIR_DX[c.dir] * 30), i32(cy + DIR_DY[c.dir] * 30), 0x00ff80)
	for b, d in c.blocks[:8] {
		if !(b.active || b.kind != 0) do continue
		debug_line(i32(cx + DIR_DX[d] * 20), i32(cy + DIR_DY[d] * 20),
			i32(cx + DIR_DX[d] * 40), i32(cy + DIR_DY[d] * 40), 0xff3030)
	}

	for o in game.render_list {
		if o == c do continue
		debug_rect(i32(o.hit.left + sx), i32(o.hit.top), i32(o.hit.right - o.hit.left),
			i32(o.hit.bottom - o.hit.top), 0x80c0ff)
		if o.kind == .Object {
			debug_text(i32(o.x + sx - 10), i32(o.hit.top - 3), fmt.tprintf("%s f%d", o.name, o.frame), 0xc0ff80)
		} else {
			debug_text(i32(o.x + sx - 10), i32(o.hit.top - 3), fmt.tprintf("c%d %s", o.id, seq_name(o, o.seq)), 0x80c0ff)
		}
	}
	debug_rect(i32(c.hit.left + sx), i32(c.hit.top), i32(c.hit.right - c.hit.left),
		i32(c.hit.bottom - c.hit.top), 0xffa040)

	// goal: target, arrival tolerance, path
	g := &c.goal
	if g.active {
		gx, gy := g.x + sx, g.y
		tx, ty := c.sx * 9, c.sy * 7
		#partial switch g.type {
		case .Y_Band:
			debug_rect(0, i32(gy), VIEW_W, i32(ty), 0xff60ff)
		case:
			debug_rect(i32(gx - tx / 2), i32(gy - ty / 2), i32(tx), i32(ty), 0xff60ff)
		}
		debug_line(i32(cx), i32(cy), i32(gx), i32(gy), 0xff60ff)
		debug_text(i32(gx + 6), i32(gy - 6), seq_name(c, g.seq), 0xff60ff)
	}

	// text panel
	st := &game.stats
	sb := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&sb, "sim time   %.1f s   seed %08x\n", f64(now_ms) / 1000, rng.seed)
	fmt.sbprintf(&sb, "spider     pos (%d, %d)  scale %d%%  speed %dx%d  size %d\n",
		c.x, c.y, c.scale, c.sx, c.sy, c.size)
	fmt.sbprintf(&sb, "anim       %s  dir %d  frame %d/%d  step %d  plays %d%s%s\n",
		seq_name(c, c.seq), c.dir, c.frame + 1, len(creature_dir(c).frames), c.step, c.plays,
		c.moving_x || c.moving_y ? "  moving" : "", c.run ? "  running" : "")
	fmt.sbprintf(&sb, "turning    %s\n",
		c.turn_dir != 0 ? fmt.tprintf("%s to %d", c.turn_dir > 0 ? "cw" : "ccw", c.turn_target) : "-")
	fmt.sbprint(&sb, "queue      ")
	for q in c.queue[:c.queue_len] do fmt.sbprintf(&sb, "%s/d%d/x%d  ", seq_name(c, q.seq), q.dir, q.plays)
	fmt.sbprint(&sb, c.queue_len == 0 ? "-\n" : "\n")
	if g.active {
		fmt.sbprintf(&sb, "goal       %v (%d, %d) then %s, %ds left%s\n", g.type, g.x, g.y,
			seq_name(c, g.seq), g.timeout_s - int(now_ms - g.start_ms) / 1000,
			g.detouring ? fmt.tprintf("  detour via %d", g.walk_dir) : "")
	} else {
		fmt.sbprint(&sb, "goal       -\n")
	}
	fmt.sbprintf(&sb, "hiding     %d%s\n", c.hide, c.no_clamp ? "  (floor clamp off)" : "")
	in_box := 0
	for &cr in game.crickets do if cr.active && cr.in_box do in_box += 1
	fmt.sbprintf(&sb, "crickets   tank %d  box %d  storage %d  eaten %d%s%s\n",
		crickets_in_tank(), in_box, game.storage, game.eaten,
		c.target_id >= 0 ? fmt.tprintf("  target c%d", c.target_id) : "", c.eating ? "  eating" : "")
	fmt.sbprintf(&sb, "needs      food %d  water %d  health %d  mood %d  temperament %d%s\n",
		st.food, st.water, st.health, st.mood, st.temperament, st.interacted ? "  touched" : "")
	fmt.sbprint(&sb, "cooldowns  ")
	ids := &game.seq
	for id in ([?]int{ids.log_hide, ids.glass, ids.crush}) {
		fmt.sbprintf(&sb, "%s %.0fs ago  ", seq_name(c, id), f64(now_ms - c.last_played[id]) / 1000)
	}
	debug_panel(strings.to_string(sb))
}

// The two looping sounds (0x416510): running water while the fountain is in
// the tank (not in the box view), scraping while an object is dragged.
sound_loops :: proc() {
	f := &game.objects[FOUNTAIN]
	fountain := f.active && !f.in_box && game.input.view != .Box
	if fountain != game.loop_fountain {
		game.loop_fountain = fountain
		host_loop(465, fountain)
	}
	drag := false
	if game.input.carry == .Object {
		o := &game.objects[game.input.carry_id]
		drag = abs(o.x - game.drag_x) > 2 || abs(o.y - game.drag_y) > 2
		game.drag_x, game.drag_y = o.x, o.y
	}
	if drag != game.loop_drag {
		game.loop_drag = drag
		host_loop(403, drag)
	}
}
