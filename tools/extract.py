#!/usr/bin/env python3
"""Extract game data from original Virtual Creatures installers.

Usage: python3 -I tools/extract.py <dir with setup_*.exe / plugin_*.exe> <out dir>

Never executes the originals: the installers are Info-ZIP self-extractors, so
the payload is read with zipfile, and PE resources are parsed directly.

Output per variant (cr = Chile Rose, rk = Red Knee):
  <out>/<variant>/<name>.idx / .pix   animation index + RLE pixel blobs
  <out>/<variant>/palette.bin         256 * RGB palette
  <out>/<variant>/sounds/<id>.wav     sound effects from VC.EXE
  <out>/<variant>/bitmaps/<mod>_<id>.bmp
  <out>/<variant>/vc.dat
  <out>/<variant>/manifest.json
"""
import io
import json
import os
import struct
import sys
import zipfile

RT_BITMAP = 2
RT_RCDATA = 10


def u16(d, o):
    return struct.unpack_from("<H", d, o)[0]


def u32(d, o):
    return struct.unpack_from("<I", d, o)[0]


def pe_resources(data):
    """Yield (type, name, bytes) for every resource leaf. type/name: int or str."""
    pe = u32(data, 0x3C)
    nsec = u16(data, pe + 6)
    opt = pe + 24
    opt_size = u16(data, pe + 20)
    dd = opt + (96 if u16(data, opt) == 0x10B else 112)
    rsrc_rva = u32(data, dd + 8 * 2)
    secs = []
    for i in range(nsec):
        s = opt + opt_size + 40 * i
        vsize, va, rsize, raw = struct.unpack_from("<IIII", data, s + 8)
        secs.append((va, max(vsize, rsize), raw))

    def rva2off(rva):
        for va, size, raw in secs:
            if va <= rva < va + size:
                return rva - va + raw
        raise ValueError(f"rva {rva:#x} not mapped")

    base = rva2off(rsrc_rva)

    def entry_name(v):
        if v & 0x80000000:
            o = base + (v & 0x7FFFFFFF)
            return data[o + 2 : o + 2 + 2 * u16(data, o)].decode("utf-16-le")
        return v

    def walk(off):
        n = u16(data, off + 12) + u16(data, off + 14)
        for i in range(n):
            name, ptr = struct.unpack_from("<II", data, off + 16 + 8 * i)
            yield entry_name(name), ptr

    for tname, tptr in walk(base):
        for rname, rptr in walk(base + (tptr & 0x7FFFFFFF)):
            for _lang, lptr in walk(base + (rptr & 0x7FFFFFFF)):
                rva, size = struct.unpack_from("<II", data, base + lptr)
                o = rva2off(rva)
                yield tname, rname, data[o : o + size]


def bmp_file(dib):
    """Prefix a resource DIB with a BITMAPFILEHEADER."""
    hs = u32(dib, 0)
    bpp = u16(dib, 14)
    clr = u32(dib, 32)
    pal = (clr or (1 << bpp if bpp <= 8 else 0)) * 4
    return b"BM" + struct.pack("<IHHI", 14 + len(dib), 0, 0, 14 + hs + pal) + dib


def dib_palette(dib):
    """256 BGRX entries after the header -> 768 bytes RGB."""
    hs = u32(dib, 0)
    out = bytearray()
    for i in range(256):
        b, g, r, _ = dib[hs + 4 * i : hs + 4 * i + 4]
        out += bytes((r, g, b))
    return bytes(out)


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def extract_anims(module, prefix, out, files):
    rc = {name: d for t, name, d in pe_resources(module) if t == RT_RCDATA}
    # Index blob is followed by its pixel blob: 9000/9001 in VCG, 1000/2000 in VCG2.
    ids = sorted(k for k in rc if isinstance(k, int))
    for rid, pid in zip(ids, ids[1:]):
        idx = rc[rid]
        if not idx[:1].isalpha() or rc[pid][:1].isalpha():
            continue  # not an index/pixel pair
        name = prefix + idx[:32].split(b"\0")[0].decode().lower()
        write(f"{out}/{name}.idx", idx)
        write(f"{out}/{name}.pix", rc[pid])
        files += [f"{name}.idx", f"{name}.pix"]
        yield name


def main():
    src, dst = sys.argv[1], sys.argv[2]
    for variant in ("cr", "rk"):
        out = f"{dst}/{variant}"
        files, anims, sounds = [], [], []
        setup = zipfile.ZipFile(f"{src}/setup_{variant}.exe")
        vc = setup.read("VC.EXE")
        vcg = setup.read("VCG.DLL")
        write(f"{out}/vc.dat", setup.read("VC.DAT"))

        anims += extract_anims(vcg, "", out, files)
        plugin = f"{src}/plugin_{variant}.exe"
        if os.path.exists(plugin):
            vcg2 = zipfile.ZipFile(plugin).read("VCG2.DLL")
            anims += extract_anims(vcg2, "plugin_", out, files)

        palette = None
        for modname, mod in (("vc", vc), ("vcg", vcg)):
            for t, name, d in pe_resources(mod):
                if t == "WAVE":
                    write(f"{out}/sounds/{name}.wav", d)
                    sounds.append(name)
                elif t == RT_BITMAP:
                    write(f"{out}/bitmaps/{modname}_{name}.bmp", bmp_file(d))
                    files.append(f"bitmaps/{modname}_{name}.bmp")
                    if modname == "vcg" and name == 9100:  # creature buffer: tank palette
                        palette = dib_palette(d)
        write(f"{out}/palette.bin", palette)
        files.append("palette.bin")

        manifest = {"files": files, "anims": anims, "sounds": sorted(sounds)}
        write(f"{out}/manifest.json", json.dumps(manifest, indent=1).encode())
        print(variant, "anims:", anims, "sounds:", len(sounds))


if __name__ == "__main__":
    main()
