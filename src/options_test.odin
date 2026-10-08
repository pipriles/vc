#+build !js
package vc

import "core:testing"

@(test)
help_lines_match_the_original_table :: proc(t: ^testing.T) {
	// spot checks against the table at 0x42dd68 (line numbers the
	// right-click help jumps to depend on these)
	testing.expect_value(t, HELP[0].text, "TOP SCREEN ICONS")
	testing.expect_value(t, HELP[19].text, "MOOD INDICATOR")
	testing.expect_value(t, HELP[25].text, "BOTTOM SCREEN BUTTONS")
	testing.expect_value(t, HELP[36].text, "KNOCK")
	testing.expect_value(t, HELP[88].text, "SCAN MODE")
	testing.expect_value(t, HELP[120].text, "FLOATING PANEL")
	testing.expect_value(t, HELP[127].text, "SETTINGS OPTIONS")
	testing.expect_value(t, HELP[152].text, "ADDITIONAL HELP")
	testing.expect_value(t, HELP[159].text, "http://www.virtualcreatures.com/vc")
	testing.expect_value(t, CREDITS[30].text, "Stephen Rose")
	for l, i in HELP do if l.icon == 1 {
		testing.expectf(t, l.index >= 0 && l.index < 10, "line %d: button %d", i, l.index)
	}
}

@(private = "file")
run_box :: proc(n: int) {for _ in 0 ..< n do box_tick()}

@(test)
options_box_opens_switches_and_closes :: proc(t: ^testing.T) {
	if !sim_setup(t, 4) do return
	b := &game.ui.box
	button(Button(6))
	testing.expect_value(t, b.state, Box_State.Opening)
	run_box(10)
	testing.expect_value(t, b.state, Box_State.Open)
	testing.expect_value(t, b.page, Box_Page.Menu)

	// click Stats: press and release over its button
	y, _, _ := item_row(.Menu, 2)
	box_pointer(.Down, BOX_CX + 20, y + 5)
	box_pointer(.Up, BOX_CX + 20, y + 5)
	testing.expect(t, b.switching, "the page wipe starts")
	run_box(40)
	testing.expect(t, !b.switching, "the wipe ends")
	testing.expect_value(t, b.page, Box_Page.Stats)

	// right-click help while open: the help page at the water tap
	open_help(71)
	run_box(40)
	testing.expect_value(t, b.page, Box_Page.Help)
	testing.expect_value(t, b.top, 71)

	button(Button(6))
	run_box(10)
	testing.expect_value(t, b.state, Box_State.Closed)
}

@(test)
frame_rate_buttons_cycle :: proc(t: ^testing.T) {
	if !sim_setup(t, 4) do return
	settings.frame_rate = 1
	box_activate(.Minus, 0)
	testing.expect_value(t, settings.frame_rate, 2)
	box_activate(.Minus, 0)
	testing.expect_value(t, settings.frame_rate, 0)
	box_activate(.Plus, 0)
	testing.expect_value(t, settings.frame_rate, 2)
	settings.frame_rate = 0
}

@(test)
download_crickets_fills_the_box :: proc(t: ^testing.T) {
	if !sim_setup(t, 4) do return
	for &c in game.crickets do c.active = false
	game.storage = 0
	download_crickets()
	n := 0
	for c in game.crickets do if c.active && c.in_box do n += 1
	testing.expect_value(t, n, 12)
	testing.expect_value(t, game.storage, 0)
}
