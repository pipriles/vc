# vc_port

Browser port of an old virtual pet tarantula game. Written in Odin, compiled to WebAssembly, drawn on a canvas.

## Requirements

- Odin (`brew install odin`) and `wasm-ld` (`brew install lld`)
- Python 3, for the dev server
- Node, for the browser smoke test
- The original game data, included in `data/` (`data/cr` and `data/rk`)

### Extracting the game data

To regenerate `data/` from your own copies of the installers (`setup_cr.exe`, `setup_rk.exe`,
`plugin_cr.exe`, `plugin_rk.exe`); nothing from them is executed:

```sh
python3 -I tools/extract.py "/path/to/installers" data
```

## Build and run

```sh
./build.sh                  # build/vc.wasm and the site in build/
python3 -I tools/serve.py   # no-cache dev server on :8081
```

Open http://127.0.0.1:8081/ for the Chile Rose tank, `?v=rk` for the Red
Knee, and `viewer.html` for the animation viewer.

## Tests

```sh
./test.sh                                    # everything
./test.sh -define:ODIN_TEST_NAMES=vc.<name>  # one native test
```

Runs the native tests, then builds the wasm and smoke-tests it in Node.
What the tests cover and how to keep them fast: `docs/TESTING.md`.
