# slipstream (GPU vector shapes and text)

Repo: `jlt-commons/slipstream` (tagged).
Jolt wrapper for [Slughorn](https://github.com/AlphaPixel/slughorn): curves and
glyphs rendered on the GPU at any scale. Full docs in the repo's `docs/`
(`core.md`, `scene.md`, `glimmer.md`, `rendering.md`, `demoscene.md`).
Needs jolt 0.8.23+.

Use it for resolution-independent 2D (vector UI, logos, crisp text,
gradients, masks, blend modes, SDF effects). It renders into its own GLFW or
glimmer window; the repo has no raylib integration.

## Build

Needs CMake, a C++20 compiler, pkg-config, FreeType, `nlohmann/json`. The
`native` task fetches Slughorn (pinned, or `SLUGHORN_HOME`), GLFW, GLAD and
msdfgen.

```bash
cd slipstream
jolt -P && jolt native                    # ~35 s on an M-series Mac
SLIPSTREAM_TEST_FONT=/System/Library/Fonts/Geneva.ttf jolt test
```

As a dependency, use a plain git dep
(`io.github.jlt-commons/slipstream {:git/tag "<latest>" :git/sha "<sha>"}`, fill
with `jdep jlt-commons/slipstream`; see the jolt skill's `references/deps-and-tasks.md`).
Its `:jolt/native` spec carries `:build "native"`, so the jolt release after 0.8.25 that adds `:build` support (0.8.26+, jolt#1571) builds
`native/libslipstream.dylib` in the gitlib checkout on first run (~35 s). On
jolt 0.8.25, run `jolt -P && jolt native` once inside the gitlib checkout (find
it with `jolt -Spath`). It brings `jolt-lang/glimmer` and `jolt-lang/nrepl`
with it.

## Declarative scene (verified)

```clojure
(require '[slipstream.core :as slug])

(def scene-data
  [:scene {:texture-width 512 :curve-precision 32}
   [:font {:id :body :path "/System/Library/Fonts/Geneva.ttf"}]
   [:path {:id :rect} [:rect 0 0 1 1]]
   [:linear-gradient {:id :sky :from [0 0] :to [1 0]}
    [0 [0.1 0.2 0.8 1]]
    [1 [0.2 0.8 1.0 1]]]
   [:shape {:id :background :path :rect :fill :sky}]
   [:text {:font :body :at [0.1 -0.2] :size 0.5
           :align :left :anchor :baseline :color [1 1 1 1]}
    "Slipstream"]])

(slug/with-scene [scene scene-data]          ; compiles, always frees the native atlas
  (slug/shape scene :background)            ; band/metrics map
  (slug/mesh scene))                         ; {:stride 80 :attributes {...} ...}

(require '[slipstream.glfw :as glfw])
(glfw/run! scene-data {:max-frames 60})      ; reference renderer (standard fill only)
```

## Reactive glimmer scene (verified)

```clojure
(require '[glimmer.core :as ui] '[glimmer.ratom :as r] '[slipstream.glimmer])

(def state (r/atom {:label "Reactive" :color [1 1 1 1] :path [[:rect 0 0 0.5 0.5]]}))

(defn app []
  (let [{:keys [label color path]} @state]
    [:scene {}
     [:group {}
      [:shape {:path path :fill {:type :linear :from [0 0] :to [0.5 0.5]
                                 :stops [[0 [1 0 0 1]] [1 [0 0 1 1]]]}}]
      [:text {:font "/System/Library/Fonts/Geneva.ttf"
              :text label :at [0.05 0.75 0] :size 0.15
              :align :left :anchor :baseline :color color}]]]))

(future (Thread/sleep 1000) (ui/on-gui #(swap! state assoc :label "Changed")))
(ui/run app :width 640 :height 480 :bounds [0 1 0 1] :auto-quit-ms 2500)
```

- Updates from other threads go through `ui/on-gui`.
- Changing placement/color/opacity/visibility updates layer data only; a
  path change rebuilds that one shape; text changes reuse glyphs.
- Shapes take `:effect` maps with GLSL hooks and typed `:uniforms`
  (`slipstream.glimmer-effects` lists the types). Masks: `[:group {:mask ...}]`.
- `ui/run` opts seen in the examples: `:title :width :height :bounds
  :auto-quit-ms :on-start :after-render`.

## Live development

`slipstream.example.demoscene` is the reference for a live loop: it starts
`(jolt.nrepl/start port middleware {})` before the UI loop, and the editor
redefines palette/update fns and swaps the ratom while the window runs.

```bash
jolt -m slipstream.example.demoscene /System/Library/Fonts/Geneva.ttf --port 0 --auto-quit-ms 3000
```

Note that it writes `.nrepl-port` into the cwd and removes it on clean exit.
