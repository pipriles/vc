#+build !js
package vc

import "base:runtime"
import "core:os"
import "core:strings"

// Native stand-ins for the JS host, used by `odin test` and headless runs.
// Files are read from data_dir (e.g. "data/cr").

data_dir := "data/cr"

file_size :: proc "contextless" (name: string) -> i32 {
	context = runtime.default_context()
	path := strings.concatenate({data_dir, "/", name}, context.temp_allocator)
	fi, err := os.stat(path, context.temp_allocator)
	if err != nil do return -1
	return i32(fi.size)
}

file_read :: proc "contextless" (name: string, dst: [^]u8) {
	context = runtime.default_context()
	path := strings.concatenate({data_dir, "/", name}, context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err == nil do copy(dst[:len(data)], data)
}

present :: proc "contextless" (rgba: [^]u8, w, h: i32) {}
host_mode :: proc "contextless" () -> i32 {return 0}
host_time :: proc "contextless" () -> f64 {return 0}
ui_add_anim :: proc "contextless" (name: string) {}
ui_add_seq :: proc "contextless" (anim: i32, name: string, dir_mask: u32) {}
ui_status :: proc "contextless" (seq, dir, frame, frames: i32) {}
tank_status :: proc "contextless" (food, water, health, mood, temperament: i32, seq: string, dir: i32) {}
debug_begin :: proc "contextless" () {}
debug_rect :: proc "contextless" (x, y, w, h: i32, color: u32) {}
debug_line :: proc "contextless" (x0, y0, x1, y1: i32, color: u32) {}
debug_text :: proc "contextless" (x, y: i32, text: string, color: u32) {}
debug_panel :: proc "contextless" (text: string) {}
debug_log :: proc "contextless" (text: string) {}
host_sound :: proc "contextless" (id: int) {}
ui_add_object :: proc "contextless" (id: i32, name: string, in_tank: bool) {}
host_cursor :: proc "contextless" (set, frame: i32) {}
host_view :: proc "contextless" (view: i32) {}
host_tool :: proc "contextless" (tool: i32, follow: bool) {}
host_options :: proc "contextless" (open: bool) {}
ui_begin :: proc "contextless" () {}
ui_text :: proc "contextless" (x, y: int, text: string) {}
host_loop :: proc "contextless" (id: int, on: bool) {}
