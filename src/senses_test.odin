#+build !js
package vc

import "core:log"
import "core:testing"

@(private = "file")
put_cricket :: proc(i, x, y: int) -> ^Creature {
	c := &game.crickets[i]
	c.active, c.in_box, c.carried = true, false, 0
	c.x, c.y = x, y
	c.prev_x, c.prev_y = x, y
	clear_queue(c)
	creature_update_position(c)
	return c
}

@(private = "file")
put_spider :: proc(x, y: int) -> ^Creature {
	s := &game.spider
	s.x, s.y = x, y
	s.prev_x, s.prev_y = x, y
	clear_queue(s)
	clear_goal(s)
	creature_update_position(s)
	game.senses.area_x, game.senses.area_y, game.senses.area_ms = x, y, now_ms
	return s
}

@(test)
hungry_spider_stalks_and_catches_a_cricket :: proc(t: ^testing.T) {
	if !sim_setup(t, 31) do return
	game.stats.food = 15
	s := put_spider(500, 330)
	put_cricket(0, 760, 360)
	eaten := game.eaten
	stalked, froze := false, false
	for _ in 0 ..< 1200 { // two minutes
		tank_advance(TICK)
		stalked ||= game.senses.hunt == .Stalk
		froze ||= game.senses.hunt == .Freeze
		if game.eaten > eaten do break
	}
	_ = s
	testing.expect(t, stalked, "it stalked the cricket")
	testing.expect(t, froze, "it froze before pouncing")
	testing.expect(t, game.eaten > eaten, "and ate it")
}

@(test)
spider_doesnt_notice_a_cricket_far_away :: proc(t: ^testing.T) {
	if !sim_setup(t, 32) do return
	game.stats.food = 45
	put_spider(250, 330)
	put_cricket(0, 1000, 300)
	for _ in 0 ..< 100 { // ten seconds
		tank_advance(TICK)
		testing.expect(t, game.senses.hunt == .None, "stalking a cricket it can't have noticed")
		if game.senses.hunt != .None do break
	}
}

@(test)
thirsty_spider_finds_a_bowl_it_hasnt_seen :: proc(t: ^testing.T) {
	if !sim_setup(t, 33) do return
	bowl := &game.objects[BOWL]
	bowl.x, bowl.y = 1000, 300
	object_update_position(bowl)
	put_spider(200, 330)
	game.senses.bowl_known = false
	game.stats.water = 30
	drank := false
	for _ in 0 ..< 6000 { // ten minutes
		before := game.stats.water
		tank_advance(TICK)
		if game.stats.water > before {drank = true; break}
	}
	log.infof("bowl known %v, water %d", game.senses.bowl_known, game.stats.water)
	testing.expect(t, game.senses.bowl_known, "it found the bowl")
	testing.expect(t, drank, "and drank")
}

@(test)
route_goes_round_a_line_of_objects :: proc(t: ^testing.T) {
	if !sim_setup(t, 34) do return
	game.objects[BOWL].in_box = true // only the rocks in the way
	s := put_spider(300, 330)
	// rocks in a column between the spider and the target, leaving a gap
	// only at the top
	ids := [?]int{2, 3, 6}
	for id, i in ids {
		o := &game.objects[id]
		o.active, o.in_box = true, false
		o.x, o.y = 600, 300 + i * 70
		object_update_position(o)
	}
	wx, wy, ex, ey, ok := plan_route(s, 900, 360)
	testing.expect(t, ok, "a route")
	testing.expectf(t, abs(ex - 900) <= GRID && abs(ey - 360) <= GRID, "reaching the target (ends at %d,%d)", ex, ey)
	testing.expectf(t, wy <= s.y, "heading up round the rocks first (next %d,%d)", wx, wy)
}

@(test)
glass_trip_goes_round_an_obstacle_by_the_wall :: proc(t: ^testing.T) {
	if !sim_setup(t, 35) do return
	game.objects[BOWL].in_box = true
	s := put_spider(154, 300)
	// rocks right under it and below-right, as in a stuck run seen in
	// the browser ("detour: 3 blocked, going 6" until it timed out)
	for r in ([?]struct {id, x, y: int}{{2, 175, 385}, {3, 300, 400}}) {
		o := &game.objects[r.id]
		o.active, o.in_box = true, false
		o.x, o.y = r.x, r.y
		object_update_position(o)
	}
	glass_y := (100 - s.size) / 2 + GLASS_Y
	move_to(s, .Y_Band, s.x, glass_y, 4, game.seq.glass, 60)
	reached := false
	for _ in 0 ..< 600 { // a minute
		tank_advance(TICK)
		if s.y >= glass_y - 25 {reached = true; break}
	}
	testing.expectf(t, reached, "never got to the glass (y %d, glass %d)", s.y, glass_y)
}

@(test)
cricket_out_of_reach_is_brought_back :: proc(t: ^testing.T) {
	if !sim_setup(t, 36) do return
	s := put_spider(250, 330)
	// a cricket boxed in by rocks, far from the spider
	cr := put_cricket(0, 900, 330)
	for r in ([?]struct {id, x, y: int}{{2, 840, 330}, {3, 960, 330}, {6, 900, 260}, {5, 900, 410}, {4, 845, 250}}) {
		o := &game.objects[r.id]
		o.active, o.in_box = true, false
		o.x, o.y = r.x, r.y
		object_update_position(o)
	}
	grid_reach(s)
	testing.expect(t, !grid_near_reached(cr.x, cr.y), "the setup puts it out of reach")
	reached := false
	for _ in 0 ..< 300 { // thirty seconds
		tank_advance(TICK)
		grid_reach(s)
		if grid_near_reached(cr.x, cr.y) {reached = true; break}
	}
	testing.expectf(t, reached, "still out of reach at (%d, %d)", cr.x, cr.y)
}

@(test)
cricket_command_drops_one :: proc(t: ^testing.T) {
	if !sim_setup(t, 37) do return
	before := crickets_in_tank()
	for ch in transmute([]u8)string("CRICKET") do tank_char(i32(ch))
	tank_char(13)
	tank_tick()
	testing.expect_value(t, crickets_in_tank(), before + 1)
}
