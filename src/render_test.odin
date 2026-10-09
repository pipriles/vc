#+build !js
package vc

import "core:testing"

// The browser steps every display frame; only frames that differ from the
// one on screen are converted and sent.
@(test)
identical_frames_are_not_sent_again :: proc(t: ^testing.T) {
	if !sim_setup(t, 41) do return
	game.scroll_x, game.from_scroll = 200, 200
	tank_render()
	n := presented
	tank_render()
	testing.expect_value(t, presented, n)

	// a different view is sent, and converted with the current palette
	game.scroll_x, game.from_scroll = 300, 300
	tank_render()
	testing.expect_value(t, presented, n + 1)
	col := state.palette[view[0]]
	testing.expect(t, view_rgba[0] == col[0] && view_rgba[1] == col[1] && view_rgba[2] == col[2], "rgba from the palette")

	// so is the same view with a changed palette
	saved := state.palette
	defer state.palette = saved
	state.palette[view[0]] = {col[0] ~ 0xff, col[1], col[2]}
	tank_render()
	testing.expect_value(t, presented, n + 2)
	testing.expect_value(t, view_rgba[0], col[0] ~ 0xff)
}
