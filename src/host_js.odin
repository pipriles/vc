#+build js
package vc

// Imports provided by web/main.js.

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
	// debug overlay, view coordinates; colour is 0xRRGGBB
	debug_begin :: proc() ---
	debug_rect ::  proc(x, y, w, h: i32, color: u32) ---
	debug_line ::  proc(x0, y0, x1, y1: i32, color: u32) ---
	debug_text ::  proc(x, y: i32, text: string, color: u32) ---
	debug_panel :: proc(text: string) ---
	debug_log ::   proc(text: string) ---
	host_sound ::  proc(id: int) --- // WAVE resource id
	host_loop ::   proc(id: int, on: bool) ---
	host_save ::   proc(json: string) ---
	host_message :: proc(title, text: string) ---
	host_cursor :: proc(set, frame: i32) ---
	host_view ::   proc(view: i32) ---
	host_tool ::   proc(tool: i32, follow: bool) ---
	host_open ::    proc(what: i32) --- // 0 = the website, 1 = floating panel
	ui_text_ex ::   proc(x, y, w, h: int, text: string, font, color, flags: i32) --- // flags: 1 centre, 2 wrap, 4 clip
	host_set_sound :: proc(on: bool) ---
	host_fullscreen :: proc() ---
	host_settings :: proc(frame_rate: i32, smooth, help_text: bool, saver_idle: i32) ---
	host_saver ::   proc() --- // start the screensaver, full screen
	host_name ::    proc(name: string) --- // the pet's name changed (edited in the tank)
	host_tz_offset :: proc() -> i32 --- // minutes east of UTC
	ui_begin ::    proc() ---
	ui_text ::     proc(x, y: int, text: string) ---
	ui_tip ::      proc(x, y: int, text: string) --- // a tooltip (0x411fe0): boxed, moved left to fit
}
