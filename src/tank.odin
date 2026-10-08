package vc

import "core:fmt"
import "core:slice"

// The terrarium: 1200x480 tank seen through a 640x480 viewfinder.

SCROLL_STEP :: 20 // px per tick when panning (wnd_proc_main)

Seq_Ids :: struct {
	circle, walk, lurk, lurk_d, crush, threat, glass, hair, clean: int,
	pickup, drop, catch_, catch_reset, kill, kill_reset, log_hide, web_laying, dead: int,
}

Game :: struct {
	tank:     Bitmap,
	spider_a: Anim,
	spider:   Creature,
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

frame_buf: [MAX_W * MAX_H]u8
view: [VIEW_W * VIEW_H]u8 // palette indices
view_rgba: [VIEW_W * VIEW_H * 4]u8

tank_init :: proc() -> bool {
	tank, ok := bmp_load(load_file("bitmaps/vcg_4500.bmp"))
	if !ok {
		fmt.eprintln("missing tank bitmap")
		return false
	}
	game.tank = tank
	state.palette = tank.palette

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
	game.spider.seq = game.seq.lurk
	start_sequence(&game.spider)
	game.stats = {food = 30, water = 30}
	spider_stats_tick(&game.stats)

	game.follow = true
	game.speed = 1
	game.scroll_x = clamp(game.spider.x - VIEW_W / 2, 0, TANK_W - VIEW_W)
	return true
}

tank_tick :: proc() {
	now_ms += 100
	creature_tick(&game.spider)
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

tank_render :: proc() {
	t := &game.tank
	for y in 0 ..< VIEW_H {
		copy(view[y * VIEW_W:][:VIEW_W], t.pixels[y * t.w + game.scroll_x:][:VIEW_W])
	}

	// draw creatures back to front
	list := [?]^Creature{&game.spider}
	slice.sort_by(list[:], proc(a, b: ^Creature) -> bool {return a.y < b.y})
	for c in list do draw_creature(c)

	for i in 0 ..< VIEW_W * VIEW_H {
		col := state.palette[view[i]]
		view_rgba[4 * i + 0] = col[0]
		view_rgba[4 * i + 1] = col[1]
		view_rgba[4 * i + 2] = col[2]
		view_rgba[4 * i + 3] = 255
	}
	present(&view_rgba[0], VIEW_W, VIEW_H)
	s := &game.stats
	tank_status(
		i32(s.food), i32(s.water), i32(s.health), i32(s.mood), i32(s.temperament),
		game.spider.anim.seqs[game.spider.seq].name, i32(game.spider.dir),
	)
}

// Draws the frame scaled to scale% around the creature's centre (blit at
// 0x417180: frame canvas centred on (x, y), keys skipped). The shadow
// colour (key2) is skipped by that blit; the original draws shadows in a
// separate pass not decoded yet, approximated here by darkening.
draw_creature :: proc(c: ^Creature) {
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
			if p == a.key do continue
			dst := &view[vy * VIEW_W + vx]
			if p == d.key2 {
				dst^ = shade[dst^]
			} else {
				dst^ = p
			}
		}
	}
}

// Darkened palette lookup for the approximate shadow pass.
shade: [256]u8

build_shade_table :: proc() {
	for c, i in state.palette {
		want := [3]int{int(c[0]) * 55 / 100, int(c[1]) * 55 / 100, int(c[2]) * 55 / 100}
		best, best_d := 0, max(int)
		for p, j in state.palette {
			d0, d1, d2 := int(p[0]) - want[0], int(p[1]) - want[1], int(p[2]) - want[2]
			if dist := d0 * d0 + d1 * d1 + d2 * d2; dist < best_d {
				best, best_d = j, dist
			}
		}
		shade[i] = u8(best)
	}
}
