package vc

// Parser for the VCG animation format (see docs/FORMAT.md).
//
// An animation is a pair of blobs: an index (sequences, directions, frame
// tables) and a pixel blob holding RLE-compressed palette-indexed frames.

INDEX_HEADER_SIZE :: 40
SEQ_RECORD_SIZE   :: 18764
DIR_BLOCK_BASE    :: 0x48
DIR_BLOCK_SIZE    :: 0x924 // the last block of a record is truncated (unused tail)
// Per-frame tables (64 entries) relative to the frame-count field b:
// dx i8 @0x708, dy i8 @0x748, reverse u8 @0x788, hold flag i16 @0x7c8,
// hold i16 @0x848, lock-scale u8 @0x8c8. The last block of a record ends
// before 0x8c8 + 64, so only tables up to hold are read.
DIR_COUNT         :: 8
MAX_FRAMES        :: 64

Frame :: struct {
	offset, length: u32,    // RLE data in Seq.pix
	box:            [4]i32, // content bounds x0, y0, x1, y1 (top-down)
	dx, dy:         i8,     // per-frame displacement (usually 0)
	hold_flag:      i16,    // nonzero: hold this frame for hold ticks
	hold:           i16,    // ticks to hold; negative = random up to -hold
}

// Per-direction header. Field names follow how VC.EXE uses them
// (sequence start at 0x404830, creature tick at 0x406780).
Dir :: struct {
	frames:      []Frame,
	move_x:      bool, // creature moves while playing (60% chance per play)
	move_y:      bool, // creature moves while playing (always)
	no_clamp:    bool, // skip tank-floor clamping (+0xc2)
	needs_check: bool, // only valid if its precondition holds (0x403000)
	key2:        u8,   // second skipped palette index: the shadow colour
}

Seq :: struct {
	name:        string,
	pix:         []u8, // pixel blob holding this sequence's frames
	rand_repeat: bool, // repeat count = rand_n(max_repeat) + 1
	max_repeat:  int,
	dirs:        [DIR_COUNT]Dir,
}

Anim :: struct {
	name: string,
	w, h: int,
	key:  u8, // transparent palette index
	seqs: []Seq,
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
	if len(idx) < INDEX_HEADER_SIZE + n * SEQ_RECORD_SIZE do return

	a.seqs = make([]Seq, n)
	for &s, i in a.seqs {
		r := idx[INDEX_HEADER_SIZE + i * SEQ_RECORD_SIZE:][:SEQ_RECORD_SIZE]
		s.name = c_string(r[:32])
		s.pix = pix
		s.rand_repeat = le_u32(r, 0x24) != 0
		s.max_repeat = int(le_u32(r, 0x28))
		for &d, k in s.dirs {
			// b = frame-count field; the block header starts at b - 0x14
			b := r[DIR_BLOCK_BASE + k * DIR_BLOCK_SIZE:]
			h := r[DIR_BLOCK_BASE + k * DIR_BLOCK_SIZE - 0x14:]
			d.move_x = le_u16(h, 0x00) != 0
			d.move_y = le_u16(h, 0x02) != 0
			d.no_clamp = le_u16(h, 0x06) != 0
			d.needs_check = le_u16(h, 0x12) != 0
			d.key2 = b[6]
			d.frames = make([]Frame, min(int(le_u16(b, 4)), MAX_FRAMES))
			for &f, j in d.frames {
				for c in 0 ..< 4 do f.box[c] = i32(le_u32(b, 8 + 16 * j + 4 * c))
				f.offset = le_u32(b, 0x408 + 4 * j)
				f.length = le_u32(b, 0x508 + 4 * j)
				f.dx = i8(b[0x708 + j])
				f.dy = i8(b[0x748 + j])
				f.hold_flag = i16(le_u16(b, 0x7c8 + 2 * j))
				f.hold = i16(le_u16(b, 0x848 + 2 * j))
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

// Appends the plugin's sequences after the base ones, like VC.EXE does with
// VCG2.DLL. Sequence lookup by name is last-wins, so plugin versions of
// duplicated names (CRUSH, CLEAN, LURK_D) take over.
anim_merge :: proc(base, plugin: Anim) -> Anim {
	m := base
	m.seqs = make([]Seq, len(base.seqs) + len(plugin.seqs))
	copy(m.seqs, base.seqs)
	copy(m.seqs[len(base.seqs):], plugin.seqs)
	return m
}

// Expands one RLE frame of (count, index) byte pairs into dst (w*h bytes,
// top-down rows). Frames are stored bottom-up like Windows DIBs, and runs
// may cross row boundaries.
frame_decode :: proc "contextless" (a: ^Anim, s: ^Seq, f: Frame, dst: []u8) -> bool {
	src := s.pix[f.offset:][:f.length]
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
// Last match wins, like map_sequence_ids in VC.EXE.
seq_find :: proc "contextless" (a: ^Anim, name: string) -> (idx: int) {
	idx = -1
	for s, i in a.seqs do if s.name == name do idx = i
	return
}

seq_dir_mask :: proc "contextless" (s: ^Seq) -> (mask: u32) {
	for d, k in s.dirs do if len(d.frames) > 0 do mask |= 1 << u32(k)
	return
}
