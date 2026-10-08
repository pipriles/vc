package vc

import "core:fmt"

// Entry point. The JS host picks the mode: the tank (game) or the
// animation viewer. Host imports live in host_js.odin / host_native.odin.

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
