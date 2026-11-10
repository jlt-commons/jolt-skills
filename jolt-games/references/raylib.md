# raylib-jlt in depth

Repo: `jlt-commons/raylib-jlt` (library in `lib/`, guide in `docs/guide/`,
site <https://jlt-commons.github.io/raylib-jlt/>). Examples:
`jlt-commons/raylib-jolt-demo`, one sub-project per demo; grep it for any
raylib function name to find a working call. Every snippet below ran on
macOS arm64 with raylib 6.0.

## Modules

`net.b12n.raylib.all` re-exports the 19 modules (generated; 499 vars). Require
a module directly only for a narrow slice.

| module | what |
|---|---|
| `core` | window lifecycle, flags, monitors, clipboard, `run!` |
| `kwargs` | `window! text! rect! circle! line! pixel! ellipse! sector! ring! line-ex! fps! text-width` |
| `shapes` | raw `draw-*` (positional, exact C types), blend modes, `rect-pro! rect-rounded! circle-gradient!` |
| `color` | `rgba`, named palette, `get-color` |
| `input` | keys, mouse, gamepad, touch, gestures, `get-random-value` |
| `camera` | `with-camera-2d`, `with-camera-3d`, `world-to-screen`, `camera3d-alloc`, `update-camera!` |
| `models` | `draw-grid cube! sphere! draw-cube! draw-sphere! draw-cylinder! draw-plane!`, meshes, instancing |
| `textures` | GPU textures via rlgl: `texture-from-fn texture! render-texture with-render-texture` |
| `images` | CPU images: generators, processing, `image->texture` |
| `shaders` | `shader shader-vf with-shader uniform-loc set-uniform-*!` |
| `audio` | raw `AudioStream` only: `load-audio-stream on-audio-stream! update-audio-stream` |
| `rlgl` / `splines` / `rays` / `files` / `log` / `util` | immediate mode, splines, picking, dropped files, trace log, hashes |
| `native` | `vector2-layout vector3-layout rectangle-layout texture2d-layout staged` |

Not bound: `LoadTexture`/`DrawTexture*` from files, `Font`, `Model` files,
`Sound`, `Music`, `Wave`. Bind them yourself (below).

## Drawing conventions

- Colors are packed `uint32` (`(rl/rgba r g b a)`), passed as `:uint`.
- Keyword wrappers take a map or flat keys, and coerce numbers.
- Raw `rl/draw-*` are positional with exact types: `(rl/draw-circle (int x) (int y) (double r) color)`.
  Use them in hot loops to skip the kwargs map.
- raylib batches geometry; `rl/flush-batch` forces it (needed before a
  screenshot or when switching GL state yourself).

## 2D camera, 3D

```clojure
(rl/with-camera-2d {:target-x px :target-y py :offset-x 400 :offset-y 225 :zoom 2.0}
  (fn [] (draw-world)))

(def cam {:pos-x 6.0 :pos-y 5.0 :pos-z 6.0 :target-x 0.0 :target-y 0.0 :target-z 0.0
          :up-x 0.0 :up-y 1.0 :up-z 0.0 :fovy 45.0 :projection 0})
(rl/with-camera-3d cam
  (fn []
    (rl/draw-grid 10 1.0)
    (rl/cube! {:pos [0 0.5 0] :size 1 :color rl/MAROON})
    (rl/sphere! {:pos [2 0.5 -1] :radius 0.5 :color rl/SKYBLUE})))
(let [[sx sy] (rl/world-to-screen [0 1.2 0] cam)]       ; label a 3D point, outside the 3D block
  (rl/text! "cube" {:x (- sx 20) :y (- sy 20) :size 20 :color rl/DARKGRAY}))
```

For a camera that persists and is driven by raylib's controller:
`(def c (rl/camera3d-alloc ...same keys...))`, `(rl/update-camera! c rl/CAMERA-ORBITAL)`
each frame, `(rl/begin-mode-3d-ptr c) ... (rl/end-mode-3d)`, `(rl/camera3d-free! c)`.
The camera wrappers pass the struct by pointer, correct only on arm64 (see SKILL.md gotchas).

## Textures, render targets, shaders

```clojure
(def checker (rl/texture-from-fn 64 64
               (fn [x y] (if (even? (+ (quot x 8) (quot y 8))) rl/WHITE rl/BLACK))))
(rl/texture-filter! checker rl/RL-TEXTURE-FILTER-NEAREST)   ; pixel art
(def rt (rl/render-texture 160 90))                           ; {:fbo :texture :width :height}
(def sh (rl/shader "#version 330
in vec2 fragTexCoord; in vec4 fragColor; out vec4 finalColor;
uniform float t;
void main() { finalColor = vec4(fragTexCoord.x, 0.5 + 0.5*sin(t), 1.0 - fragTexCoord.y, 1.0); }"))
(def t-loc (rl/uniform-loc sh "t"))                           ; look up once, not per frame

;; per frame
(rl/with-render-texture rt (fn [] (rl/clear-background rl/DARKBLUE)
                                  (rl/circle! {:x 80 :y 45 :radius 30 :color rl/GOLD})))
(rl/begin-drawing)
(rl/texture! checker {:x 20 :y 20 :width 128 :height 128})
(rl/texture! (:texture rt) {:x 200 :y 20 :width 320 :height 180 :v0 1.0 :v1 0.0}) ; FBOs are upside down
(rl/set-uniform-float! sh t-loc (rl/get-time))
(rl/with-shader sh (fn [] (rl/texture! checker {:x 20 :y 220 :width 300 :height 120})))
(rl/end-drawing)

;; teardown
(rl/unload-shader! sh) (rl/unload-render-texture! rt) (rl/unload-texture! checker)
```

`texture!` also takes `:u0 :v0 :u1 :v1` (atlas regions), `:rotation`,
`:origin-x :origin-y`, `:tint`. `rl/update-texture-from-fn!` re-uploads pixels.
Shaders must start with `#version 330` (desktop GL 3.3 core).

## Audio streams (synthesized sound)

The callback runs on raudio's own thread; raylib-jlt binds it `:collect-safe`.

```clojure
(rl/init-audio-device)
(def stream (rl/load-audio-stream 44100 32 1))      ; rate, 32-bit float, mono
(def phase (atom 0.0))
(def entry (rl/on-audio-stream! stream
             (fn [buf frames]
               (loop [i 0 p (double @phase)]
                 (if (< i frames)
                   (do (ffi/write buf :float (Math/sin (* 2.0 Math/PI p)) (* 4 i))
                       (recur (inc i) (let [q (+ p (/ 440.0 44100.0))] (if (>= q 1.0) (- q 1.0) q))))
                   (reset! phase p)))
               nil)))
(rl/play-audio-stream stream)
;; shutdown order matters: stop the callback before freeing it
(rl/clear-audio-stream-callback! stream)
(rl/unload-audio-stream stream)
(rl/free-callable! entry)
(rl/close-audio-device)
```

## Binding what's missing (by-value structs work)

jolt has `[:by-value [:struct ...]]` (since 0.7.23). Parts of raylib-jlt's
docs and docstrings still say by-value `Vector2`/`Vector3` arguments are
impossible and route around them with rlgl; that is out of date.

A by-value **return** is called with a destination pointer as an extra first
argument, and returns that pointer. Write the descriptor literally in
`defcfn` (a layout var doesn't work there). Nested structs must be nested in
the descriptor so C padding is right.

Sound effects from files:

```clojure
(ns mygame.sound
  (:require [jolt.ffi :as ffi]))

;; Sound = {AudioStream stream; unsigned frameCount}. AudioStream pads to 32 bytes,
;; so the nesting matters: flat fields put frameCount at 28 and LoadSound "fails".
(def sound-layout
  (ffi/layout [:struct [[:stream [:struct [[:buffer :pointer] [:processor :pointer]
                                            [:sample-rate :uint32] [:sample-size :uint32]
                                            [:channels :uint32]]]]
                        [:frame-count :uint32]]]))

(ffi/defcfn ^:private load-sound-raw "LoadSound" [:string]
  [:by-value [:struct [[:stream [:struct [[:buffer :pointer] [:processor :pointer]
                                           [:sample-rate :uint32] [:sample-size :uint32]
                                           [:channels :uint32]]]]
                       [:frame-count :uint32]]]])
(ffi/defcfn ^:private play-sound-raw "PlaySound"
  [[:by-value [:struct [[:stream [:struct [[:buffer :pointer] [:processor :pointer]
                                            [:sample-rate :uint32] [:sample-size :uint32]
                                            [:channels :uint32]]]]
                        [:frame-count :uint32]]]]] :void)
(ffi/defcfn ^:private unload-sound-raw "UnloadSound"
  [[:by-value [:struct [[:stream [:struct [[:buffer :pointer] [:processor :pointer]
                                            [:sample-rate :uint32] [:sample-size :uint32]
                                            [:channels :uint32]]]]
                        [:frame-count :uint32]]]]] :void)
(ffi/defcfn set-master-volume "SetMasterVolume" [:float] :void)

(defn load-sound [path]                      ; after rl/init-audio-device
  (let [p (ffi/alloc (ffi/layout-size sound-layout))]
    (load-sound-raw p path)
    (when (zero? (ffi/read-field p sound-layout :frame-count))
      (ffi/free p)
      (throw (ex-info "LoadSound failed" {:path path})))
    p))
(defn play! [snd] (play-sound-raw snd))
(defn unload-sound [snd] (unload-sound-raw snd) (ffi/free snd))
```

Sprites from PNG files (needs an open window):

```clojure
(ns mygame.texture
  (:require [jolt.ffi :as ffi]))

(def texture-layout (ffi/layout [:struct [[:id :uint] [:width :int] [:height :int]
                                          [:mipmaps :int] [:format :int]]]))
(ffi/defcfn ^:private load-texture-raw "LoadTexture" [:string]
  [:by-value [:struct [[:id :uint] [:width :int] [:height :int] [:mipmaps :int] [:format :int]]]])
(ffi/defcfn ^:private unload-texture-raw "UnloadTexture"
  [[:by-value [:struct [[:id :uint] [:width :int] [:height :int] [:mipmaps :int] [:format :int]]]]] :void)
(ffi/defcfn ^:private draw-texture-ex-raw "DrawTextureEx"          ; texture, Vector2 pos, rot, scale, tint
  [[:by-value [:struct [[:id :uint] [:width :int] [:height :int] [:mipmaps :int] [:format :int]]]]
   [:by-value [:struct [[:x :float] [:y :float]]]]
   :float :float :uint] :void)

(def ^:private v2-layout (ffi/layout [:struct [[:x :float] [:y :float]]]))
(defonce ^:private v2 (ffi/alloc (ffi/layout-size v2-layout)))  ; reused scratch, no per-draw alloc

(defn load-texture [path]
  (let [t (ffi/alloc (ffi/layout-size texture-layout))]
    (load-texture-raw t path)
    (if (zero? (ffi/read-field t texture-layout :id))
      (do (ffi/free t) (throw (ex-info "LoadTexture failed" {:path path})))
      t)))

(defn draw! [t x y & {:keys [rotation scale tint] :or {rotation 0.0 scale 1.0 tint 0xffffffff}}]
  (ffi/write-field v2 v2-layout :x (double x))
  (ffi/write-field v2 v2-layout :y (double y))
  (draw-texture-ex-raw t v2 (double rotation) (double scale) tint))

(defn unload-texture [t] (unload-texture-raw t) (ffi/free t))
```

Look up struct definitions in `/opt/homebrew/include/raylib.h` (or the
distro's) rather than from memory. Mask C `bool` returns with `0xff`.

## Headless smoke runs

The demos honour `RAYLIB_APP_AUTO_QUIT_MS=1500` (close after a timer) and
`RAYLIB_APP_SHOT=shot.png` (one frame to PNG, relative path) through their
`net.b12n.raylib-jlt.app` harness (in raylib-jolt-demo's `common/`, not the
library). Copy the pattern: a deadline in the loop condition, and
`(rl/flush-batch) (rl/take-screenshot "x.png")` on one frame. Look at the
PNG: a compile or load check does not show that it rendered.

```bash
cd raylib-jolt-demo/bounce && RAYLIB_APP_AUTO_QUIT_MS=1500 jolt -M:run
cd raylib-jolt-demo && jolt -M:check        # compile every demo, no window
```

When a REPL-hosted window kills the process with no Clojure error, it is a
native crash: `ls -t ~/Library/Logs/DiagnosticReports/jolt-*.ips | head -1`.
