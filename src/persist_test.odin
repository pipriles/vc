#+build !js
package vc

import "core:log"
import "core:testing"

@(test)
save_load_round_trip :: proc(t: ^testing.T) {
	if !sim_setup(t, 21) do return
	for i in 0 ..< 3000 {
		if i % 600 == 0 do game.pending_drops += 1
		tank_tick()
	}
	game.pending_objects[BELL] = 1
	tank_tick()
	before := make_save()
	tank_save()
	testing.expect(t, len(saved_json) > 100, "save written")

	// a fresh tank, then load what was saved (native host_time is 0, so no catch-up)
	tank_reset()
	testing.expect(t, load_game(), "save loaded")
	after := make_save()
	testing.expect_value(t, after.spider, before.spider)
	testing.expect_value(t, after.food, before.food)
	testing.expect_value(t, after.water, before.water)
	testing.expect_value(t, after.mood, before.mood)
	testing.expect_value(t, after.crickets, before.crickets)
	testing.expect_value(t, after.objects, before.objects)
	testing.expect_value(t, after.eaten, before.eaten)
	testing.expect_value(t, after.seed, before.seed)
}

@(test)
one_day_away :: proc(t: ^testing.T) {
	if !sim_setup(t, 5) do return
	st := &game.stats
	st.food, st.water = 60, 60
	bowl := &game.objects[BOWL]
	bowl.frame = 4
	catch_up(24 * 60, 0)
	log.infof("after a day: food %d water %d health %d bowl %d", st.food, st.water, st.health, bowl.frame)
	// food -2 per 120 min, water -2 per 150 min, refilled from the bowl below 80
	testing.expect(t, st.food < 60 && st.food >= 30, "food went down about 24")
	testing.expect(t, bowl.frame < 4, "drank from the bowl")
	testing.expect(t, !game.life.dead, "survives a day")
}

@(test)
starves_while_away :: proc(t: ^testing.T) {
	if !sim_setup(t, 6) do return
	game.objects[BOWL].frame = 0
	catch_up(5 * 24 * 60, 1_000_000)
	testing.expect(t, game.life.dead, "five days without care: dead")
	testing.expect(t, game.life.died_at > 1_000_000 && game.life.died_at < 1_000_000 + 5 * 86400, "date of death within the absence")
	log.infof("died %.1f hours in", (game.life.died_at - 1_000_000) / 3600)

	for _ in 0 ..< 50 do tank_tick()
	s := &game.spider
	testing.expect(t, s.seq == game.seq.dead && s.frame == 0, "lies still on DEAD")
	testing.expect(t, !spider_pickable(s), "can't be picked up")
	testing.expect(t, last_message == "YOUR CREATURE HAS DIED!", "death notice shown")
	food := game.stats.food
	for _ in 0 ..< 1000 do tank_tick()
	testing.expect_value(t, game.stats.food, food)

	// resurrection: crickets are still in the box
	game.pending_resurrect = true
	for _ in 0 ..< 100 do tank_tick()
	testing.expect(t, !game.life.dead, "resurrected")
	testing.expect_value(t, game.life.resurrections, 1)
	testing.expect_value(t, s.size, 40)
	testing.expect(t, game.stats.food >= 29 && game.stats.water >= 29, "needs reset to 30")
	testing.expect(t, s.seq != game.seq.dead, "moving again")
}

@(test)
no_resurrection_without_crickets :: proc(t: ^testing.T) {
	if !sim_setup(t, 8) do return
	for &c in game.crickets do c.active = false
	game.storage = 0
	spider_dies(&game.spider, 0)
	game.pending_resurrect = true
	tank_tick()
	testing.expect(t, game.life.dead, "still dead")
	testing.expect(t, last_message == "RESURRECT CREATURE", "explains why")
}

@(test)
eats_tank_crickets_while_away :: proc(t: ^testing.T) {
	if !sim_setup(t, 9) do return
	for _ in 0 ..< 4 do game.pending_drops += 1
	tank_tick()
	game.stats.food = 20
	before := game.eaten
	catch_up(6 * 60, 0)
	log.infof("ate %d crickets while away, food %d", game.eaten - before, game.stats.food)
	testing.expect(t, game.eaten > before, "hungry spider eats crickets in the tank")
}
