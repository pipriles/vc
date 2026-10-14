#+build !js
package vc

import "core:mem"
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

// The browser calls step every display frame. What a frame formats with
// the temp allocator (the box's cricket counts, the options text) must be
// let go at the end of it, or memory grows for as long as the box is open.
@(test)
step_lets_go_of_the_frames_text :: proc(t: ^testing.T) {
	if !sim_setup(t, 3) do return
	buf := make([]u8, 1 << 20)
	defer delete(buf)
	arena: mem.Arena
	mem.arena_init(&arena, buf)
	context.temp_allocator = mem.arena_allocator(&arena)

	game.pending_buttons[0] = .Feed
	game.pending_buttons_len = 1
	tank_tick()
	if !testing.expect(t, game.input.view == .Box, "the box view") do return
	tank_render()
	testing.expect(t, arena.offset > 0, "the box view formats its counts")
	for _ in 0 ..< 10 {
		step(1.0 / 120)
		testing.expect_value(t, arena.offset, 0)
	}
}
