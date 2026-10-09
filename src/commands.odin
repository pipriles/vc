package vc

import "base:runtime"

// Hidden typed commands (0x409de0, typed through wnd_proc's WM_CHAR):
// letters and digits collect (upper-cased) in a 16-character buffer, and
// Enter checks it against 19 words, stored with 100 added to each letter
// (0x42b4e8). A match, while the creature is alive, plays the slurp (457),
// shows a blinking "C" bottom right for 50 frames and does something.

COMMANDS := [19]string {
	"VENUS", "FLYTRAP", "BUFFALO", "PARKER", "DIET", "SAHARA", "PARTY",
	"LANDOFTHEGIANTS", "MICROCOSM", "JARVIS", "VINNIE", "OLIVER", "SWAMPY",
	"SURFER", "FLINT", "SHOWFPS", "KAMIKAZE", "URSULLA", "GLOBALBEACH",
}

Commands :: struct {
	typed:       [16]u8,
	n:           int,
	mark:        int,  // frames left showing "C" (0x454712)
	size_force:  int,  // 1 giant (size 100), 2 tiny (size 5) (0x455a64)
	flat_out:    bool, // FLINT: no frame-rate limit (0x455a62)
	show_fps:    bool, // SHOWFPS (0x44f75a)
	logo_skin:   bool, // GLOBALBEACH: the spider wears the Global Beach logo (0x4514ac)
	fps_ticks:   int,  // for SHOWFPS: frames counted this second
	fps_second:  f64,
	fps:         int,
}

cmd: Commands

// A typed character (letters and digits; 13 = Enter).
@(export)
tank_char :: proc "c" (ch: i32) {
	context = runtime.default_context()
	c := cmd_upper(ch)
	if ch == 13 {
		cmd_run(string(cmd.typed[:cmd.n]))
		cmd.n = 0
		return
	}
	if cmd.n > 15 do cmd.n = 0
	if (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') {
		cmd.typed[cmd.n] = u8(c)
		cmd.n += 1
	}
}

cmd_upper :: proc(ch: i32) -> i32 {return ch >= 'a' && ch <= 'z' ? ch - 32 : ch}

cmd_run :: proc(word: string) {
	if game.life.dead do return
	which := -1
	for w, i in COMMANDS do if w == word {which = i; break}
	if which < 0 do return
	s := &game.spider
	ids := &game.seq
	st := &game.stats
	host_sound(457)
	cmd.mark = 50
	debug_logf("typed command %s", word)
	switch which {
	case 0: // VENUS: to the glass
		move_to(s, .Y_Band, s.x, (100 - s.size) / 2 + GLASS_Y, 4, ids.glass, 60)
	case 1: // FLYTRAP: lay webs all round
		if rand_n(10) > 4 {
			enqueue_anim(s, ids.web_laying, 2, 6, flush = true)
			for d in ([?]int{0, 4, 6}) do enqueue_anim(s, ids.web_laying, d, 6)
		} else {
			enqueue_anim(s, ids.web_laying, 0, 6, flush = true)
			for d in ([?]int{2, 4, 6}) do enqueue_anim(s, ids.web_laying, d, 6)
		}
	case 2: // BUFFALO: hide under the rock
		move_to(s, .Point, LOG_X, FLOOR_TOP, 7, ids.log_hide, 120)
	case 3: // PARKER: wait at the bell
		move_to(s, .Creature_A, -1, -1, 4, ids.lurk, 120, target = BELL)
	case 4: // DIET
		st.food = max(st.food - 10, 0)
	case 5: // SAHARA
		st.water = max(st.water - 10, 0)
	case 6: // PARTY: the crickets in the box dance (only seen in the box)
		if game.input.view == .Box {
			for &c in game.crickets do if c.active && c.in_box do cricket_dance(&c)
		} else {
			cmd.mark = 0
		}
	case 7: // LANDOFTHEGIANTS
		cmd.size_force = cmd.size_force != 1 ? 1 : 0
		spider_growth(false)
	case 8: // MICROCOSM
		cmd.size_force = cmd.size_force != 2 ? 2 : 0
		spider_growth(false)
	case 9: // JARVIS
		enqueue_anim(s, ids.hair, 4, 4, flush = true)
	case 10: // VINNIE
		enqueue_anim(s, ids.threat, 4, 3, flush = true)
	case 11: // OLIVER: empty the bowl
		game.objects[BOWL].frame = 0
	case 12: // SWAMPY: the yucca grows a frame
		y := &game.objects[YUCCA]
		if y.active {
			y.frame -= 1
			if y.frame < 0 do y.frame = y.def.frames - 2
		}
	case 13: // SURFER: a corner web
		add_corner_web(false)
		floor_rebuild()
	case 14: // FLINT
		cmd.flat_out = !cmd.flat_out
	case 15: // SHOWFPS
		cmd.show_fps = !cmd.show_fps
	case 16: // KAMIKAZE: the crickets in the tank walk up to the spider
		for &c in game.crickets do if c.active && !c.in_box {
			stop_current(&c)
			clear_queue(&c)
			clear_goal(&c)
			move_to(&c, .Point, s.x, s.y, -1, game.cseq.web_stuck, 120)
		}
	case 17: // URSULLA: a moult, now
		game.skin.active = false
		game.skin.shed_at = 0
		spider_moult()
	case 18: // GLOBALBEACH
		cmd.logo_skin = !cmd.logo_skin
	}
}

// PARTY's routine for each cricket in the box (the original's queue).
cricket_dance :: proc(c: ^Creature) {
	ids := &game.cseq
	stop_current(c)
	clear_queue(c)
	enqueue_anim(c, ids.jump, -1, 5, flush = true)
	for st in ([?][2]int{{7, 16}, {2, 16}, {3, 14}, {6, 18}, {0, 10}, {3, 18}, {6, 18}}) {
		enqueue_anim(c, ids.jump, st[0], st[1])
	}
	run := rand_n(2)
	plays := rand_n(2) + 1
	enqueue_anim(c, ids.walk, min(rand_n(2), 1), plays, run = run != 0)
	run = rand_n(2)
	plays = rand_n(2) + 1
	dir := rand_n(10) < 5 ? min(rand_n(2), 1) : rand_n(2) + 6
	enqueue_anim(c, ids.walk, dir, plays, run = run != 0)
	enqueue_anim(c, ids.lurk, 0, 5)
	enqueue_anim(c, ids.web_stuck, 4, 3)
	run = rand_n(2)
	plays = rand_n(6) + 2
	enqueue_anim(c, ids.walk, min(rand_n(8), 7), plays, run = run != 0)
	enqueue_anim(c, ids.chirp, -1, 8)
}

// Once a frame: the mark's countdown and the frame counter.
cmd_tick :: proc() {
	cmd.mark = max(cmd.mark - 1, 0)
	cmd.fps_ticks += 1
	if t := host_time(); t >= cmd.fps_second + 1 {
		cmd.fps = cmd.fps_ticks
		cmd.fps_ticks, cmd.fps_second = 0, t
	}
	if cmd.logo_skin do logo_skin_tick()
}

// Drawn over the view: "FPS:nn" bottom left and the mark bottom right,
// both blinking with the low-needs blink (0x40ca70 end).
cmd_draw :: proc() {
	if game.ui.blink >= 5 do return
	if cmd.show_fps do ui_text(10, 464, fmt_fps(cmd.fps))
	if cmd.mark > 0 do ui_text(620, 464, "C")
}

fmt_fps :: proc(n: int) -> string {
	b := new([8]u8, context.temp_allocator)
	copy(b[:], "FPS:")
	b[4] = u8('0' + (n / 10) % 10)
	b[5] = u8('0' + n % 10)
	return string(b[:6])
}

// GLOBALBEACH: a 320 x 200 texture of the Global Beach logo (vcg_2013,
// cropped 14 px each side and 34 / 46 top and bottom) tiled at a size
// that grows and shrinks 2 px every other frame (11..479 by 11..299),
// painted onto the spider's body (0x40d81e, 0x417600).
LOGO_TEX_W :: 320
LOGO_TEX_H :: 200
logo_tex: [LOGO_TEX_W * LOGO_TEX_H]u8
logo_tile := [4]int{320, 200, 2, 2} // w, h, dw, dh
logo_wait := 0

logo_skin_tick :: proc() {
	logo_wait -= 1
	if logo_wait >= 1 do return
	logo_wait = 2
	b := &assets.options_box.beach
	if len(b.pixels) == 0 do return
	sx0, sy0 := 14, 34
	sw, sh := b.w - 28, b.h - 80
	tw, th := logo_tile[0], logo_tile[1]
	for y in 0 ..< LOGO_TEX_H do for x in 0 ..< LOGO_TEX_W {
		u := (x % tw) * sw / tw + sx0
		v := (y % th) * sh / th + sy0
		logo_tex[y * LOGO_TEX_W + x] = b.pixels[v * b.w + u]
	}
	logo_tile[0] += logo_tile[2]
	logo_tile[1] += logo_tile[3]
	if logo_tile[0] < 11 || logo_tile[0] > 479 do logo_tile[2] = -logo_tile[2]
	if logo_tile[1] < 11 || logo_tile[1] > 299 do logo_tile[3] = -logo_tile[3]
}
