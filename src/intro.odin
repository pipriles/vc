package vc

// The opening sequence (main update 0x40ca70 while 0x4519c4 < 3):
// 0. the splash (vcg_5000, the egg) fades in from black, its palette's
//    channels rising 8 a frame (0x41ca80); 24 frames on, plus 1.5 s;
// 1. sound 415, and a spider grooming (CLEAN, facing 4) appears at
//    (160, 180) on it: pixels show once their palette index is at most a
//    threshold rising 5 / 4 / 3 a frame (10 / 14 / 18 fps; indices of 128
//    and up count as negative and always show, 0x412940); it only starts
//    moving once fully shown. 90 / 110 / 120 frames, the last 25 darkening
//    the palette 10 a frame (0x41c9b0);
// 2. the click (400) and the tank.
// A key press skips to 2. The game doesn't run meanwhile.
// (The plugin's CLEAN, which replaces the spider's, has no frames facing 4:
// the intro uses the spider's own.)

Intro :: struct {
	stage:      int, // 0..2 as above, 3 = done
	countdown:  int, // stage 0: 600 - 25 a frame; stage 1: frames left
	hold_ms:    u32, // stage 0: when the countdown ran out
	alpha:      int, // stage 1: palette index threshold, 0..127
	step:       int,
	frame:      int, // next frame to show
	seq:        int,
	shown:      int, // frame and threshold drawn this tick (taken before
	shown_alpha: int, // they advance, as the original draws then steps)
	palette:    [256][3]u8, // shown palette (fading)
}

intro: Intro = {stage = 3}

@(export)
tank_intro :: proc "contextless" () {
	intro = {stage = 0, countdown = 600, seq = -1} // the palette starts black
}

@(export)
tank_skip_intro :: proc "contextless" () {
	if intro.stage < 2 do intro.stage = 2
}

intro_active :: proc() -> bool {return intro.stage < 3}

// Once a game frame instead of the game.
intro_tick :: proc() {
	in_ := &intro
	switch in_.stage {
	case 0:
		// fade in: each channel up by 8 towards the game palette
		for c, i in state.palette do for k in 0 ..< 3 {
			v := int(in_.palette[i][k]) + 8
			in_.palette[i][k] = u8(min(v, int(c[k])))
		}
		in_.countdown = max(in_.countdown - 25, 0)
		if in_.countdown == 0 && in_.hold_ms == 0 do in_.hold_ms = max(now_ms, 1)
		if in_.hold_ms != 0 && now_ms > in_.hold_ms + 1500 {
			in_.stage = 1
			in_.frame, in_.alpha = 0, 0
			rates := [3]int{10, 14, 18}
			fps := rates[clamp(settings.frame_rate, 0, 2)]
			switch {
			case fps < 13: in_.step, in_.countdown = 5, 90
			case fps < 17: in_.step, in_.countdown = 4, 110
			case:          in_.step, in_.countdown = 3, 120
			}
			in_.seq = intro_seq()
			// starting on the last frame, so it moves from frame 0
			if in_.seq >= 0 do in_.frame = len(assets.spider.seqs[in_.seq].dirs[4].frames) - 1
			in_.shown, in_.shown_alpha = in_.frame, 0
			host_sound(415)
		}
	case 1:
		in_.shown, in_.shown_alpha = in_.frame, in_.alpha
		if in_.alpha > 126 do in_.frame += 1
		in_.alpha = min(in_.alpha + in_.step, 127)
		in_.countdown -= 1
		if in_.countdown < 1 {
			in_.stage = 2
		} else if in_.countdown < 25 {
			// fade out: every channel down by 10 (not below 1)
			for &c in in_.palette do for k in 0 ..< 3 do c[k] = u8(max(int(c[k]) - 10, 1))
		}
	case 2:
		in_.stage = 3
		host_sound(400)
	}
}

// The spider's own CLEAN (the first of that name), which faces 4.
intro_seq :: proc() -> int {
	a := &assets.spider
	for s, i in a.seqs do if s.name == "CLEAN" && len(s.dirs[4].frames) > 0 do return i
	return -1
}

intro_render :: proc() {
	in_ := &intro
	dst = view_surface()
	splash := &assets.splash
	for i in 0 ..< VIEW_W * VIEW_H do view[i] = 0
	if len(splash.pixels) == VIEW_W * VIEW_H do copy(view[:], splash.pixels)
	if in_.stage >= 1 && in_.seq >= 0 {
		a := &assets.spider
		s := &a.seqs[in_.seq]
		d := &s.dirs[4]
		f := d.frames[in_.shown % len(d.frames)]
		buf := frame_buf[:a.w * a.h]
		if frame_decode(a, s, f, buf) {
			key := frame_key(a, buf)
			for j in 0 ..< a.h do for i in 0 ..< a.w {
				p := buf[j * a.w + i]
				// signed byte compare, as the original: 128..255 always show
				if p == key || (p < 128 && int(p) > in_.shown_alpha) do continue
				x, y := 160 + i, 180 + j
				if x < VIEW_W && y < VIEW_H do view[y * VIEW_W + x] = p
			}
		}
	}
	ui_begin()
	present_view(&in_.palette)
}
