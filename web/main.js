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

// the saved game (one per variant) is offered to the game as save.json
const SAVE_KEY = `vc-save-${variant}`;
if (mode === 0) {
	try {
		const saved = localStorage.getItem(SAVE_KEY);
		if (saved) files.set("save.json", new TextEncoder().encode(saved));
	} catch {}
}

const mem = new odin.WasmMemoryInterface();
const canvas = $("view");
const ctx = canvas.getContext("2d");
const seqs = []; // viewer: per animation [{name, mask}]
const overlay = $("overlay");
const octx = overlay?.getContext("2d");
if (octx) { octx.font = "12px ui-monospace, Menlo, monospace"; octx.lineWidth = 1; }
const debugLines = [];

// The original's 4-channel mixer (play_sound, 0x415f00): channel 0 for the
// eating crunches (they cut it off), channels 1-3 for everything else
// (first free one; skipped when all are busy or the same sound is already
// playing, except the bell), and two looping sounds the game switches on
// and off: running water (465, channel 1) and scraping (403, channel 2).
const sound = {
	ctx: null,
	buffers: new Map(),
	ch: [null, null, null, null], // {id, src, end, loop}
	loops: new Map(), // id -> wanted on
	on: true,
	volume: 1,
	gain: null,
	unlock() {
		if (this.ctx) return;
		this.ctx = new AudioContext();
		this.gain = this.ctx.createGain();
		this.gain.gain.value = this.volume;
		this.gain.connect(this.ctx.destination);
		for (const id of manifest.sounds ?? []) {
			fetch(`${base}sounds/${id}.wav`).then((r) => r.arrayBuffer())
				.then((b) => this.ctx.decodeAudioData(b))
				.then((buf) => { this.buffers.set(id, buf); if (this.loops.get(id)) this.loop(id, true); })
				.catch(() => {});
		}
	},
	busy(c) { return c && (c.loop || c.end > this.ctx.currentTime); },
	start(chan, id, loop) {
		const buf = this.buffers.get(id);
		if (!buf) return;
		this.stop(chan);
		const src = this.ctx.createBufferSource();
		src.buffer = buf;
		src.loop = loop;
		src.connect(this.gain);
		src.start();
		this.ch[chan] = { id, src, end: this.ctx.currentTime + buf.duration, loop };
	},
	stop(chan) {
		const c = this.ch[chan];
		if (c) { try { c.src.stop(); } catch {} }
		this.ch[chan] = null;
	},
	play(id) {
		if (!this.on || !this.ctx) return;
		if (id >= 450 && id <= 456) return this.start(0, id, false);
		if (id !== 466 && this.ch.some((c) => this.busy(c) && c.id === id)) return;
		for (let chan = 1; chan <= 3; chan++) {
			if (!this.busy(this.ch[chan])) return this.start(chan, id, false);
		}
	},
	loop(id, on) {
		this.loops.set(id, on);
		if (!this.ctx) return;
		const chan = id === 465 ? 1 : 2;
		if (on && this.on) this.start(chan, id, true);
		else if (this.ch[chan]?.id === id) this.stop(chan);
	},
	setVolume(v) {
		this.volume = v;
		if (this.gain) this.gain.gain.value = v;
	},
	setOn(on) {
		this.on = on;
		if (!this.ctx) return;
		for (let chan = 0; chan < 4; chan++) this.stop(chan);
		if (on) for (const [id, want] of this.loops) if (want) this.loop(id, true);
	},
};
window.vcSound = sound; // for debugging in the console
addEventListener("pointerdown", () => sound.unlock(), { capture: true });
addEventListener("keydown", () => sound.unlock(), { capture: true });
const noop = () => {};
const tctx = $("ui-text")?.getContext("2d");
if (tctx) { tctx.font = "bold 11px Arial, sans-serif"; tctx.textBaseline = "top"; }
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
		host_sound: (id) => sound.play(id),
		host_loop: (id, on) => sound.loop(id, !!on),
		host_save: (p, n) => { try { localStorage.setItem(SAVE_KEY, mem.loadString(p, n)); } catch {} },
		host_message: (tp, tn, xp, xn) => showMessage(mem.loadString(tp, tn), mem.loadString(xp, xn)),
		host_life: (born, died, resurrections, eaten, dead) => showLife(born, died, resurrections, eaten, dead),
		host_cursor: (set, frame) => setCursor(set, frame),
		host_view: (view) => setView(view),
		host_tool: noop,
		host_options: (open) => { $("options").hidden = !open; },
		host_open: (what) => (what === 0 ? openWebsite() : toggleFloatingPanel()),
		ui_begin: () => tctx?.clearRect(0, 0, 640, 480),
		ui_text: (x, y, p, n) => {
			const text = mem.loadString(p, n);
			tctx.fillStyle = "#000";
			tctx.fillText(text, x + 1, y + 1);
			tctx.fillStyle = "#fff";
			tctx.fillText(text, x, y);
		},
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

// Original cursors (manifest.cursors[set][frame] = {file, hotspot}).
const cursorCss = Object.fromEntries(Object.entries(manifest.cursors ?? {}).map(([set, frames]) =>
	[set, frames.map((f) => `url(${base}${f.file}) ${f.hotspot[0]} ${f.hotspot[1]}, auto`)]));
function setCursor(set, frame) {
	const css = cursorCss[set]?.[frame] ?? cursorCss[set]?.[0];
	if (css && canvas.style.cursor !== css) canvas.style.cursor = css;
}

function setView(view) {
	document.body.dataset.view = view === 3 ? "box" : "tank";
}

// The website button: the original site is gone, so offer the Wayback
// Machine's copy (the original asked first, as it had to close down).
const WEBSITE = "https://web.archive.org/web/2000/http://www.virtualcreatures.com/vc";
function openWebsite() {
	if (confirm("Visiting the VC Website opens an archived copy of it in a new tab.\nDo you wish to continue?")) {
		window.open(WEBSITE, "_blank", "noopener");
	}
}

// The floating panel: the original shrank the tank into a small window on
// top of the others. Here the view goes into a picture-in-picture window,
// and a worker timer keeps the simulation going while the tab is hidden
// (animation frames stop there).
let pipVideo = null, pipTimer = null, pipPrev = 0;
function floating() { return pipVideo !== null && document.pictureInPictureElement === pipVideo; }
async function toggleFloatingPanel() {
	if (floating()) { await document.exitPictureInPicture().catch(() => {}); return; }
	if (!document.pictureInPictureEnabled) {
		showMessage("FLOATING PANEL", "This browser can't show the tank in a floating window.");
		return;
	}
	if (!pipVideo) {
		pipVideo = document.createElement("video");
		pipVideo.muted = true;
		pipVideo.playsInline = true;
		pipVideo.style.cssText = "position:fixed;width:1px;height:1px;opacity:0;pointer-events:none";
		pipVideo.srcObject = canvas.captureStream(14);
		document.body.append(pipVideo);
		pipVideo.addEventListener("leavepictureinpicture", () => onFloating(false));
		pipVideo.addEventListener("enterpictureinpicture", () => onFloating(true));
	}
	try {
		await pipVideo.play();
		await pipVideo.requestPictureInPicture();
	} catch (e) {
		showMessage("FLOATING PANEL", `The floating window could not be opened (${e.message}).`);
	}
}
function onFloating(on) {
	if (on && !pipTimer) {
		const src = "setInterval(() => postMessage(0), 100)";
		pipTimer = new Worker(URL.createObjectURL(new Blob([src], { type: "text/javascript" })));
		const ctx = mem.exports.default_context_ptr();
		pipPrev = performance.now();
		pipTimer.onmessage = () => {
			const now = performance.now();
			if (document.hidden) mem.exports.step((now - pipPrev) / 1000, ctx);
			pipPrev = now;
		};
	} else if (!on && pipTimer) {
		pipTimer.terminate();
		pipTimer = null;
	}
	window.vcFloatingChanged?.(on);
}

function showMessage(title, text) {
	const box = $("message");
	if (!box) return;
	$("message-title").textContent = title;
	$("message-text").textContent = text;
	box.hidden = false;
}

const fmtDate = (sec) => new Date(sec * 1000).toLocaleString();
function fmtSpan(sec) {
	const m = Math.max(0, Math.floor(sec / 60));
	return `Days: ${Math.floor(m / 1440)}, Hours: ${Math.floor(m / 60) % 24}, Minutes: ${m % 60}`;
}
let lifeShown = "";
function showLife(born, died, resurrections, eaten, dead) {
	if (!$("life")) return;
	const now = Date.now() / 1000;
	const text = [
		`Birth Date: ${born ? fmtDate(born) : "-"}`,
		`Time Alive: ${born ? fmtSpan((dead && died ? died : now) - born) : "-"}`,
		dead ? `Death Date: ${fmtDate(died)}` : null,
		`No of Resurrections: ${resurrections}`,
		`Total No of Crickets Eaten: ${eaten}`,
	].filter(Boolean).join("\n");
	if (text !== lifeShown) { $("life").textContent = text; lifeShown = text; }
	$("resurrect").disabled = !dead;
}

function setupTank() {
	$("message-ok").onclick = () => { $("message").hidden = true; };
	$("resurrect").onclick = () => mem.exports.tank_resurrect();
	$("new-spider").onclick = () => {
		if (confirm("Start again with a new spider? The current one is lost.")) mem.exports.tank_new_spider();
	};

	// saving: every minute, when hidden, when closed; time away is replayed
	const save = () => { if (!window.vcNoSave) mem.exports.tank_save(); }; // vcNoSave: for testing
	setInterval(save, 60_000);
	addEventListener("pagehide", save);
	let hiddenAt = 0;
	// while floating the simulation keeps running: nothing to catch up
	window.vcFloatingChanged = (on) => { if (document.hidden) hiddenAt = on ? 0 : Date.now(); };
	document.addEventListener("visibilitychange", () => {
		if (document.hidden) {
			hiddenAt = floating() ? 0 : Date.now();
			save();
		} else if (hiddenAt) {
			const minutes = Math.floor((Date.now() - hiddenAt) / 60_000);
			hiddenAt = 0;
			if (minutes >= 3) mem.exports.tank_resume(minutes);
		}
	});

	// sound on/off (the original's Sound menu item; plays the click)
	let soundOn = true;
	try { soundOn = localStorage.getItem("vc-sound") !== "off"; } catch {}
	$("sound").checked = soundOn;
	sound.setOn(soundOn);
	$("sound").onchange = () => {
		sound.unlock();
		sound.setOn($("sound").checked);
		sound.play(400);
		try { localStorage.setItem("vc-sound", $("sound").checked ? "on" : "off"); } catch {}
	};

	// volume, 0-100 %
	let volume = 100;
	try { volume = +(localStorage.getItem("vc-volume") ?? 100); } catch {}
	if (!Number.isFinite(volume)) volume = 100;
	$("volume").value = volume;
	sound.setVolume(volume / 100);
	$("volume").oninput = () => {
		sound.setVolume($("volume").value / 100);
		try { localStorage.setItem("vc-volume", $("volume").value); } catch {}
	};
	$("volume").onchange = () => { sound.unlock(); sound.play(400); };

	// pet name (kept in this browser until saving exists)
	const setName = (name) => {
		mem.exports.tank_name_clear();
		for (const ch of name.toUpperCase()) mem.exports.tank_name_char(ch.charCodeAt(0));
		try { localStorage.setItem("vc-name", name); } catch {}
	};
	let savedName = "";
	try { savedName = localStorage.getItem("vc-name") ?? ""; } catch {}
	$("pet-name").value = savedName;
	setName(savedName);
	$("pet-name").oninput = () => setName($("pet-name").value);

	// pointer events in canvas pixels
	const toCanvas = (e) => {
		const r = canvas.getBoundingClientRect();
		return [Math.floor((e.clientX - r.left) * canvas.width / r.width),
			Math.floor((e.clientY - r.top) * canvas.height / r.height)];
	};
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
		if (e.target.tagName === "INPUT" && e.target.type !== "checkbox" && e.target.type !== "range") return;
		if (e.key === "d" || e.key === "D") setDebug(!$("debug").checked);
		if (e.key === "c" || e.key === "C") mem.exports.tank_drop_cricket();
		if (e.key >= "1" && e.key <= "5") mem.exports.tank_set_tool(+e.key - 1);
	});
	let saved = false;
	try { saved = localStorage.getItem("vc-debug") === "1"; } catch {}
	setDebug(saved);

	$("speed").oninput = () => {
		$("speedv").textContent = `${$("speed").value}×`;
		mem.exports.tank_set_speed(+$("speed").value);
	};
	// left button: the current tool; right (or middle) drag pans the viewfinder
	let panX = null;
	canvas.oncontextmenu = (e) => e.preventDefault();
	canvas.onpointerdown = (e) => {
		canvas.setPointerCapture(e.pointerId);
		if (e.button !== 0) { panX = e.clientX; return; }
		mem.exports.tank_pointer(1, ...toCanvas(e));
	};
	canvas.onpointerup = (e) => {
		if (panX !== null) { panX = null; return; }
		mem.exports.tank_pointer(2, ...toCanvas(e));
	};
	canvas.onpointermove = (e) => {
		if (panX !== null) {
			const k = canvas.width / canvas.getBoundingClientRect().width;
			mem.exports.tank_scroll(Math.round((panX - e.clientX) * k));
			panX = e.clientX;
			return;
		}
		mem.exports.tank_pointer(0, ...toCanvas(e));
	};
	canvas.onpointerleave = (e) => mem.exports.tank_pointer(3, ...toCanvas(e));
	setView(0);
}

$("variant").value = variant;
$("variant").onchange = () => { location.search = `?v=${$("variant").value}`; };

await odin.runWasm("vc.wasm", null, imports, mem);
if (mode === 1) setupViewer(); else setupTank();
