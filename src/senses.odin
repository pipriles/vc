package vc

// Port: what the spider notices and what it does about it. The original
// knows where the bowl is wherever it is, notices crickets only when one is
// dropped near it (350 x 175 px) or stuck in a web close by (200 x 140), and
// otherwise only finds crickets by bumping into them. Here:
// - it notices things inside an area round it, wider when it's hungry
//   (and twice as wide for the big, still water bowl);
// - a cricket it notices may be hunted: stalked at walking pace, then a
//   pause, then the pounce and the catch; it gives up when the cricket gets
//   away or is taken out of the tank;
// - it only goes for the bowl once it has seen it, and forgets it when it
//   finds it gone;
// - when it has stayed in one area for minutes, or it's hungry or thirsty
//   with nothing in sight, it goes exploring.

Hunt_Phase :: enum {
	None,
	Stalk, // walking up to it
	Freeze, // still, about to pounce
	Pounce, // running at it (a chase goal ending in CATCH)
}

Senses :: struct {
	hunt:            Hunt_Phase,
	prey:            int, // cricket id
	hunt_ms:         u32, // when the hunt (or the freeze) started
	freeze_ms:       int, // length of the freeze
	ignore_id:       int, // cricket given up on, and until when
	ignore_until:    u32,
	bowl_known:      bool,
	bowl_x, bowl_y:  int, // where it saw the bowl last
	area_x, area_y:  int, // the area it's been in, and since when
	area_ms:         u32,
	last_sense_ms:   u32,
}

senses_init :: proc() {
	game.senses = {prey = -1, ignore_id = -1}
	s := &game.spider
	game.senses.area_x, game.senses.area_y = s.x, s.y
}

// Half sizes of the noticing area (an ellipse, flatter in depth like the
// original's ranges): 220 x 110 px, half again when peckish, double when
// starving.
notice_range :: proc() -> (rx, ry: int) {
	food := game.stats.food
	r := 220
	if food < 50 do r = 330
	if food < 25 do r = 440
	return r, r / 2
}

in_area :: proc(s: ^Creature, x, y, rx, ry: int) -> bool {
	dx, dy := f64(x - s.x) / f64(rx), f64(y - s.y) / f64(ry)
	return dx * dx + dy * dy <= 1
}

hunting :: proc() -> bool {return game.senses.hunt != .None}

// Can the spider look around and act on it now?
spider_alert :: proc(s: ^Creature) -> bool {
	return !game.life.dead && s.hide == 0 && s.carried == 0 && !s.eating &&
		s.tool == .None && !(s.goal.active && (s.goal.type == .Cursor || s.goal.seq == game.seq.log_hide))
}

// Once a game step.
senses_tick :: proc() {
	s := &game.spider
	ss := &game.senses
	if ss.hunt != .None do hunt_tick(s)
	if now_ms < ss.last_sense_ms + 1000 do return
	ss.last_sense_ms = now_ms
	if !spider_alert(s) {
		if ss.hunt != .None && (s.carried != 0 || game.life.dead || s.hide != 0) do give_up(s, "interrupted")
		return
	}
	rx, ry := notice_range()

	// the bowl: seen when it's in the (doubled) area, forgotten when it
	// isn't where it was seen
	bowl := &game.objects[BOWL]
	bowl_here := bowl.active && !bowl.in_box
	if bowl_here && in_area(s, bowl.x, bowl.y, rx * 2, ry * 2) {
		if !ss.bowl_known do debug_logf("spider notices the water bowl")
		ss.bowl_known, ss.bowl_x, ss.bowl_y = true, bowl.x, bowl.y
	} else if ss.bowl_known && in_area(s, ss.bowl_x, ss.bowl_y, rx, ry) &&
	   (!bowl_here || abs(bowl.x - ss.bowl_x) + abs(bowl.y - ss.bowl_y) > 60) {
		ss.bowl_known = false
		debug_logf("spider finds the bowl gone")
	}

	if ss.hunt == .None && !s.goal.active do look_for_prey(s, rx, ry)
	if ss.hunt == .None do maybe_explore(s, rx, ry)
}

// A cricket wandering in the area may be hunted; the hungrier, the likelier.
look_for_prey :: proc(s: ^Creature, rx, ry: int) {
	ss := &game.senses
	food := game.stats.food
	best, best_d := -1, max(int)
	for &c, i in game.crickets {
		if !c.active || c.in_box || c.carried != 0 do continue
		if i == ss.ignore_id && now_ms < ss.ignore_until do continue
		if !in_area(s, c.x, c.y, rx, ry) do continue
		if d := abs(c.x - s.x) + abs(c.y - s.y); d < best_d do best, best_d = i, d
	}
	if best < 0 do return
	// too full (the original's test for a dropped cricket), else a chance
	// that grows with hunger
	if rand_n(25) + 65 <= food do return
	chance := food < 30 ? 9 : food < 50 ? 6 : 3
	if rand_n(10) >= chance do return
	ss.hunt, ss.prey, ss.hunt_ms = .Stalk, best, now_ms
	debug_logf("spider notices cricket %d and stalks it (food %d)", best, food)
	stalk_step(s)
}

// Distance at which it stops to pounce: its own reach plus a little.
strike_distance :: proc(s: ^Creature) -> int {return (s.hit.right - s.hit.left) / 2 + 30}

// Walks (no running) to a point at striking distance on its own side.
stalk_step :: proc(s: ^Creature) {
	cr := &game.crickets[game.senses.prey]
	dx, dy := f64(s.x - cr.x), f64(s.y - cr.y)
	d := max(1, abs(dx) + abs(dy))
	k := f64(strike_distance(s)) / d
	x, y := cr.x + int(dx * k), cr.y + int(dy * k)
	move_to(s, .Point, x, y, dir_towards(s, cr.x, cr.y), game.seq.lurk, 60)
}

dir_towards :: proc(s: ^Creature, x, y: int) -> int {
	dx, dy := x - s.x, y - s.y
	ax, ay := abs(dx), abs(dy)
	if ax > 2 * ay do return dx > 0 ? 2 : 6
	if ay > 2 * ax do return dy > 0 ? 4 : 0
	if dx > 0 do return dy > 0 ? 3 : 1
	return dy > 0 ? 5 : 7
}

hunt_tick :: proc(s: ^Creature) {
	ss := &game.senses
	cr := &game.crickets[ss.prey]
	rx, ry := notice_range()
	switch {
	case !cr.active || cr.in_box || cr.carried != 0:
		give_up(s, "it's gone")
		return
	case !in_area(s, cr.x, cr.y, rx * 3 / 2, ry * 3 / 2):
		give_up(s, "it got away")
		return
	case s.eating || s.seq == game.seq.catch_ || s.seq == game.seq.kill:
		ss.hunt = .None // caught (or at least lunged): the hunt is over
		return
	}
	d := abs(cr.x - s.x) + abs(cr.y - s.y)
	switch ss.hunt {
	case .None:
	case .Stalk:
		if d <= strike_distance(s) + 15 {
			// close: stop dead for a moment, then pounce
			clear_goal(s)
			clear_queue(s)
			ss.hunt, ss.hunt_ms = .Freeze, now_ms
			ss.freeze_ms = 400 + rand_n(12) * 100
			s.pause = ss.freeze_ms / tick_ms()
			debug_logf("spider freezes %d ms before pouncing", ss.freeze_ms)
		} else if now_ms > ss.hunt_ms + 60_000 {
			give_up(s, "too long")
		} else if !s.goal.active {
			stalk_step(s)
		} else if s.goal.type == .Point {
			// the cricket moves: keep the approach point on it
			dx, dy := f64(s.x - cr.x), f64(s.y - cr.y)
			k := f64(strike_distance(s)) / max(1, abs(dx) + abs(dy))
			s.goal.x, s.goal.y = cr.x + int(dx * k), cr.y + int(dy * k)
			s.goal.dir = dir_towards(s, cr.x, cr.y)
		}
	case .Freeze:
		if now_ms >= ss.hunt_ms + u32(ss.freeze_ms) {
			ss.hunt = .Pounce
			move_to(s, .Creature_B, -1, -1, -1, game.seq.catch_, 6, target = ss.prey)
			debug_logf("spider pounces at cricket %d", ss.prey)
		}
	case .Pounce:
		if !s.goal.active do ss.hunt = .None
	}
}

give_up :: proc(s: ^Creature, why: string) {
	ss := &game.senses
	debug_logf("spider gives up on cricket %d: %s", ss.prey, why)
	if s.goal.active && s.goal.type != .Cursor do clear_goal(s)
	ss.ignore_id, ss.ignore_until = ss.prey, now_ms + 15_000
	ss.hunt, ss.prey = .None, -1
}

// Stuck in one area for 4 minutes, or a minute when hungry or thirsty with
// nothing in sight: walk somewhere well away that it can get to.
maybe_explore :: proc(s: ^Creature, rx, ry: int) {
	ss := &game.senses
	if abs(s.x - ss.area_x) > 200 || abs(s.y - ss.area_y) > 120 {
		ss.area_x, ss.area_y, ss.area_ms = s.x, s.y, now_ms
		return
	}
	if s.goal.active do return
	st := &game.stats
	needy := (st.food < 40 && !prey_in_area(s, rx, ry)) || (st.water < 50 && !ss.bowl_known)
	if now_ms < ss.area_ms + (needy ? 60_000 : 240_000) do return
	grid_prepare(s)
	for _ in 0 ..< 12 {
		x := WALL_MARGIN + rand_n(TANK_W - 2 * WALL_MARGIN)
		y := FLOOR_TOP + rand_n(VIEW_H - FLOOR_TOP - 60)
		if abs(x - s.x) + abs(y - s.y) < 350 || !grid_fits(x, y) do continue
		debug_logf("spider goes exploring to (%d, %d)%s", x, y, needy ? " looking for food or water" : "")
		move_to(s, .Point, x, y, -1, game.seq.lurk, 90)
		break
	}
	ss.area_ms = now_ms
}

prey_in_area :: proc(s: ^Creature, rx, ry: int) -> bool {
	for &c in game.crickets do if c.active && !c.in_box && in_area(s, c.x, c.y, rx, ry) do return true
	return false
}
