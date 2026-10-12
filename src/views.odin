package vc

// The whole-tank view (zoom out, with the object panel) and the close-up
// (zoom in), from the main update (0x40ca70) and 0x40e360.

WHOLE_H     :: VIEW_H * VIEW_W / TANK_W // 256: the tank scaled to the view width
PANEL_Y     :: 0x104 // 260: object cells start here
CELL        :: 96    // 0x42c730 x 0x42c734
CELL_COLS   :: VIEW_W / (CELL + 8) - 1 // 5
CELL_X0     :: VIEW_W / 2 - CELL_COLS * (CELL + 8) / 2 // 60
CELL_STEP_X :: CELL + 10
CELL_STEP_Y :: CELL + 8

cell_rect :: proc(i: int) -> (x, y: int) {
	return CELL_X0 + (i % CELL_COLS) * CELL_STEP_X, PANEL_Y + (i / CELL_COLS) * CELL_STEP_Y
}

cell_at :: proc(vx, vy: int) -> int {
	for i in 0 ..< OBJECT_COUNT {
		x, y := cell_rect(i)
		if vx >= x && vx < x + CELL && vy >= y && vy < y + CELL do return i
	}
	return -1
}

// view -> tank coordinates in the whole-tank view
whole_to_tank :: proc(vx, vy: int) -> (x, y: int) {
	return vx * TANK_W / VIEW_W, vy * VIEW_H / WHOLE_H
}

// Whole tank: the scene scaled to 640x256, the object panel below.
whole_render :: proc() {
	for i in 0 ..< len(view) do view[i] = 0
	for y in 0 ..< WHOLE_H {
		sy := y * VIEW_H / WHOLE_H
		for x in 0 ..< VIEW_W do view[y * VIEW_W + x] = tank_buf[sy * TANK_W + x * TANK_W / VIEW_W]
	}

	in_ := &game.input
	hover := in_.inside && in_.carry == .None ? cell_at(in_.vx, in_.vy) : -1
	corners := &game.ui.cell_corners
	cw := corners.w
	ch := corners.h / 4
	for &o, i in game.objects {
		x, y := cell_rect(i)
		placeable := o.active && o.in_box && objects_in_tank() < MAX_OBJECTS_IN_TANK
		// dithered cell, lighter when it can be dragged out (0x40e2a0)
		colour: u8 = i == hover && placeable ? 2 : 1
		for j := 0; j < CELL; j += 2 do for k := 0; k < CELL; k += 2 do view[(y + j) * VIEW_W + x + k] = colour
		if o.active && o.in_box {
			s := min(100, (CELL - 8) * 100 / max(o.fw, o.fh))
			draw_object(&o, .Shadow, x + CELL / 2, y + CELL / 2, s)
			draw_object(&o, .Body, x + CELL / 2, y + CELL / 2, s)
		}
		if cw > 0 {
			draw_keyed_part(corners, x, y, 0, ch)
			draw_keyed_part(corners, x + CELL - cw, y, ch, ch)
			draw_keyed_part(corners, x, y + CELL - ch, 2 * ch, ch)
			draw_keyed_part(corners, x + CELL - cw, y + CELL - ch, 3 * ch, ch)
		}
	}
	ui_begin()
	for &o, i in game.objects {
		x, y := cell_rect(i)
		ui_text(x + 4, y + 4, o.name)
	}
}

// Close-up: the spider's frame box stretched to the whole view.
close_render :: proc() {
	s := &game.spider
	w, h := s.anim.w, s.anim.h
	x0 := clamp(s.x - w / 2, 0, TANK_W - w)
	y0 := clamp(s.y - h / 2, 0, VIEW_H - h)
	for y in 0 ..< VIEW_H {
		row := (y0 + y * h / VIEW_H) * TANK_W + x0
		for x in 0 ..< VIEW_W do view[y * VIEW_W + x] = tank_buf[row + x * w / VIEW_W]
	}
	ui_begin()
}

leave_view :: proc() {
	in_ := &game.input
	if in_.view == .Whole do in_.tool = game.saved_tool
	in_.view = .Tank
	host_view(i32(in_.view))
}

// Pointer in the whole-tank view: drag objects between the tank and the
// panel; a click anywhere else goes back to the tank.
whole_pointer :: proc(ev: Pointer_Event, vx, vy: int) {
	in_ := &game.input
	in_.x, in_.y = whole_to_tank(vx, vy)
	#partial switch ev {
	case .Down:
		if c := cell_at(vx, vy); c >= 0 && game.objects[c].active && game.objects[c].in_box && objects_in_tank() < MAX_OBJECTS_IN_TANK {
			in_.carry, in_.carry_id = .Object, c
			in_.down = true
			set_cursor(3)
			return
		}
		if vy < WHOLE_H {
			for &o in game.objects {
				if !o.active || o.in_box || !hit_test(&o.c, in_.x, in_.y) do continue
				in_.carry, in_.carry_id = .Object, o.id
				in_.down = true
				set_cursor(3)
				return
			}
		}
		leave_view()
	case .Move:
		if in_.carry == .Object {
			o := &game.objects[in_.carry_id]
			if vy >= WHOLE_H {
				o.in_box = true // back in the panel
			} else {
				o.in_box = false
				o.x, o.y = in_.x, in_.y
				object_update_position(o)
			}
			set_cursor(3)
			return
		}
		over := cell_at(vx, vy)
		set_cursor(over >= 0 && game.objects[over].in_box && objects_in_tank() < MAX_OBJECTS_IN_TANK ? 2 : 1)
	case .Up:
		in_.down = false
		if in_.carry == .Object {
			o := &game.objects[in_.carry_id]
			if o.in_box do debug_logf("%s back in the panel", o.name)
			else do debug_logf("%s placed at (%d, %d)", o.name, o.x, o.y)
		}
		in_.carry = .None
		set_cursor(1)
	case .Leave:
	}
}
