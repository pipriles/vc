#+build !js
package vc

import "core:testing"

// Startup with many clock-like seeds: catches rand edge cases (rand_n(n) == n)
// that fixed-seed runs miss.
@(test)
startup_seed_sweep :: proc(t: ^testing.T) {
	if !have_data(t, "cr") do return
	for seed in 0 ..< 3000 {
		now_ms = 0
		if !testing.expect(t, load_assets(), "assets") do return
		rng.seed = u32(seed * 7919 + 1)
		tank_reset()
		for _ in 0 ..< 50 do tank_tick()
	}
}
