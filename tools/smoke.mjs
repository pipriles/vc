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

async function run(variant, mode) {
	const base = `${root}/data/${variant}/`;
	const manifest = JSON.parse(readFileSync(base + "manifest.json", "utf8"));
	const files = new Map(manifest.files.map((n) => [n, new Uint8Array(readFileSync(base + n))]));

	const mem = new odin.WasmMemoryInterface();
	const str = (p, n) => mem.loadString(p, n);
	const log = [];
	const vc = {
		file_size: (p, n) => files.get(str(p, n))?.length ?? -1,
		file_read: (p, n, dst) => { const f = files.get(str(p, n)); mem.loadBytes(dst, f.length).set(f); },
		present: noop, host_mode: () => mode, host_time: () => Date.now() / 1000,
		ui_add_anim: noop, ui_add_seq: noop, ui_status: noop, ui_add_object: noop,
		tank_status: noop, host_sound: noop,
		debug_begin: noop, debug_rect: noop, debug_line: noop, debug_text: noop,
		debug_panel: noop, debug_log: (p, n) => log.push(str(p, n)),
	};
	const imports = { ...odin.setupDefaultImports(mem, null), vc };
	const { instance } = await WebAssembly.instantiate(wasmBytes, imports);
	const ex = instance.exports;
	mem.setExports(ex);
	mem.setMemory(ex.memory);
	ex._start();
	const ctx = ex.default_context_ptr();

	if (mode === 0) {
		ex.tank_set_debug(1);
		for (let i = 0; i < 10; i++) ex.tank_set_object(i, 1);
	}
	for (let t = 0; t < ticks; t++) {
		if (mode === 0 && t % 200 === 0) ex.tank_drop_cricket();
		if (!ex.step(0.1, ctx)) throw new Error("step returned false");
	}
	return log.length;
}

let failed = false;
for (const variant of ["cr", "rk"]) {
	for (const [mode, name] of [[0, "tank"], [1, "viewer"]]) {
		try {
			const n = await run(variant, mode);
			console.log(`ok   ${variant} ${name} (${ticks} ticks${mode === 0 ? `, ${n} log lines` : ""})`);
		} catch (e) {
			failed = true;
			console.log(`FAIL ${variant} ${name}: ${e.message}`);
		}
	}
}
process.exit(failed ? 1 : 0);
