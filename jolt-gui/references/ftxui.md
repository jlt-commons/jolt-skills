# ftxui-jolt: Reagent-style API over C++ FTXUI

```clojure
io.github.jlt-commons/ftxui-jolt {:git/url "https://github.com/jlt-commons/ftxui-jolt"
                                  :git/tag "<latest>" :git/sha "<sha>"}
```

Fill `<latest>`/`<sha>` with `jdep jlt-commons/ftxui-jolt` (jolt skill,
deps-and-tasks.md). Independent of glimmer: FTXUI re-renders the whole tree
after every event, so there is no reconciler and no ratom library; state is
plain atoms. Namespaces: `ftxui.core` (public API), `ftxui.dom`,
`ftxui.widget`, `ftxui.render`, `ftxui.color`, `ftxui.keys`, `ftxui.ffi`.

## Native build (once per checkout)

The FFI binds a C shim with FTXUI linked in statically. Building it needs
cmake 3.14+ and a C++17 compiler; FTXUI is fetched at a pinned commit (about a
minute). `jolt native` in the ftxui-jolt checkout writes
`native/libftxui_jolt.{dylib,so}` and `native/libftxui_jolt.a`, which its
`:jolt/native` names relative to that checkout. The spec carries
`:build "native"`, so on jolt 0.8.26+ (the first release after 0.8.25, which
adds `:build` support, jolt#1571) a plain git dep builds it on first run.
On jolt 0.8.25, build it in the gitlib checkout yourself:

```bash
jolt -P    # fetch deps
cd "$(dirname "$(jolt -Spath | tr ':' '\n' | grep ftxui-jolt | head -1)")" && jolt native
```

`FTXUI_SOURCE_DIR=~/src/FTXUI jolt native` builds against a local FTXUI.

## Counter (run headless and in a pty)

```clojure
(ns myapp.core
  (:require [ftxui.core :as ui :refer [atom]]))   ; atom that redraws on change

(defn counter []
  (let [n (atom 0)]                                ; Form-2, as in reagent
    (fn []
      [:vbox {:border :rounded}
       [:text {:bold true} " Count: " @n " "]
       [:separator]
       [:hbox
        [:button {:label "-1" :on-click #(swap! n dec)}]
        [:button {:label "+1" :on-click #(swap! n inc)}]
        [:button {:label "quit" :on-click ui/exit!}]]])))

(defn -main [& _] (ui/run counter :mode :fit-component))
```

Headless, driving real FTXUI widgets (this printed `Count: 0` then `Count: 1`):

```clojure
(ui/with-screen [s counter]
  (println (ui/render-text s 30 7))   ; the next frame as text, 30x7
  (ui/send-key! s :arrow-right)       ; focus "+1"
  (ui/send-key! s :return)
  (println (ui/render-text s 30 7)))
```

Also `ui/send-char!`, `ui/send-input!` (raw terminal bytes), `ui/send-mouse!`,
`ui/refresh!`, `ui/stats`, and `(ui/render-text [:border "hi"] 6 3)` for bare
hiccup. `ui/render-ansi` includes escape codes; pin colour depth with
`(ftxui.ffi/set-color-support 3)` before asserting on them.

## API (`ftxui.core`)

- `(run comp & opts)`: run on the calling thread until `exit!` or ctrl-c.
  `:mode` `:fullscreen` (default), `:fit-component`, `:terminal-output`,
  `:fixed` (+ `:width :height`), `:fullscreen-alternate`, `:fullscreen-primary`;
  `:mouse false`; `:on-event`; `:auto-exit-ms`; `:force-ctrl-c false`;
  `:async true` returns a future (REPL use).
- `(exit!)`, `(refresh!)` (after changing a plain atom outside a handler),
  `(atom x)`, `(post-key! :return)`, `(post-char! "abc")`, `(reload!)`.
- A throw in a handler or render stops the loop and `run` rethrows it.

## Hiccup

Elements (rebuilt every frame): `:text :vtext :paragraph :wrapped :separator
:gauge :spinner :filler :empty :hbox :vbox :dbox :stack :hflow :vflow
:flexbox :gridbox :table :border :window :canvas`. A `:canvas` takes `:draw`
ops: `[:line x1 y1 x2 y2 {:color :red}]`, `[:circle x y r {:filled true}]`,
`[:ellipse …]`, `[:point …]`, `[:text x y s]` (pixel coordinates, braille by
default).

Widgets (stateful, created once per position or `:key`): `:button`, `:input`
(`:value :placeholder :password :multiline`, `:on-change`, `:on-enter`,
`:on-key`), `:checkbox`, `:menu`, `:toggle`, `:radiobox`, `:dropdown`,
`:slider`, `:collapsible`, `:modal` (main + dialog children, `:show`),
`:maybe`, `:resizable-split`, `:hoverable`, `:scroll`, `:floating-window`,
`:catch-event`. Value props are controlled: if `:on-change` doesn't write the
value back, the next frame restores the prop.

Decorators on any node: `:bold :dim :italic :inverted :underlined :blink
:strikethrough`, `:color`/`:bg` (`:red`, 0–255, `[:rgb r g b]`, `"#f80"`,
`[:gradient :red :blue]`), `:border`, `:width`/`:height` (`n`, `[:<= n]`),
`:flex`, `:frame`, `:align`, `:focus`, `:hyperlink`.

Focus follows layout: a `:vbox`/`:hbox` with several focusable children
becomes an FTXUI container (arrows and Tab move through it). Keyed rows:
`(for [t @tasks] ^{:key (:id t)} [task-row t])`.

## Shipping

`jolt build -m myapp.core -o target/myapp` links `libftxui_jolt.a` and libc++
into the binary (the `:static` entry in its `:jolt/native`); the result needs
no FTXUI on the target. Verified on macOS.
