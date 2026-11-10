# Building native binaries

Source: `building-and-deps.md` (sections "Building binaries" onward),
`tools-deps.md` (Standalone binaries, Tree-shaking), `embedded-resources.md`.

`jolt build -m NS` AOT-compiles the app, its deps, `clojure.core` and the
runtime into **one self-contained executable**: Chez native code in a vfasl
boot image, linked against the Chez kernel. No JVM, no Chez, no source on the
target. The distributed `jolt` carries the kernel; the build needs only `cc`
(macOS: `xcode-select --install`).

```bash
jolt build -m myapp.core -o target/myapp     # default output: target/release/<project>
./target/myapp args                          # args reach -main
```

## Modes and flags

| flag / `:jolt/build` key | effect |
|---|---|
| (default) release | type inference, your defs direct-linked, inlining; `^:redef`/`^:dynamic` opt a def out |
| `--opt` / `:opt true` | same code, drops app inspector info (smaller; frames on `defn` lines) |
| `--dev` | fast build, no inference; output in `target/debug/` |
| `--no-direct-link` | every app var stays redefinable |
| `--closed-world` / `:closed-world true` (`--tree-shake`) | drop everything unreachable from `-main` (1–2 MB) |
| `--boot fast\|small\|plain` / `:boot :small` | boot image encoding: fastest start / smallest / no vfasl |
| `:embed ["resources"]` | bake dirs in; `io/resource` serves them (as `jar:file:jolt-embedded-resources.jar!/…`) |
| `:exclude-resources ["**.ext.js" "cljsjs/"]` | leave dependency files out |
| `--dynamic` / `:dynamic-natives true` | load `:jolt/native` libs at runtime instead of linking `:static` archives |
| `--include NS` / `:include [ns]` | bake a namespace only reached via runtime `requiring-resolve` |
| `--signable` | structurally complete executable (passes `codesign --verify --strict`) |
| `--library` | shared object for embedding (`jolt_library_init` / `jolt_lookup`) |
| `--target MACHINE --target-pack DIR` | cross-compile (see jolt's `tools/cross-compile`) |
| `--profile-gen` / `--profile-use F…` | profile-guided build |

CLI flags beat `deps.edn`, which beats env (`JOLT_BOOT`, …).

## Things that bite in a binary but not in `jolt -m`

- **Runtime resolution**: `eval`, `load-string`, a computed `(require (symbol x))`
  keep the compiler in the binary; `resolve`/`ns-resolve`/`requiring-resolve` on
  the live path stop `--closed-world` from shaking (the build names the sites and
  prints the `:jolt/tree-shake {:allow-dynamic […]}` line to paste, but only
  paste it when the site is truly dead). A namespace reached only via
  `requiring-resolve` needs `--include`.
- **Resources**: only `:embed` dirs and dependency resources are inside. Files
  read through `io/file` stay external by design (config that's edited without
  a rebuild). A dependency that reads its own resource at load (Selmer's error
  template) may need a copy in your `resources/`.
- **Natives**: a spec with `:static` is linked in; without it the binary loads
  the shared object at startup, so it has to exist on the target. On Linux a C++
  dependency may need `LD_PRELOAD=$(g++ -print-file-name=libstdc++.so) jolt build …`
  (newsroom README).
- **macOS**: an unsigned binary gets quarantined when downloaded:
  `xattr -d com.apple.quarantine ./app`, or sign it (`--signable` first).
- **Platform floors**: prebuilt jolt ships for macOS (arm64, x86_64), Linux
  x86_64 (glibc ≥ 2.17), Windows x86_64 and aarch64 Android. Build release binaries on the oldest OS you support (newsroom
  uses `ubuntu-22.04`).

## Caches and knobs

`~/.jolt/aot-cache` (namespace cache, shared with `jolt run`),
`~/.jolt/runtime-cache`, `~/.jolt/build-cache` (per-namespace units, parallel
compile). `JOLT_BUILD_CACHE=0`, `JOLT_BUILD_JOBS=N`, `JOLT_BUILD_PROFILE=1`
(phase timings), `JOLT_MAX_HEAP=4g` for very large apps.

## Typed numeric code

Inference covers most float code in builds. Otherwise add `^double`/`^long` hints
on params/returns/loop bindings/record fields (contracts: `^long` raises on
overflow instead of promoting), or `(double x)`/`(long x)` casts where values come
from I/O or untyped maps. REPL/`-e`/nREPL skip whole-program passes, so measure
performance in a built binary.

## CI pattern (from newsroom)

- Install a jolt release per target:
  `https://github.com/jolt-lang/jolt/releases/download/vX.Y.Z/jolt-vX.Y.Z-<target>.tar.gz`
  with targets `aarch64-macos`, `x86_64-linux`, `x86_64-windows` (`.zip`); put
  the extracted `jolt` on `PATH`. See https://github.com/yogthos/newsroom/blob/main/ci/install-jolt.sh.
- Cache `~/.jolt/gitlibs` and `~/.m2` (newsroom points `JOLT_GITLIBS_DIR` and
  `JOLT_MAVEN_REPOSITORY` into the workspace for actions/cache).
- Run tests (`jolt -M:test`), then `jolt build`, then a smoke script that starts
  the binary in a clean environment and probes it (https://github.com/yogthos/newsroom/blob/main/ci/smoke.sh).
  That last step is what proves the archive carries its natives and resources.
- Windows runs under MSYS2 UCRT64 with the native libs (openssl, sqlite3,
  libxml2, zlib) installed through pacman.
- Optionally pin the jolt version with a repository variable (`JOLT_PIN`).
