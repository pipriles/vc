// Tests web/mixer.js (the original's sound mixer) in Node, with stand-ins
// for the AudioWorklet globals.
import { readFileSync } from "node:fs";

let Mixer;
const env = {
	sampleRate: 11025,
	AudioWorkletProcessor: class { constructor() { this.port = { onmessage: null }; } },
	registerProcessor: (_name, cls) => { Mixer = cls; },
};
new Function(...Object.keys(env), readFileSync(new URL("../web/mixer.js", import.meta.url), "utf8"))(...Object.values(env));

let failed = 0;
const check = (ok, what) => { console.log(`${ok ? "ok  " : "FAIL"} mixer: ${what}`); if (!ok) failed++; };
const tone = (n, v) => new Uint8Array(n).fill(v);
const run = (m, samples) => {
	const out = [];
	for (let done = 0; done < samples; done += 128) {
		const o = new Float32Array(128);
		m.process([], [[o]]);
		out.push(...o);
	}
	return out;
};
const mixer = () => {
	const m = new Mixer();
	m.message({ type: "sound", id: 401, data: tone(20000, 228) }); // +100
	m.message({ type: "sound", id: 402, data: tone(20000, 228) });
	m.message({ type: "sound", id: 450, data: tone(20000, 28) }); // -100
	m.message({ type: "sound", id: 465, data: tone(5000, 178) }); // +50, looped
	return m;
};

{ // from silence a sound starts at once
	const m = mixer();
	m.message({ type: "play", id: 401 });
	const out = run(m, 256);
	check(Math.abs(out[0] - 100 / 128) < 1e-6, "starts at once when idle");
}
{ // channels add, and clip at 255
	const m = mixer();
	m.message({ type: "play", id: 401 });
	m.message({ type: "play", id: 402 });
	// started together from silence: the second joins the second block
	const out = run(m, 2048 * 2);
	check(Math.abs(out[0] - 100 / 128) < 1e-6 && Math.abs(out[2048] - 127 / 128) < 1e-6,
		"a sound started right after the first joins the next block; together they clip at 255");
}
{ // the same sound isn't started twice; channel 0's crunch is separate
	const m = mixer();
	m.message({ type: "play", id: 401 });
	m.message({ type: "play", id: 401 });
	m.message({ type: "play", id: 450 });
	const busy = m.ch.map((c) => (c.active ? c.id : 0));
	check(JSON.stringify(busy) === "[450,401,0,0]", `channels ${JSON.stringify(busy)}`);
}
{ // while playing, a new sound waits for the queued block: about 2 blocks
	const m = mixer();
	m.message({ type: "play", id: 401 });
	run(m, 1024); // half way through the first block
	m.message({ type: "play", id: 402 });
	const out = run(m, 2048 * 3);
	const first = out.findIndex((v) => v > 120 / 128); // when both add up
	check(first >= 2048 - 1024 + 2048 - 128 && first <= 2048 + 1024 + 128, `second sound starts ${first} samples later (after the queued block)`);
}
{ // a loop keeps going until turned off, then plays out
	const m = mixer();
	m.message({ type: "loop", id: 465, on: true });
	const out = run(m, 2048 * 3);
	check(out.every((v) => Math.abs(v - 50 / 128) < 1e-6), "the water loop runs on");
	m.message({ type: "loop", id: 465, on: false });
	const after = run(m, 2048 * 4);
	check(after.slice(-128).every((v) => v === 0), "and stops after being turned off");
}
if (failed) process.exit(1);
