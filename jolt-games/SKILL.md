---
name: jolt-games
description: Build games, graphics, simulations and interactive 2D/3D programs on Jolt (Clojure on Chez Scheme, no JVM). Use when the user wants a game, game loop, sprite/shape drawing, 3D scene, particle or physics simulation, visualization window, immediate-mode GUI, ECS, sound effects or a game binary in jolt/Clojure; mentions raylib, raylib-jlt (net.b12n.raylib), raygui / raygui-jlt, ents or flecs, slipstream / Slughorn vector rendering, graviton, raylib-jolt-demo, raylib-ios, raylib-android, UPBGE / upbge-jolt, or primitive-math; or wants to live-reload a running game from an nREPL or speed up per-frame Clojure code.
---

# Games and graphics on jolt

Read the `jolt` skill first for project layout, deps.edn, tasks, `jolt.ffi` and
`jolt build`; this skill only covers what is specific to games.

All graphics on jolt go through C over `jolt.ffi`. The main stack is
**raylib 6** via `jlt-commons/raylib-jlt` (namespace `net.b12n.raylib.all`),
which calls the system `libraylib` directly. No codegen, no C shim.

## Which library for which job

| Job | Use | Notes |
|---|---|---|
| 2D/3D game, sim, visualization window | **raylib-jlt** | git dep, `:deps/root "lib"`. ~500 vars. `references/raylib.md` |
| Something raylib-jlt doesn't bind (sound files, PNG textures, ...) | your own `ffi/defcfn` next to it | by-value structs work; verified recipes in `references/raylib.md` |
| Buttons, sliders, text boxes in a raylib window | **raygui-jlt** | not a library: copy `raygui.clj` + vendored header. `references/raygui.md` |
| Many entities, systems, queries, observers | **ents** (flecs) | plain git dep; first run builds flecs (`:build`, jolt 0.8.26+; on 0.8.25 build by hand). `references/ents.md` |
| Resolution-independent vector shapes/text (GPU), reactive scenes | **slipstream** | C++ build, glimmer backend. `references/slipstream.md` |
| iPhone / Android | **raylib-ios**, **raylib-android** | separate toolchains, own bindings. `references/mobile.md` |
| Scripting a Blender/UPBGE scene or game | **upbge-jolt** | has its own skill: `skills/upbge-jolt/SKILL.md` in that repo |
| Hot per-frame numeric code | plain Clojure + hints + primitive arrays | `references/perf.md`. `primitive-math` is for API compatibility, not speed |

Worked example of a whole game: `jlt-commons/graviton` (pure world + input
snapshot + render + a trimmed raylib binding of its own, with writ specs). 187
small programs: `jlt-commons/raylib-jolt-demo` (one sub-project each; `cd
asteroids && jolt -M:run`).

## Setup

```bash
brew install raylib          # macOS; Linux: distro raylib 6.0+ (Ubuntu has none: build from source)
jolt --version               # raylib-jlt needs jolt >= 0.8.0
```

raylib must be **6.0+**: `DrawCircleGradient` changed ABI in 6.0, and 5.5
links fine but draws in the wrong place.

```clojure
;; deps.edn
{:jolt/min-version "0.8.25"
 :paths ["src"]
 :deps {net.b12n/raylib {:git/url   "https://github.com/jlt-commons/raylib-jlt.git"
                         :git/sha   "<sha>"    ; untagged: full HEAD sha
                         :deps/root "lib"}}
 :aliases {:test {:extra-paths ["test"] :main-opts ["-m" "mygame.test-runner"]}}
 :tasks {play {:doc "run the game" :main-opts ["-m" "mygame.main"]}
         test {:doc "pure tests, no window" :task (jolt "-M:test")}
         dist {:doc "native binary" :task (shell "jolt" "build" "-m" "mygame.main" "-o" "target/mygame")}}}
```

raylib-jlt has no tags; pin the current HEAD commit. Fill shas with `jdep
OWNER/REPO` (see the jolt skill's `references/deps-and-tasks.md`, "Depending on
a library: use the latest tag"); never copy a sha from docs. The library's
own `:jolt/native` (Homebrew path first, then `libraylib.so.6`) is inherited,
so you don't restate it. Don't name a task `run` (built-in).

## Layout (graviton's shape)

```
src/mygame/world.clj   pure state + (step world input dt). No raylib. Unit-tested.
src/mygame/main.clj    window, loop, read-input (data), draw (reads world only)
src/mygame/*.clj       extra bindings raylib-jlt lacks (sound, texture, ...)
test/mygame/...        world tests run headless: jolt test
```

Keep raylib out of the world namespace. Input becomes a plain map each frame,
the world is a value, drawing only reads it. Then the logic tests without a
window and the REPL can inspect and reset the state.

## Skeleton (verified on macOS, raylib 6.0)

```clojure
(ns mygame.world)

(def W 800)
(def H 450)

(defn initial [] {:x 400.0 :y 225.0 :vx 180.0 :vy 140.0 :paused? false})

(defn- bounce
  "Point the velocity back inside. A plain flip leaves a ball that overshot
  oscillating inside the wall."
  ^double [^double p ^double v ^double lo ^double hi]
  (cond (< p lo) (Math/abs v)
        (> p hi) (- (Math/abs v))
        :else v))

(defn step [w {:keys [pause? reset?]} dt]
  (let [w (cond-> w reset? (merge (initial)) pause? (update :paused? not))]
    (if (:paused? w)
      w
      (let [dt (double dt)
            x  (+ (double (:x w)) (* (double (:vx w)) dt))
            y  (+ (double (:y w)) (* (double (:vy w)) dt))]
        (assoc w :x x :y y
               :vx (bounce x (:vx w) 20.0 (- W 20.0))
               :vy (bounce y (:vy w) 20.0 (- H 20.0)))))))
```

```clojure
(ns mygame.main
  (:require [net.b12n.raylib.all :as rl]
            [jolt.nrepl]
            [mygame.world :as world]))

(defonce state (atom (world/initial)))  ; the live world, readable from a REPL
(defonce quit? (atom false))            ; (reset! quit? true) closes the window

(defn read-input []
  {:pause? (rl/key-pressed? rl/KEY-SPACE)
   :reset? (rl/key-pressed? rl/KEY-R)})

(defn draw [w]
  (rl/clear-background rl/RAYWHITE)
  (rl/circle! {:x (:x w) :y (:y w) :radius 20 :color rl/MAROON})
  (rl/text! "SPACE pause, R reset" {:x 10 :y 420 :size 20 :color rl/DARKGRAY})
  (rl/fps! {:x 10 :y 10}))

(defn frame! []          ; called through its var: redefining it takes effect next frame
  (swap! state world/step (read-input) (rl/get-frame-time))
  (rl/begin-drawing)
  (draw @state)
  (rl/end-drawing))

(defn run-loop []
  (rl/window! {:width world/W :height world/H :title "mygame"})
  (rl/set-target-fps 60)
  (reset! quit? false)
  (let [quit-at (some-> (System/getenv "QUIT_MS") parse-long (+ (System/currentTimeMillis)))]
    (while (not (or @quit? (rl/window-should-close?)
                    (and quit-at (> (System/currentTimeMillis) quit-at))))
      (frame!)))
  (rl/close-window))

(defn -main [& _]
  (let [stop-repl (when (System/getenv "NREPL") (jolt.nrepl/start 7888))]
    (try (run-loop) (finally (when stop-repl (stop-repl))))))
```

`jolt play` runs it, `QUIT_MS=2000 jolt play` is a timed smoke run, `jolt test`
runs the world tests, `jolt dist` builds `target/mygame` (21 MB, starts and runs).

## Live reloading a running game

Both ways were tested against the skeleton: redefining `draw` from the REPL
changed the next frame, and `(swap! state ...)`/`(reset! quit? true)` from the
REPL drove the running loop.

1. **Game owns the process, REPL embedded** (simplest): `NREPL=1 jolt play`,
   then connect an editor to 7888. `jolt.nrepl/start` returns a stop fn. The
   process exits once the loop ends *and* the editors disconnect.
2. **REPL first**: `jolt nrepl-server`, then evaluate `(rl/run! run-loop)`.
   `rl/run!` (= `jolt.host/call-on-main-thread-async`) puts the window on the
   main thread and returns, so the REPL stays free. A bare `(-main)` from an
   nREPL eval **kills the process on macOS**: AppKit traps `InitWindow` off the
   main thread, with no Clojure exception.

Rules:
- The loop must call through vars (`(frame!)`, `(draw @state)`), not hold fn
  values captured at start, or redefinitions are invisible.
- Never call raylib (draw, load, unload, window) from an eval. Raylib belongs
  to the thread that opened the window. Change data (atoms) or redefine fns
  and let the loop make the calls. Mobile hosts provide `on-next-frame!` for
  one-shot native work.
- Reads of atoms are fine from any thread.
- `defonce` the state, so reloading the namespace keeps the running world.
- A built binary (and `JOLT_DIRECT_LINK=1`) may inline across call sites; a
  redefinition then reaches the REPL but not the loop. Develop from source runs.

## raylib-jlt core API (all via `rl/`)

```clojure
;; window/frame
(rl/window! {:width 800 :height 450 :title "t"})  (rl/set-target-fps 60)
(rl/window-should-close?) (rl/begin-drawing) (rl/end-drawing) (rl/close-window)
(rl/clear-background rl/RAYWHITE) (rl/get-frame-time) (rl/get-time)
(rl/set-config-flags rl/FLAG-WINDOW-RESIZABLE) ; before window!
(rl/get-screen-width) (rl/toggle-fullscreen) (rl/set-exit-key rl/KEY-NULL)
;; drawing: a map or flat keyword args; numbers are coerced to the C types for you
(rl/rect! {:x 10 :y 10 :width 50 :height 20 :color rl/RED})
(rl/circle! {:x 100 :y 100 :radius 8.5 :color rl/BLUE})
(rl/line! {:x1 0 :y1 0 :x2 50 :y2 50 :color rl/BLACK})
(rl/text! "hi" {:x 10 :y 10 :size 20 :color rl/DARKGRAY}) (rl/text-width "hi" {:size 20})
(rl/line-ex! ...) (rl/sector! ...) (rl/ring! ...) (rl/rect-rounded! ...)
;; colors are packed uint32s
(rl/rgba 255 128 0 255)  rl/WHITE rl/BLACK rl/GOLD ...
;; input
(rl/key-down? rl/KEY-LEFT) (rl/key-pressed? rl/KEY-SPACE) (rl/key-released? k)
(rl/mouse-down? rl/MOUSE-LEFT) (rl/mouse-pressed? b) (rl/get-mouse-x) (rl/get-mouse-y)
(rl/get-mouse-wheel) (rl/get-char-pressed) (rl/gamepad-available? 0) (rl/get-touch-x 0)
(rl/get-random-value 0 100)
;; 2D camera, 3D camera (f is a thunk drawn inside the mode)
(rl/with-camera-2d {:target-x x :target-y y :offset-x 400 :offset-y 225 :zoom 2.0} (fn [] ...))
(rl/with-camera-3d cam (fn [] (rl/draw-grid 10 1.0) (rl/cube! {:pos [0 0.5 0] :size 1 :color rl/MAROON})))
```

3D, textures, render targets, shaders, audio streams, binding missing calls
(sound files, PNG sprites) and headless smoke testing: `references/raylib.md`.

## Building and shipping

`jolt build -m mygame.main -o target/mygame` (or the `dist` task). The binary
loads `libraylib` dynamically at startup, so the target machine needs raylib
6 installed (`otool -L` shows no raylib: it is dlopened from the
`:jolt/native` candidates). macOS binaries are unsigned (`xattr -d
com.apple.quarantine` on the receiving machine, or sign). A native lib you
build yourself (raygui, flecs) is declared with a project-relative path, so the
binary only finds it when run from the project directory, unless you add a
`:static` archive (see the `jolt` skill's `references/build.md`).

## Gotchas

- **Never call raylib off the window's thread** (REPL evals, futures, fibers).
- `:float` values read back from C (`ffi/read`, ents components, `get-mouse-wheel`)
  are `java.lang.Float`, as on the JVM. `=` with a double is true, but the hash
  differs, so a set or map keyed by doubles may not find them (small and large
  collections can answer differently, on the JVM too). Wrap in
  `(double ...)` before using them as set members or map keys.
- Raw bindings (`rl/draw-circle`, `rl/draw-rectangle`) take exact C types:
  ints for positions, doubles for `:float`. A ratio or double where `:int` is
  expected throws `invalid foreign-procedure argument` at the first frame. The
  keyword wrappers (`rect!`, `circle!`, `text!`) coerce for you.
- C `bool` returns come back as ints with garbage in the high bytes; raylib-jlt
  masks with `0xff`. Do the same in your own bindings.
- `rl/with-camera-2d`/`with-camera-3d` (and `begin-mode-3d-ptr`) pass the
  camera struct by pointer, which is only correct on arm64 (Apple Silicon).
  On x86-64 Linux/Intel Macs bind `BeginMode2D`/`BeginMode3D` yourself with
  `[:by-value ...]` (`world-to-screen` already does it that way).
- `take-screenshot` writes relative to the cwd; call `rl/flush-batch` first or
  the batched geometry is missing from the image.
- `rl/run!` shadows `clojure.core/run!` in `net.b12n.raylib.all`.
- Per-frame cost is allocation and lazy seqs, not FFI calls. See `references/perf.md`.
