package vc

// Parser for the VCG animation format (see docs/FORMAT.md).
//
// An animation is a pair of blobs: an index (sequences, directions, frame
// tables) and a pixel blob holding RLE-compressed palette-indexed frames.

INDEX_HEADER_SIZE :: 40
SEQ_RECORD_SIZE   :: 18764
DIR_BLOCK_BASE    :: 0x48
DIR_BLOCK_SIZE    :: 0x924 // the last block of a record is truncated (unused tail)
DIR_COUNT         :: 8
MAX_FRAMES        :: 64

Frame :: struct {
	offset, length: u32,    // RLE data in Anim.pix
	box:            [4]i32, // x0, y0, x1, y1 inside the canvas, y bottom-up as stored
}

Dir :: struct {
	frames: []Frame,
	flags:  [8]u8, // 8 bytes before the frame count; (1,0,1,0) on moving sequences
	unk:    u16,   // purpose unknown (0x31 for creatures, 0 for effects)
}

Seq :: struct {
	name: string,
	hdr:  []u8, // 40 bytes of per-sequence fields, not yet understood
	dirs: [DIR_COUNT]Dir,
}

Anim :: struct {
	name: string,
	w, h: int,
	key:  u8, // transparent palette index
	seqs: []Seq,
	pix:  []u8,
}

@(private = "file")
le_u16 :: #force_inline proc "contextless" (b: []u8, o: int) -> u16 {
	return u16(b[o]) | u16(b[o + 1]) << 8
}

@(private = "file")
le_u32 :: #force_inline proc "contextless" (b: []u8, o: int) -> u32 {
	return u32(b[o]) | u32(b[o + 1]) << 8 | u32(b[o + 2]) << 16 | u32(b[o + 3]) << 24
}

@(private = "file")
c_string :: proc "contextless" (b: []u8) -> string {
	n := 0
	for n < len(b) && b[n] != 0 do n += 1
	return string(b[:n])
}

// Parses an index blob. Strings and slices in the result point into idx/pix,
// so both must outlive the Anim.
anim_parse :: proc(idx, pix: []u8) -> (a: Anim, ok: bool) {
	if len(idx) < INDEX_HEADER_SIZE do return
	a.name = c_string(idx[:32])
	n := int(le_u16(idx, 32))
	a.w = int(le_u16(idx, 34))
	a.h = int(le_u16(idx, 36))
	a.pix = pix
	if len(idx) < INDEX_HEADER_SIZE + n * SEQ_RECORD_SIZE do return

	a.seqs = make([]Seq, n)
	for &s, i in a.seqs {
		r := idx[INDEX_HEADER_SIZE + i * SEQ_RECORD_SIZE:][:SEQ_RECORD_SIZE]
		s.name = c_string(r[:32])
		s.hdr = r[32:DIR_BLOCK_BASE]
		for &d, k in s.dirs {
			b := r[DIR_BLOCK_BASE + k * DIR_BLOCK_SIZE:]
			copy(d.flags[:], r[DIR_BLOCK_BASE + k * DIR_BLOCK_SIZE - 0x14:][:8])
			d.unk = le_u16(b, 6)
			d.frames = make([]Frame, min(int(le_u16(b, 4)), MAX_FRAMES))
			for &f, j in d.frames {
				for c in 0 ..< 4 do f.box[c] = i32(le_u32(b, 8 + 16 * j + 4 * c))
				f.offset = le_u32(b, 0x408 + 4 * j)
				f.length = le_u32(b, 0x508 + 4 * j)
				if u64(f.offset) + u64(f.length) > u64(len(pix)) do return
			}
		}
	}

	// The top-left pixel of every frame is background, so the first RLE run
	// of any frame gives the transparent key.
	for s in a.seqs {
		for d in s.dirs {
			if len(d.frames) > 0 && d.frames[0].length >= 2 {
				a.key = pix[d.frames[0].offset + 1]
				return a, true
			}
		}
	}
	return
}

// Expands one RLE frame of (count, index) byte pairs into dst (w*h bytes,
// top-down rows). Frames are stored bottom-up like Windows DIBs, and runs
// may cross row boundaries.
frame_decode :: proc "contextless" (a: ^Anim, f: Frame, dst: []u8) -> bool {
	src := a.pix[f.offset:][:f.length]
	w, total := a.w, a.w * a.h
	if len(dst) < total do return false
	o := 0 // pixel index in stored (bottom-up) order
	for i := 0; i + 1 < len(src); i += 2 {
		n, v := int(src[i]), src[i + 1]
		if o + n > total do return false
		for n > 0 {
			x := o % w
			k := min(n, w - x)
			row := a.h - 1 - o / w
			for &p in dst[row * w + x:][:k] do p = v
			o += k
			n -= k
		}
	}
	return o == total
}

// Bitmask of directions that have frames.
seq_dir_mask :: proc "contextless" (s: ^Seq) -> (mask: u32) {
	for d, k in s.dirs do if len(d.frames) > 0 do mask |= 1 << u32(k)
	return
}
