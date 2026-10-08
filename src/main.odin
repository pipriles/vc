package vc

import "core:fmt"

// Entry point. The JS host picks the mode: the tank (game) or the
// animation viewer.

foreign import host "vc"

@(default_calling_convention = "contextless")
foreign host {
	// Files are prefetched by the JS host, so these are synchronous.
	file_size ::   proc(name: string) -> i32 ---
	file_read ::   proc(name: string, dst: [^]u8) ---
	present ::     proc(rgba: [^]u8, w, h: i32) ---
	host_mode ::   proc() -> i32 --- // 0 = tank, 1 = viewer
	host_time ::   proc() -> f64 --- // seconds since the epoch, for srand(time(NULL))
	ui_add_anim :: proc(name: string) ---
	ui_add_seq ::  proc(anim: i32, name: string, dir_mask: u32) ---
	ui_status ::   proc(seq, dir, frame, frames: i32) ---
	tank_status :: proc(food, water, health, mood, temperament: i32, seq: string, dir: i32) ---
}

MAX_W :: 320
MAX_H :: 200
TICK  :: 0.1 // seconds per tick: original uses SetTimer(hwnd, 1, 100)

Mode :: enum {
	Tank,
	Viewer,
}

mode: Mode
running: bool

load_file :: proc(name: string) -> []u8 {
	n := file_size(name)
	if n < 0 do return nil
	buf := make([]u8, int(n))
	if n > 0 do file_read(name, raw_data(buf))
	return buf
}

main :: proc() {
	mode = host_mode() == 1 ? .Viewer : .Tank
	switch mode {
	case .Tank:
		running = tank_init()
		if running do build_shade_table()
	case .Viewer:
		running = viewer_init()
	}
	if !running do fmt.eprintln("initialisation failed")
}

@(export)
step :: proc(dt: f64) -> bool {
	if !running do return false
	switch mode {
	case .Tank:
		tank_step(dt)
	case .Viewer:
		viewer_step(dt)
	}
	return true
}
