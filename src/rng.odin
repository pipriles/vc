package vc

// Bit-exact MSVC CRT rand(), as used by VC.EXE (seeded with time(NULL)).

Rng :: struct {
	seed: u32,
}

rng: Rng

rand :: proc "contextless" () -> int {
	rng.seed = rng.seed * 0x343FD + 0x269EC3
	return int((rng.seed >> 16) & 0x7FFF)
}

// The original's ubiquitous idiom `rand() * n / 0x7fff`: an integer in [0, n],
// where n itself only comes up when rand() returns 0x7fff.
rand_n :: proc "contextless" (n: int) -> int {
	return rand() * n / 0x7FFF
}
