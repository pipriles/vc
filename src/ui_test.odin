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
