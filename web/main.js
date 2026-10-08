// Host for the Odin wasm module: prefetches data files, exposes them through
// the "vc" foreign import, and blits frames to a canvas. The page picks the
// mode with <body data-mode="tank|viewer">.

const SCALE = 3; // viewer zoom
const DIR_NAMES = ["0 ↑", "1 ↗", "2 →", "3 ↘", "4 ↓", "5 ↙", "6 ←", "7 ↖"];

const $ = (id) => document.getElementById(id);
const mode = document.body.dataset.mode === "viewer" ? 1 : 0;
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
const seqs = []; // viewer: per animation [{name, mask}]
const overlay = $("overlay");
const octx = overlay?.getContext("2d");
if (octx) { octx.font = "12px ui-monospace, Menlo, monospace"; octx.lineWidth = 1; }
const debugLines = [];
const hex = (c) => `#${c.toString(16).padStart(6, "0")}`;

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
				if (mode === 1) canvas.style.width = `${w * SCALE}px`;
			}
			const px = new Uint8ClampedArray(mem.memory.buffer, ptr, w * h * 4);
			ctx.putImageData(new ImageData(px, w, h), 0, 0);
		},
		host_mode: () => mode,
		host_time: () => Date.now() / 1000,
		ui_add_anim: (p, n) => {
			$("anim").add(new Option(mem.loadString(p, n), seqs.length));
			seqs.push([]);
		},
		ui_add_seq: (anim, p, n, mask) => seqs[anim].push({ name: mem.loadString(p, n), mask }),
		ui_status: (seq, dir, frame, frames) => {
			$("status").textContent = `frame ${frame + 1} / ${frames}`;
			if ($("dir").value != dir) $("dir").value = dir;
		},
		debug_begin: () => {
			octx.clearRect(0, 0, overlay.width, overlay.height);
		},
		debug_rect: (x, y, w, h, color) => {
			octx.strokeStyle = hex(color);
			octx.strokeRect(x + 0.5, y + 0.5, w, h);
		},
		debug_line: (x0, y0, x1, y1, color) => {
			octx.strokeStyle = hex(color);
			octx.beginPath();
			octx.moveTo(x0 + 0.5, y0 + 0.5);
			octx.lineTo(x1 + 0.5, y1 + 0.5);
			octx.stroke();
		},
		debug_text: (x, y, p, n, color) => {
			octx.fillStyle = hex(color);
			octx.fillText(mem.loadString(p, n), x, y);
		},
		debug_panel: (p, n) => { $("debug-panel").textContent = mem.loadString(p, n); },
		debug_log: (p, n) => {
			const log = $("debug-log");
			debugLines.push(mem.loadString(p, n));
			if (debugLines.length > 200) debugLines.shift();
			log.textContent = debugLines.join("\n");
			log.scrollTop = log.scrollHeight;
		},
		host_sound: (id) => {}, // sound comes later
		ui_add_object: (id, p, n, inTank) => {
			const label = document.createElement("label");
			const box = document.createElement("input");
			box.type = "checkbox";
			box.checked = !!inTank;
			box.onchange = () => mem.exports.tank_set_object(id, box.checked ? 1 : 0);
			label.append(box, " " + mem.loadString(p, n));
			$("objects")?.append(label);
		},
		tank_status: (food, water, health, mood, temper, p, n, dir) => {
			$("status").textContent =
				`food ${food}  water ${water}  health ${health}  mood ${mood}  temperament ${temper}` +
				`  ·  ${mem.loadString(p, n)} ${DIR_NAMES[dir]}`;
		},
	},
};

function setupViewer() {
	const fillDirs = () => {
		const s = seqs[$("anim").value]?.[$("seq").value];
		$("dir").replaceChildren(...DIR_NAMES.map((name, k) => {
			const o = new Option(name, k);
			o.disabled = !s || !(s.mask & (1 << k));
			return o;
		}));
	};
	const fillSeqs = () => {
		const list = seqs[$("anim").value] ?? [];
		$("seq").replaceChildren(...list.map((s, i) => new Option(s.name, i)));
		fillDirs();
	};
	const select = () => mem.exports.viewer_select(+$("anim").value, +$("seq").value, +$("dir").value);

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
	fillSeqs();
}

function setupTank() {
	const setDebug = (on) => {
		$("debug").checked = on;
		document.body.classList.toggle("show-debug", on);
		if (!on) octx.clearRect(0, 0, overlay.width, overlay.height);
		mem.exports.tank_set_debug(on ? 1 : 0);
		try { localStorage.setItem("vc-debug", on ? "1" : ""); } catch {}
	};
	$("debug").onchange = () => setDebug($("debug").checked);
	$("drop").onclick = () => mem.exports.tank_drop_cricket();
	$("fill").onclick = () => mem.exports.tank_fill_bowl();
	addEventListener("keydown", (e) => {
		if (e.target.tagName === "INPUT" && e.target.type !== "checkbox") return;
		if (e.key === "d" || e.key === "D") setDebug(!$("debug").checked);
		if (e.key === "c" || e.key === "C") mem.exports.tank_drop_cricket();
	});
	let saved = false;
	try { saved = localStorage.getItem("vc-debug") === "1"; } catch {}
	setDebug(saved);

	$("follow").onchange = () => mem.exports.tank_set_follow($("follow").checked ? 1 : 0);
	$("speed").oninput = () => {
		$("speedv").textContent = `${$("speed").value}×`;
		mem.exports.tank_set_speed(+$("speed").value);
	};
	// drag to pan the viewfinder (scan mode)
	let dragX = null;
	canvas.onpointerdown = (e) => { dragX = e.clientX; canvas.setPointerCapture(e.pointerId); };
	canvas.onpointerup = () => { dragX = null; };
	canvas.onpointermove = (e) => {
		if (dragX === null) return;
		const k = canvas.width / canvas.getBoundingClientRect().width;
		mem.exports.tank_scroll(Math.round((dragX - e.clientX) * k));
		dragX = e.clientX;
		$("follow").checked = false;
	};
}

$("variant").value = variant;
$("variant").onchange = () => { location.search = `?v=${$("variant").value}`; };

await odin.runWasm("vc.wasm", null, imports, mem);
if (mode === 1) setupViewer(); else setupTank();
