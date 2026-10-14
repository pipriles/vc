# VCG animation format (Virtual Creatures, 1999)

Animations live in `RT_RCDATA` resources of `VCG.DLL` / `VCG2.DLL`, in pairs:
even id = **index**, odd id = **pixels** (e.g. 9000/9001 spider, 9002/9003 cricket,
9004/9005 logo, 9006/9007 footprints, 9008/9009 web, 9010/9011 skin; plugin 1000/2000).

## Index blob
| off | type | field |
|-----|------|-------|
| 0   | char[32] | creature name (`SPIDER`, `CRICKET`, ...) |
| 32  | u16 | sequence count N |
| 34  | u16 | canvas width (320) |
| 36  | u16 | canvas height (200) |
| 38  | u16 | pad |
| 40  | Seq[N] | fixed 18764-byte records |

## Seq record (18764 bytes)
| off | type | field |
|-----|------|-------|
| 0    | char[32] | sequence name (`WALK`, `CIRCLE`, `LURK`, `THREAT`, ...) |
| 32   | u32 | 0 |
| 36   | u32 | random repeats: plays = rand()*max/0x7fff + 1 |
| 40   | u32 | max repeats |
| 0x48 + k*0x924 | Dir[8] | one block per facing direction k=0..7 (base b below) |

Each Dir block really starts 0x14 bytes before b (its flag bytes sit at
b-0x14); the last block of a record is cut short, so never slice a fixed
0x924 bytes past b. `enqueue_anim` also reads a u16 at b-2.

## Dir block (0x924 bytes, base b)
| off | type | field |
|-----|------|-------|
| b-0x14  | u16 | move_x: moves while playing (60% chance per play) |
| b-0x12  | u16 | move_y: moves while playing |
| b-0x10  | u16 | ping-pong (random) |
| b-0x0e  | u16 | no floor clamp |
| b-0x0c  | u32 | ping-pong |
| b-0x08  | u32 | random hold |
| b-0x04  | u16 | hold |
| b-0x02  | u16 | needs precondition check |
| b+2     | u16 | hold max |
| b+4     | u16 | frame count F (0 = direction unused) |
| b+6     | u8  | key2: second skipped colour = shadow (0x31) |
| b+8     | {u32 x0,y0,x1,y1}[64] | per-frame bounding box in canvas |
| b+0x408 | u32[64] | per-frame offset into pixel blob |
| b+0x508 | u32[64] | per-frame byte length |
| b+0x708 | i8[64]  | per-frame dx |
| b+0x748 | i8[64]  | per-frame dy |
| b+0x788 | u8[64]  | reverse dx/dy when playing backward |
| b+0x7c8 | i16[64] | hold flag |
| b+0x848 | i16[64] | hold ticks (negative = random) |
| b+0x8c8 | u8[64]  | keep previous scale (not present in the last block) |

## Pixel blob
Each frame = RLE `(u8 count, u8 palette_index)` pairs, row-major **bottom-up**
(like DIBs; runs may cross rows),
decoding to exactly width*height (64000) bytes. Palette = 8-bit palette of
VCG bitmaps. Index 7 (spider) / 0xFA (others) = transparent key (but see
"Transparent colour" below). Shadow pixels are the direction's key2 colour
(0x31 = 49), drawn as solid colour 49 in a shadow pass before the bodies;
no blending.

Animation pairs per DLL: VCG has 9000/9001 spider, 9002/9003 cricket,
9004/9005 logo, 9006/9007 footprints, 9008/9009 web, 9010/9011 skin;
VCG2 (plugin) has 1000/2000 extra spider sequences
(CRUSH, GLASS, HAIR, CLEAN, LOG_HIDE, WEB_LAYING, LURK_D).

Palettes differ per variant (Chile Rose vs Red Knee); take it from VCG
bitmap 1000. Index 7 = 0x808080 (spider key), 0xFA = 0x00FF00.

See BEHAVIOR.md for runtime behaviour.

## Transparent colour
The original takes each decoded frame's first bitmap byte as transparent:
the bottom-left pixel (frames are stored bottom-up). The spider's own
sequences use palette 7, the plugin's GLASS uses 250 (green).
