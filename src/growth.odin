package vc

// Growth, moulting and the slow object animations (spider_growth 0x403ac0,
// moult 0x408d50, object_slow_anim 0x403c90).

NEWBORN_SIZE  :: 40   // 0x42b038
GROWTH_DAYS   :: 15.0 // 0x42b034: from newborn to full size
SKIN_STAGE    :: 1920 // minutes per crumbling stage
SKIN_STAGES   :: 3
YUCCA_DAY     :: 1440 // minutes per growth frame: 9 days / (frames - 1)

Skin :: struct {
	using c:    Creature,
	stage_age:  int, // minutes into the current crumbling stage
	shed_at:    f64, // unix seconds, at most one moult a day
}

age_minutes :: proc() -> int {
	return max(0, int((host_time() - game.life.born_at) / 60))
}

// size = min(100, 40 + minutes alive / ((24 / ((100 - 40) / 15)) * 60)):
// one point every 6 hours, full grown after 15 days.
spider_growth :: proc(check_moult: bool) {
	if game.life.dead do return
	s := &game.spider
	per_day := int((100 - NEWBORN_SIZE) / GROWTH_DAYS)
	minutes_per_point := 24.0 / f64(per_day) * 60
	size := int(f64(age_minutes()) / minutes_per_point + NEWBORN_SIZE)
	s.size = min(size, 100)

	// The original only checks for a moult while starting up (the game loop
	// flag 0x456058 is still off), i.e. after time away.
	if !check_moult do return
	days := age_minutes() / 1440
	if days >= 28 {
		for days >= 56 do days -= 28
		days -= 28
		if days <= 5 do spider_moult()
	} else if f64(days) <= GROWTH_DAYS {
		// floor(days / trunc(15 * 0.33333334f)) >= 1; the divisor truncates to 5
		if days / 5 >= 1 do spider_moult()
	}
}

// A shed skin appears somewhere on the floor (0x408d50), at most once a day
// and only when the last one has crumbled away.
spider_moult :: proc() {
	k := &game.skin
	if k.active do return
	if k.shed_at != 0 && host_time() - k.shed_at < 24 * 3600 do return
	k.dir = rand_n(2)
	k.active = true
	k.stage_age = 0
	k.frame = 0
	k.size = game.spider.size
	k.x = rand_n(800) + 200
	k.y = rand_n(220) + 170
	k.prev_x, k.prev_y = k.x, k.y
	k.shed_at = host_time()
	creature_update_position(&k.c)
	debug_logf("the spider moulted (size %d)", k.size)
}

skin_init :: proc() {
	k := &game.skin
	creature_init(&k.c, &game.skin_a, 0, 0, 0, 0, NEWBORN_SIZE)
	k.kind = .Skin
	k.id = 10
	k.name = "skin"
	k.active = false
	k.seq = 0
}

// Minutes passing for the slow animations: the skin crumbles a stage every
// 1920 minutes and is gone after 3; the yucca grows a frame a day.
slow_anims :: proc(minutes: int) {
	k := &game.skin
	if k.active {
		k.stage_age += minutes
		for k.stage_age >= SKIN_STAGE {
			k.stage_age -= SKIN_STAGE
			k.frame += 1
			if k.frame >= SKIN_STAGES {
				k.active = false
				k.frame = 0
				break
			}
		}
	}
	y := &game.objects[YUCCA]
	if y.active && !y.in_box {
		if game.life.dead {
			y.frame = y.def.frames - 1
		} else if y.frame > 0 && y.frame < y.def.frames - 1 {
			game.yucca_age += minutes
			for game.yucca_age >= YUCCA_DAY && y.frame > 0 {
				game.yucca_age -= YUCCA_DAY
				y.frame -= 1
			}
		}
	}
}

// Once a game minute (0x41f4d0).
minute_tick :: proc() {
	spider_growth(false)
	slow_anims(1)
	age_webs(1)
}
