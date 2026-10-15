#+build !js
package vc

import "core:testing"

@(private = "file")
slide_done :: proc() {
	for _ in 0 ..< 10 do ui_slide_tick()
}

@(test)
logo_cycles_with_slides :: proc(t: ^testing.T) {
	if !sim_setup(t, 1) do return
	u := &game.ui
	testing.expect(t, u.shown && !u.icons_only, "starts with everything shown")

	// 1: the buttons slide down off the view, the indicators stay
	ui_toggle()
	testing.expect_value(t, u.slide, 1)
	ui_slide_tick()
	testing.expect_value(t, u.btn_y, BUTTON_Y + 10)
	slide_done()
	testing.expect(t, !u.shown && u.icons_only && u.slide == 0, "indicators only")

	// 2: the indicators slide up out of the view
	ui_toggle()
	ui_slide_tick()
	testing.expect_value(t, u.ind_y, INDICATOR_B - 14)
	slide_done()
	testing.expect(t, !u.shown && !u.icons_only, "nothing shown")

	// 3: the indicators slide back down, then the buttons are back
	ui_toggle()
	testing.expect(t, u.slide == 2 && u.ind_y == 0 && u.btn_y == VIEW_H, "sliding in")
	slide_done()
	testing.expect(t, u.shown && !u.icons_only && u.cycle == 1, "all shown again")
}

@(test)
right_click_with_ui_hidden_flashes_then_cycles :: proc(t: ^testing.T) {
	if !sim_setup(t, 2) do return
	u := &game.ui
	in_ := &game.input
	in_.tool = .Tap
	pointer_event(.Right, 300, 300) // shown: cycles straight away
	testing.expect_value(t, in_.tool, Tool.Pickup)
	u.shown, u.icons_only = false, false
	pointer_event(.Right, 300, 300) // hidden: only shows the button
	testing.expect_value(t, in_.tool, Tool.Pickup)
	testing.expect_value(t, u.tools_flash, 50)
	pointer_event(.Right, 300, 300) // while it shows: cycles
	testing.expect_value(t, in_.tool, Tool.Prod)
	for _ in 0 ..< 50 do ui_tick()
	testing.expect_value(t, u.tools_flash, 0)
	u.shown = true
}

@(test)
name_edited_in_the_tank :: proc(t: ^testing.T) {
	if !sim_setup(t, 3) do return
	u := &game.ui
	testing.expect_value(t, string(u.name[:u.name_len]), "ENTER PETS NAME HERE")
	tank_step(TICK) // drawn: the name's box is known
	pointer_event(.Down, 20, 15)
	pointer_event(.Up, 20, 15)
	testing.expect(t, u.name_edit, "a click on the name edits it")
	u.caret = 0
	for ch in transmute([]u8)string("tom") do tank_char(i32(ch))
	testing.expect_value(t, string(u.name[:4]), "TOME") // overwrites
	tank_key(46) // Delete the E
	tank_key(35) // End
	tank_key(8)  // Backspace
	testing.expect_value(t, string(u.name[:u.name_len]), "TOMR PETS NAME HER")
	food := game.stats.food
	for ch in transmute([]u8)string("diet") do tank_char(i32(ch))
	tank_char(13)
	testing.expect_value(t, game.stats.food, food) // no commands while editing
	testing.expect(t, !u.name_edit, "Enter finishes")
	pointer_event(.Down, 20, 15)
	pointer_event(.Down, 300, 300)
	testing.expect(t, !u.name_edit, "a click elsewhere finishes")

	tank_key('+')
	tank_tick()
	testing.expect_value(t, game.input.view, View.Close)
	tank_key(27)
	testing.expect_value(t, game.input.view, View.Tank)
}

// A wide view (port): more tank, the buttons centred, the indicators and the
// logo at the right edge, the Options box in the middle and its clicks shifted.
@(test)
wide_view_layout :: proc(t: ^testing.T) {
	if !sim_setup(t, 61) do return
	defer tank_set_view_width(VIEW_W)
	b0 := game.ui.buttons[0].x
	tank_set_view_width(1041) // made even
	testing.expect_value(t, view_w, 1040)
	testing.expect_value(t, game.ui.buttons[0].x, b0 + 200)
	testing.expect_value(t, logo_x(), VIEW_W - 96 - 10 + 400)
	testing.expect_value(t, ind_x(), INDICATOR_X + 400)
	game.follow = false
	tank_scroll(10_000)
	testing.expect_value(t, game.scroll_x, TANK_W - 1040)

	// the Options button, where it now is, opens the box; a click in the
	// box's middle (640 coordinates + 200) lands in it
	b: ^UI_Button
	for &bt in game.ui.buttons do if bt.cmd == 6 do b = &bt
	if !testing.expect(t, b != nil, "an Options button") do return
	press(.Down, b.x + 4, BUTTON_Y + 4)
	press(.Up, b.x + 4, BUTTON_Y + 4)
	for _ in 0 ..< 20 do tank_tick()
	testing.expect_value(t, game.ui.box.state, Box_State.Open)
	testing.expect(t, box_covers(VIEW_W / 2, VIEW_H / 2), "the box covers its middle in 640 coordinates")
	testing.expect_value(t, tank_ui_at(i32(VIEW_W / 2 + 200), VIEW_H / 2), 0) // the box, not the tank UI

	// every screen draws at the widest view
	tank_set_view_width(MAX_VIEW_W)
	tank_render()
	for v in ([?]View{.Whole, .Close, .Box}) {
		game.input.view = v
		tank_render()
	}
	game.input.view = .Tank
}

// The logo spins gold (direction 4), green while the pointer is on it
// (direction 0); pressed it shrinks, and the release toggles the UI
// (0x40ca70, the 0x201 / 0x202 branches).
@(test)
logo_gold_green_and_release :: proc(t: ^testing.T) {
	if !sim_setup(t, 62) do return
	u := &game.ui
	mean_warmth :: proc() -> int {
		// red minus green over the logo's box
		r, g := 0, 0
		for y in LOGO_Y ..< LOGO_Y + 72 do for x in logo_x() ..< logo_x() + 96 {
			c := state.palette[view[y * view_w + x]]
			r += int(c[0]); g += int(c[1])
		}
		return (r - g) / (96 * 72)
	}
	tank_render()
	gold := mean_warmth()
	x, y := logo_x() + 48, LOGO_Y + 36
	press(.Move, x, y)
	tank_tick()
	testing.expect(t, u.logo_hover, "the pointer on the logo")
	tank_render()
	green := mean_warmth()
	testing.expectf(t, gold > green + 5, "gold, then green under the pointer (red - green: %d, %d)", gold, green)

	cycle := u.cycle
	press(.Down, x, y)
	tank_tick()
	testing.expect(t, u.logo_down, "held down")
	testing.expect_value(t, u.cycle, cycle) // not yet
	press(.Up, x, y)
	tank_tick()
	testing.expect(t, !u.logo_down, "released")
	testing.expect(t, u.cycle != cycle || u.slide_t > 0, "the release toggles the buttons and icons")
}
