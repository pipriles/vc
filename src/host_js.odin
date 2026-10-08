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
}
