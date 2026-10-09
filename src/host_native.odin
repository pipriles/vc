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
	if name == "save.json" do return i32(len(saved_json))
	path := strings.concatenate({data_dir, "/", name}, context.temp_allocator)
	fi, err := os.stat(path, context.temp_allocator)
	if err != nil do return -1
	return i32(fi.size)
}

file_read :: proc "contextless" (name: string, dst: [^]u8) {
	context = runtime.default_context()
	if name == "save.json" {
		copy(dst[:len(saved_json)], saved_json)
		return
	}
	path := strings.concatenate({data_dir, "/", name}, context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err == nil do copy(dst[:len(data)], data)
}

presented: int // frames sent to the host, for tests
present :: proc "contextless" (rgba: [^]u8, w, h: i32) {presented += 1}
host_mode :: proc "contextless" () -> i32 {return 0}
host_time :: proc "contextless" () -> f64 {return 1_000_000_000} // a fixed "now" for tests
ui_add_anim :: proc "contextless" (name: string) {}
ui_add_seq :: proc "contextless" (anim: i32, name: string, dir_mask: u32) {}
ui_status :: proc "contextless" (seq, dir, frame, frames: i32) {}
tank_status :: proc "contextless" (food, water, health, mood, temperament: i32, seq: string, dir: i32) {}
debug_begin :: proc "contextless" () {}
debug_rect :: proc "contextless" (x, y, w, h: i32, color: u32) {}
debug_line :: proc "contextless" (x0, y0, x1, y1: i32, color: u32) {}
debug_text :: proc "contextless" (x, y: i32, text: string, color: u32) {}
debug_panel :: proc "contextless" (text: string) {}
debug_print := false // tests may turn this on to see the debug log
debug_log :: proc "contextless" (text: string) {
	if debug_print {
		context = runtime.default_context()
		os.write_string(os.stdout, text)
		os.write_string(os.stdout, "\n")
	}
}
host_sound :: proc "contextless" (id: int) {}
host_cursor :: proc "contextless" (set, frame: i32) {}
host_view :: proc "contextless" (view: i32) {}
host_tool :: proc "contextless" (tool: i32, follow: bool) {}
host_open :: proc "contextless" (what: i32) {}
ui_text_ex :: proc "contextless" (x, y, w, h: int, text: string, font, color, flags: i32) {}
host_set_sound :: proc "contextless" (on: bool) {}
host_fullscreen :: proc "contextless" () {}
host_settings :: proc "contextless" (frame_rate: i32, smooth, help_text: bool, saver_idle: i32) {}
host_saver :: proc "contextless" () {}
host_tz_offset :: proc "contextless" () -> i32 {return 0}
ui_begin :: proc "contextless" () {}
ui_text :: proc "contextless" (x, y: int, text: string) {}
host_loop :: proc "contextless" (id: int, on: bool) {}
host_save :: proc "contextless" (json: string) {
	context = runtime.default_context()
	delete(saved_json)
	saved_json = strings.clone(json)
}
host_message :: proc "contextless" (title, text: string) {
	context = runtime.default_context()
	last_message = strings.clone(title)
}
saved_json: string // what the last save wrote (tests read it back as save.json)
last_message: string
