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
