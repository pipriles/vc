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
	floor := c.no_clamp ? HIDE_Y : c.seq == game.seq.log_hide ? FLOOR_TOP - 10 : FLOOR_TOP
	ok := c.x >= WALL_MARGIN && c.x <= TANK_W - WALL_MARGIN && c.y >= floor &&
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

@(test)
whole_tank_and_close_up :: proc(t: ^testing.T) {
	if !sim_setup(t, 11) do return
	game.pending_buttons[0] = Button(1)
	game.pending_buttons_len = 1
	tank_tick()
	testing.expect(t, game.input.view == .Whole && game.input.tool == .Pickup, "zoom out: whole tank with the pick-up tool")
	for _ in 0 ..< 3 do tank_render()

	// drag the bell (cell 1) from the panel into the tank
	cx, cy := cell_rect(BELL)
	press(.Down, cx + 40, cy + 40)
	press(.Move, 400, 200)
	press(.Up, 400, 200)
	tank_tick()
	bell := &game.objects[BELL]
	testing.expect(t, !bell.in_box, "bell placed in the tank")
	tx, ty := whole_to_tank(400, 200)
	testing.expectf(t, abs(bell.x - tx) < 2 && bell.y >= FLOOR_TOP, "bell near (%d, %d): (%d, %d)", tx, ty, bell.x, bell.y)

	// and the bowl back into the panel
	bowl := &game.objects[BOWL]
	bx, by := bowl.x * VIEW_W / TANK_W, bowl.y * WHOLE_H / VIEW_H
	press(.Down, bx, by)
	press(.Move, bx, 300)
	press(.Up, bx, 300)
	tank_tick()
	testing.expect(t, bowl.in_box, "bowl dragged back into the panel")

	// a click on empty space returns to the tank and restores the tool
	press(.Down, 5, 470)
	tank_tick()
	testing.expect(t, game.input.view == .Tank && game.input.tool == .Tap, "back to the tank")

	game.pending_buttons[0] = Button(0)
	game.pending_buttons_len = 1
	tank_tick()
	testing.expect(t, game.input.view == .Close, "zoom in: close-up")
	tank_render()
	press(.Down, 100, 100)
	tank_tick()
	testing.expect(t, game.input.view == .Tank, "click leaves the close-up")
}

@(test)
edges_dont_scroll_unless_carrying :: proc(t: ^testing.T) {
	if !sim_setup(t, 8) do return
	game.follow = false
	game.scroll_x = 300
	pointer_event(.Move, VIEW_W - 5, 300)
	pointer_event(.Move, 5, 300)
	for _ in 0 ..< 10 do tank_tick()
	testing.expect_value(t, game.scroll_x, 300)
}

@(test)
held_spider_stays_on_pickup :: proc(t: ^testing.T) {
	if !sim_setup(t, 12) do return
	s := &game.spider
	pickup_at(s.x, s.y)
	other := 0
	for i in 0 ..< 1200 { // two minutes in the hand
		carry_move(400 + (i * 7) % 400, 300)
		tank_advance(TICK)
		if s.carried == 1 && s.seq != game.seq.pickup do other += 1
	}
	testing.expectf(t, other == 0, "%d ticks on other animations while held", other)
}

@(test)
any_tool_but_the_tap_drags_crickets :: proc(t: ^testing.T) {
	if !sim_setup(t, 45) do return
	s := &game.spider
	s.x, s.y = 1000, 300
	creature_update_position(s)
	cr := &game.crickets[0]
	cr.in_box = false
	cr.x, cr.y = 400, 350
	cr.prev_x, cr.prev_y = cr.x, cr.y
	creature_update_position(cr)
	game.scroll_x = 0
	for tool in ([?]Tool{.Prod, .Stroke, .Follow, .Tap}) {
		game.input.tool = tool
		game.input.carry = .None
		cr.carried = 0
		pointer_event(.Down, cr.x, cr.y)
		dragged := game.input.carry == .Cricket
		testing.expectf(t, dragged == (tool != .Tap), "%v drags the cricket: %v", tool, dragged)
		pointer_event(.Up, cr.x, cr.y)
	}
}

@(test)
no_drinking_from_a_bowl_being_dragged :: proc(t: ^testing.T) {
	if !sim_setup(t, 46) do return
	s := &game.spider
	clear_goal(s)
	clear_queue(s)
	s.x, s.y, s.dir = 600, 300, 4
	s.prev_x, s.prev_y = s.x, s.y
	creature_update_position(s)
	game.stats.water = 30
	bowl := &game.objects[BOWL]
	bowl.frame = bowl.def.frames - 1
	game.scroll_x = 0
	game.input.tool = .Pickup
	bowl.x, bowl.y = 900, 400
	object_update_position(bowl)
	pointer_event(.Down, bowl.x, bowl.y)
	testing.expect(t, game.input.carry == .Object && game.input.carry_id == BOWL, "dragging the bowl")
	// held right under the spider's mouth
	for _ in 0 ..< 20 {
		pointer_event(.Move, s.x, s.y + 60)
		creature_update_position(s)
	}
	testing.expect_value(t, game.stats.water, 30)
	pointer_event(.Up, s.x, s.y + 60)
	testing.expect_value(t, bowl.carried, 0)
}
