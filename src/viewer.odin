package vc

import "core:fmt"

// Animation viewer: plays any sequence/direction of the extracted animations.

ANIM_FILES :: [?]string{"spider", "plugin_spider", "cricket", "footprints", "web", "skin", "logo"}

BACKGROUND :: [3]u8{0x00, 0x80, 0x80} // Windows 98 desktop teal

state: struct {
	anims:                 [dynamic]Anim,
	palette:               [256][3]u8,
	anim, seq, dir, frame: int,
	accum, speed:          f64,
	paused:                bool,
}

indices: [MAX_W * MAX_H]u8
rgba: [MAX_W * MAX_H * 4]u8

viewer_init :: proc() -> bool {
	if pal := load_file("palette.bin"); len(pal) == 768 {
		for &c, i in state.palette do c = {pal[3 * i], pal[3 * i + 1], pal[3 * i + 2]}
	}

	for name in ANIM_FILES {
		idx := load_file(fmt.tprintf("%s.idx", name))
		pix := load_file(fmt.tprintf("%s.pix", name))
		a, ok := anim_parse(idx, pix)
		if !ok || a.w > MAX_W || a.h > MAX_H {
			fmt.eprintln("skipping animation", name)
			continue
		}
		append(&state.anims, a)
		ai := i32(len(state.anims) - 1)
		ui_add_anim(name)
		for &s in a.seqs do ui_add_seq(ai, s.name, seq_dir_mask(&s))
	}

	state.speed = 1
	viewer_select(0, 0, 0)
	return len(state.anims) > 0
}

current_dir :: proc "contextless" () -> ^Dir {
	if state.anim >= len(state.anims) do return nil
	a := &state.anims[state.anim]
	if state.seq >= len(a.seqs) do return nil
	return &a.seqs[state.seq].dirs[state.dir]
}

@(export)
viewer_select :: proc "contextless" (anim, seq, dir: i32) {
	if int(anim) >= len(state.anims) do return
	state.anim = int(anim)
	a := &state.anims[state.anim]
	state.seq = clamp(int(seq), 0, len(a.seqs) - 1)
	s := &a.seqs[state.seq]
	state.dir = clamp(int(dir), 0, DIR_COUNT - 1)
	if len(s.dirs[state.dir].frames) == 0 {
		// fall back to the first direction that has frames
		for d, k in s.dirs do if len(d.frames) > 0 {state.dir = k; break}
	}
	state.frame = 0
	state.accum = 0
}

@(export)
viewer_set_speed :: proc "contextless" (speed: f64) {
	state.speed = speed
}

@(export)
viewer_set_paused :: proc "contextless" (paused: i32) {
	state.paused = paused != 0
}

@(export)
viewer_step_frame :: proc "contextless" (delta: i32) {
	d := current_dir()
	if d == nil || len(d.frames) == 0 do return
	n := len(d.frames)
	state.frame = ((state.frame + int(delta)) % n + n) % n
}

viewer_step :: proc(dt: f64) {
	if !state.paused {
		state.accum += dt * state.speed
		if state.accum > 1 do state.accum = TICK // don't replay a backlog after a stall
		for state.accum >= TICK {
			state.accum -= TICK
			viewer_step_frame(1)
		}
	}
	viewer_render()
}

viewer_render :: proc() {
	d := current_dir()
	if d == nil || len(d.frames) == 0 do return
	a := &state.anims[state.anim]
	s := &a.seqs[state.seq]
	n := a.w * a.h
	if !frame_decode(a, s, d.frames[state.frame], indices[:n]) do return

	for i in 0 ..< n {
		v := indices[i]
		c := v == a.key ? BACKGROUND : state.palette[v]
		rgba[4 * i + 0] = c[0]
		rgba[4 * i + 1] = c[1]
		rgba[4 * i + 2] = c[2]
		rgba[4 * i + 3] = 255
	}
	present(&rgba[0], i32(a.w), i32(a.h))
	ui_status(i32(state.seq), i32(state.dir), i32(state.frame), i32(len(d.frames)))
}
