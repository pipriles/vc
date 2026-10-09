package vc

// VC.EXE computes sizes as `trunc(a / (100.0 / scale))` on the x87 FPU,
// whose 64-bit mantissa rounds differently from f64 near integers
// (e.g. a=200, scale=11: f64 gives 21, the original 22). This reproduces
// the x87 result exactly with integer arithmetic.
x87_scale_trunc :: proc "contextless" (a, scale: int) -> int {
	if a <= 0 || scale <= 0 do return 0
	M, k := x87_quotient(scale)

	// v = a / q = (a << k) / M, then rounded to 64 bits and truncated
	N := u128(a) << k
	ip := N / M
	r := N % M
	if ip == 0 do return 0
	e: uint = 0
	for (ip >> (e + 1)) > 0 do e += 1
	// rounding reaches ip + 1 when the remaining fraction is within half an ulp
	if ((M - r) << (64 - e)) <= M do ip += 1
	return int(ip)
}

// q = 100/scale rounded to nearest-even on a 64-bit mantissa: q = M / 2^k.
// Finding k takes ~60 128-bit divisions, so it's cached per scale (scales
// are small; the sim calls this many times a tick).
@(private = "file")
x87_cache: [256]struct {
	M: u128,
	k: uint,
}

@(private = "file")
x87_quotient :: proc "contextless" (scale: int) -> (M: u128, k: uint) {
	if scale < len(x87_cache) && x87_cache[scale].M != 0 {
		return x87_cache[scale].M, x87_cache[scale].k
	}
	for (u128(100) << (k + 1)) / u128(scale) < u128(1) << 64 do k += 1
	num := u128(100) << k
	M = num / u128(scale)
	rem := num % u128(scale)
	if 2 * rem > u128(scale) || (2 * rem == u128(scale) && M & 1 == 1) do M += 1
	if M >= u128(1) << 64 {
		M >>= 1
		k -= 1
	}
	if scale < len(x87_cache) do x87_cache[scale] = {M, k}
	return
}
