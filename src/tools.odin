package vc

// Player tools, cursors, buttons and the cricket box (wnd_proc_main mouse
// handling, button handler 0x41c4b0, cursor sets 0x41c890).

Tool :: enum {
	Tap    = 0, // tap on the glass (default)
	Pickup = 1, // pick up and move
	Prod   = 2,
	Stroke = 3,
	Follow = 4, // the spider follows the cursor
}
TOOL_COUNT :: 5

View :: enum {
	Tank  = 0,
	Whole = 1, // whole tank and object panel (zoom out)
	Close = 2, // close-up of the spider (zoom in)
	Box   = 3, // the cricket box (feed)
}

// Cursor sets (RT_GROUP_CURSOR 200 + 10*set): 0 pointer, 1 open hand,
// 2 hand over something to grab, 3 grabbing, 4 prod, 5 knock, 6 tap hover,
// 7 stroke. Frames per set:
CURSOR_FRAMES := [8]int{1, 1, 1, 1, 2, 2, 1, 2}
CURSOR_TICKS :: 3 // a cursor frame lasts 4 ticks

Pointer_Event :: enum i32 {
	Move = 0,
	Down = 1,
	Up   = 2,
	Leave = 3,
	Right = 4, // right button released without dragging
}

Carry :: enum {
	None,
	Spider,
	Cricket,
	Object,
}

Input :: struct {
	tool:            Tool,
	view:            View,
	x, y:            int, // pointer in tank (or box) coordinates
	vx, vy:          int, // pointer in view coordinates
	inside:          bool,
	down:            bool,
	cursor_set:      int,
	cursor_frame:    int,
	cursor_count:    int,
	prodding:        bool, // started a prod on the spider (0x44c038)
	stroking:        bool, // started a stroke on the spider (0x44c078)
	carry:           Carry,
	carry_id:        int,
}

set_cursor :: proc(set: int) {
	in_ := &game.input
	if set == in_.cursor_set do return
	in_.cursor_set = set
	in_.cursor_frame = 0
	in_.cursor_count = 0
	host_cursor(i32(set), 0)
}

// Cursor animation, once per tick (wnd_proc_main timer). Looping the
// prod/knock/stroke cursors is what touches the spider.
cursor_tick :: proc() {
	in_ := &game.input
	in_.cursor_count += 1
	if in_.cursor_count <= CURSOR_TICKS do return
	in_.cursor_count = 0
	in_.cursor_frame += 1
	if in_.cursor_frame >= CURSOR_FRAMES[in_.cursor_set] do in_.cursor_frame = 0
	host_cursor(i32(in_.cursor_set), i32(in_.cursor_frame))
	if in_.cursor_frame != 0 do return
	s := &game.spider
	switch in_.cursor_set {
	case 5:
		host_sound(404)
		s.tool = .Tap
	case 4:
		host_sound(410)
		s.tool = .Prod
	case 7:
		host_sound(411)
		s.tool = .Stroke
	}
}

// Point-in-hit-rect test (0x416be0): the rect shrunk by 1/8 on each side,
// except for crickets.
hit_test :: proc(c: ^Creature, x, y: int) -> bool {
	r := c.hit
	if c.kind != .Cricket {
		dx, dy := (r.right - r.left) / 8, (r.bottom - r.top) / 8
		r = {r.left + dx, r.top + dy, r.right - dx, r.bottom - dy}
	}
	return x >= r.left && x < r.right && y >= r.top && y < r.bottom
}

// Whether the spider may be picked up (0x403a60).
spider_pickable :: proc(s: ^Creature) -> bool {
	return game.input.carry == .None && s.seq != game.seq.kill && s.hide == 0 &&
		s.y >= FLOOR_TOP && !s.eating && !game.life.dead
}

pointer_event :: proc(ev: Pointer_Event, vx, vy: int) {
	in_ := &game.input
	in_.inside = ev != .Leave
	in_.vx, in_.vy = vx, vy
	switch in_.view {
	case .Whole:
		whole_pointer(ev, vx, vy)
		return
	case .Close:
		if ev == .Down do leave_view()
		return
	case .Tank:
		if ev == .Right {
			if !box_covers(vx, vy) do ui_right_click(vx, vy)
			return
		}
		if game.ui.box.state != .Closed && in_.carry == .None && box_pointer(ev, vx, vy) do return
		if ui_pointer(ev, vx, vy) do return
	case .Box:
	}
	if ev == .Right do return
	if in_.view == .Tank {
		in_.x, in_.y = vx + game.scroll_x, vy
		game.cursor_x = in_.x
	} else {
		in_.x, in_.y = vx, vy
	}
	s := &game.spider

	switch ev {
	case .Right: // handled above
	case .Leave:
		if in_.carry == .None do in_.down = false
	case .Down:
		in_.down = true
		if in_.view == .Box {
			box_pick(in_.x, in_.y)
			return
		}
		switch in_.tool {
		case .Tap:
			set_cursor(5)
		case .Prod, .Stroke:
			if hit_test(s, in_.x, in_.y) && spider_pickable(s) && s.seq != game.seq.drop {
				if in_.tool == .Prod {
					set_cursor(4)
					in_.prodding = true
				} else {
					set_cursor(7)
					in_.stroking = true
				}
			}
		case .Pickup:
			pickup_at(in_.x, in_.y)
		case .Follow:
			if !s.goal.active || now_ms > s.goal.start_ms + 10_000 {
				move_to(s, .Cursor, in_.x, in_.y, -1, game.seq.lurk_d, 60)
			}
		}
	case .Move:
		// pointer at the left/right edge scrolls the viewfinder: port, only
		// while carrying something (the original always did; the port pans
		// with a right-drag or two fingers instead)
		if in_.view == .Tank && in_.carry != .None {
			if vx > VIEW_W - 20 {
				game.scroll_right, game.scroll_left = 8, 0
			} else if vx < 20 {
				game.scroll_left, game.scroll_right = 8, 0
			}
		}
		if in_.carry != .None {
			carry_move(in_.x, in_.y)
			set_cursor(3)
			return
		}
		if in_.view == .Box {
			set_cursor(box_cricket_at(in_.x, in_.y) >= 0 ? 2 : 1)
			return
		}
		switch in_.tool {
		case .Tap:
			set_cursor(in_.down ? 5 : 6)
		case .Pickup:
			set_cursor(grabbable_at(in_.x, in_.y) ? 2 : 1)
		case .Prod, .Stroke, .Follow:
			on_spider := hit_test(s, in_.x, in_.y)
			if in_.down && in_.prodding && on_spider {
				set_cursor(4)
			} else if in_.down && in_.stroking && on_spider {
				set_cursor(7)
			} else {
				set_cursor(1)
				in_.prodding, in_.stroking = false, false
			}
		}
	case .Up:
		in_.down = false
		in_.prodding, in_.stroking = false, false
		carry_release()
		pointer_event(.Move, vx, vy)
	}
}

grabbable_at :: proc(x, y: int) -> bool {
	s := &game.spider
	if hit_test(s, x, y) && spider_pickable(s) do return true
	for &o in game.objects do if o.active && !o.in_box && hit_test(&o.c, x, y) do return true
	for &c in game.crickets do if c.active && !c.in_box && hit_test(&c, x, y) do return true
	return false
}

// Pick-up tool press: the spider, else a cricket, else an object.
pickup_at :: proc(x, y: int) {
	in_ := &game.input
	s := &game.spider
	if hit_test(s, x, y) && spider_pickable(s) && s.seq != game.seq.drop {
		in_.carry = .Spider
		s.carried = 1
		force_sequence(s, game.seq.pickup)
		host_sound(405)
		debug_logf("picked up the spider")
		return
	}
	for &c in game.crickets {
		if !c.active || c.in_box || !hit_test(&c, x, y) do continue
		in_.carry, in_.carry_id = .Cricket, c.id
		c.carried = 1
		force_sequence(&c, game.cseq.pickup)
		host_sound(407)
		return
	}
	for &o in game.objects {
		if !o.active || o.in_box || !hit_test(&o.c, x, y) do continue
		in_.carry, in_.carry_id = .Object, o.id
		return
	}
}

carry_move :: proc(x, y: int) {
	in_ := &game.input
	switch in_.carry {
	case .None:
	case .Spider:
		c := &game.spider
		c.x, c.y = x, y
		c.prev_x, c.prev_y = x, y
		creature_update_position(c)
	case .Cricket:
		c := &game.crickets[in_.carry_id]
		c.x, c.y = x, y
		c.prev_x, c.prev_y = x, y
		creature_update_position(c)
	case .Object:
		o := &game.objects[in_.carry_id]
		o.x, o.y = x, y
		object_update_position(o)
	}
}

carry_release :: proc() {
	in_ := &game.input
	switch in_.carry {
	case .None:
	case .Spider:
		s := &game.spider
		s.carried = 2
		force_sequence(s, game.seq.drop)
		debug_logf("dropped the spider")
	case .Cricket:
		c := &game.crickets[in_.carry_id]
		c.carried = 2
		force_sequence(c, game.cseq.drop)
		debug_logf("cricket %d released", c.id)
		spider_sees_cricket(&game.spider, c)
	case .Object:
		o := &game.objects[in_.carry_id]
		if game.input.y >= VIEW_H - 2 {
			o.in_box = true // dragged out of the tank: put away
			debug_logf("%s put away", o.name)
		}
	}
	in_.carry = .None
}

// End the current sequence now and play seq next (0x408140 with "now").
force_sequence :: proc(c: ^Creature, seq: int) {
	clear_queue(c)
	clear_goal(c)
	c.turn_target, c.turn_dir = -1, 0
	c.pop_turning = false
	c.prev_seq = c.seq
	c.seq = seq
	c.dir = 4
	c.plays = 1
	c.step = 1
	c.back_pass = 0
	if c.kind == .Spider && seq == game.seq.pickup do c.tool = .Carry
	start_sequence(c)
}

// --- the cricket box ----------------------------------------------------

box_cricket_at :: proc(x, y: int) -> int {
	if crickets_in_tank() >= MAX_IN_TANK do return -1
	for &c in game.crickets do if c.active && c.in_box && hit_test(&c, x, y) do return c.id
	return -1
}

// Clicking a cricket in the box takes it out and carries it into the tank;
// clicking anywhere else goes back to the tank.
box_pick :: proc(x, y: int) {
	id := box_cricket_at(x, y)
	if id < 0 {
		game.input.view = .Tank
		host_view(i32(game.input.view))
		return
	}
	c := &game.crickets[id]
	in_ := &game.input
	in_.view = .Tank
	c.in_box = false
	c.carried = 1
	in_.carry, in_.carry_id = .Cricket, id
	tx := x + game.scroll_x
	c.x, c.y = tx, max(y, 200)
	c.prev_x, c.prev_y = c.x, c.y
	force_sequence(c, game.cseq.pickup)
	host_sound(407)
	host_view(i32(in_.view))
}

// --- buttons --------------------------------------------------------------

Button :: enum i32 {
	Scan_Follow = 2,
	Feed        = 3,
	Next_Tool   = 4,
	Water       = 7,
	Clear       = 9,
	Tank        = 100, // back from the box
}

@(export)
tank_pointer :: proc "contextless" (ev: Pointer_Event, x, y: i32) {
	n := game.pending_pointer_len
	if n >= len(game.pending_pointer) do return
	game.pending_pointer[n] = {ev, int(x), int(y)}
	game.pending_pointer_len = n + 1
}

@(export)
tank_button :: proc "contextless" (b: Button) {
	n := game.pending_buttons_len
	if n >= len(game.pending_buttons) do return
	game.pending_buttons[n] = b
	game.pending_buttons_len = n + 1
}

@(export)
tank_set_tool :: proc "contextless" (t: i32) {
	if t >= 0 && t < TOOL_COUNT do game.input.tool = Tool(t)
}

Pending_Pointer :: struct {
	ev:   Pointer_Event,
	x, y: int,
}

handle_input :: proc() {
	for p in game.pending_pointer[:game.pending_pointer_len] do pointer_event(p.ev, p.x, p.y)
	game.pending_pointer_len = 0
	for b in game.pending_buttons[:game.pending_buttons_len] do button(b)
	game.pending_buttons_len = 0
}

button :: proc(b: Button) {
	in_ := &game.input
	click := true
	#partial switch b {
	case .Scan_Follow:
		game.follow = !game.follow
	case .Feed:
		in_.view = .Box
	case Button(0):
		in_.view = .Close
	case Button(1):
		game.saved_tool = in_.tool
		in_.tool = .Pickup
		in_.view = .Whole
	case .Tank:
		in_.view = .Tank
	case .Next_Tool:
		// with the UI hidden the first one only shows the tools button
		// for 50 frames; while it shows, they cycle (0x41c4b0 case 4)
		s := &game.spider
		if s.goal.active && s.goal.type == .Cursor do clear_goal(s)
		u := &game.ui
		if u.shown || u.tools_flash > 0 do in_.tool = Tool((int(in_.tool) + 1) % TOOL_COUNT)
		if !u.shown do u.tools_flash = 50
	case .Water:
		bowl := &game.objects[BOWL]
		if bowl.active && !bowl.in_box && bowl.frame < bowl.def.frames - 1 {
			bowl.frame += 1
			host_sound(402)
			click = false
			if game.stats.water < 35 {
				move_to(&game.spider, .Creature_A, -1, -1, -1, game.seq.lurk, 120, target = BOWL)
			}
		}
	case .Clear:
		clear_debris()
	case Button(8):
		// the website (long gone: the host offers an archived copy)
		host_open(0)
		click = false
	case Button(5):
		// floating panel: the host shows the view in a small always-on-top window
		host_open(1)
	case:
		if int(b) == 6 {
			box_toggle()
		}
	}
	if click do host_sound(400)
	host_view(i32(in_.view))
	host_tool(i32(in_.tool), game.follow)
}
