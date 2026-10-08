#+build !js
package vc

import "core:log"
import "core:testing"

press :: proc(ev: Pointer_Event, x, y: int) {
	game.pending_pointer[game.pending_pointer_len] = {ev, x, y}
	game.pending_pointer_len += 1
}

check_spider_ok :: proc(t: ^testing.T, tick: int) -> bool {
	c := &game.spider
	frames := len(c.anim.seqs[c.seq].dirs[c.dir].frames)
	ok := c.x >= WALL_MARGIN && c.x <= TANK_W - WALL_MARGIN && c.y >= (c.no_clamp ? HIDE_Y : FLOOR_TOP) &&
		c.y < VIEW_H && frames > 0 && c.frame >= 0 && c.frame < frames
	return testing.expectf(t, ok, "tick %d: bad spider state x=%d y=%d seq=%s frame=%d/%d",
		tick, c.x, c.y, seq_name(c, c.seq), c.frame, frames)
}

@(test)
tools_on_the_spider :: proc(t: ^testing.T) {
	if !sim_setup(t, 99) do return
	s := &game.spider
	reactions, moods := 0, map[int]bool{}
	defer delete(moods)
	picked, dropped := false, false

	for i in 0 ..< 20_000 {
		phase := (i / 400) % 4
		vx, vy := s.x - game.scroll_x, s.y
		switch phase {
		case 0, 1: // stroke, then prod: hold the button on the spider
			game.input.tool = phase == 0 ? .Stroke : .Prod
			if i % 400 == 0 || i % 400 == 200 do press(.Down, vx, vy)
			press(.Move, vx, vy)
			if i % 400 == 199 || i % 400 == 399 do press(.Up, vx, vy)
		case 2: // tap on the glass anywhere
			game.input.tool = .Tap
			if i % 400 == 0 do press(.Down, 320, 400)
			if i % 400 == 399 do press(.Up, 320, 400)
		case 3: // pick the spider up, carry it, drop it
			game.input.tool = .Pickup
			if i % 400 == 0 do press(.Down, vx, vy)
			if game.input.carry == .Spider {
				picked = true
				press(.Move, 300 + (i % 100), 350)
			}
			if i % 400 == 60 {
				press(.Up, 300, 350)
				dropped = true
			}
		}
		before := s.last_react
		tank_tick()
		if s.last_react != before do reactions += 1
		moods[game.stats.mood] = true
		if !check_spider_ok(t, i) do return
	}
	log.infof("reactions %d, distinct moods %d, mood now %d", reactions, len(moods), game.stats.mood)
	testing.expect(t, reactions > 20, "spider reacts to the tools")
	testing.expect(t, len(moods) > 5, "tools change the mood")
	testing.expect(t, picked && dropped, "spider picked up and dropped")
	testing.expect(t, game.spider.carried == 0, "carry state cleared after the drop")
}

@(test)
feed_from_the_box :: proc(t: ^testing.T) {
	if !sim_setup(t, 7) do return
	game.stats.food = 100 // full: it won't eat the cricket straight away
	game.pending_buttons[0] = .Feed
	game.pending_buttons_len = 1
	tank_tick()
	testing.expect(t, game.input.view == .Box, "feed opens the box")
	for _ in 0 ..< 10 do tank_tick() // crickets move in the box view
	c: ^Creature
	for &cr in game.crickets do if cr.active && cr.in_box {c = &cr; break}
	if !testing.expect(t, c != nil, "a cricket in the box") do return
	press(.Down, c.x, c.y)
	tank_tick()
	testing.expect(t, game.input.view == .Tank, "back to the tank carrying it")
	testing.expect(t, game.input.carry == .Cricket && !c.in_box, "cricket carried")
	// release it in view, as far from the spider as possible (any touch is a catch)
	game.follow = false
	game.scroll_x = game.spider.x < TANK_W / 2 ? TANK_W - VIEW_W : 0
	rx := game.spider.x < TANK_W / 2 ? 560 : 80
	press(.Move, rx, 420)
	press(.Up, rx, 420)
	for _ in 0 ..< 60 do tank_tick()
	testing.expectf(t, crickets_in_tank() == 1, "cricket released into the tank (eaten %d)", game.eaten)
	testing.expect(t, c.carried == 0, "cricket finished dropping")
}
