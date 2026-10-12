#+build !js
package vc

import "core:testing"

@(private = "file")
type_word :: proc(w: string) {
	for ch in transmute([]u8)w do tank_char(i32(ch))
	tank_char(13)
}

@(test)
typed_commands :: proc(t: ^testing.T) {
	if !sim_setup(t, 50) do return
	defer cmd = {}
	s := &game.spider
	st := &game.stats
	food := st.food
	type_word("diet")
	testing.expect_value(t, st.food, food - 10)
	testing.expect_value(t, cmd.mark, 50)
	type_word("NOTAWORD")
	testing.expect_value(t, st.food, food - 10)

	type_word("LANDOFTHEGIANTS")
	testing.expect_value(t, s.size, 100)
	type_word("MICROCOSM")
	testing.expect_value(t, s.size, 5)
	type_word("MICROCOSM")
	testing.expect(t, s.size != 5, "back to its own size")

	game.skin.active = false
	type_word("URSULLA")
	testing.expect(t, game.skin.active, "a moult")

	type_word("VENUS")
	testing.expect(t, s.goal.active && s.goal.seq == game.seq.glass, "off to the glass")

	cr := &game.crickets[0]
	cr.in_box, cr.active = false, true
	type_word("KAMIKAZE")
	testing.expect(t, cr.goal.active && cr.goal.type == .Spider, "the cricket heads for the spider")
	game.spider.x = 600 // it follows the spider as it moves
	goal_check(cr)
	testing.expect(t, !cr.goal.active || cr.goal.x == game.spider.x, "aiming at where the spider is now")

	type_word("OLIVER")
	testing.expect_value(t, game.objects[BOWL].frame, 0)

	type_word("GLOBALBEACH")
	testing.expect(t, cmd.logo_skin, "logo skin on")
	for _ in 0 ..< 5 do tank_step(TICK) // drawn with the texture
	type_word("SHOWFPS")
	testing.expect(t, cmd.show_fps, "fps shown")

	// junk before a word spoils it (the buffer only empties at 16
	// characters or on Enter), as in the original
	for _ in 0 ..< 20 do tank_char('X')
	type_word("DIET")
	testing.expect_value(t, st.food, max(food - 10, 0))
	type_word("DIET")
	testing.expect_value(t, st.food, max(food - 20, 0))

	// nothing while dead
	game.life.dead = true
	defer game.life.dead = false
	type_word("SAHARA")
	water := st.water
	testing.expect_value(t, st.water, water)
}
