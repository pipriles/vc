package vc

// The in-view UI: button row, needs indicators, pet name and logo (the
// logo toggles the rest; the original's exit button isn't needed here), drawn into the view like the original (main update 0x40ca70,
// buttons 0x41bc..: table, 0x4060b0 draw, indicators 0x40e990).

BUTTON_Y      :: 420 // 0x1a4
BUTTON_X0     :: 20  // (640 - 0x208) / 2 - 40
BUTTON_GAP    :: 4
INDICATOR_X   :: 342 // 0x156
INDICATOR_Y   :: 13  // 0x55 minus the mood gauge's frame height
INDICATOR_B   :: 85  // 0x55: bottom of the indicators when shown
RING_FRAMES   :: 14
PRESSED_SCALE :: 70

// Row order and resource ids from the table at 0x41bc..; the command is the
// resource id - 300.
BUTTON_DEFS := [10]struct {
	bitmap, frames: int,
} {
	{304, 5}, // tools (frame = current tool)
	{303, 1}, // feed
	{307, 1}, // water
	{302, 2}, // scan / follow (frame 0 scan, 1 follow)
	{300, 1}, // close-up view
	{301, 1}, // whole tank
	{309, 1}, // clear debris
	{306, 1}, // options
	{308, 1}, // website
	{305, 1}, // floating panel
}

TOOL_TIPS := [TOOL_COUNT]string {
	"Use this icon to tap on the glass to attract the creatures attention.",
	"Use this icon to pick up and move your creature.",
	"Use this icon to gently prod your pet and attract attention.",
	"Use this icon to stroke your pet.",
	"Have your creature follow the cursor with this icon.",
}

button_tip :: proc(cmd: int) -> string {
	switch cmd {
	case 4: return TOOL_TIPS[int(game.input.tool)]
	case 3: return "Feed your creature here."
	case 7: return "Water your creature here."
	case 2:
		return game.follow ? "Follow Mode : In this mode, your spider remains in the centre of the viewfinder." : "Scan Mode : In this mode, the viewfinder can be moved freely."
	case 0: return "Close up view of your creature."
	case 1: return "View the entire tank and select tank objects."
	case 9: return "Removes all debris from the tank."
	case 6: return game.ui.box.state == .Open || game.ui.box.state == .Opening ? "Close the Options box." : "Open the Options box."
	case 8: return "Visit the Virtual Creatures Website."
	case 5: return "Run Virtual Creatures as Floating Panel."
	}
	return ""
}

UI_Button :: struct {
	bmp:    Bitmap,
	fw, fh: int,
	x:      int,
	cmd:    int,
	frames: int,
}

UI :: struct {
	buttons:      [10]UI_Button,
	ring:         Bitmap, // vc_320: spins round the hovered button
	gauges:       [4]Bitmap, // mood (1000), health (1003), water (1002), food (1001)
	cell_corners: Bitmap, // vcg_2009: object panel cell corners
	// The logo cycles all shown -> indicators only (buttons slide down) ->
	// nothing (indicators slide up) -> all (indicators slide down, buttons
	// slide up) (0x418e..; slide in main update 0x40ca70).
	shown:        bool, // buttons on (0x44d9c0)
	icons_only:   bool, // indicators stay while the buttons are off (0x44d9c2)
	cycle:        int,  // (0x44cb4c)
	slide:        int,  // 0 none, 1 out, 2 in (0x44df64)
	slide_t:      int,  // ticks left (0x4560fe)
	ind_y, btn_y: int,  // indicator bottom and button row while sliding (0x454710, 0x4525e6)
	from_ind, from_btn: int, // smooth drawing: at the start of the last step
	logo_hover:   bool,
	font:         Bitmap, // vcg_2008: A-Z, 0-9
	logo:         Anim,
	hover:        int, // button index, -1 none
	pressed:      int,
	ring_frame:   int,
	ring_count:   int,
	blink:        int, // 0..10, low needs blink (0x451f30)
	logo_frame:   int,
	box:          Box, // the Options box
	saver:        bool, // screensaver: no UI, the view follows the spider
	tools_flash:  int,  // ticks the tools button shows alone while hidden (0x4514b8)
	floating:     bool, // port: shown in the floating window, no buttons or logo
	saver_follow: bool, // follow mode before it
	name:         [24]u8,
	name_len:     int,
}

// x offsets of the name font glyphs A-Z then 0-9, and the strip's end (0x431248)
FONT_X := [37]int{0, 16, 32, 46, 63, 81, 95, 114, 131, 138, 156, 172, 187, 208, 223, 241, 258,
	274, 295, 311, 328, 344, 364, 385, 403, 419, 437, 452, 462, 478, 492, 507, 523, 539, 553, 569, 584}

ui_init :: proc() {
	u := &game.ui
	x := BUTTON_X0
	for def, i in BUTTON_DEFS {
		b := &u.buttons[i]
		b.bmp = assets.ui[i]
		b.frames = def.frames
		b.fw, b.fh = b.bmp.w, b.bmp.h / max(def.frames, 1)
		b.x = x
		b.cmd = def.bitmap - 300
		x += b.fw + BUTTON_GAP
	}
	u.ring = assets.ring
	u.gauges = assets.gauges
	u.cell_corners = assets.corners
	u.font = assets.font
	u.logo = assets.logo
	u.hover, u.pressed = -1, -1
	u.shown, u.cycle = true, 1
	u.box.held = -1
}

// Help page top line for a right-clicked button (0x4065b0).
button_help_line :: proc(i: int) -> int {
	switch i {
	case 0: return 34 + 6 * int(game.input.tool)
	case 1: return 64
	case 2: return 71
	case 3: return game.follow ? 80 : 86
	case 4: return 91
	case 5: return 96
	case 6: return 103
	case 7: return 108
	case 8: return 112
	case 9: return 118
	}
	return 0
}

// The right button released in the tank (0x205): help for a button or
// indicator under the pointer, otherwise the tools command.
ui_right_click :: proc(vx, vy: int) {
	u := &game.ui
	if game.input.carry != .None do return
	if u.shown && u.slide == 0 {
		if b := button_at(vx, vy); b >= 0 {
			open_help(button_help_line(b))
			return
		}
	}
	if line := indicator_help_at(vx, vy); line >= 0 {
		open_help(line)
		return
	}
	button(.Next_Tool)
}

// The floating panel (picture-in-picture) shows the tank without the
// bottom row and the logo (the original's miniature had no controls).
@(export)
tank_set_floating :: proc "contextless" (on: i32) {
	game.ui.floating = on != 0
	game.ui.hover, game.ui.logo_hover = -1, false
}

// Screensaver mode (port of VC.SCR, which started VC.EXE full screen):
// nothing drawn over the tank and the viewfinder follows the spider.
@(export)
tank_set_saver :: proc "contextless" (on: i32) {
	u := &game.ui
	if (on != 0) == u.saver do return
	u.saver = on != 0
	if u.saver {
		u.saver_follow = game.follow
		game.follow = true
		u.hover, u.pressed, u.logo_hover = -1, -1, false
	} else {
		game.follow = u.saver_follow
	}
}

// The logo was clicked.
ui_toggle :: proc() {
	u := &game.ui
	u.cycle += 1
	u.slide_t = 6
	if u.cycle == 1 && u.icons_only {
		u.icons_only, u.cycle = false, 0
	} else if u.cycle > 1 {
		u.icons_only, u.cycle = true, 0
	}
	if u.cycle == 0 {
		u.slide, u.ind_y, u.btn_y = 1, INDICATOR_B, BUTTON_Y
	} else {
		u.slide, u.ind_y, u.btn_y = 2, 0, VIEW_H
	}
	u.from_ind, u.from_btn = u.ind_y, u.btn_y
	// 14 px a tick for the indicators, (480 - 420) / 6 for the buttons
	host_sound(400)
}

ui_slide_tick :: proc() {
	u := &game.ui
	if u.slide == 0 do return
	u.slide_t -= 1
	if u.slide_t < 0 {
		u.shown = u.slide != 1
		u.slide = 0
	}
	if u.slide == 1 {
		u.ind_y -= 14
		u.btn_y += 10
	} else {
		u.ind_y += 14
		u.btn_y -= 10
	}
}

ui_tick :: proc() {
	u := &game.ui
	u.blink = (u.blink + 1) % 11
	u.tools_flash = max(u.tools_flash - 1, 0)
	ui_slide_tick()
	u.ring_count += 1
	if u.ring_count > 3 {
		u.ring_count = 0
		u.ring_frame = (u.ring_frame + 1) % RING_FRAMES
	}
	if n := logo_frames(); n > 0 do u.logo_frame = (u.logo_frame + 1) % n
}

logo_frames :: proc() -> int {
	a := &game.ui.logo
	if len(a.seqs) == 0 do return 0
	return len(a.seqs[0].dirs[0].frames)
}

button_at :: proc(vx, vy: int) -> int {
	for b, i in game.ui.buttons {
		if vx >= b.x && vx < b.x + b.fw && vy >= BUTTON_Y && vy < BUTTON_Y + b.fh do return i
	}
	return -1
}

LOGO_X :: VIEW_W - 96 - 10
LOGO_Y :: VIEW_H - 72 - 8

over_logo :: proc(vx, vy: int) -> bool {
	return vx >= LOGO_X && vx < LOGO_X + 96 && vy >= LOGO_Y && vy < LOGO_Y + 72
}

// Pointer handling for the UI; returns true when the UI took the event.
ui_pointer :: proc(ev: Pointer_Event, vx, vy: int) -> bool {
	u := &game.ui
	if game.input.carry != .None do return false
	b := u.shown && !u.floating ? button_at(vx, vy) : -1
	u.hover = b
	u.logo_hover = !u.floating && over_logo(vx, vy)
	#partial switch ev {
	case .Down:
		if b >= 0 {
			u.pressed = b
			button(Button(u.buttons[b].cmd))
			return true
		}
		if u.logo_hover {
			ui_toggle()
			return true
		}
	case .Up:
		was := u.pressed
		u.pressed = -1
		if was >= 0 do return true
	case .Leave:
		u.hover, u.pressed, u.logo_hover = -1, -1, false
	}
	if b >= 0 || u.logo_hover {
		set_cursor(0)
		return true
	}
	return false
}

// Draws the UI over the scene (view coordinates, palette indices).
ui_draw :: proc() {
	u := &game.ui
	ui_begin()
	if u.saver do return

	// pet name, top left, in the bitmap font
	draw_name(10, 10)

	if !u.floating do ui_draw_logo()
	if u.logo_hover && settings.help_text do ui_text(LOGO_X - 120, LOGO_Y - 16, "Toggle display of buttons and icons.")
	// needs: mood gauge (frame = temperament), then health, water, food
	iy := u.slide != 0 ? lerp_pos(u.from_ind, u.ind_y, 40) : u.shown ? INDICATOR_B : 0
	if u.icons_only do iy = INDICATOR_B
	if iy >= 1 do draw_indicators(iy)

	// button row with the ring round the hovered button
	if u.floating do return
	if u.slide == 0 && u.shown {
		for &b, i in u.buttons {
			if i == u.hover && u.ring.w > 0 {
				rh := u.ring.h / RING_FRAMES
				draw_keyed_part(&u.ring, b.x + (b.fw - u.ring.w) / 2, BUTTON_Y + (b.fh - rh) / 2,
					u.ring_frame * rh, rh)
			}
			draw_button(&b, BUTTON_Y, i == u.pressed ? PRESSED_SCALE : 100)
			if i == u.hover && settings.help_text do ui_text(b.x, BUTTON_Y - 16, button_tip(b.cmd))
		}
	} else if u.slide == 0 && u.tools_flash > 0 {
		// right-clicked while hidden: the tools button alone
		draw_button(&u.buttons[0], BUTTON_Y, 100)
	} else if (u.slide == 1 && u.icons_only) || u.slide == 2 {
		// (the original pops the buttons in at the end; they slide in here)
		by := lerp_pos(u.from_btn, u.btn_y, 40)
		for &b in u.buttons do draw_button(&b, by, 100)
	}
}

draw_button :: proc(b: ^UI_Button, y, scale: int) {
	frame := 0
	switch b.cmd {
	case 4: frame = int(game.input.tool)
	case 2: frame = game.follow ? 1 : 0 // (0x451748: 1 = follow)
	}
	draw_scaled_part(&b.bmp, b.x, y, b.fw, b.fh, frame * b.fh, scale)
}

// Help line for the indicator under the pointer, -1 if none: mood 16,
// health 11, water 6, food 0 (wnd_proc 0x205 via the hover flags).
indicator_help_at :: proc(px, py: int) -> int {
	u := &game.ui
	if u.slide != 0 || !(u.shown || u.icons_only) do return -1
	g := &u.gauges[0]
	gh := g.h / 8
	top := INDICATOR_B - gh
	if px > INDICATOR_X + 10 && px < INDICATOR_X + g.w - 10 && py > top + 5 && py < top + gh - 5 do return 16
	x := INDICATOR_X + 4 + g.w
	lines := [3]int{11, 6, 0}
	for i in 0 ..< 3 {
		b := &u.gauges[i + 1]
		fh := b.h / 10
		if px > x + 12 && px < x + b.w - 12 && py > top + 5 && py < top + fh - 5 do return lines[i]
		x += b.w + 4
	}
	return -1
}

// The four indicators with their bottom at y (0x40e990).
draw_indicators :: proc(y: int) {
	u := &game.ui
	st := &game.stats
	g := &u.gauges[0]
	gh := g.h / 8
	top := y - gh
	draw_keyed_part(g, INDICATOR_X, top, clamp(st.temperament, 0, 7) * gh, gh)
	tip_x := 0
	x := INDICATOR_X + 4 + g.w
	values := [3]int{st.health, st.water, st.food}
	tips := [4]string {
		"Mood Indicator. Judge your creatures mood from this.",
		"Health Indicator. Judge your creatures health from this.",
		"Water Indicator. Judge your creatures Water levels from this.",
		"Food Indicator. Judge your creatures hunger levels from this.",
	}
	px, py := game.input.vx, game.input.vy
	if settings.help_text && game.input.inside && px > INDICATOR_X + 10 && px < INDICATOR_X + g.w - 10 &&
	   py > top + 5 && py < top + gh - 5 {
		ui_text(INDICATOR_X, top + gh + 2, tips[0])
	}
	for v, i in values {
		b := &u.gauges[i + 1]
		fh := b.h / 10
		frame := (v - 1) / 10
		if v < 31 && u.blink < 5 do frame = 0 // low: blink
		frame = clamp(frame, 0, 9)
		if v > 9 || u.blink > 4 do draw_keyed_part(b, x, top, frame * fh, fh)
		if settings.help_text && game.input.inside && px > x + 12 && px < x + b.w - 12 &&
		   py > top + 5 && py < top + fh - 5 {
			ui_text(x - 200, top + fh + 2, tips[i + 1])
		}
		x += b.w + 4
		tip_x = x
	}
	_ = tip_x
}

// Animated VC logo, bottom right (logo creature 0x455ac0).
ui_draw_logo :: proc() {
	u := &game.ui
	n := logo_frames()
	if n == 0 do return
	a := &u.logo
	s := &a.seqs[0]
	f := s.dirs[0].frames[u.logo_frame % n]
	buf := frame_buf[:a.w * a.h]
	if !frame_decode(a, s, f, buf) do return
	for j in 0 ..< a.h do for i in 0 ..< a.w {
		p := buf[j * a.w + i]
		if p != a.key do dst.px[(LOGO_Y + j) * dst.w + LOGO_X + i] = p
	}
}

// Name in the bitmap font: A-Z and 0-9, other characters as 10 px gaps.
draw_name :: proc(x0, y0: int) {
	u := &game.ui
	f := &u.font
	if f.w == 0 do return
	x := x0
	for ch in u.name[:u.name_len] {
		g := -1
		switch ch {
		case 'A' ..= 'Z': g = int(ch - 'A')
		case 'a' ..= 'z': g = int(ch - 'a')
		case '0' ..= '9': g = 26 + int(ch - '0')
		}
		if g < 0 {
			x += 10
			continue
		}
		gx, gw := FONT_X[g], FONT_X[g + 1] - FONT_X[g] - 1
		key: u8 = 0 // white glyphs on black
		for j in 0 ..< f.h do for i in 0 ..< gw {
			p := f.pixels[j * f.w + gx + i]
			vx, vy := x + i, y0 + j
			if p != key && vx >= 0 && vx < dst.w && vy >= 0 && vy < dst.h do dst.px[vy * dst.w + vx] = p
		}
		x += gw + 1
	}
}

// Rows [sy, sy+h) of a bitmap scaled to scale% and centred in w x h at (x0, y0).
draw_scaled_part :: proc(b: ^Bitmap, x0, y0, w, h, sy, scale: int) {
	dw, dh := x87_scale_trunc(w, scale), x87_scale_trunc(h, scale)
	if dw <= 0 || dh <= 0 do return
	ox, oy := x0 + (w - dw) / 2, y0 + (h - dh) / 2
	key := b.pixels[0]
	for j in 0 ..< dh {
		vy := oy + j
		if vy < 0 || vy >= dst.h do continue
		row := (sy + j * h / dh) * b.w
		for i in 0 ..< dw {
			vx := ox + i
			if vx < 0 || vx >= dst.w do continue
			p := b.pixels[row + i * w / dw]
			if p != key do dst.px[vy * dst.w + vx] = p
		}
	}
}

@(export)
tank_name_clear :: proc "contextless" () {
	game.ui.name_len = 0
}

@(export)
tank_name_char :: proc "contextless" (ch: i32) {
	u := &game.ui
	if u.name_len < len(u.name) && ch > 31 && ch < 127 {
		u.name[u.name_len] = u8(ch)
		u.name_len += 1
	}
}
