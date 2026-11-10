# OpenGL in a jolt UI: glimmer-gl and glitter-gl

Both put a `GtkGLArea` (`:gl-area`) in the hiccup tree and ship a thi.ng/geom
port: unboxed `Vec3`, column-major `Matrix44`, meshes as data, primitives, and
shaders as data. GTK4 plus the system OpenGL (macOS framework, Linux
`libGL.so.1`); both natives come in through the deps.

```clojure
;; glimmer (reactive) — brings glimmer-gtk
jolt-lang/glimmer-gl {:git/url "https://github.com/jolt-lang/glimmer-gl"
                      :git/tag "<latest>" :git/sha "<sha>"}
;; glitter (single atom) — brings glitter; untagged, use the HEAD sha
io.github.jlt-commons/glitter-gl {:git/url "https://github.com/jlt-commons/glitter-gl"
                                  :git/sha "<sha>"}
```

Fill `<latest>`/`<sha>` with `jdep OWNER/REPO` (jolt skill, deps-and-tasks.md).

## Geometry (run)

```clojure
(require '[glimmer-gl.primitives :as p] '[glimmer-gl.mesh :as mesh])

(def scene
  (mesh/merge-meshes
    (p/cuboid 1.0)
    (-> (p/sphere 1.0 24 16) (mesh/subdivide) (mesh/translate 2 0 0))))

(select-keys (mesh/->floats scene {:shading :smooth}) [:count :stride])
;; => {:count 8676, :stride 6}   :data is x y z nx ny nz per vertex
```

`glimmer-gl.primitives`: `cuboid tetrahedron sphere plane quad`.
`glimmer-gl.mesh`: `transform translate scale merge-meshes subdivide
triangles face-normal vertex-normals ->floats`. `glimmer-gl.matrix`: `mul
invert transpose ident translation scaling perspective rotate-x/y/z ->vec`.
Upload with `glimmer-gl.gl/write-floats` (returns a pointer; `ffi/free` it).

## Shaders as data (run)

Bodies are data statements, not GLSL strings; declarations are generated:

```clojure
(require '[glimmer-gl.shader :as sh])

(def spec
  {:version  "330 core"
   :uniforms {:u_mvp :mat4 :u_time [:float 0.0]}     ; type or [type default]
   :attribs  {:a_pos [:vec3 0] :a_normal [:vec3 1]}  ; [type location]
   :varying  {:v_normal :vec3}
   :fs-out   {:frag :vec4}
   :vs-main  [[:set :v_normal :a_normal]
              [:set :gl_Position [:* :u_mvp [:vec4 :a_pos 1.0]]]]
   :fs-main  [[:let :n :vec3 [:normalize :v_normal]]
              [:set :frag [:vec4 [:* [:+ :n 1.0] 0.5] 1.0]]]})

(:vs-src (sh/sources spec))   ; pure, no GL context
;; "#version 330 core\nuniform mat4 u_mvp;\n…void main() {\n  v_normal = a_normal;\n  gl_Position = u_mvp * vec4(a_pos, 1.0);\n}"
```

Statements: `[:let name type expr]`, `[:set name expr]`, `[:if c [then…]
[else…]]`. Expressions: keywords (names), numbers (floats), `[:. x :xyz]`
swizzle, `[:neg x]`, infix `:+ :- :* :/ :< :> :== :and :or …`, anything else is
a call (`[:normalize v]`, `[:vec4 …]`). Optional `:prelude` (raw GLSL string,
e.g. helper fns) and `:precision`. Compose modules with
`(sh/merge-specs base lighting fog)` (maps merge, `:vs-main`/`:fs-main`
concatenate). With a current context: `(sh/program spec)` compiles and
locates uniforms/attribs, `(sh/set-uniforms! prog {:u_mvp m :u_time t})`,
`(sh/attrib-loc prog :a_pos)`. `sh/adapt-spec` retargets to GLSL ES.

`sources` rejects keys it does not know: raw GLSL `:vs`/`:fs` strings are an
error. Write shader bodies as `:vs-main`/`:fs-main` statement data.

## A GL pane in glimmer

```clojure
(require '[glimmer.core :as ui] '[glimmer-gl.gtk :as glx])  ; registers :gl-area, :scale

(defn app []
  [:vbox
   [:scale {:min 0 :max 1 :step 0.01 :value @speed :on-value #(reset! speed %)}]
   [:gl-area {:version [3 2] :depth-buffer true :hexpand true :vexpand true
              :on-realize on-realize        ; (fn [area]) build GL objects
              :on-render  on-render         ; (fn [area]) draw
              :on-resize  on-resize         ; (fn [area w h])
              :on-tick    on-tick}]])       ; (fn [area]) per frame, queues a redraw

(ui/run app :title "gl" :width 900 :height 640)
```

In `on-realize` call `(glx/make-current area)` first. The full working app
(control panel + rotating lit mesh with a composed plasma shader) is
https://github.com/jolt-lang/examples/tree/main/glimmer-gl-app (`gl_demo/core.clj`,
`gl_demo/scene.clj`); copied with git deps it ran here and printed
"GL ready".

`glimmer-gl.offscreen/ensure-current!` gives a display-bound context with no
window, for render-to-texture work and GL tests (returns `{:error …}` when no
display); framebuffer 0 is incomplete there, so draw into an FBO.

## glitter-gl

Same geometry/shader namespaces under `glitter-gl.*` (plus `vec2`,
`quaternion`, `aabb`, `bezier`, `intersect`, `polyhedra`, `scene`), and
`glitter-gl.gtk` registers `:gl-area` into glitter's widget registry.
`glitter-gl.app/reactive-area` builds the `:gl-area` prop map bound to the
glitter state atom (scene graph, shadow mapping). Examples in the repo:
`jolt -M:plasma|ripple|orbit|knot|gears|textured|picking`; `jolt -M:check` is a
headless sanity check (ran: "check: ok").
