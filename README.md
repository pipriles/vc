# vc_port

Browser port of *Virtual Creatures — Pet Spider* (Global Beach / Virtual
Creatures Ltd., 1999): Chile Rose and Red Knee tarantulas plus the plugin
animation packs. Written in Odin, compiled to WebAssembly, drawn on a canvas.

The original game data is not included. Extract it from your own copies of
the installers (`setup_cr.exe`, `setup_rk.exe`, `plugin_cr.exe`,
`plugin_rk.exe`); nothing from them is executed.

## Requirements
- Odin (`brew install odin`) and `wasm-ld` (`brew install lld`)
- Python 3 (extraction only)
- Ghidra + JDK 21 (reverse engineering only)

## Build and run
```sh
python3 -I tools/extract.py "/path/to/installers" data
./build.sh
python3 -I tools/serve.py   # no-cache dev server on :8081
```
Open http://127.0.0.1:8081/ (`?v=rk` for Red Knee).

## Layout
| path | contents |
|------|----------|
| `src/`   | Odin: format parser (`vcg.odin`), viewer/game (`main.odin`) |
| `web/`   | HTML + JS host (file prefetch, canvas blit) |
| `tools/` | extractor, Ghidra scripts (`decompile.sh`) |
| `re/`    | `symbols.txt`: names for addresses in `VC.EXE` |
| `docs/`  | `FORMAT.md` (animation format), `BEHAVIOR.md` (game logic notes) |

## Status
- [x] Installer + resource extraction
- [x] Animation format decoded; viewer for all sequences/directions
- [ ] Game logic reverse engineering (in progress, see `docs/BEHAVIOR.md`)
- [ ] Tank scene, spider AI, crickets, stats, tools, sound
