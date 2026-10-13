// Headless smoke test of the browser build: runs build/vc.wasm in Node with
// the extracted data, for both variants and both pages, and fails on any
// trap. Catches problems the native `odin test` run can't (js_wasm32-only
// code paths, host imports).
//
// Usage: node tools/smoke.mjs [ticks]

import { readFileSync } from "node:fs";
import { runInThisContext } from "node:vm";

const root = new URL("..", import.meta.url).pathname;
const ticks = Number(process.argv[2] ?? 3000);

// odin.js is a browser script that sets window.odin
globalThis.window = globalThis;
runInThisContext(readFileSync(`${root}/build/odin.js`, "utf8"));
const wasmBytes = readFileSync(`${root}/build/vc.wasm`);

function noop() {}

async function run(variant, mode, saveJson = null) {
	const base = `${root}/data/${variant}/`;
	const manifest = JSON.parse(readFileSync(base + "manifest.json", "utf8"));
	const files = new Map(manifest.files.map((n) => [n, new Uint8Array(readFileSync(base + n))]));
	if (saveJson) files.set("save.json", new TextEncoder().encode(saveJson));

	const mem = new odin.WasmMemoryInterface();
	const str = (p, n) => mem.loadString(p, n);
	const log = [];
	let saved = "";
	const vc = {
		file_size: (p, n) => files.get(str(p, n))?.length ?? -1,
		file_read: (p, n, dst) => { const f = files.get(str(p, n)); mem.loadBytes(dst, f.length).set(f); },
		present: noop, host_mode: () => mode, host_time: () => Date.now() / 1000,
		ui_add_anim: noop, ui_add_seq: noop, ui_status: noop, 
		tank_status: noop, host_sound: noop, host_loop: noop, host_save: (p, n) => { saved = str(p, n); },
		host_message: noop,  host_cursor: noop, host_view: noop, host_tool: noop,
		host_open: noop, ui_text_ex: noop, host_set_sound: noop, host_fullscreen: noop, host_settings: noop, host_saver: noop, host_name: noop, host_tz_offset: () => 0, ui_begin: noop, ui_text: noop, ui_tip: noop,
		debug_begin: noop, debug_rect: noop, debug_line: noop, debug_text: noop,
		debug_panel: noop, debug_log: (p, n) => log.push(str(p, n)),
	};
	const imports = { ...odin.setupDefaultImports(mem, null), vc };
	const { instance } = await WebAssembly.instantiate(wasmBytes, imports);
	const ex = instance.exports;
	mem.setExports(ex);
	mem.setMemory(ex.memory);
	if (mode === 0) ex.tank_set_debug(1); // log the load / catch-up during start-up
	ex._start();
	const ctx = ex.default_context_ptr();

	if (mode === 0) {
		ex.tank_set_debug(1);
		for (const ch of "ICK4 7") ex.tank_name_char(ch.charCodeAt(0));
		for (let i = 0; i < 10; i++) ex.tank_set_object(i, 1);
	}
	for (let t = 0; t < ticks; t++) {
		if (mode === 0 && t % 200 === 0) ex.tank_drop_cricket();
		if (mode === 0 && t % 50 === 0) {
			// poke at the tank with every tool, the buttons and the box
			ex.tank_set_tool((t / 50) % 5);
			const x = (t * 37) % 640, y = 150 + (t * 53) % 330;
			ex.tank_pointer(1, x, y);
			ex.tank_pointer(0, x + 20, y + 10);
			if (t % 100 === 0) ex.tank_pointer(2, x + 20, y + 10);
			ex.tank_button([2, 3, 4, 7, 9, 100, 0, 1, 5, 6, 8][(t / 50) % 11]);
			// and the in-view buttons by pointer
			ex.tank_pointer(0, 20 + ((t / 50) % 10) * 52 + 20, 440);
			ex.tank_pointer(1, 20 + ((t / 50) % 10) * 52 + 20, 440);
			ex.tank_pointer(2, 20 + ((t / 50) % 10) * 52 + 20, 440);
		}
		if (!ex.step(0.1, ctx)) throw new Error("step returned false");
	}
	if (mode === 0) {
		ex.tank_save();
		if (!saved.startsWith("{")) throw new Error("tank_save wrote nothing");
		ex.tank_resume(600); // ten hours away
		ex.tank_resurrect();
		ex.tank_new_spider();
		ex.tank_set_frame_rate(2, 1); // 18 fps, smooth
		ex.tank_set_saver(1);
		for (let t = 0; t < 50; t++) ex.step(0.016, ctx);
		ex.tank_set_saver(0);
		// touch: padded buttons, and what's under a finger
		ex.tank_set_touch(1);
		if (ex.tank_ui_at(30, 440) !== 1) throw new Error("no button under a finger at (30, 440)");
		if (ex.tank_ui_at(580, 440) !== 2) throw new Error("no logo under a finger at (580, 440)");
		if (ex.tank_ui_at(320, 250) !== 0) throw new Error("UI in the middle of the tank");
		ex.tank_set_touch(0);
		// every typed command, then a few drawn frames
		for (const w of ["VENUS", "FLYTRAP", "BUFFALO", "PARKER", "DIET", "SAHARA", "PARTY", "LANDOFTHEGIANTS",
			"MICROCOSM", "JARVIS", "VINNIE", "OLIVER", "SWAMPY", "SURFER", "FLINT", "SHOWFPS", "KAMIKAZE",
			"URSULLA", "GLOBALBEACH"]) {
			for (const ch of w) ex.tank_char(ch.charCodeAt(0));
			ex.tank_char(13);
			for (let t = 0; t < 10; t++) ex.step(0.1, ctx);
		}
		ex.tank_intro(); // the opening sequence, drawn
		for (let t = 0; t < 200; t++) ex.step(0.1, ctx);
		ex.tank_skip_intro();
		ex.tank_set_frame_rate(1, 0);
		for (let t = 0; t < 50; t++) ex.step(0.1, ctx);
	}
	return mode === 0 && !saveJson ? { lines: log.length, saved } : { lines: log.length, log };
}

let failed = false;
for (const variant of ["cr", "rk"]) {
	for (const [mode, name] of [[0, "tank"], [1, "viewer"]]) {
		try {
			const r = await run(variant, mode);
			console.log(`ok   ${variant} ${name} (${ticks} ticks${mode === 0 ? `, ${r.lines} log lines` : ""})`);
			if (mode === 0) {
				// load that save as if it was written 30 hours ago
				const old = JSON.parse(r.saved);
				old.saved_at -= 30 * 3600;
				const r2 = await run(variant, 0, JSON.stringify(old));
				const caught = r2.log.some((l) => l.includes("catching up 1800 minutes"));
				if (!caught) throw new Error("save not loaded / no catch-up");
				console.log(`ok   ${variant} tank loads a 30-hour-old save`);
			}
		} catch (e) {
			failed = true;
			console.log(`FAIL ${variant} ${name}: ${e.message}`);
		}
	}
}
process.exit(failed ? 1 : 0);
