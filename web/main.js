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
// The text layer is 640 x 480 like the view and scaled up the same way
// (pixelated): the original drew its text with GDI into the 8-bit frame,
// so it has no smoothing and grows in blocks with the picture.
function fitText() {
	if (!tctx) return;
	tctx.setTransform(1, 0, 0, 1, 0, 0);
	tctx.font = "bold 11px Arial, sans-serif";
	tctx.textBaseline = "top";
}
fitText();
addEventListener("resize", fitText);
document.addEventListener("fullscreenchange", fitText);
// Options box fonts by GDI cell height: Arial bold 18, bold 12, bold italic 16
// (font 2 is the tooltip font, 0x4526b8: created bold, but footage of the
// original shows it regular, so it's drawn regular everywhere it's used)
const BOX_FONTS = { 1: "bold 16px Arial, sans-serif", 2: "11px Arial, sans-serif", 3: "italic bold 14px Arial, sans-serif" };
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
		host_name: (p, n) => window.vcNameChanged?.(mem.loadString(p, n)),
		host_tz_offset: () => -new Date().getTimezoneOffset(),
		ui_text: (x, y, p, n) => uiOps?.push(["text", x, y, mem.loadString(p, n)]),
		ui_tip: (x, y, p, n) => uiOps?.push(["tip", x, y, mem.loadString(p, n)]),
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
		else if (op[0] === "tip") uiTip(...op.slice(1));
		else uiText(...op.slice(1));
	}
}
// Text as GDI drew it into the palette frame: each pixel either the text
// colour or untouched, no smoothing, stems snapped to whole pixels, whole-
// pixel advances and no kerning. The browser's text is smoothed and not
// hinted, so each character is drawn alone at four sub-pixel offsets, the
// one with the crispest coverage kept and cut at half coverage (cached).
const crisp = document.createElement("canvas");
crisp.width = crisp.height = 48;
const cctx = crisp.getContext("2d", { willReadFrequently: true });
const glyphs = new Map();
const GLYPH = 48, GLYPH_PAD = 4;
function glyph(font, ch) {
	const key = font + "|" + ch;
	let g = glyphs.get(key);
	if (g) return g;
	cctx.font = font;
	cctx.textBaseline = "top";
	const adv = Math.round(cctx.measureText(ch).width);
	let best = null, bestScore = -1;
	for (const off of [0, 0.25, 0.5, 0.75]) {
		cctx.clearRect(0, 0, GLYPH, GLYPH);
		cctx.fillStyle = "#fff";
		cctx.fillText(ch, GLYPH_PAD + off, GLYPH_PAD);
		const d = cctx.getImageData(0, 0, GLYPH, GLYPH).data;
		let score = 0;
		const mask = new Uint8Array(GLYPH * GLYPH);
		for (let k = 0; k < mask.length; k++) {
			const a = d[k * 4 + 3];
			score += Math.abs(a - 127.5);
			mask[k] = a >= 128 ? 1 : 0;
		}
		if (score > bestScore) { bestScore = score; best = mask; }
	}
	g = { adv, mask: best };
	glyphs.set(key, g);
	return g;
}
// The original's small font (tooltips, the object panel, the Options box's
// small text) comes from the bitmap font in gdifont.js.
const SMALL_FONT = "11px Arial, sans-serif";
const bitmapFont = () => typeof GDI_FONT !== "undefined" && tctx.font === SMALL_FONT;
function textWidth(text) {
	if (!bitmapFont()) return tctx.measureText(text).width;
	let w = 0;
	for (const ch of text) w += GDI_FONT[ch]?.[0] ?? glyph(tctx.font, ch).adv;
	return w;
}
function crispText(text, x, y, color) {
	if (!text) return;
	const font = tctx.font;
	if (bitmapFont()) {
		bitmapText(text, Math.round(x), Math.round(y), color);
		return;
	}
	const gs = [...text].map((ch) => glyph(font, ch));
	const w = gs.reduce((n, g) => n + g.adv, 0) + GLYPH;
	const img = tctx.createImageData(w, GLYPH), d = img.data;
	const r = (color >> 16) & 255, g8 = (color >> 8) & 255, b = color & 255;
	let pen = 0;
	for (const g of gs) {
		for (let yy = 0; yy < GLYPH; yy++) for (let xx = 0; xx < GLYPH; xx++) {
			if (!g.mask[yy * GLYPH + xx]) continue;
			const px = pen + xx;
			if (px >= w) continue;
			const k = (yy * w + px) * 4;
			d[k] = r; d[k + 1] = g8; d[k + 2] = b; d[k + 3] = 255;
		}
		pen += g.adv;
	}
	crisp2.width = w; crisp2.height = GLYPH;
	crisp2.getContext("2d").putImageData(img, 0, 0);
	tctx.drawImage(crisp2, Math.round(x) - GLYPH_PAD, Math.round(y) - GLYPH_PAD);
}
const crisp2 = document.createElement("canvas");
function bitmapText(text, x, y, color) {
	const w = Math.ceil(textWidth(text)) + 2, h = GDI_FONT_HEIGHT;
	const img = tctx.createImageData(w, h), d = img.data;
	const r = (color >> 16) & 255, g8 = (color >> 8) & 255, b = color & 255;
	const set = (px, py) => {
		if (px < 0 || px >= w || py < 0 || py >= h) return;
		const k = (py * w + px) * 4;
		d[k] = r; d[k + 1] = g8; d[k + 2] = b; d[k + 3] = 255;
	};
	let pen = 0;
	const fallback = [];
	for (const ch of text) {
		const g = GDI_FONT[ch];
		if (g) {
			const [adv, row0] = g;
			for (let j = 2; j < g.length; j++) {
				const line = g[j];
				for (let i = 0; i < line.length; i++) if (line[i] === "#") set(pen + i, row0 + j - 2);
			}
			pen += adv;
		} else {
			fallback.push([ch, pen]);
			pen += glyph(tctx.font, ch).adv;
		}
	}
	crisp2.width = w; crisp2.height = h;
	crisp2.getContext("2d").putImageData(img, 0, 0);
	tctx.drawImage(crisp2, x, y);
	// (characters the bitmap font lacks: the thresholded rendering)
	for (const [ch, at] of fallback) crispGlyphs([ch], x + at, y, color);
}
// thresholded characters (see glyph), drawn from (x, y)
function crispGlyphs(chars, x, y, color) {
	const font = tctx.font;
	const gs = chars.map((ch) => glyph(font, ch));
	const w = gs.reduce((n, g) => n + g.adv, 0) + GLYPH;
	const img = tctx.createImageData(w, GLYPH), d = img.data;
	const r = (color >> 16) & 255, g8 = (color >> 8) & 255, b = color & 255;
	let pen = 0;
	for (const g of gs) {
		for (let yy = 0; yy < GLYPH; yy++) for (let xx = 0; xx < GLYPH; xx++) {
			if (!g.mask[yy * GLYPH + xx] || pen + xx >= w) continue;
			const k = (yy * w + pen + xx) * 4;
			d[k] = r; d[k + 1] = g8; d[k + 2] = b; d[k + 3] = 255;
		}
		pen += g.adv;
	}
	crisp2.width = w; crisp2.height = GLYPH;
	crisp2.getContext("2d").putImageData(img, 0, 0);
	tctx.drawImage(crisp2, Math.round(x) - GLYPH_PAD, Math.round(y) - GLYPH_PAD);
}
// text for the Options box: font 1 Arial bold 18, 2 bold 12, 3 bold
// italic 16 (GDI cell heights); flags 1 centre, 2 word wrap, 4 clip
function uiTextEx(x, y, w, h, text, font, color, flags) {
	tctx.save();
	tctx.font = BOX_FONTS[font] ?? BOX_FONTS[1];
	if (flags & 4) { tctx.beginPath(); tctx.rect(x, y, w, h); tctx.clip(); }
	let lines = [text];
	if (flags & 2) {
		lines = [];
		let line = "";
		for (const word of text.split(" ")) {
			const t = line ? `${line} ${word}` : word;
			if (line && textWidth(t) > w) { lines.push(line); line = word; } else line = t;
		}
		lines.push(line);
	}
	lines.forEach((l, k) => {
		const lx = flags & 1 ? x + Math.floor((w - textWidth(l)) / 2) : x;
		crispText(l, lx, y + k * 12, color);
	});
	tctx.restore();
}
// A tooltip as the original draws it (0x411fe0): Arial with a 12 px cell
// (11 px, which matches the text width in footage of the original; regular
// as in the footage, though the font is created bold), unsmoothed, moved
// left so
// it ends 20 px short of the right edge, on a box of palette colour 2 (dark
// green in both variants) 2 px larger all round, outlined with the tank's
// white pen, white text.
function uiTip(x, y, text) {
	tctx.save();
	tctx.font = SMALL_FONT;
	tctx.textBaseline = "top";
	const w = Math.ceil(textWidth(text)), h = 12;
	if (x + w >= 640 - 20) x -= x + w - (640 - 20);
	tctx.fillStyle = "#008000";
	tctx.fillRect(x - 2, y - 2, w + 4, h + 4);
	tctx.strokeStyle = "#fff";
	tctx.lineWidth = 1;
	tctx.strokeRect(x - 1.5, y - 1.5, w + 3, h + 3);
	crispText(text, x, y, 0xffffff);
	tctx.restore();
}
function uiText(x, y, text) {
	crispText(text, x + 1, y + 1, 0x000000);
	crispText(text, x, y, 0xffffff);
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
// The current cursor, also drawn under a finger on touch screens.
let cursorNow = null; // {url, hx, hy}
function setCursor(set, frame) {
	const f = manifest.cursors?.[set]?.[frame] ?? manifest.cursors?.[set]?.[0];
	if (f) cursorNow = { url: `${base}${f.file}`, hx: f.hotspot[0], hy: f.hotspot[1] };
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
	// small screens: the settings fold into the gear button
	if ($("menu")) $("menu").onclick = () => document.body.classList.toggle("bar-open");
	canvas.addEventListener("pointerdown", () => document.body.classList.remove("bar-open"));

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
	if (savedName) setName(savedName); // else the new pet's "ENTER PETS NAME HERE"
	window.vcNameChanged = (name) => {
		$("pet-name").value = name;
		try { localStorage.setItem("vc-name", name); } catch {}
	};
	$("pet-name").oninput = () => setName($("pet-name").value);
	const setNameEverywhere = (name) => { $("pet-name").value = name; setName(name); };

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
	addEventListener("keydown", (e) => {
		mem.exports.tank_skip_intro(); // a key skips the opening (as the original)
		if (e.target.tagName === "INPUT" && e.target.type !== "checkbox" && e.target.type !== "range") return;
		if (e.ctrlKey || e.metaKey || e.altKey) return;
		// editing the pet's name in the tank: everything goes to it
		if (mem.exports.tank_name_editing()) {
			const keys = { ArrowLeft: 37, ArrowRight: 39, Home: 36, End: 35, Backspace: 8, Delete: 46, Escape: 27 };
			if (keys[e.key]) mem.exports.tank_key(keys[e.key]);
			else if (e.key === "Enter") mem.exports.tank_char(13);
			else if (/^[a-zA-Z0-9 ]$/.test(e.key)) mem.exports.tank_char(e.key.charCodeAt(0));
			else return;
			e.preventDefault();
			return;
		}
		// letters and digits, and Enter, go to the game (the original's typed
		// commands); the port's own shortcuts need Shift so typing doesn't
		// trigger them; "+" / "-" zoom in and out, Esc goes back (original)
		if (e.key === "Enter") mem.exports.tank_char(13);
		else if (/^[a-zA-Z0-9]$/.test(e.key) && !e.shiftKey) mem.exports.tank_char(e.key.charCodeAt(0));
		if (e.key === "+" || e.key === "-" || e.key === "Escape") mem.exports.tank_key(e.key === "Escape" ? 27 : e.key.charCodeAt(0));
		if (e.shiftKey && e.key.toUpperCase() === "D") setDebug(!$("debug").checked);
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
	// button); right (or middle) drag, or two fingers, pans the viewfinder.
	// Touch: a finger on a button, indicator or the logo shows its tooltip;
	// lifted, it presses it; held half a second, it gives the help (the
	// logo: a box to type a command). Elsewhere it's the tool, with the
	// tool's cursor drawn under the finger.
	let panX = null, panFrom = null, panning = false;
	const touches = new Map(); // pointerId -> clientX, for two-finger panning
	let twoFinger = false;
	let uiTouch = null; // {kind, x, y, at: [cx, cy], timer, long}
	const touchX = () => [...touches.values()].reduce((a, b) => a + b, 0) / touches.size;
	const k = () => canvas.width / canvas.getBoundingClientRect().width;
	const finger = $("finger");
	const showFinger = (e) => {
		if (!finger || !cursorNow) { if (finger) finger.hidden = true; return; }
		const r = canvas.getBoundingClientRect(), sc = r.width / canvas.width;
		finger.src = cursorNow.url;
		finger.style.width = `${32 * sc}px`;
		finger.style.left = `${e.clientX - r.left - cursorNow.hx * sc}px`;
		finger.style.top = `${e.clientY - r.top - cursorNow.hy * sc}px`;
		finger.hidden = false;
	};
	const hideFinger = () => { if (finger) finger.hidden = true; };
	const typeCommand = () => {
		const w = prompt("Type a command");
		if (!w) return;
		for (const ch of w) mem.exports.tank_char(ch.charCodeAt(0));
		mem.exports.tank_char(13);
	};
	canvas.oncontextmenu = (e) => e.preventDefault();
	canvas.onpointerdown = (e) => {
		canvas.setPointerCapture(e.pointerId);
		if (e.pointerType === "touch") {
			if (!document.body.classList.contains("touch")) {
				document.body.classList.add("touch");
				mem.exports.tank_set_touch(1);
			}
			touches.set(e.pointerId, e.clientX);
			if (touches.size === 2) {
				// a second finger: stop what the first was doing, pan instead
				twoFinger = true;
				if (uiTouch) { clearTimeout(uiTouch.timer); uiTouch = null; }
				hideFinger();
				mem.exports.tank_pointer(3, ...toCanvas(e));
				panX = touchX();
				return;
			}
			if (twoFinger) return;
			const [x, y] = toCanvas(e);
			const kind = mem.exports.tank_ui_at(x, y);
			if (kind) {
				mem.exports.tank_pointer(0, x, y); // hover: its tooltip
				uiTouch = { kind, x, y, at: [e.clientX, e.clientY], long: false };
				if (kind === 3) {
					// the name: no keyboard on a phone, so a text box
					uiTouch = null;
					const name = prompt("Your pet's name", $("pet-name").value);
					if (name !== null) { setNameEverywhere(name.toUpperCase().slice(0, 23)); }
					return;
				}
				uiTouch.timer = setTimeout(() => {
					if (!uiTouch) return;
					uiTouch.long = true;
					if (uiTouch.kind === 2) typeCommand();
					else mem.exports.tank_pointer(4, uiTouch.x, uiTouch.y); // help
				}, 500);
				return;
			}
			showFinger(e);
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
			hideFinger();
			if (uiTouch) {
				const t = uiTouch;
				uiTouch = null;
				clearTimeout(t.timer);
				if (!t.long && e.type === "pointerup") {
					mem.exports.tank_pointer(1, t.x, t.y);
					mem.exports.tank_pointer(2, t.x, t.y);
				}
				mem.exports.tank_pointer(3, t.x, t.y); // no hover left behind
				return;
			}
			mem.exports.tank_pointer(2, ...toCanvas(e));
			mem.exports.tank_pointer(3, ...toCanvas(e));
			return;
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
		if (e.pointerType === "touch" && uiTouch) {
			// sliding off cancels the long press; it's a tap only where it started
			if (Math.hypot(e.clientX - uiTouch.at[0], e.clientY - uiTouch.at[1]) > 10) {
				clearTimeout(uiTouch.timer);
				uiTouch.long = true;
			}
			return;
		}
		if (panFrom) {
			if (!panning && Math.hypot(e.clientX - panFrom[0], e.clientY - panFrom[1]) < 5) return;
			panning = true;
			mem.exports.tank_scroll(Math.round((panX - e.clientX) * k()));
			panX = e.clientX;
			return;
		}
		// the right button pressed and released while the left one is held
		// (carrying a cricket) arrives here, not as pointerdown / pointerup
		if (e.pointerType === "mouse" && e.button === 2) {
			if (!(e.buttons & 2)) mem.exports.tank_pointer(4, ...toCanvas(e));
			return;
		}
		if (e.pointerType === "touch") showFinger(e);
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
