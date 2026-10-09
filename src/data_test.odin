#+build !js
package vc

import "core:fmt"
import "core:log"
import "core:testing"

// Checks against the original game data in data/{cr,rk} (skipped when
// absent; create it with tools/extract.py).

ANIMS :: [?]string{"spider", "plugin_spider", "cricket", "footprints", "web", "skin", "logo"}

load_anim :: proc(name: string) -> (Anim, bool) {
	return anim_parse(
		load_file(fmt.tprintf("%s.idx", name)),
		load_file(fmt.tprintf("%s.pix", name)),
	)
}

have_data :: proc(t: ^testing.T, variant: string) -> bool {
	data_dir = fmt.tprintf("data/%s", variant)
	if file_size("spider.idx") < 0 {
		log.infof("no extracted data in %s, skipping", data_dir)
		return false
	}
	return true
}

@(test)
spider_index_shape :: proc(t: ^testing.T) {
	if !have_data(t, "cr") do return
	a, ok := load_anim("spider")
	testing.expect(t, ok)
	testing.expect_value(t, a.name, "SPIDER")
	testing.expect_value(t, a.w, 320)
	testing.expect_value(t, a.h, 200)
	testing.expect_value(t, a.key, 7)
	names := [?]string{"CIRCLE", "WALK", "LURK", "LURK_D", "CRUSH", "THREAT", "CLEAN",
		"PICKUP", "DROP", "CATCH", "CATCH_RESET", "KILL", "KILL_RESET", "DEAD"}
	testing.expect_value(t, len(a.seqs), len(names))
	for n, i in names do testing.expect_value(t, a.seqs[i].name, n)
	for d in a.seqs[0].dirs do testing.expect_value(t, len(d.frames), 12) // CIRCLE: all 8 dirs
	walk := a.seqs[1].dirs[0]
	testing.expect(t, walk.move_x && walk.move_y, "WALK moves")
	testing.expect_value(t, walk.key2, 0x31)
	testing.expect(t, a.seqs[1].rand_repeat && a.seqs[1].max_repeat == 7)
}

// Every frame must decode to exactly w*h pixels. The index also stores a
// box per frame (top-down, x1 inclusive, y1 exclusive); it is a hit area,
// not always tight (THREAT reuses frame 0's box while rearing up), but most
// frames match their content exactly. Matching in our orientation and not
// when flipped independently confirms the bottom-up row order.
@(test)
frames_decode_within_stored_box :: proc(t: ^testing.T) {
	for variant in ([?]string{"cr", "rk"}) {
		if !have_data(t, variant) do continue
		buf := make([]u8, MAX_W * MAX_H)
		defer delete(buf)
		frames, matched, matched_flipped := 0, 0, 0
		for name in ANIMS {
			a, ok := load_anim(name)
			testing.expectf(t, ok, "%s/%s parses", variant, name)
			if !ok do continue
			for &s in a.seqs {
				for d in s.dirs {
					for f in d.frames {
						frames += 1
						n := a.w * a.h
						if !testing.expectf(t, frame_decode(&a, &s, f, buf[:n]), "%s %s decodes", name, s.name) do continue
						x0, y0, x1, y1 := a.w, a.h, -1, -1
						for y in 0 ..< a.h do for x in 0 ..< a.w {
							if buf[y * a.w + x] == a.key do continue
							x0, y0 = min(x0, x), min(y0, y)
							x1, y1 = max(x1, x), max(y1, y)
						}
						if x1 < 0 do continue // empty frame
						b := f.box
						near :: proc(a: int, b: i32) -> bool {return abs(a - int(b)) <= 1}
						x_ok := near(x0, b[0]) && near(x1, b[2])
						if x_ok && near(y0, b[1]) && near(y1 + 1, b[3]) do matched += 1
						fy0, fy1 := a.h - 1 - y1, a.h - 1 - y0 // same content, rows flipped
						if x_ok && near(fy0, b[1]) && near(fy1 + 1, b[3]) do matched_flipped += 1
					}
				}
			}
		}
		log.infof("%s: %d frames, %d match their box, %d would match flipped",
			variant, frames, matched, matched_flipped)
		testing.expectf(t, matched * 100 >= frames * 85, "%s: only %d/%d frames match", variant, matched, frames)
		testing.expectf(t, matched_flipped * 100 <= frames * 5, "%s: %d frames match flipped", variant, matched_flipped)
	}
}

@(test)
plugin_merge_is_last_wins :: proc(t: ^testing.T) {
	if !have_data(t, "cr") do return
	base, _ := load_anim("spider")
	plug, _ := load_anim("plugin_spider")
	m := anim_merge(base, plug)
	testing.expect_value(t, len(m.seqs), len(base.seqs) + len(plug.seqs))
	testing.expect(t, seq_find(&m, "CRUSH") >= len(base.seqs), "plugin CRUSH overrides base")
	testing.expect(t, seq_find(&m, "GLASS") >= len(base.seqs), "plugin-only sequence found")
	testing.expect(t, seq_find(&m, "WALK") < len(base.seqs))
}

@(test)
glass_frames_draw_without_their_green_background :: proc(t: ^testing.T) {
	if !sim_setup(t, 1) do return
	s := &game.spider
	s.seq, s.dir, s.size, s.scale = game.seq.glass, 4, 100, 100
	n := len(creature_dir(s).frames)
	testing.expect(t, n > 0, "GLASS faces 4")
	for f in 0 ..< n {
		s.frame = f
		dst = tank_surface()
		for &p in tank_buf do p = 0
		draw_creature(s, .Body, 0)
		green := 0
		for p in tank_buf do if p == 250 do green += 1
		testing.expectf(t, green < 50, "frame %d drew %d green pixels", f, green)
		if green >= 50 do break
	}
}
