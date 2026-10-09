package vc

// Port: a route planner for the spider's walks (the original only steers
// straight at its target and detours round one obstacle at a time). The
// floor is a grid of 20 px squares; a square is free when the spider's body
// (the middle of its frame box, as in its collisions with objects) fits
// there without touching an object. A breadth-first search over the eight
// neighbours gives the route; the spider heads for a square a few steps
// along it. No random numbers are drawn.

GRID :: 20
GRID_X0 :: WALL_MARGIN
GRID_Y0 :: FLOOR_TOP
GRID_W :: (TANK_W - 2 * WALL_MARGIN) / GRID + 1
GRID_H :: (VIEW_H - FLOOR_TOP) / GRID + 1
PATH_AHEAD :: 4 // squares ahead to head for

@(private = "file")
grid_free: [GRID_W * GRID_H]bool
@(private = "file")
grid_from: [GRID_W * GRID_H]i16 // previous square on the route, -1 none, -2 start
@(private = "file")
grid_queue: [GRID_W * GRID_H]i16

grid_cell :: proc(x, y: int) -> (gx, gy: int) {
	gx = clamp((x - GRID_X0 + GRID / 2) / GRID, 0, GRID_W - 1)
	gy = clamp((y - GRID_Y0 + GRID / 2) / GRID, 0, GRID_H - 1)
	return
}

grid_pos :: proc(gx, gy: int) -> (x, y: int) {return GRID_X0 + gx * GRID, GRID_Y0 + gy * GRID}

// Marks the squares where the spider's body fits.
@(private = "file")
grid_build :: proc(c: ^Creature) {
	h := c.hit
	w, hh := h.right - h.left, h.bottom - h.top
	// the body box relative to the spider's position (see collide_mark)
	l, t := h.left + w / 5 - c.x, h.top + hh / 5 - c.y
	r, b := h.right - w / 5 - c.x, h.bottom - hh / 5 - c.y
	dh := x87_scale_trunc(c.anim.h, c.scale)
	for gy in 0 ..< GRID_H do for gx in 0 ..< GRID_W {
		x, y := grid_pos(gx, gy)
		free := y + dh / 3 < VIEW_H
		body := Rect{x + l, y + t, x + r, y + b}
		if free do for &o in game.objects {
			if !o.active || o.in_box do continue
			// a few pixels of slack, as the collisions allow some overlap
			ob := Rect{o.hit.left + 4, o.hit.top + 4, o.hit.right - 4, o.hit.bottom - 4}
			if rects_intersect(body, ob) {free = false; break}
		}
		grid_free[gy * GRID_W + gx] = free
	}
}

// Plans from the spider to (tx, ty). Returns the point to head for next
// and where the route ends: the target's square, or the reachable square
// nearest to it when the target can't be reached.
plan_route :: proc(c: ^Creature, tx, ty: int) -> (wx, wy: int, end_x, end_y: int, ok: bool) {
	return plan(c, tx, ty, -1, -1)
}

// Plans to the nearest reachable spot whose y lies in [y0, y1] (goals
// where only the height matters, like the glass); (tx, ty) is the fallback.
plan_route_band :: proc(c: ^Creature, y0, y1, tx, ty: int) -> (wx, wy: int, end_x, end_y: int, ok: bool) {
	return plan(c, tx, ty, y0, y1)
}

@(private = "file")
plan :: proc(c: ^Creature, target_x, target_y, band0, band1: int) -> (wx, wy: int, end_x, end_y: int, ok: bool) {
	tx, ty := target_x, target_y
	grid_build(c)
	sx, sy := grid_cell(c.x, c.y)
	ex, ey := grid_cell(tx, ty)
	band := band0 >= 0
	for &f in grid_from do f = -1
	start := sy * GRID_W + sx
	grid_from[start] = -2
	grid_free[start] = true // wherever it stands now
	head, tail := 0, 0
	grid_queue[tail] = i16(start); tail += 1
	best, best_d := start, max(int)
	for head < tail {
		i := int(grid_queue[head]); head += 1
		gx, gy := i % GRID_W, i / GRID_W
		if band {
			// breadth first: the first square in the band is the nearest
			if _, y := grid_pos(gx, gy); y >= band0 && y <= band1 {
				best, best_d = i, 0
				tx, ty = grid_pos(gx, gy)
				break
			}
		}
		if d := (gx - ex) * (gx - ex) + (gy - ey) * (gy - ey); d < best_d {
			best, best_d = i, d
			if d == 0 && !band do break
		}
		for dy in -1 ..= 1 do for dx in -1 ..= 1 {
			nx, ny := gx + dx, gy + dy
			if (dx == 0 && dy == 0) || nx < 0 || ny < 0 || nx >= GRID_W || ny >= GRID_H do continue
			n := ny * GRID_W + nx
			if !grid_free[n] || grid_from[n] != -1 do continue
			// no cutting corners between two blocked squares
			if dx != 0 && dy != 0 && !grid_free[gy * GRID_W + nx] && !grid_free[ny * GRID_W + gx] do continue
			grid_from[n] = i16(i)
			grid_queue[tail] = i16(n); tail += 1
		}
	}
	end_x, end_y = grid_pos(best % GRID_W, best / GRID_W)
	if best == start {
		return tx, ty, end_x, end_y, false
	}
	// walk back from the end to find the square PATH_AHEAD steps along
	steps := 0
	for i := best; grid_from[i] != -2; i = int(grid_from[i]) do steps += 1
	target := best
	for k := steps - min(PATH_AHEAD, steps); k > 0; k -= 1 do target = int(grid_from[target])
	wx, wy = grid_pos(target % GRID_W, target / GRID_W)
	if best_d == 0 && steps <= PATH_AHEAD {
		wx, wy = tx, ty // last stretch: the target itself
	}
	return wx, wy, end_x, end_y, true
}

// Whether the spider's body fits at (x, y) (after a plan_route or
// grid_prepare for the same spider).
grid_prepare :: proc(c: ^Creature) {grid_build(c)}
grid_fits :: proc(x, y: int) -> bool {
	gx, gy := grid_cell(x, y)
	return grid_free[gy * GRID_W + gx]
}
