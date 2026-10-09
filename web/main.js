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
// Sound. "gritty" and "smooth" run the original's own mixer (mixer.js:
// 8-bit, 11025 Hz, double-buffered, clipped), the first holding each sample
// at the output rate, the second letting the browser resample it smoothly;
// "modern" plays each sound directly with the same channel rules.
const sound = {
	mode: "gritty",
	ctx: null,
	node: null, // the mixer, in the original modes
	buffers: new Map(), // modern: decoded sounds
	ch: [null, null, null, null], // modern: {id, src, end, loop}
	loops: new Map(), // id -> wanted on
	on: true,
	volume: 1,
	gain: null,
	unlock() {
		if (this.ctx) return;
		const original = this.mode !== "modern";
		this.ctx = this.mode === "smooth" ? new AudioContext({ sampleRate: 11025 }) : new AudioContext();
		this.gain = this.ctx.createGain();
		this.gain.gain.value = this.volume;
		this.gain.connect(this.ctx.destination);
		const ctx = this.ctx;
		const ready = original
			? ctx.audioWorklet.addModule("mixer.js").then(() => {
				if (ctx !== this.ctx) return;
				this.node = new AudioWorkletNode(ctx, "vc-mixer", { outputChannelCount: [1] });
				this.node.connect(this.gain);
			})
			: Promise.resolve();
		ready.then(() => {
			for (const id of manifest.sounds ?? []) {
				fetch(`${base}sounds/${id}.wav`).then((r) => r.arrayBuffer()).then((b) => {
					if (ctx !== this.ctx) return;
					if (original) {
						// the original copies the bytes after the 44-byte header (0x415f00)
						const v = new DataView(b);
						const len = Math.min(v.getUint32(40, true), b.byteLength - 44);
						this.node.port.postMessage({ type: "sound", id, data: new Uint8Array(b.slice(44, 44 + len)) });
						if (this.loops.get(id) && this.on) this.loop(id, true);
					} else {
						return ctx.decodeAudioData(b).then((buf) => {
							this.buffers.set(id, buf);
							if (this.loops.get(id)) this.loop(id, true);
						});
					}
				}).catch(() => {});
			}
		}).catch(() => {});
	},
	setMode(mode) {
		if (mode === this.mode) return;
		const was = !!this.ctx;
		if (this.ctx) this.ctx.close().catch(() => {});
		this.ctx = this.node = this.gain = null;
		this.buffers.clear();
		this.ch = [null, null, null, null];
		this.mode = mode;
		if (was) this.unlock();
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
		if (this.node) return this.node.port.postMessage({ type: "play", id });
		if (this.mode !== "modern") return; // the mixer is still loading
		if (id >= 450 && id <= 456) return this.start(0, id, false);
		if (id !== 466 && this.ch.some((c) => this.busy(c) && c.id === id)) return;
		for (let chan = 1; chan <= 3; chan++) {
			if (!this.busy(this.ch[chan])) return this.start(chan, id, false);
		}
	},
	loop(id, on) {
		this.loops.set(id, on);
		if (!this.ctx) return;
		if (this.node) return this.node.port.postMessage({ type: "loop", id, on: on && this.on });
		if (this.mode !== "modern") return;
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
		if (this.node) this.node.port.postMessage({ type: "stop" });
		for (let chan = 0; chan < 4; chan++) this.stop(chan);
		if (on) for (const [id, want] of this.loops) if (want) this.loop(id, true);
	},
};
try { sound.mode = localStorage.getItem("vc-audio") ?? "gritty"; } catch {}
window.vcSound = sound; // for debugging in the console
addEventListener("pointerdown", () => sound.unlock(), { capture: true });
addEventListener("keydown", () => sound.unlock(), { capture: true });
const noop = () => {};
const tctx = $("ui-text")?.getContext("2d");
let uiOps = null, uiShown = "[]"; // UI text: this frame's calls, what's drawn (uiFlush)
// The text canvas matches the displayed size (the view is scaled up), so
// text stays sharp; everything draws in 640 x 480 view coordinates.
function fitText() {
	const c = $("ui-text");
	if (!c || !tctx) return;
	const r = c.getBoundingClientRect();
	const w = Math.max(640, Math.round(r.width * devicePixelRatio));
	if (c.width !== w) {
		c.width = w;
		c.height = Math.round(w * 3 / 4);
		uiShown = null; // resizing cleared it
	}
	tctx.setTransform(c.width / 640, 0, 0, c.height / 480, 0, 0);
	tctx.font = "bold 11px Arial, sans-serif";
	tctx.textBaseline = "top";
}
fitText();
addEventListener("resize", fitText);
document.addEventListener("fullscreenchange", fitText);
// Options box fonts by GDI cell height: Arial bold 18, bold 12, bold italic 16
const BOX_FONTS = { 1: "bold 16px Arial, sans-serif", 2: "bold 10.5px Arial, sans-serif", 3: "italic bold 14px Arial, sans-serif" };
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
		host_cursor: (set, frame) => setCursor(set, frame),
		host_view: (view) => setView(view),
		host_tool: noop,
		host_open: (what) => (what === 0 ? openWebsite() : toggleFloatingPanel()),
		ui_begin: () => uiBegin(),
		ui_text_ex: (x, y, w, h, p, n, font, color, flags) =>
			uiOps?.push(["ex", x, y, w, h, mem.loadString(p, n), font, color, flags]),
		host_set_sound: (on) => setSound(!!on),
		host_fullscreen: () => toggleFullscreen(),
		host_settings: (rate, smooth, helpText, idle) => {
			const st = { rate, smooth: !!smooth, helpText: !!helpText, idle };
			window.vcSettingsChanged?.(st);
			try { localStorage.setItem("vc-settings", JSON.stringify(st)); } catch {}
		},
		host_saver: () => window.vcStartSaver?.(true),
		host_tz_offset: () => -new Date().getTimezoneOffset(),
		ui_text: (x, y, p, n) => uiOps?.push(["text", x, y, mem.loadString(p, n)]),
		tank_status: (food, water, health, mood, temper, p, n, dir) =>
			showStatus(food, water, health, mood, temper, mem.loadString(p, n), dir),
	},
};

// UI text is redrawn by the game every frame (ui_begin, then the labels),
// but is usually empty or unchanged: collect a frame's calls and repaint the
// text canvas only when they differ from what it shows, so the browser
// doesn't recomposite it every display frame.
function uiBegin() {
	if (!tctx) return;
	if (uiOps === null) queueMicrotask(uiFlush); // after this step returns
	uiOps = [];
}
function uiFlush() {
	const ops = uiOps;
	uiOps = null;
	const key = JSON.stringify(ops);
	if (key === uiShown) return;
	uiShown = key;
	tctx.clearRect(0, 0, 640, 480);
	for (const op of ops) {
		if (op[0] === "ex") uiTextEx(...op.slice(1));
		else uiText(...op.slice(1));
	}
}
// text for the Options box: font 1 Arial bold 18, 2 bold 12, 3 bold
// italic 16 (GDI cell heights); flags 1 centre, 2 word wrap, 4 clip
function uiTextEx(x, y, w, h, text, font, color, flags) {
	tctx.save();
	tctx.font = BOX_FONTS[font] ?? BOX_FONTS[1];
	tctx.fillStyle = hex(color);
	if (flags & 4) { tctx.beginPath(); tctx.rect(x, y, w, h); tctx.clip(); }
	let lines = [text];
	if (flags & 2) {
		lines = [];
		let line = "";
		for (const word of text.split(" ")) {
			const t = line ? `${line} ${word}` : word;
			if (line && tctx.measureText(t).width > w) { lines.push(line); line = word; } else line = t;
		}
		lines.push(line);
	}
	lines.forEach((l, k) => {
		const lx = flags & 1 ? x + (w - tctx.measureText(l).width) / 2 : x;
		tctx.fillText(l, lx, y + k * 12);
	});
	tctx.restore();
}
function uiText(x, y, text) {
	tctx.fillStyle = "#000";
	tctx.fillText(text, x + 1, y + 1);
	tctx.fillStyle = "#fff";
	tctx.fillText(text, x, y);
}

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
	mem.exports.tank_set_floating(on ? 1 : 0); // no bottom row or logo in the small window
	window.vcFloatingChanged?.(on);
}

// Sound on or off from the Options box (plays the click when turned on).
function setSound(on) {
	sound.unlock();
	sound.setOn(on);
	try { localStorage.setItem("vc-sound", on ? "on" : "off"); } catch {}
}

// Full screen: the stage (view and dialogs), scaled to fit.
function toggleFullscreen() {
	const stage = $("stage");
	if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
	else stage.requestFullscreen?.().catch(() => {});
}

// The creature's state as text (shown with the debug tools).
const ARROWS = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"];
function showStatus(food, water, health, mood, temper, seq, dir) {
	const text = `Food ${food} · Water ${water} · Health ${health} · Mood ${mood} · ` +
		`Temperament ${temper} · ${seq} ${ARROWS[dir] ?? ""}`;
	if ($("status") && $("status").textContent !== text) $("status").textContent = text;
}

function showMessage(title, text) {
	const box = $("message");
	if (!box) return;
	$("message-title").textContent = title;
	$("message-text").textContent = text;
	box.hidden = false;
}

function setupTank() {
	$("message-ok").onclick = () => { $("message").hidden = true; };
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

	// settings: sound, full screen and help text live in the Options box;
	// the frame rate too, with smooth motion beside it in the top bar
	let soundOn = true;
	try { soundOn = localStorage.getItem("vc-sound") !== "off"; } catch {}
	sound.setOn(soundOn);
	let st = { rate: 1, smooth: true, helpText: true, idle: 0 };
	try { st = { ...st, ...JSON.parse(localStorage.getItem("vc-settings") ?? "{}") }; } catch {}
	const pushState = () => mem.exports.tank_set_host_state(sound.on ? 1 : 0, document.fullscreenElement ? 1 : 0, st.helpText ? 1 : 0);
	pushState();
	mem.exports.tank_set_frame_rate(st.rate, st.smooth ? 1 : 0);
	mem.exports.tank_set_saver_idle(st.idle);
	window.vcSettingsChanged = (next) => { st = next; };
	document.addEventListener("fullscreenchange", pushState);
	mem.exports.tank_set_variant(variant === "rk" ? 1 : 0);
	mem.exports.tank_intro(); // the opening sequence
	canvas.addEventListener("pointerdown", () => mem.exports.tank_skip_intro()); // port: a tap skips it too
	if ($("plate")) $("plate").textContent = variant === "rk" ? "RED KNEE TARANTULA" : "CHILE ROSE TARANTULA";
	$("fullscreen").onclick = toggleFullscreen;

	// screensaver: UI and cursor hidden, the view follows the spider; any
	// input ends it. After the idle minutes set in Options > Utilities, or
	// full screen from its button there (full screen needs a click).
	const stage = $("stage");
	let saverOn = false, saverFull = false, saverSince = 0, lastInput = Date.now();
	const startSaver = (full) => {
		if (saverOn || mode !== 0) return;
		saverOn = true;
		saverFull = full;
		saverSince = Date.now();
		stage.classList.add("saver");
		mem.exports.tank_set_saver(1);
		if (full && !document.fullscreenElement) stage.requestFullscreen?.().catch(() => {});
	};
	const stopSaver = () => {
		if (!saverOn) return;
		saverOn = false;
		stage.classList.remove("saver");
		mem.exports.tank_set_saver(0);
		if (saverFull && document.fullscreenElement) document.exitFullscreen().catch(() => {});
	};
	window.vcStartSaver = startSaver;
	const onInput = (e) => {
		lastInput = Date.now();
		if (!saverOn) return;
		if (Date.now() - saverSince < 800) { e.stopPropagation(); return; } // settling after the switch
		if (e.type === "pointermove" && Math.hypot(e.movementX, e.movementY) < 3) return;
		stopSaver();
		e.stopPropagation(); // the input that ends it does nothing else
		if (e.cancelable && e.type !== "pointermove") e.preventDefault();
	};
	for (const t of ["pointermove", "pointerdown", "pointerup", "keydown", "wheel"]) {
		addEventListener(t, onInput, { capture: true, passive: false });
	}
	document.addEventListener("fullscreenchange", () => { if (!document.fullscreenElement && saverFull) stopSaver(); });
	setInterval(() => {
		const min = +st.idle;
		if (min > 0 && !document.hidden && Date.now() - lastInput >= min * 60_000) startSaver(false);
	}, 5000);

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

	// how the sound is produced (to compare with the original by ear)
	if ($("audio")) {
		$("audio").value = sound.mode;
		$("audio").onchange = () => {
			sound.setMode($("audio").value);
			sound.unlock();
			try { localStorage.setItem("vc-audio", $("audio").value); } catch {}
		};
	}

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
	addEventListener("keydown", (e) => {
		mem.exports.tank_skip_intro(); // a key skips the opening (as the original)
		if (e.target.tagName === "INPUT" && e.target.type !== "checkbox" && e.target.type !== "range") return;
		// letters and digits, and Enter, go to the game (the original's typed
		// commands); the port's own shortcuts need Shift so typing doesn't
		// trigger them
		if (e.key === "Enter") mem.exports.tank_char(13);
		else if (/^[a-zA-Z0-9]$/.test(e.key) && !e.shiftKey && !e.ctrlKey && !e.metaKey && !e.altKey) mem.exports.tank_char(e.key.charCodeAt(0));
		if (e.shiftKey && e.key.toUpperCase() === "D") setDebug(!$("debug").checked);
		if (e.shiftKey && e.key.toUpperCase() === "C") mem.exports.tank_drop_cricket();
		if (e.shiftKey && e.key.toUpperCase() === "F") $("fullscreen").click();
		if (e.key >= "1" && e.key <= "5") mem.exports.tank_set_tool(+e.key - 1);
	});
	let saved = false;
	try { saved = localStorage.getItem("vc-debug") === "1"; } catch {}
	setDebug(saved);

	$("speed").oninput = () => {
		$("speedv").textContent = `${$("speed").value}×`;
		mem.exports.tank_set_speed(+$("speed").value);
	};
	// left button (or one finger): the current tool; right click: help on a
	// button or indicator, otherwise the next tool (the original's right
	// button); right (or middle) drag, or two fingers, pans the viewfinder
	let panX = null, panFrom = null, panning = false;
	const touches = new Map(); // pointerId -> clientX, for two-finger panning
	let twoFinger = false;
	const touchX = () => [...touches.values()].reduce((a, b) => a + b, 0) / touches.size;
	const k = () => canvas.width / canvas.getBoundingClientRect().width;
	canvas.oncontextmenu = (e) => e.preventDefault();
	canvas.onpointerdown = (e) => {
		canvas.setPointerCapture(e.pointerId);
		if (e.pointerType === "touch") {
			touches.set(e.pointerId, e.clientX);
			if (touches.size === 2) {
				// a second finger: stop what the first was doing, pan instead
				twoFinger = true;
				mem.exports.tank_pointer(3, ...toCanvas(e));
				panX = touchX();
				return;
			}
			if (twoFinger) return;
		} else if (e.button !== 0) {
			panX = e.clientX;
			panFrom = [e.clientX, e.clientY, e.button];
			panning = false;
			return;
		}
		mem.exports.tank_pointer(1, ...toCanvas(e));
	};
	canvas.onpointerup = canvas.onpointercancel = (e) => {
		if (e.pointerType === "touch") {
			touches.delete(e.pointerId);
			if (twoFinger) {
				if (touches.size === 0) { twoFinger = false; panX = null; }
				else panX = touchX();
				return;
			}
		} else if (panFrom) {
			if (!panning && panFrom[2] === 2) mem.exports.tank_pointer(4, ...toCanvas(e));
			panX = panFrom = null;
			return;
		}
		mem.exports.tank_pointer(2, ...toCanvas(e));
	};
	canvas.onpointermove = (e) => {
		if (e.pointerType === "touch" && twoFinger) {
			if (!touches.has(e.pointerId)) return;
			touches.set(e.pointerId, e.clientX);
			const x = touchX();
			mem.exports.tank_scroll(Math.round((panX - x) * k()));
			panX = x;
			return;
		}
		if (panFrom) {
			if (!panning && Math.hypot(e.clientX - panFrom[0], e.clientY - panFrom[1]) < 5) return;
			panning = true;
			mem.exports.tank_scroll(Math.round((panX - e.clientX) * k()));
			panX = e.clientX;
			return;
		}
		mem.exports.tank_pointer(0, ...toCanvas(e));
	};
	canvas.onpointerleave = (e) => mem.exports.tank_pointer(3, ...toCanvas(e));
	setView(0);
}

$("variant").value = variant;
// the animation viewer link is for development: ?dev shows it
if (params.has("dev") && $("viewer-link")) $("viewer-link").hidden = false;
$("variant").onchange = () => { location.search = `?v=${$("variant").value}`; };

await odin.runWasm("vc.wasm", null, imports, mem);
if (mode === 1) setupViewer(); else setupTank();
