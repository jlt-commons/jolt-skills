# glimmer-tui: terminal backend over ncursesw

```clojure
jolt-lang/glimmer-tui {:git/url "https://github.com/jolt-lang/glimmer-tui"
                       :git/tag "<latest>" :git/sha "<sha>"}
```

Fill `<latest>`/`<sha>` with `jdep jolt-lang/glimmer-tui` (jolt skill,
deps-and-tasks.md). Nothing to install on macOS or a desktop Linux: it binds
the system ncurses (6.0 API only, which is what macOS ships). Minimal
containers may need `libncursesw6`. jolt 0.8.0+.

Same components as any glimmer app ([glimmer.md](glimmer.md)); sizes are
character cells. For a full-screen editor-style app compare with ftxui-jolt
([ftxui.md](ftxui.md)): glimmer-tui needs no C++ build and shares components
with the GUI backends; ftxui has more ready-made widgets.

## Counter (run in a pty and headless)

```clojure
(ns myapp.core
  (:require [glimmer.ratom :refer [atom]]
            [glimmer.core :as ui]
            [glimmer-tui.core :as tui]))

(defn counter []
  (let [count (atom 0)]
    (fn []
      [:vbox {:spacing 1 :margin 1}
       [:label {:label (str "Count: " @count) :bold true}]
       [:hbox {:spacing 2}
        [:button {:label "- 1" :on-click #(swap! count dec)}]
        [:button {:label "+ 1" :on-click #(swap! count inc)}]
        [:button {:label "quit" :on-click tui/quit!}]]])))

(defn -main [& _] (ui/run counter))
```

`ui/run` options here: `:tick-ms`, `:quit-keys` (default ctrl-c/ctrl-q, e.g.
`#{"ctrl+c" "q"}`), `:on-error (fn [throwable phase])` (keeps the loop alive;
phase `:key :timer :render :paint :mouse`), `:on-mouse`, `:paste-timeout-ms`,
`:auto-quit-ms`. It raises when there is no usable terminal
(`tui/usable-terminal?`).

## Widgets

| tag | notes |
|---|---|
| `:window` `:box` `:hbox` `:vbox` | layout; `:orientation` on `:box` |
| `:frame` | one child; `:label`, `:border` (`:rounded :thick :double :ascii …`), `:border-color` |
| `:scroll` | viewport; `:orientation :vertical/:horizontal/:both`, `:scrollbar` |
| `:overlay` | floats over the screen; `:anchor :center`, `:modal`, `:on-close` (Esc) |
| `:label` `:button` `:entry` `:checkbutton` `:separator` | `:entry`: `:text :placeholder :echo` (`:normal :password :none`) `:char-limit :on-paste` |
| `:listbox` | `:items :selected :descriptions`; `:on-select (fn [i item])`, `:on-activate` |
| `:table` | `:columns [{:title "Name" :key :name :width 12 :align :end}]`, `:rows`, `:selected`, `:row-style` |
| `:progress` `:spinner` `:paginator` `:help` | `:help` renders the focused widget's key bindings |

Every widget: `:margin`/`:padding` (n, `[v h]`, `[t r b l]`), `:halign`,
`:valign`, `:hexpand`, `:vexpand`, `:width-request`, `:height-request`,
`:color`/`:bg` (`:red`, 0–255, `"#ff6432"`, `[r g b]`, folded down to what the
terminal supports), `:bold :dim :underline :reverse :blink`, `:sensitive`,
`:autofocus true` (start focus here, so single-key bindings work before Tab).

Events: `:on-click`, `:on-change` (text), `:on-activate`, `:on-toggled`,
`:on-select`, `:on-scroll`, `:on-close`, and `:on-key` on any container
(receives the event, return truthy to consume). Keys go to the focused widget,
then its ancestors:

```clojure
(require '[glimmer-tui.keys :as k])
[:vbox {:on-key (fn [e] (when (k/match? e "d") (open-dialog!) true))} ...]
[:listbox {:items rows :keys {:down ["down" "n"]}}]   ; rebind per widget
```

Timers run on the loop thread (the only one allowed to touch widgets):
`(tui/every! 80 #(swap! tick inc))`, `tui/after!`, `tui/cancel!`.

Custom widgets: `glimmer-tui.widget/register-widget!` (each built-in under
`glimmer-tui.widgets.*` is one such spec).

## Testing without a terminal (run)

`glimmer-tui.screen/buffer-screen` is an in-memory grid; `attach!` points a
session at it, so a whole app can be mounted, typed into and asserted on:

```clojure
(ns myapp.core-test
  (:require [clojure.test :refer [deftest is]]
            [glimmer.core :as ui]
            [glimmer-tui.core :as tui]
            [glimmer-tui.widget :as w]
            [glimmer-tui.screen :as scr]
            [myapp.core :refer [counter]]))

(deftest clicking-plus
  (let [root (w/node :window {})
        screen (scr/buffer-screen 40 8)]
    (tui/attach! root screen)
    (ui/mount root :window [counter])
    (tui/frame!)
    (tui/press! 9)    ; Tab: focus "- 1" -> "+ 1"
    (tui/press! 10)   ; Enter
    (tui/frame!)
    (is (some #(re-find #"Count: 1" %) (scr/lines screen)))))
```

`scr/lines` returns one right-trimmed string per row; `scr/text-at`,
`scr/style-at`, `tui/click!`, `tui/scroll!`, `tui/focus!` are there for finer
assertions.

## Running for real

- In a terminal: `jolt -m myapp.core`.
- From a script or CI: it needs a pty. `script -q /dev/null jolt ...` fails
  when stdin is not a tty; this works:
  `python3 -c 'import pty,sys; pty.spawn(sys.argv[1:])' jolt -m myapp.core`
  (pass `:auto-quit-ms` so it ends).
- From nREPL: `(tui/run-async counter)` returns `{:quit! :result}`; the UI
  takes over the server's terminal, so use `tap>` instead of `println`.
- `jolt build -m myapp.core -o target/myapp` gives a binary that uses the
  system ncurses (run in a pty here).
