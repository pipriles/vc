// The original's software sound mixer, as an AudioWorklet.
//
// VC.EXE doesn't hand sounds to Windows: it opens one 8-bit mono waveOut
// stream at 11025 Hz and mixes four channels into it itself
// (play 0x415f00, fill 0x416680):
// - channel 0 takes the eating crunches (450-456), cut off by the next;
//   channel 1 the running water loop (465), channel 2 the scraping loop
//   (403); anything else the first free channel of 1-3, skipped when that
//   sound is already playing there (except the bell, 466) or none is free;
// - the output is double-buffered in blocks of 2048 samples; a block is
//   mixed when one finishes, so a sound starts in the block after the one
//   queued (up to ~0.37 s late) unless the output was idle;
// - mixing adds the channels' (sample - 128) and clips to 0..255.
// The processor runs that at 11025 Hz and holds each sample for the
// output's rate ("gritty": like a card without a smoothing filter), or
// the AudioContext itself runs at 11025 Hz and the browser smooths it.

const BLOCK = 2048;
const RATE = 11025;

class VCMixer extends AudioWorkletProcessor {
	constructor() {
		super();
		this.sounds = new Map(); // id -> Uint8Array of 8-bit samples
		this.ch = [0, 1, 2, 3].map(() => ({ active: false, id: 0, data: null, pos: 0, loop: false }));
		this.queue = []; // mixed blocks waiting to be played
		this.cur = null;
		this.pos = 0; // position in cur, in 11025 Hz samples
		this.step = RATE / sampleRate;
		this.port.onmessage = (e) => this.message(e.data);
	}

	message(m) {
		switch (m.type) {
		case "sound": this.sounds.set(m.id, m.data); break;
		case "play": this.play(m.id); break;
		case "loop": this.loop(m.id, m.on); break;
		case "stop":
			for (const c of this.ch) c.active = false;
			this.queue = [];
			this.cur = null;
			break;
		}
	}

	load(chan, id, loop) {
		const data = this.sounds.get(id);
		if (!data) return;
		Object.assign(this.ch[chan], { active: true, id, data, pos: 0, loop });
		this.fill_one(); // the original mixes a block straight away if one is free
	}

	play(id) {
		if (id >= 450 && id <= 456) return this.load(0, id, false); // the crunch restarts
		const busy = (c) => c.active;
		if (id !== 466 && this.ch.slice(1).some((c) => busy(c) && c.id === id)) return;
		for (let chan = 1; chan <= 3; chan++) {
			if (!busy(this.ch[chan])) return this.load(chan, id, false);
		}
	}

	loop(id, on) {
		const chan = id === 465 ? 1 : 2;
		const c = this.ch[chan];
		if (on) {
			if (!(c.active && c.id === id && c.loop)) this.load(chan, id, true);
		} else if (c.active && c.id === id) {
			c.loop = false; // as in the original: it plays out, then stops
		}
	}

	// One block, as 0x416680 mixes it; false when nothing is playing.
	mix() {
		if (!this.ch.some((c) => c.active)) return false;
		const out = new Uint8Array(BLOCK);
		const sum = new Int32Array(BLOCK);
		for (const c of this.ch) {
			if (!c.active) continue;
			let n = Math.min(BLOCK, c.data.length - c.pos);
			for (let i = 0; i < n; i++) sum[i] += c.data[c.pos + i] - 128;
			c.pos += n;
			if (n < BLOCK) {
				if (!c.loop) {
					c.active = false;
				} else {
					// wraps once to fill the rest of the block
					const rest = Math.min(BLOCK - n, c.data.length);
					for (let i = 0; i < rest; i++) sum[n + i] += c.data[i] - 128;
					c.pos = rest;
				}
			}
		}
		for (let i = 0; i < BLOCK; i++) out[i] = Math.max(0, Math.min(255, sum[i] + 128));
		this.queue.push(out);
		return true;
	}

	// Double buffering: one block playing, one waiting. Each call (a sound
	// starting, a buffer coming back) mixes at most one block, as 0x416510.
	fill_one() {
		if ((this.cur ? 1 : 0) + this.queue.length < 2) this.mix();
	}

	process(_inputs, outputs) {
		const o = outputs[0][0];
		for (let i = 0; i < o.length; i++) {
			if (!this.cur) {
				if (!this.queue.length) this.fill_one();
				this.cur = this.queue.shift() ?? null;
				if (!this.cur) { o[i] = 0; continue; }
				this.fill_one(); // the freed buffer is mixed again
			}
			o[i] = (this.cur[Math.floor(this.pos)] - 128) / 128;
			this.pos += this.step;
			if (this.pos >= BLOCK) {
				this.pos -= BLOCK;
				this.cur = null; // that buffer is free: the next is mixed
			}
		}
		for (let k = 1; k < outputs[0].length; k++) outputs[0][k].set(o);
		return true;
	}
}

registerProcessor("vc-mixer", VCMixer);
