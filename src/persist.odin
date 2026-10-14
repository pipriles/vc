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
	web_stuck:      bool,
	anim:           Save_Anim,
}

// What a creature is in the middle of (the original saved its whole
// creature struct but the queue, 0x414a60). has = false in older saves.
Save_Anim :: struct {
	has:                  bool,
	seq, frame, step:     int,
	plays, bounces:       int,
	back_pass, left:      int,
	hold, pause:          int,
	run, eating:          bool,
	target_id:            int,
	moving_x, moving_y:   bool,
	goal:                 Goal,
	goal_since_ms:        u32, // goal.start_ms as time since then
}

snapshot_anim :: proc(c: ^Creature) -> Save_Anim {
	a := Save_Anim {
		has = true,
		seq = c.seq, frame = c.frame, step = c.step,
		plays = c.plays, bounces = c.bounces, back_pass = c.back_pass, left = c.left,
		hold = c.hold, pause = c.pause,
		run = c.run, eating = c.eating, target_id = c.target_id,
		moving_x = c.moving_x, moving_y = c.moving_y,
		goal = c.goal,
	}
	if c.goal.active do a.goal_since_ms = now_ms - c.goal.start_ms
	return a
}

restore_anim :: proc(c: ^Creature, a: Save_Anim) {
	if !a.has || a.seq < 0 || a.seq >= len(c.anim.seqs) do return
	c.seq = a.seq
	n := len(creature_dir(c).frames)
	if n == 0 {
		c.seq = 0
		return
	}
	c.frame = clamp(a.frame, 0, n - 1)
	c.step = a.step if a.step != 0 else 1
	c.plays, c.bounces, c.back_pass, c.left = a.plays, a.bounces, a.back_pass, a.left
	c.hold, c.pause = a.hold, a.pause
	c.run, c.eating, c.target_id = a.run, a.eating, a.target_id
	c.moving_x, c.moving_y = a.moving_x, a.moving_y
	c.goal = a.goal
	if c.goal.active do c.goal.start_ms = now_ms - min(a.goal_since_ms, now_ms)
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
		anim:                  Save_Anim,
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
}

// --- save / load ------------------------------------------------------------

// Cold (once a minute and at start-up). Not optimised: the Save copies by
// value split into thousands of loads and stores that took ~6 s of the
// -o:speed build to schedule (see box_art_load).
@(optimization_mode = "none")
make_save :: proc() -> Save {
	s := &game.spider
	st := &game.stats
	sv: Save
	sv.version = SAVE_VERSION
	sv.saved_at = host_time()
	sv.seed = rng.seed
	sv.spider = {s.x, s.y, s.dir, s.size, s.hide, game.life.dead, snapshot_anim(s)}
	sv.food, sv.water, sv.mood = st.food, st.water, st.mood
	sv.since_food_ms = now_ms - st.last_food
	sv.since_water_ms = now_ms - st.last_water
	for t, i in s.last_played {
		if i < len(sv.since_played_ms) do sv.since_played_ms[i] = now_ms - t
	}
	for &c, i in game.crickets do sv.crickets[i] = {c.active, c.in_box, c.x, c.y, c.dir, c.web_stuck, snapshot_anim(&c)}
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

@(optimization_mode = "none") // cold, see make_save
apply_save :: proc(sv: ^Save) {
	s := &game.spider
	st := &game.stats
	s.x, s.y, s.dir, s.size = sv.spider.x, sv.spider.y, clamp(sv.spider.dir, 0, 7), sv.spider.size
	s.prev_x, s.prev_y = s.x, s.y
	s.hide = sv.spider.hide
	restore_anim(s, sv.spider.anim)
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
		c.web_stuck = r.web_stuck
		restore_anim(&c, r.anim)
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

// What became of save.json at start-up; the page warns (and keeps a copy)
// when there was one the game couldn't use, as a new pet replaces it.
Save_Status :: enum i32 {
	None,
	Loaded,
	Unreadable,
	Wrong_Version,
}
save_status: Save_Status

@(export)
tank_save_status :: proc "contextless" () -> Save_Status {return save_status}

// Loads save.json if there is one and replays the time since it was saved.
load_game :: proc() -> bool {
	save_status = .None
	data := load_file("save.json")
	if len(data) == 0 do return false
	sv: Save
	if err := json.unmarshal(data, &sv); err != nil {
		save_status = .Unreadable
		return false
	}
	if sv.version != SAVE_VERSION {
		save_status = .Wrong_Version
		return false
	}
	save_status = .Loaded
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

// The page was hidden for `seconds`. The original kept running while
// minimized, so an absence of up to REPLAY_MAX_S is replayed tick by tick,
// as if the tank had been on screen (silently, without drawing). A longer
// one takes the catch-up for the whole minutes, then replays the rest.
REPLAY_MAX_S :: 60 * 60

@(export)
tank_away :: proc "c" (seconds: f64) {
	context = runtime.default_context()
	if mode != .Tank || !running || seconds <= 0 do return
	rest := seconds
	if rest > REPLAY_MAX_S {
		minutes := int(rest / 60)
		catch_up(minutes, host_time() - rest)
		rest -= f64(minutes) * 60
	}
	replaying = true
	defer replaying = false
	tick := f64(tick_ms()) / 1000
	game.accum += rest
	for game.accum >= tick {
		game.accum -= tick
		tank_tick()
		free_all(context.temp_allocator)
	}
}

// True while tank_away replays: the sounds stay quiet.
replaying: bool

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
	s.tool = .None
	s.last_react = now_ms
	clear_queue(s) // (dropping what the finished hook queued)
	stop_current(s)
	if s.hide != 0 {
		s.hide = 0
		s.no_clamp = false
	}
	for &c in game.crickets do if c.active && !c.in_box && !c.web_stuck do place_free_creature(&c)

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
	// crickets stuck in webs are free again
	for &c in game.crickets do c.web_stuck = false
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
// Once a run, 20 frames into a dead spider (at start, or after it dies;
// a later death in the same run gets no message, as in the original).
death_notice := 20

death_notice_tick :: proc() {
	if !game.life.dead || game.ui.saver || death_notice <= 0 do return
	death_notice -= 1
	if death_notice == 0 {
		host_message("YOUR CREATURE HAS DIED!",
			"To resurrect it, click on the 'Resurrect Creature' option in the 'Utilities' menu from the Options dialog box.")
	}
}

// Fewer than 6 crickets left (box, store and tank): once a run, 20 frames
// after it's noticed, a reminder that more can be fetched (wnd_proc timer,
// 0x431c6c).
low_crickets_notice := 20

low_crickets_tick :: proc() {
	if game.cricket_total >= 6 || game.ui.saver || low_crickets_notice <= 0 do return
	low_crickets_notice -= 1
	if low_crickets_notice > 0 do return
	n := game.cricket_total
	title := n == 0 ? "YOU DON'T HAVE ANY CRICKETS LEFT!" : n == 1 ? "YOU ONLY HAVE 1 CRICKET LEFT!" : fmt.tprintf("YOU ONLY HAVE %d CRICKETS LEFT!", n)
	host_message(title, "To download extra crickets, click on the 'Download Crickets' option in the 'Utilities' menu from the Options dialog box.")
}
