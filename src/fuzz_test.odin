#+build !js
package vc

import "core:fmt"
import "core:testing"

// Random input through the real entry points (pointer, tools, buttons,
// typed commands, objects, the box, save and reload, catch-up, new spider),
// with the invariants checked after every tick. Fixed seeds, so a failure
// names the seed and tick and replays the same way. Found the placement
// bugs where a catch-up or a cricket rescue left creatures out of bounds.

@(private = "file")
fuzz_state: u32

// xorshift, separate from the game's rng so the input doesn't change it
@(private = "file")
fuzz_n :: proc(n: int) -> int {
	fuzz_state ~= fuzz_state << 13
	fuzz_state ~= fuzz_state >> 17
	fuzz_state ~= fuzz_state << 5
	return int(fuzz_state % u32(max(n, 1)))
}

@(private = "file")
FUZZ_WORDS := [?]string{"VENUS", "FLYTRAP", "BUFFALO", "PARKER", "DIET", "SAHARA", "PARTY", "LANDOFTHEGIANTS",
	"MICROCOSM", "JARVIS", "VINNIE", "OLIVER", "SWAMPY", "SURFER", "FLINT", "SHOWFPS", "KAMIKAZE",
	"URSULLA", "GLOBALBEACH", "CRICKET"}

// Every creature on a valid frame and inside its bounds, sane counts.
@(private = "file")
fuzz_check :: proc(t: ^testing.T, at: string) -> bool {
	s := &game.spider
	if s.seq < 0 || s.seq >= len(s.anim.seqs) || s.dir < 0 || s.dir > 7 {
		return testing.expectf(t, false, "%s: spider seq %d dir %d", at, s.seq, s.dir)
	}
	if n := len(s.anim.seqs[s.seq].dirs[s.dir].frames); n == 0 || s.frame < 0 || s.frame >= n {
		return testing.expectf(t, false, "%s: spider %s dir %d frame %d of %d", at, seq_name(s, s.seq), s.dir, s.frame, n)
	}
	if s.carried == 0 && (s.x < WALL_MARGIN || s.x > TANK_W - WALL_MARGIN || s.y < HIDE_Y || s.y >= VIEW_H) {
		return testing.expectf(t, false, "%s: spider at (%d, %d), hide %d", at, s.x, s.y, s.hide)
	}
	if s.queue_len < 0 || s.queue_len > QUEUE_LEN || s.scale < 5 || s.scale > 100 {
		return testing.expectf(t, false, "%s: queue %d, scale %d", at, s.queue_len, s.scale)
	}
	for &c in game.crickets {
		if !c.active do continue
		if c.seq < 0 || c.seq >= len(c.anim.seqs) || c.dir < 0 || c.dir > 7 {
			return testing.expectf(t, false, "%s: cricket %d seq %d dir %d", at, c.id, c.seq, c.dir)
		}
		if n := len(c.anim.seqs[c.seq].dirs[c.dir].frames); n == 0 || c.frame < 0 || c.frame >= n {
			return testing.expectf(t, false, "%s: cricket %d %s dir %d frame %d of %d", at, c.id, seq_name(&c, c.seq), c.dir, c.frame, n)
		}
		if c.carried != 0 do continue
		out := c.in_box ? (c.x < 50 || c.x > 590 || c.y < 286 || c.y > 460) : (c.x < 80 || c.x > TANK_W - 80 || c.y < 180 || c.y >= VIEW_H)
		if out do return testing.expectf(t, false, "%s: cricket %d at (%d, %d), in the box %v", at, c.id, c.x, c.y, c.in_box)
	}
	if game.storage < 0 || crickets_in_tank() > MAX_IN_TANK + 1 {
		return testing.expectf(t, false, "%s: storage %d, %d crickets in the tank", at, game.storage, crickets_in_tank())
	}
	return true
}

// One random action.
@(private = "file")
fuzz_act :: proc(t: ^testing.T) -> bool {
	switch fuzz_n(16) {
	case 0, 1, 2, 3:
		ev := Pointer_Event(fuzz_n(5))
		x, y := fuzz_n(660) - 10, fuzz_n(500) - 10
		if fuzz_n(3) == 0 { 	// near the spider, where the tools do something
			s := &game.spider
			x, y = s.x - game.scroll_x + fuzz_n(40) - 20, s.y + fuzz_n(40) - 20
		}
		tank_pointer(ev, i32(x), i32(y))
	case 4:
		game.input.tool = Tool(fuzz_n(TOOL_COUNT))
	case 5:
		buttons := [?]Button{.Scan_Follow, .Feed, .Next_Tool, .Water, .Clear, .Tank, Button(0), Button(1), Button(6)}
		tank_button(buttons[fuzz_n(len(buttons))])
	case 6:
		if fuzz_n(20) == 0 {
			for ch in transmute([]u8)FUZZ_WORDS[fuzz_n(len(FUZZ_WORDS))] do tank_char(i32(ch))
			tank_char(13)
		}
	case 7:
		tank_set_object(i32(fuzz_n(OBJECT_COUNT)), i32(fuzz_n(2)))
	case 8:
		if fuzz_n(10) == 0 do game.pending_drops += 1
	case 9:
		keys := [?]i32{'+', '-', 27, 37, 39, 8, 46}
		tank_key(keys[fuzz_n(len(keys))])
	case 10:
		if fuzz_n(50) == 0 {
			tank_save()
			tank_reset()
			if !testing.expect(t, load_game(), "reload the save") do return false
		}
	case 11:
		if fuzz_n(30) == 0 do catch_up(fuzz_n(3000) + 1, host_time() - 3 * 3600)
	case 12:
		if fuzz_n(400) == 0 && game.life.dead do game.pending_resurrect = true
	case 13:
		if fuzz_n(50) == 0 do game.stats.food, game.stats.water = fuzz_n(101), fuzz_n(101)
	case 14:
		if game.ui.box.state != .Closed do box_pointer(Pointer_Event(fuzz_n(3)), fuzz_n(640), fuzz_n(480))
	case 15:
		if fuzz_n(1000) == 0 do tank_new_spider()
	}
	return true
}

@(private = "file")
fuzz_run :: proc(t: ^testing.T, variant: string, seed: u32, ticks: int) -> bool {
	now_ms = 0
	settings = {frame_rate = 0}
	saved_json = ""
	death_notice, low_crickets_notice = 20, 20
	cmd = {}
	if !testing.expect(t, tank_init(), "tank_init") do return false
	mode, running = .Tank, true
	rng.seed = seed
	fuzz_state = seed * 2654435761 + 1
	for i in 0 ..< ticks {
		if fuzz_n(4) == 0 && !fuzz_act(t) do return false
		tank_tick()
		if i % 50 == 0 do tank_render() // the drawing code too, now and then
		if !fuzz_check(t, fmt.tprintf("%s seed %d tick %d", variant, seed, i)) do return false
		free_all(context.temp_allocator)
	}
	return true
}

// The seeds include ones that hit the placement bugs (cr 2 after a
// catch-up; cr 21, 40, 47 and rk 17 in a rescue).
@(test)
fuzz_random_input_keeps_the_invariants :: proc(t: ^testing.T) {
	seeds := [2][4]u32{{2, 21, 40, 47}, {1, 2, 3, 17}}
	for variant, v in ([2]string{"cr", "rk"}) {
		// a string literal: data_dir must outlive the temp allocator
		data_dir = v == 1 ? "data/rk" : "data/cr"
		data_variant = variant
		assets.loaded = false // load this variant's animations and bitmaps
		if file_size("spider.idx") < 0 do continue // no extracted data
		for seed in seeds[v] {
			if !fuzz_run(t, variant, seed, 6000) do break
		}
	}
	// the next test gets the Chile Rose back, and no typed cheats left on
	data_dir, data_variant = "data/cr", "cr"
	assets.loaded = false
	cmd = {}
}
