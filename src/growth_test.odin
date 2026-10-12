#+build !js
package vc

import "core:log"
import "core:testing"

@(test)
grows_with_age :: proc(t: ^testing.T) {
	if !sim_setup(t, 31) do return
	game.life.born_at = host_time() - 2 * 86400
	spider_growth(false)
	testing.expect_value(t, game.spider.size, 48) // 40 + 2880 / 360
	game.life.born_at = host_time() - 15 * 86400
	spider_growth(false)
	testing.expect_value(t, game.spider.size, 100)
	game.life.born_at = host_time() - 40 * 86400
	spider_growth(false)
	testing.expect_value(t, game.spider.size, 100)
}

@(test)
moults_and_the_skin_crumbles :: proc(t: ^testing.T) {
	if !sim_setup(t, 32) do return
	game.life.born_at = host_time() - 6 * 86400
	k := &game.skin
	k.shed_at = game.life.born_at // hatched 6 days ago
	spider_growth(true)
	testing.expect(t, k.active, "moults on day 6")
	testing.expect_value(t, k.size, game.spider.size)
	testing.expect(t, k.y >= FLOOR_TOP && k.x >= WALL_MARGIN, "skin on the floor")
	update_render_list()
	found := false
	for c in game.render_list do if c == &k.c do found = true
	testing.expect(t, found, "skin drawn in the tank")
	tank_render()

	// moulting doesn't restart the day's wait: once the skin is gone it
	// may moult again at the next start
	shed := k.shed_at
	k.active = false
	spider_growth(true)
	testing.expect(t, k.active, "moults again")
	testing.expect_value(t, k.shed_at, shed)
	// but not within a day of a new or resurrected spider
	k.active = false
	k.shed_at = host_time() - 3600
	spider_growth(true)
	testing.expect(t, !k.active, "no moult within a day of a resurrection")
	k.shed_at = host_time() - 25 * 3600
	spider_growth(true)

	slow_anims(SKIN_STAGE)
	testing.expect_value(t, k.frame, 1)
	slow_anims(2 * SKIN_STAGE)
	testing.expect(t, !k.active, "crumbled away after 3 stages")
	game.life.born_at = host_time() - 2 * 86400
	k.shed_at = 0
	spider_growth(true)
	testing.expect(t, !k.active, "no moult before day 5")
}

@(test)
yucca_regrows_after_resurrection :: proc(t: ^testing.T) {
	if !sim_setup(t, 33) do return
	game.pending_objects[YUCCA] = 1
	tank_tick()
	spider_dies(&game.spider, 0)
	game.pending_resurrect = true
	tank_tick()
	y := &game.objects[YUCCA]
	testing.expect_value(t, y.frame, 8)
	slow_anims(YUCCA_DAY)
	testing.expect_value(t, y.frame, 7)
	slow_anims(10 * YUCCA_DAY)
	testing.expect_value(t, y.frame, 0) // full grown
}

@(test)
footprints_webs_and_clearing :: proc(t: ^testing.T) {
	if !sim_setup(t, 34) do return
	for _ in 0 ..< 3000 do tank_tick()
	prints := 0
	for f in game.footprints do if f.scale > 0 do prints += 1
	log.infof("%d footprints after 5 minutes", prints)
	testing.expect(t, prints > 0, "walking leaves footprints")
	changed := 0
	for p, i in floor_buf do if p != assets.tank.pixels[i] do changed += 1
	testing.expect(t, changed > 0, "footprints drawn into the floor")

	// lay webs, a cricket walks into one
	s := &game.spider
	s.x, s.y = 600, 300
	creature_update_position(s)
	s.step, s.plays = 1, 2
	for d in ([?]int{0, 4}) {
		s.dir = d
		spider_lay_web(s)
	}
	webs := 0
	for w in game.webs do if w.scale > 0 do webs += 1
	testing.expect_value(t, webs, 2)
	w := game.webs[0]
	game.pending_drops += 1
	tank_tick()
	cr: ^Creature
	for &c in game.crickets do if c.active && !c.in_box {cr = &c; break}
	if !testing.expect(t, cr != nil, "cricket in the tank") do return
	cr.carried = 0
	cr.x, cr.y = (w.rect.left + w.rect.right) / 2, (w.rect.top + w.rect.bottom) / 2
	creature_update_position(cr)
	cricket_web_check(cr)
	testing.expect(t, cr.web_stuck, "cricket stuck in the web")

	age_webs(WEB_PIECE_LIFE)
	webs = 0
	for p in game.webs do if p.scale > 0 do webs += 1
	testing.expect_value(t, webs, 0) // gone after two days

	add_corner_web(false)
	testing.expect(t, game.corner_webs[0].active, "corner web")
	age_webs(4 * 1440)
	testing.expect(t, !game.corner_webs[0].active, "corner web gone after 4 days")

	clear_debris()
	prints = 0
	for f in game.footprints do if f.scale > 0 do prints += 1
	testing.expect_value(t, prints, 0)
	testing.expect(t, !cr.web_stuck, "clearing frees stuck crickets")
}
