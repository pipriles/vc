package vc

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
	stats:    Spider_Stats,
	seq:      Seq_Ids,
	scroll_x: int,
	follow:   bool,
	accum:    f64,
	speed:    f64,
	sec_ms:   u32,
}

game: Game
now_ms: u32 // simulation clock, advanced 100 ms per tick
debug_enabled: bool

frame_buf: [MAX_W * MAX_H]u8
view: [VIEW_W * VIEW_H]u8 // palette indices
view_rgba: [VIEW_W * VIEW_H * 4]u8

tank_init :: proc() -> bool {
	game = {}
	tank, ok := bmp_load(load_file("bitmaps/vcg_4500.bmp"))
	if !ok {
		fmt.eprintln("missing tank bitmap")
		return false
	}
	game.tank = tank
	state.palette = tank.palette
	game.rock, _ = bmp_load(load_file("bitmaps/vcg_4005.bmp"))
	game.remains_bmp, _ = bmp_load(load_file("bitmaps/vcg_4004.bmp"))

	base, ok1 := anim_parse(load_file("spider.idx"), load_file("spider.pix"))
	if !ok1 do return false
	game.spider_a = base
	if plug, ok2 := anim_parse(load_file("plugin_spider.idx"), load_file("plugin_spider.pix")); ok2 {
		game.spider_a = anim_merge(base, plug)
	}
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

	rng.seed = u32(host_time())
	// new spider (0x406680 call in the setup path): x 100, y 300, speed 5x3, size 40
	creature_init(&game.spider, a, 100, 300, 5, 3, 40)
	game.spider.idle = spider_idle
	game.spider.finished = spider_finished
	game.spider.can_play = spider_can_play
	game.spider.name = "spider"
	game.spider.seq = game.seq.lurk
	start_sequence(&game.spider)
	game.stats = {food = 30, water = 30}
	spider_stats_tick(&game.stats)

	cricket_a, ok3 := anim_parse(load_file("cricket.idx"), load_file("cricket.pix"))
	if !ok3 do return false
	game.cricket_a = cricket_a
	crickets_init()
	update_render_list()

	game.follow = true
	game.speed = 1
	game.scroll_x = clamp(game.spider.x - VIEW_W / 2, 0, TANK_W - VIEW_W)
	return true
}

// Creatures in the tank, back to front.
update_render_list :: proc() {
	clear(&game.render_list)
	append(&game.render_list, &game.spider)
	for &c in game.crickets do if c.active && !c.in_box do append(&game.render_list, &c)
	slice.sort_by(game.render_list[:], proc(a, b: ^Creature) -> bool {return a.y < b.y})
}

tank_tick :: proc() {
	now_ms += 100
	handle_pending_drops()
	update_render_list()
	creature_tick(&game.spider)
	for &c in game.crickets do creature_tick(&c)
	if now_ms >= game.sec_ms + 1000 {
		game.sec_ms = now_ms
		spider_stats_tick(&game.stats)
	}
	if game.follow {
		target := clamp(game.spider.x - VIEW_W / 2, 0, TANK_W - VIEW_W)
		game.scroll_x += clamp(target - game.scroll_x, -SCROLL_STEP, SCROLL_STEP)
	}
}

tank_step :: proc(dt: f64) {
	game.accum += dt * game.speed
	if game.accum > 1 do game.accum = TICK
	for game.accum >= TICK {
		game.accum -= TICK
		tank_tick()
	}
	tank_render()
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
	t := &game.tank
	for y in 0 ..< VIEW_H {
		copy(view[y * VIEW_W:][:VIEW_W], t.pixels[y * t.w + game.scroll_x:][:VIEW_W])
	}

	// cricket remains on the sand (0x40ca70)
	rb := &game.remains_bmp
	for r in game.remains do if r.used && rb.w > 0 {
		draw_keyed_part(rb, r.x - game.scroll_x - rb.w / 2, r.y, r.kind * rb.h / 6, rb.h / 6)
	}

	// shadows of every creature first, then bodies (0x417390, 0x417180)
	update_render_list()
	for c in game.render_list do draw_creature(c, .Shadow)
	for c in game.render_list do draw_creature(c, .Body)
	if game.spider.y < FLOOR_TOP && game.rock.w > 0 {
		draw_keyed(&game.rock, ROCK_DRAW_X - game.scroll_x, ROCK_DRAW_Y)
	}

	for i in 0 ..< VIEW_W * VIEW_H {
		col := state.palette[view[i]]
		view_rgba[4 * i + 0] = col[0]
		view_rgba[4 * i + 1] = col[1]
		view_rgba[4 * i + 2] = col[2]
		view_rgba[4 * i + 3] = 255
	}
	present(&view_rgba[0], VIEW_W, VIEW_H)
	if debug_enabled do draw_debug()
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
draw_creature :: proc(c: ^Creature, pass: Draw_Pass) {
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
	x0 := c.x - game.scroll_x - dw / 2
	y0 := c.y - dh / 2
	for j in 0 ..< dh {
		vy := y0 + j
		if vy < 0 || vy >= VIEW_H do continue
		sy := j * a.h / dh
		for i in 0 ..< dw {
			vx := x0 + i
			if vx < 0 || vx >= VIEW_W do continue
			p := frame_buf[sy * a.w + i * a.w / dw]
			if p == a.key || (p == d.key2) != (pass == .Shadow) do continue
			view[vy * VIEW_W + vx] = p
		}
	}
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
		if vy < 0 || vy >= VIEW_H do continue
		for x in 0 ..< b.w {
			vx := x0 + x
			if vx < 0 || vx >= VIEW_W do continue
			if p := b.pixels[(sy + y) * b.w + x]; p != key do view[vy * VIEW_W + vx] = p
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
		debug_text(i32(o.x + sx - 10), i32(o.hit.top - 3), fmt.tprintf("c%d %s", o.id, seq_name(o, o.seq)), 0x80c0ff)
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
