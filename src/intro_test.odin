#+build !js
package vc

import "core:testing"

@(test)
intro_runs_then_the_game_starts :: proc(t: ^testing.T) {
	if !sim_setup(t, 40) do return
	defer intro = {stage = 3}
	tank_intro()
	s := &game.spider
	x, y := s.x, s.y
	ticks, saw_spider := 0, false
	for intro_active() && ticks < 1000 {
		tank_tick()
		ticks += 1
		saw_spider ||= intro.stage == 1 && intro.alpha == 127
	}
	testing.expect(t, !intro_active(), "the intro ends")
	testing.expect(t, saw_spider, "the spider was fully shown")
	testing.expectf(t, ticks > 90 && ticks < 200, "%d frames (10 fps: 1.5 s wait plus 90)", ticks)
	testing.expect(t, s.x == x && s.y == y, "the game waited meanwhile")
	testing.expect(t, intro_seq() >= 0 && len(assets.spider.seqs[intro_seq()].dirs[4].frames) > 0, "CLEAN facing 4")
	tank_intro()
	tank_tick()
	tank_skip_intro()
	tank_tick()
	tank_tick()
	testing.expect(t, !intro_active(), "a key skips it")
}

@(test)
plants_wilt_on_death_and_recover :: proc(t: ^testing.T) {
	if !sim_setup(t, 41) do return
	defer game.life = {}
	game.stats.food, game.stats.water = 0, 0
	for _ in 0 ..< 700 do tank_tick() // past a minute
	testing.expect(t, game.life.dead, "died")
	testing.expect_value(t, game.objects[CACTUS1].frame, 1)
	testing.expect_value(t, game.objects[CACTUS2].frame, 1)
	testing.expect_value(t, game.objects[YUCCA].frame, game.objects[YUCCA].def.frames - 1)
	spider_resurrect()
	testing.expect_value(t, game.objects[CACTUS1].frame, 0)
	testing.expect_value(t, game.objects[CACTUS2].frame, 0)
}
