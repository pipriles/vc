// Host for the Odin wasm module: prefetches data files, exposes them through
// the "vc" foreign import, and blits frames to a canvas.

const SCALE = 3;
const DIR_NAMES = ["0", "1", "2", "3", "4", "5", "6", "7"];

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const variant = params.get("v") ?? "cr";
const base = `data/${variant}/`;

const manifest = await fetch(base + "manifest.json").then((r) => r.json());
const files = new Map();
await Promise.all(manifest.files.map(async (name) => {
	const r = await fetch(base + name);
	if (r.ok) files.set(name, new Uint8Array(await r.arrayBuffer()));
}));

const mem = new odin.WasmMemoryInterface();
const canvas = $("view");
const ctx = canvas.getContext("2d");
const seqs = []; // per animation: [{name, mask}]

const imports = {
	vc: {
		file_size: (p, n) => files.get(mem.loadString(p, n))?.length ?? -1,
		file_read: (p, n, dst) => {
			const f = files.get(mem.loadString(p, n));
			mem.loadBytes(dst, f.length).set(f);
		},
		present: (ptr, w, h) => {
			if (canvas.width !== w || canvas.height !== h || !canvas.style.width) {
				canvas.width = w;
				canvas.height = h;
				canvas.style.width = `${w * SCALE}px`;
			}
			const px = new Uint8ClampedArray(mem.memory.buffer, ptr, w * h * 4);
			ctx.putImageData(new ImageData(px, w, h), 0, 0);
		},
		ui_add_anim: (p, n) => {
			$("anim").add(new Option(mem.loadString(p, n), seqs.length));
			seqs.push([]);
		},
		ui_add_seq: (anim, p, n, mask) => seqs[anim].push({ name: mem.loadString(p, n), mask }),
		ui_status: (seq, dir, frame, frames) => {
			$("status").textContent = `frame ${frame + 1} / ${frames}`;
			if ($("dir").value != dir) $("dir").value = dir;
		},
	},
};

function fillSeqs() {
	const list = seqs[$("anim").value] ?? [];
	$("seq").replaceChildren(...list.map((s, i) => new Option(s.name, i)));
	fillDirs();
}

function fillDirs() {
	const s = seqs[$("anim").value]?.[$("seq").value];
	$("dir").replaceChildren(...DIR_NAMES.map((name, k) => {
		const o = new Option(name, k);
		o.disabled = !s || !(s.mask & (1 << k));
		return o;
	}));
}

const select = () => mem.exports.viewer_select(+$("anim").value, +$("seq").value, +$("dir").value);

$("variant").value = variant;
$("variant").onchange = () => { location.search = `?v=${$("variant").value}`; };
$("anim").onchange = () => { fillSeqs(); select(); };
$("seq").onchange = () => { fillDirs(); select(); };
$("dir").onchange = select;
$("speed").oninput = () => {
	$("speedv").textContent = `${$("speed").value}×`;
	mem.exports.viewer_set_speed(+$("speed").value);
};
let paused = false;
$("play").onclick = () => {
	paused = !paused;
	$("play").textContent = paused ? "Play" : "Pause";
	mem.exports.viewer_set_paused(paused ? 1 : 0);
};
$("prev").onclick = () => mem.exports.viewer_step_frame(-1);
$("next").onclick = () => mem.exports.viewer_step_frame(1);

await odin.runWasm("vc.wasm", null, imports, mem);
fillSeqs();
