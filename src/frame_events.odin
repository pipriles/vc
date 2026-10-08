package vc

// Things that happen on particular animation frames: sounds, pauses, the
// spider ringing the bell, creeping under the rock (creature_post_frame
// 0x404b20, spider_post_draw 0x4057b0).

cricket_frame_sounds :: proc(c: ^Creature) {
	ids := &game.cseq
	n := len(creature_dir(c).frames)
	if c.seq == ids.drop && c.frame == 0 do host_sound(408)
	if c.seq == ids.jump && c.frame == n - 1 && game.input.view != .Box && !c.in_box do host_sound(409)
}

spider_frame_events :: proc(c: ^Creature) {
	ids := &game.seq
	t := game.stats.temperament
	f := c.frame
	n := len(creature_dir(c).frames)

	switch c.seq {
	case ids.walk:
		// stops now and then mid-walk: calmer spiders more, weak ones longer
		if f == 0 || f == 3 {
			following := c.goal.active && (c.goal.type == .Cursor || c.goal.type == .Creature_B)
			if !following {
				if rand_n(14) < t / 2 do c.pause = rand() * t * 2 / 0x7FFF + 5
				if game.stats.health < 16 && rand_n(6) == 2 do c.pause = rand() * (8 - t) * 2 / 0x7FFF + 11
			} else if rand_n(10) == game.stats.health / 10 {
				c.pause = rand_n(10) + 8
			}
		}
	case ids.threat:
		if f == 9 && c.step == 1 {
			host_sound(459)
		} else if f == n - 1 {
			c.pause = rand_n(8) + 8
		}
	case ids.clean:
		if c.dir == 6 || c.dir == 7 {
			if f == 6 || (f == 8 && c.back_pass != 0) do host_sound(461)
		} else if (c.dir >= 3 && c.dir <= 5) && (f == 8 || f == 11) {
			host_sound(462)
		}
	case ids.glass:
		if (f == 3 || f == 4 || f == 6 || f == 8 || f == 9) && c.step == 1 do host_sound(463)
		if (f == 11 && c.step == 1) || (f == 19 && c.step == -1) do host_sound(464)
	case ids.hair:
		if f == 7 do host_sound(458)
	case ids.drop:
		if f == 2 do host_sound(406)
	case ids.lurk:
		// lurking against the bell rings it
		bell := &game.objects[BELL]
		if f == n - 1 && (c.dir == 0 || c.dir == 4) && bell.active && !bell.in_box && bell.swings == 0 {
			b := c.blocks[c.dir]
			if b.active && b.kind == int(Kind.Object) && b.id == BELL {
				dx := c.x - bell.x
				if (c.dir == 0 && abs(dx) <= 29) || (c.dir == 4 && dx > 0 && dx <= 49) {
					bell.anim_step = c.dir == 0 ? -1 : 1
					bell.swings = 60
					debug_logf("spider rings the bell")
				}
			}
		}
	case ids.crush:
		if f < n - 2 || c.tool == .None {
			if f == n - 1 || f == n - 2 do c.pause = rand_n(15) + 15
		} else {
			c.pause = 0
			c.hold = 0
		}
	case ids.kill:
		if f == n - 2 do host_sound(453 + rand_n(4))
	case ids.web_laying:
		if f == 0 do host_sound(412)
		if f == 2 do host_sound(413)
		if f == 3 do spider_lay_web(c)
	}

	// footsteps on the floor
	if c.y >= FLOOR_TOP && game.input.view != .Box {
		if c.seq == ids.walk && (f == 1 || f == 3 || (f == 5 && rand_n(10) < 3)) {
			host_sound(460)
			if f == 3 do add_footprint(c, 0, 0, 1)
		} else if c.seq == ids.circle && (f == 0 || f == 6) {
			dx := rand_n(4) - 2
			dy := rand_n(4) - 2
			host_sound(460)
			add_footprint(c, dx, dy, f != 0 ? 1 : 0)
		}
	}
}

// Crawling under the rock while LOG_HIDE plays (0x4057b0, every frame):
// hidden from the start, creeping left and up, footsteps on odd frames.
spider_hide_crawl :: proc(c: ^Creature) {
	if c.seq != game.seq.log_hide do return
	c.hide = 1
	f := c.frame
	m := 100 - c.size
	if f > 8 {
		c.x -= c.sx
		if f > 17 do c.x -= m / 30 + 1
	}
	if f > m / 25 + 4 && f < 16 do c.y -= 1 + m / 65
	if f % 2 == 1 do host_sound(460)
	if f == 23 || f == 29 do host_sound(411)
}
