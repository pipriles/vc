package vc

import "base:runtime"
import "core:encoding/json"
import "core:fmt"

// Saving, the catch-up of time spent away, death and resurrection.
// Catch-up and resurrection follow VC.EXE (0x415430, 0x404230); the save
// format is the port's own (the original kept its state in vc.dat and the
// registry).

SAVE_VERSION :: 1

Save_Creature :: struct {
	active, in_box: bool,
	x, y, dir:      int,
}

Save_Object :: struct {
	in_tank: bool,
	x, y:    int,
	frame:   int,
}

Save :: struct {
	version:        int,
	saved_at:       f64, // unix seconds
	seed:           u32,
	spider:         struct {
		x, y, dir, size, hide: int,
		dead:                  bool,
	},
	food, water, mood:  int,
	since_food_ms:      u32, // time since the last food / water decay step
	since_water_ms:     u32,
	since_played_ms:    [32]u32, // per sequence, for cooldowns
	crickets:           [CRICKET_COUNT]Save_Creature,
	objects:            [OBJECT_COUNT]Save_Object,
	storage, eaten:     int,
	resurrections:      int,
	remains:            [REMAINS_COUNT]Remains,
	remains_next:       int,
	born_at, died_at:   f64, // unix seconds, died_at 0 while alive
	ui_hidden, follow:  bool,
	ui_icons_only:      bool,
	tool:               int,
	footprints:         [FOOTPRINT_COUNT]Footprint,
	footprint_next:     int,
	webs:               [WEB_PIECES]Web_Piece,
	web_next:           int,
	corner_webs:        [4]Corner_Web,
	skin:               struct {
		active:                   bool,
		x, y, dir, stage, size:   int,
		stage_age:                int,
		shed_at:                  f64,
	},
	yucca_age:          int,
}

Life :: struct {
	dead:          bool,  // (+0x162)
	born_at:       f64,
	died_at:       f64,
	resurrections: int,   // (0x454a60)
	death_notice:  int,   // ticks until "YOUR CREATURE HAS DIED!" (0x431c68)
}

// --- save / load ------------------------------------------------------------

make_save :: proc() -> Save {
	s := &game.spider
	st := &game.stats
	sv: Save
	sv.version = SAVE_VERSION
	sv.saved_at = host_time()
	sv.seed = rng.seed
	sv.spider = {s.x, s.y, s.dir, s.size, s.hide, game.life.dead}
	sv.food, sv.water, sv.mood = st.food, st.water, st.mood
	sv.since_food_ms = now_ms - st.last_food
	sv.since_water_ms = now_ms - st.last_water
	for t, i in s.last_played {
		if i < len(sv.since_played_ms) do sv.since_played_ms[i] = now_ms - t
	}
	for &c, i in game.crickets do sv.crickets[i] = {c.active, c.in_box, c.x, c.y, c.dir}
	for &o, i in game.objects do sv.objects[i] = {!o.in_box, o.x, o.y, o.frame}
	sv.storage, sv.eaten = game.storage, game.eaten
	sv.resurrections = game.life.resurrections
	sv.remains, sv.remains_next = game.remains, game.remains_next
	sv.born_at, sv.died_at = game.life.born_at, game.life.died_at
	sv.ui_hidden, sv.follow = !game.ui.shown, game.follow
	sv.ui_icons_only = game.ui.icons_only
	sv.tool = int(game.input.tool)
	sv.footprints, sv.footprint_next = game.footprints, game.footprint_next
	sv.webs, sv.web_next = game.webs, game.web_next
	sv.corner_webs = game.corner_webs
	k := &game.skin
	sv.skin = {k.active, k.x, k.y, k.dir, k.frame, k.size, k.stage_age, k.shed_at}
	sv.yucca_age = game.yucca_age
	return sv
}

apply_save :: proc(sv: ^Save) {
	s := &game.spider
	st := &game.stats
	s.x, s.y, s.dir, s.size = sv.spider.x, sv.spider.y, clamp(sv.spider.dir, 0, 7), sv.spider.size
	s.prev_x, s.prev_y = s.x, s.y
	s.hide = sv.spider.hide
	s.no_clamp = s.hide != 0 && s.y < FLOOR_TOP
	game.life.dead = sv.spider.dead
	st.food, st.water, st.mood = sv.food, sv.water, sv.mood
	st.last_food = now_ms - min(sv.since_food_ms, now_ms)
	st.last_water = now_ms - min(sv.since_water_ms, now_ms)
	for &t, i in s.last_played {
		if i < len(sv.since_played_ms) do t = now_ms - min(sv.since_played_ms[i], now_ms)
	}
	for &c, i in game.crickets {
		r := sv.crickets[i]
		c.active, c.in_box, c.x, c.y = r.active, r.in_box, r.x, r.y
		c.dir = clamp(r.dir, 0, 7)
		c.prev_x, c.prev_y = c.x, c.y
		creature_update_position(&c)
	}
	for &o, i in game.objects {
		r := sv.objects[i]
		o.in_box = !r.in_tank
		o.x, o.y = r.x, r.y
		o.frame = clamp(r.frame, 0, o.def.frames - 1)
		if r.in_tank do object_update_position(&o)
	}
	game.storage, game.eaten = sv.storage, sv.eaten
	game.life.resurrections = sv.resurrections
	game.remains, game.remains_next = sv.remains, sv.remains_next % REMAINS_COUNT
	game.life.born_at, game.life.died_at = sv.born_at, sv.died_at
	game.ui.shown, game.follow = !sv.ui_hidden, sv.follow
	game.ui.icons_only = sv.ui_icons_only && sv.ui_hidden
	game.ui.cycle = game.ui.shown ? 1 : 0
	game.ui.slide = 0
	game.input.tool = Tool(clamp(sv.tool, 0, TOOL_COUNT - 1))
	game.footprints, game.footprint_next = sv.footprints, sv.footprint_next % FOOTPRINT_COUNT
	game.webs, game.web_next = sv.webs, sv.web_next % WEB_PIECES
	game.corner_webs = sv.corner_webs
	k := &game.skin
	k.active, k.x, k.y = sv.skin.active, sv.skin.x, sv.skin.y
	k.dir, k.frame, k.size = clamp(sv.skin.dir, 0, 7), clamp(sv.skin.stage, 0, SKIN_STAGES - 1), sv.skin.size
	k.stage_age, k.shed_at = sv.skin.stage_age, sv.skin.shed_at
	k.prev_x, k.prev_y = k.x, k.y
	if k.active do creature_update_position(&k.c)
	game.yucca_age = sv.yucca_age
	spider_stats_tick(st)
	creature_update_position(s)
	game.scroll_x = clamp(s.x - VIEW_W / 2, 0, TANK_W - VIEW_W)
	rng.seed = sv.seed // last: the position updates above may draw random numbers
}

// Loads save.json if there is one and replays the time since it was saved.
load_game :: proc() -> bool {
	data := load_file("save.json")
	if len(data) == 0 do return false
	sv: Save
	if err := json.unmarshal(data, &sv); err != nil || sv.version != SAVE_VERSION {
		fmt.eprintln("ignoring unreadable save:", err)
		return false
	}
	apply_save(&sv)
	minutes := int((host_time() - sv.saved_at) / 60)
	debug_logf("loaded, %d minutes since the last save", minutes)
	if minutes > 0 do catch_up(minutes, sv.saved_at)
	return true
}

@(export)
tank_save :: proc "c" () {
	context = runtime.default_context()
	if mode != .Tank || !running do return
	sv := make_save()
	data, err := json.marshal(sv, allocator = context.temp_allocator)
	if err == nil do host_save(string(data))
	free_all(context.temp_allocator)
}

// The page was hidden for a while: replay the time like after a restart.
@(export)
tank_resume :: proc "c" (minutes: i32) {
	context = runtime.default_context()
	if mode != .Tank || !running || minutes < 1 do return
	catch_up(int(minutes), host_time() - f64(minutes) * 60)
	free_all(context.temp_allocator)
}

// --- catch-up (0x415430) ----------------------------------------------------

// Hidden under the rock, as the catch-up and the hidden idle leave it.
put_under_rock :: proc(s: ^Creature) {
	stop_current(s)
	clear_goal(s)
	clear_queue(s)
	s.x = ROCK_X - (100 - s.size) / 2
	s.y = HIDE_Y
	s.prev_x, s.prev_y = s.x, s.y
	s.hide = 1
	s.no_clamp = true
	s.dir = 6
	s.seq = game.seq.lurk
	start_sequence(s)
}

// Replays `minutes` of absence: needs decay, drinking from the bowl,
// eating crickets in the tank, wandering, and death. `since` is when the
// absence started (unix seconds), for the date of death.
catch_up :: proc(minutes: int, since: f64) {
	s := &game.spider
	st := &game.stats
	ids := &game.seq
	debug_logf("catching up %d minutes", minutes)

	if minutes < 3 {
		if s.y >= FLOOR_TOP do return
		put_under_rock(s)
		return
	}
	if minutes >= 60 do st.mood = rand_n(200) - 100
	// the sequence ends, then the spider is reset: no goal, no turn, not
	// eating, every sequence last played 5 minutes ago (0x403520, 0x408630)
	if s.finished != nil do s.finished(s)
	clear_goal(s)
	s.turn_target, s.turn_dir, s.pop_turning = -1, 0, false
	s.eating = false
	for &t in s.last_played do t = now_ms - min(now_ms, 300_000)
	if s.hide != 0 {
		s.hide = 0
		s.no_clamp = false
	}
	for &c in game.crickets do if c.active && !c.in_box do place_free_creature(&c)

	step := minutes < 30 ? 1 : minutes < 60 ? 2 : minutes < 90 ? 3 : 90
	water_acc, food_acc, day_acc, webs_today, t := 0, 0, 0, 0, 0
	bowl := &game.objects[BOWL]
	for {
		if !game.life.dead {
			if water_acc >= 150 {
				st.water = max(st.water - water_acc / 75, 0)
				water_acc -= 150
			}
			if food_acc >= 120 {
				st.food = max(st.food - food_acc / 60, 0)
				food_acc -= 120
			}
			if day_acc >= 1440 {
				day_acc -= 1440
				webs_today = 0
			}
			if st.water < 80 && bowl.active && !bowl.in_box && bowl.frame > 0 {
				bowl.frame -= 1
				st.water = min(st.water + 20, 100)
			}
			if st.food < 26 {
				ate := false
				for &c in game.crickets {
					if c.in_box || !c.active do continue
					if rand_n(10) < 5 && !ate {
						cricket_eaten(&c)
						place_free_creature(s)
						add_remains(s)
						ate = true
					}
				}
				if !ate {
					if rand_n(10) < 7 do place_free_creature(s)
					// webs: pieces round the spider, or a big corner web
					if rand_n(10) < 5 && webs_today < 3 {
						if rand_n(10) < 7 {
							add_web_piece(s, 0, 0)
							add_web_piece(s, 0, 1)
							add_web_piece(s, 2, 0)
							add_web_piece(s, 2, 1)
						}
						if rand_n(10) < 7 {
							add_web_piece(s, 4, 0)
							add_web_piece(s, 4, 1)
							add_web_piece(s, 6, 0)
							add_web_piece(s, 6, 1)
						}
						webs_today += 1
					} else if !(rand_n(10) > 4 || webs_today < 1 || webs_today > 2) {
						add_corner_web(true)
						webs_today += 1
					}
				}
			}
		}
		water_acc += step
		food_acc += step
		day_acc += step
		t += step
		slow_anims(step)
		age_webs(step)
		spider_stats_tick(st)
		if st.health < 1 && !game.life.dead {
			spider_dies(s, since + f64(t) * 60)
		}
		if t >= minutes do break
	}
	// carry the remainders into the live decay timers
	st.last_water = now_ms - min(u32(water_acc) * 60_000, now_ms)
	st.last_food = now_ms - min(u32(food_acc) * 60_000, now_ms)
	if game.life.dead {
		plants_wilt(true)
		return
	}
	// often found hiding afterwards
	if rand_n(10) > 4 {
		if rand_n(10) > 4 do return
		if st.temperament > 2 do return
	}
	put_under_rock(s)
	_ = ids
}

// --- death and resurrection ---------------------------------------------------

spider_dies :: proc(s: ^Creature, at: f64) {
	game.life.dead = true
	game.life.died_at = at
	game.stats.temperament = 0
	game.life.death_notice = 30
	stop_current(s)
	clear_goal(s)
	clear_queue(s)
	debug_logf("the spider has died")
}

// A dead spider lies still on its DEAD frame (creature_tick, dead branch).
spider_dead_tick :: proc(s: ^Creature) {
	ids := &game.seq
	if s.seq != ids.dead {
		s.seq = ids.dead
		// starts from (8 - rand())/0x7fff, i.e. 0, and steps to a direction
		// that has DEAD frames
		d := (8 - rand()) / 0x7FFF
		for _ in 0 ..< 8 {
			d = (d + 1) % 8
			if seq_has_frames(s, ids.dead, d) do break
		}
		s.dir = d
		s.step = 1
	}
	s.frame = 0
	s.plays = 1
	s.moving_x, s.moving_y = false, false
	s.hold = -1
	s.hide = 0
	creature_update_position(s)
}

// Resurrect Creature (0x404230).
@(export)
tank_resurrect :: proc "contextless" () {
	game.pending_resurrect = true
}

spider_resurrect :: proc() {
	s := &game.spider
	if !game.life.dead {
		host_message("RESURRECT CREATURE", "This option is used to bring your creature back to life after it has died!")
		return
	}
	box := 0
	for &c in game.crickets do if c.active && c.in_box do box += 1
	if game.storage < 1 && box < 1 && crickets_in_tank() < 1 {
		host_message("RESURRECT CREATURE", "You don't have any Crickets left to resurrect your creature with!")
		return
	}
	clear_debris()
	game.life.dead = false
	game.life.died_at = 0
	game.life.resurrections += 1
	plants_wilt(false)
	game.scroll_x = clamp(s.x - VIEW_W / 2, 0, TANK_W - VIEW_W)
	st := &game.stats
	st.water, st.food, st.mood = 30, 30, 0
	spider_stats_tick(st)
	s.size = 40
	s.carried = 2 // plays DROP, like being put back in the tank
	s.dir = 4
	s.prev_seq = -1
	stop_current(s)
	game.life.born_at = host_time()
	spider_growth(false)
	debug_logf("the spider was resurrected (%d times now)", game.life.resurrections)
	host_sound(400)
}

// "YOUR CREATURE HAS DIED!" a few seconds after finding it dead (0x431c68).
death_notice_tick :: proc() {
	l := &game.life
	if !l.dead || l.death_notice <= 0 do return
	l.death_notice -= 1
	if l.death_notice == 0 {
		host_message("YOUR CREATURE HAS DIED!",
			"To resurrect it, click on the 'Resurrect Creature' option in the Options panel.")
	}
}
