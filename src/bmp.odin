package vc

// Minimal loader for the 8-bit uncompressed BMP files written by tools/extract.py.

Bitmap :: struct {
	w, h:    int,
	pixels:  []u8, // palette indices, top-down rows
	palette: [256][3]u8,
}

bmp_load :: proc(data: []u8) -> (b: Bitmap, ok: bool) {
	if len(data) < 54 || data[0] != 'B' || data[1] != 'M' do return
	u32le :: proc(d: []u8, o: int) -> int {
		return int(d[o]) | int(d[o + 1]) << 8 | int(d[o + 2]) << 16 | int(d[o + 3]) << 24
	}
	bits := u32le(data, 10)
	hdr := u32le(data, 14)
	b.w = u32le(data, 18)
	h := i32(u32le(data, 22))
	bpp := int(data[28]) | int(data[29]) << 8
	if bpp != 8 || u32le(data, 30) != 0 do return // only 8-bit BI_RGB
	top_down := h < 0
	b.h = int(abs(h))

	pal := 14 + hdr
	for &c, i in b.palette {
		if pal + 4 * i + 3 > len(data) do break
		c = {data[pal + 4 * i + 2], data[pal + 4 * i + 1], data[pal + 4 * i]}
	}

	stride := (b.w + 3) &~ 3
	if bits + stride * b.h > len(data) do return
	b.pixels = make([]u8, b.w * b.h)
	for y in 0 ..< b.h {
		src := bits + stride * (top_down ? y : b.h - 1 - y)
		copy(b.pixels[y * b.w:][:b.w], data[src:][:b.w])
	}
	return b, true
}
