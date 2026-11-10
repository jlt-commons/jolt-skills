# raygui (immediate-mode GUI)

Repo: `jlt-commons/raygui-jlt` (untagged). It is an
**example suite**, not a packaged library: 24 example programs, a bindings
namespace `net.b12n.raygui-jlt.raygui` (59 of raygui's 61 functions plus a
keyword API), its own small raylib layer, and `vendor/raygui.h`. raygui is
header-only, so there is no system library: you compile one.

Running its examples: `jolt lib:build` (builds `lib/libraygui.dylib`), then
`RAYGUI_APP_AUTO_QUIT_MS=1500 jolt -M:basic-controls`. The shot path in
`RAYGUI_APP_SHOT` must be relative.

## Using it in a raylib-jlt game (verified)

A git dependency on raygui-jlt does not work well: its `:jolt/native` points at
`lib/libraygui.dylib` inside the checkout, which nothing builds. Vendor it:

1. Copy `vendor/raygui.h` and `vendor/raygui_impl.c` to `native/`.
2. Copy `src/net/b12n/raygui_jlt/raygui.clj` to `src/mygame/raygui.clj`, rename
   the ns, and change its raylib require to `[net.b12n.raylib.all :as rl]`
   (it only uses `rl/rgba`, `rl/get-color`, `rl/DARKGRAY`, all in raylib-jlt).
   Keep its EPL/zlib notices.
3. Declare and build the dylib. Link it **dynamically against libraylib**: a
   static raylib inside it would read input from a second, empty copy of
   raylib's globals and every control would be dead.

```clojure
;; deps.edn additions
:jolt/native [{:name "raygui"
               :darwin ["native/libraygui.dylib"]
               :linux  ["native/libraygui.so"]}]
:tasks {:requires ([babashka.fs :as fs])
        :init (def mac? (some? (re-find #"^Mac" (System/getProperty "os.name"))))
        native {:doc "build native/libraygui from the vendored raygui.h"
                :task (let [lib (str "native/libraygui." (if mac? "dylib" "so"))]
                        (when (seq (fs/modified-since lib ["native/raygui_impl.c" "native/raygui.h"]))
                          (apply shell
                                 (if mac?
                                   ["cc" "-O2" "-dynamiclib" "-fPIC" "-DBUILD_LIBTYPE_SHARED"
                                    "-Inative" "-I/opt/homebrew/include" "-L/opt/homebrew/lib"
                                    "native/raygui_impl.c" "-lraylib"
                                    "-framework" "CoreVideo" "-framework" "IOKit"
                                    "-framework" "Cocoa" "-framework" "OpenGL" "-o" lib]
                                   ;; GNU ld: -l flags after the source file
                                   ["cc" "-O2" "-shared" "-fPIC" "-DBUILD_LIBTYPE_SHARED" "-Inative"
                                    "-o" lib "native/raygui_impl.c"
                                    "-lraylib" "-lGL" "-lm" "-lpthread" "-ldl" "-lrt" "-lX11"]))))}}
```

`jolt native` once (jolt warns that the lib is missing until then), then run.
Adding `:build "lib:build"` to raygui-jlt's own `:jolt/native` spec is a
pending PR. Once it lands, on the jolt release after 0.8.25 that adds `:build` support (0.8.26+, jolt#1571) a plain git dep compiles
`lib/libraygui` on first run; until then (and on jolt 0.8.25) vendor it as
above, or run `jolt lib:build` once inside the gitlib checkout.

## The API

raygui keeps no widget state. Your state lives in **cells** (native memory the
control writes into); controls return what happened this frame.

```clojure
(ns guiapp.main
  (:require [net.b12n.raylib.all :as rl]
            [guiapp.raygui :as rg]))

(defn -main [& _]
  (rl/window! {:width 420 :height 200 :title "raygui"})
  (rl/set-target-fps 60)
  (let [clicks (rg/cell :int 0)
        volume (rg/cell :float 0.5)]
    (while (not (rl/window-should-close?))
      (rl/begin-drawing)
      (rl/clear-background (rg/style-color rg/DEFAULT rg/BACKGROUND-COLOR))
      (when (rg/button! :x 20 :y 20 :w 160 :h 32 :text "Click me")   ; true on the click frame
        (rg/reset-cell! clicks (inc (rg/value clicks))))
      (rg/label! :x 200 :y 26 :w 200 :h 24 :text (str "clicks: " (rg/value clicks)))
      (rg/slider! :x 80 :y 80 :w 200 :h 20 :left "volume"
                  :right (format "%.2f" (rg/value volume))
                  :cell volume :min 0.0 :max 1.0)
      (rl/end-drawing))
    (rg/free-cell! clicks)
    (rg/free-cell! volume))
  (rl/close-window))
```

- Cells: `(rg/cell type init)` with type `:float :int :bool :color :vector2
  :vector3 :rect`; `(rg/text-cell size init)` for text boxes (size includes
  the NUL). `rg/value`, `rg/reset-cell!`, `rg/free-cell!`. Allocate once,
  outside the loop.
- Controls (keyword args `:x :y :w :h` plus their own): `label! button!
  label-button! check-box! toggle! toggle-group! toggle-slider! text-box!
  text-input-box! spinner! value-box! slider! slider-bar! progress-bar!
  dropdown-box! combo-box! list-view! list-view-ex! tab-bar! panel! group-box!
  scroll-panel! window-box! message-box! color-picker! color-panel!
  status-bar! line! dummy-rec!`. Read the docstring of each before use; edit
  mode toggles (`text-box!`, `dropdown-box!`, `value-box!`) are returned, and
  you flip your own flag. raygui has no z-order: draw an open dropdown last.
- State/style: `rg/gui-set-state rg/STATE-DISABLED` / `rg/STATE-NORMAL`,
  `rg/set-alpha!`, `rg/gui-lock`/`gui-unlock`, `rg/tooltip!`,
  `rg/load-style!`, `rg/apply-style!` with `rg/styles` (paths are relative to
  raygui-jlt's `vendor/styles`; copy the `.rgs` files you want).
- Raw bindings are `rg/gui-*` (`gui-button`, `gui-slider`, ...). Bounds go
  through one module scratch buffer, so controls do not allocate per frame.
