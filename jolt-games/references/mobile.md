# iOS and Android (summary)

Both are cross-compile pipelines with their own bindings: neither uses
raylib-jlt, because there is no `libraylib.dylib`/`.so` to load on a phone
(raylib is linked statically into the executable, and raylib-jlt's
`:jolt/native` entry would fail). Read each repo's README and RUNBOOK before
starting. Nothing here was run on a device for this skill; the host-side
checks noted below were.

## Shared model: scenes are reducers

The game logic is a pure `.cljc` scene, a map of fns
`{:id :title :init :update :draw :dispose}`, each returning `[state events]`.
The platform's host loop owns the window, polls input, and calls the scene.
Drawing is a `draw-scene!` multimethod method dispatched on `:id`. So the
logic tests on the laptop with `jolt test`. Porting a desktop raylib demo
means turning its self-owned loop into this reducer and deriving geometry
from the live screen size instead of a fixed 800x450
(`raylib-ios/docs/guide/porting-an-example.md`).

## iOS: `jlt-commons/raylib-ios`

- raylib built with `PLATFORM=SDL` + GLES2 against SDL2 for iOS; both static
  archives `-force_load`ed into the binary made by `jolt build --target`.
  Runs as threaded portable bytecode (no JIT on iOS).
- Needs Xcode, cmake, Chez Scheme 10.4.1 on PATH as `chez` (exact version: a
  target pack only loads into the Chez that made it), a paired iPhone and an
  Apple Development identity.
- Tasks (in raylib-ios): `jolt test`, `SDK=device jolt deps` (SDL2 + raylib
  archives, once), `NS=my.app TARGET=device jolt build-app`, `UDID=<hardware
  udid> jolt deploy`, `jolt devices`, `jolt live` + `jolt proxy` (nREPL over USB).
- Your own app (from `docs/guide/your-own-app.md`; the host-side load check
  below was run):

```clojure
;; deps.edn
{:paths ["src"]
 :deps {net.b12n/raylib-ios {:git/url "https://github.com/jlt-commons/raylib-ios.git"
                             :git/sha "<full 40-hex sha>"}}} ; HEAD of main, as its guide does

;; src/my/scene.cljc
(ns my.scene)
(defn- init [_] [{:n 0} [[:scene/init :my-scene]]])
(defn- update-scene [state _input] [(update state :n inc) []])
(defn- draw [state _input] [state []])
(defn- dispose [state] [state [[:scene/dispose :my-scene]]])
(defn scene [] {:id :my-scene :title "My Scene"
                :init init :update update-scene :draw draw :dispose dispose})

;; src/my/scene/draw.clj
(ns my.scene.draw
  (:require [net.b12n.raylib-ios.draw :as draw]
            [net.b12n.raylib-ios.host :as rl]))
(defmethod draw/draw-scene! :my-scene [_id state {:keys [m]}]
  (let [[w h] (:screen m)]                      ; the safe region, origin already moved
    (draw/clear-to! [20 24 40 255])
    (rl/draw-text (str "frame " (:n state)) (quot w 4) (quot h 2) 48
                  (draw/color [255 255 255 255]))))

;; src/my/app.clj  (must require the draw ns: nothing else loads it)
(ns my.app
  (:require [my.scene :as scene] [my.scene.draw]
            [net.b12n.raylib-ios.runner :as runner]))
(defn -main [& _] (runner/run! (scene/scene)))
```

  Check on the host: `jolt -e "(require 'my.app)"`. Build from your project
  with raylib-ios's `tools/ios/build.sh` (find the checkout via `jolt -Spath`;
  `DRY_RUN=1` prints resolved paths). Several scenes behind a menu:
  `(net.b12n.raylib-ios.gallery/run! {:scenes [...] :categories [...]})`.
- Live: `net.b12n.raylib-ios.live` / `runner.live/live-run!` add an nREPL;
  touch raylib only through `net.b12n.raylib-ios.host/on-next-frame!`. Build
  with `DEV_BUILD=1`, or the release build's inlining hides redefinitions
  from the running loop. Ship builds without the listener (App Store 2.5.2).
- 137 ready scenes: `jlt-commons/raylib-ios-demo` (`bb <scene>`, `bb gallery`).

## Android: `jlt-commons/raylib-android` (untagged)

**Work in progress: its README says it has not yet run on Android hardware.**

- `jolt build --library` cross-compiles the entry ns to `libjoltraylib.so`
  (native arm64, `tarm64le`); a NativeActivity `main.c` dlopens it and calls
  one name published with `ffi/export!`, which is `raylib.host/run!`, the
  frame loop. raylib is compiled from pinned source into `libmain.so`;
  `:jolt/native` names `libmain.so` with `:optional true`.
- Needs jolt 0.8.1+, JDK 17 + Gradle 8.9 (for the APK build only), Android SDK
  35 + NDK, an arm64 device, an x86_64 Linux or Apple Silicon host. `jolt
  pack` cross-builds Chez once (~15 min).
- Tasks: `jolt test` (host), `jolt deps`, `jolt pack`, `NS=raylib.touch jolt
  build-app`, `jolt release`, `jolt deploy`, `jolt log`, `jolt live`, `jolt
  proxy`. A jolt task takes no arguments: use env vars (`MODE=release`).
- stdout goes nowhere on Android: log through `raylib.host/log` and read
  `jolt log`. Touch raylib from the REPL only via `raylib.host/on-next-frame!`.

## Performance on a phone

From `raylib-ios/docs/guide/performance-on-a-phone.md` (measured on an
iPhone 17 Pro): FFI calls are cheap (2400 per frame at 57 fps); lazy
sequences and per-element allocation in draw loops cost 3-4x (spirograph 14
-> 52 fps by replacing `map-indexed`/`partition` with an indexed `loop`).
Budget about a thousand lines/circles per frame; filled rectangles are
cheaper (2551 at 58 fps). See `perf.md`.
