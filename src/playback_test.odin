#+build !js
package vc

import "core:testing"

// Steps one creature's frames the way creature_tick does, without the
// AI: returns the frames shown, or false if a frame left the direction.
@(private = "file")
play_through :: proc(c: ^Creature, seq, dir, plays: int) -> (shown: [dynamic]int, ok: bool) {
	c.seq, c.dir, c.plays, c.step = seq, dir, plays, 1
	c.bounces, c.back_pass, c.run = 0, 0, false
	start_sequence(c)
	n := len(creature_dir(c).frames)
	append(&shown, c.frame)
	for _ in 0 ..< 10_000 {
		c.frame += c.step
		if c.frame < 0 || c.frame >= n do c.left = 0
		c.left -= 1
		if c.left < 1 && sequence_play_done(c) do return shown, true
		if c.frame < 0 || c.frame >= n do return shown, false
		append(&shown, c.frame)
	}
	return shown, false
}

@(test)
playback_stays_in_range :: proc(t: ^testing.T) {
	if !sim_setup(t, 7) do return
	c := &game.spider
	game.stats.temperament = 7 // most bounces
	for s, seq in c.anim.seqs {
		if seq == game.seq.circle do continue
		for dir in 0 ..< 8 {
			if len(s.dirs[dir].frames) == 0 do continue
			shown, ok := play_through(c, seq, dir, 2)
			defer delete(shown)
			testing.expectf(t, ok, "%s d%d: frame out of range after %d frames", s.name, dir, len(shown))
		}
	}
}

@(test)
crush_taps_then_plays_back :: proc(t: ^testing.T) {
	if !sim_setup(t, 3) do return
	c := &game.spider
	ids := &game.seq
	game.stats.temperament = 2
	dir := -1
	for d in 0 ..< 8 do if c.anim.seqs[ids.crush].dirs[d].pp_always {dir = d; break}
	if !testing.expect(t, dir >= 0, "a CRUSH direction plays back") do return
	shown, ok := play_through(c, ids.crush, dir, 3)
	defer delete(shown)
	if !testing.expect(t, ok, "CRUSH stays in range") do return
	n := len(c.anim.seqs[ids.crush].dirs[dir].frames)
	// forward once, at least (2 + 2) * 8 + 8 = 40 bounces over the last two
	// frames, then back to frame 1 (the pass counts n - 1 frames, so the
	// play ends as it reaches 0); a single play whatever was asked
	for f, i in shown[:n] do testing.expectf(t, f == i, "forward pass: frame %d is %d", i, f)
	testing.expect_value(t, shown[len(shown) - 1], 1)
	tail := 0
	for f in shown[n:] do if f >= n - 2 do tail += 1
	testing.expectf(t, tail >= 40, "only %d tail frames", tail)
	testing.expectf(t, len(shown) < n + 40 * 3 + 2 * n, "%d frames: more than one play", len(shown))
}

@(test)
glass_climb_comes_back_down_at_a_fixed_scale :: proc(t: ^testing.T) {
	if !sim_setup(t, 12) do return
	s := &game.spider
	s.size = 60 // small enough that the depth scale would change with y
	s.x, s.y = 600, (100 - s.size) / 2 + GLASS_Y
	s.prev_x, s.prev_y = s.x, s.y
	creature_update_position(s)
	clear_queue(s)
	clear_goal(s)
	enqueue_anim(s, game.seq.glass, 4, 1, flush = true)
	s.plays = 1
	s.left = 0
	y0 := s.y
	started, done := false, false
	top := y0
	locked_scale := -1
	scale_kept := true
	ups, downs_back := 0, 0 // moves up the glass forward, back down on the way back
	for _ in 0 ..< 3000 {
		prev_y, prev_frame, prev_step := s.y, s.frame, s.step
		creature_tick(s)
		if s.seq == game.seq.glass && s.dir == 4 {
			started = true
			top = min(top, s.y)
			if prev_frame >= 19 && prev_frame <= 28 {
				if prev_step > 0 && s.y < prev_y do ups += 1
				if prev_step < 0 && s.y > prev_y do downs_back += 1
			}
			if creature_dir(s).frames[s.frame].lock_scale {
				if locked_scale < 0 do locked_scale = s.scale
				scale_kept &&= s.scale == locked_scale
			} else {
				locked_scale = -1
			}
		} else if started {
			done = true
			break
		}
	}
	testing.expect(t, done, "GLASS played and ended")
	testing.expectf(t, top < y0 - 5, "climbed up the glass (top %d, start %d)", top, y0)
	testing.expectf(t, ups >= 9 && downs_back >= 9, "up the glass and back down (%d up, %d down)", ups, downs_back)
	testing.expect(t, scale_kept, "scale held while climbing")
}
