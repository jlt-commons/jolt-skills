# glimmer desktop backends: GTK4, AppKit, Qt Quick, BUI

All four are `glimmer.backend` implementations: require the `.core` ns, then
call `glimmer.core/run`. Components and state are in [glimmer.md](glimmer.md).
Fill `<latest>`/`<sha>` with `jdep OWNER/REPO` (jolt skill, deps-and-tasks.md).

## glimmer-gtk (GTK4)

```clojure
jolt-lang/glimmer-gtk {:git/url "https://github.com/jolt-lang/glimmer-gtk"
                       :git/tag "<latest>" :git/sha "<sha>"}
```

- System: macOS `brew install gtk4`; Debian/Ubuntu `libgtk-4-1` to run,
  `libgtk-4-dev` for headers. Its `:jolt/native` loads glib-2.0, gobject-2.0,
  gio-2.0 and gtk-4 (Homebrew paths first on macOS) and is inherited.
- Run on a Mac: `jolt -m myapp.core` works from a terminal; the loop runs on
  the process main thread.

Vocabulary (also what glimmer-appkit accepts):

| | |
|---|---|
| containers | `:window` (one child), `:box` (`:orientation :horizontal/:vertical`), `:hbox`, `:vbox`, `:frame` (one child, `:label`), `:scrolled` (one child, `:scroll-top`) |
| leaves | `:button` (`:label :tooltip :sensitive`), `:label` (`:label`/`:text`, `:markup`, `:xalign`, `:wrap`, `:max-width-chars`, `:width-chars`, `:lines`, `:ellipsize`), `:entry` (`:text :placeholder :sensitive`), `:checkbutton` (`:label :active`), `:separator` |
| every widget | `:margin` / `:margin-start/-end/-top/-bottom`, `:halign`/`:valign` (`:fill :start :end :center …`), `:hexpand`/`:vexpand`, `:width-request`/`:height-request` |
| events | `:on-click` (no args), `:on-change` (entry text), `:on-activate` (Enter), `:on-toggled` (no args) |

- `:markup` takes Pango markup or hiccup data validated against Pango's
  vocabulary: `[:label {:markup [:span {:foreground "#8e939d"} "empty"]}]`.
  HTML tags throw. Attribute names use underscores (`:font_family`).
- Enum props are keyword nicks resolved through the GObject registry at
  runtime (`:halign :start`); an integer also works.
- Setting `:text`/`:active` from a render suppresses the signal GTK would emit,
  so a re-render cannot feed back into its handler.

Extend with your own tags:

```clojure
(require '[glimmer-gtk.widget :as w])
(w/register-widget! :my-thing
  {:ctor (fn [props] ...) :apply (fn [widget props] ...)
   :container :none})                    ; or :box :window :frame :scrolled
(w/register-signal! :on-input "value-changed" (fn [widget] ...)) ; value fn optional
```

`glimmer-gl.gtk` is the worked example (`:gl-area`, `:scale`); see [gl.md](gl.md).

## glimmer-appkit (macOS)

```clojure
jolt-lang/glimmer-appkit {:git/url "https://github.com/jolt-lang/glimmer-appkit"
                          :git/tag "<latest>" :git/sha "<sha>"}
```

- Nothing to install beyond the Xcode command-line tools. AppKit and
  CoreFoundation are loaded at require time, guarded to macOS, with no
  `:jolt/native` entry, so a project's headless tests still run on Linux CI.
- Same tags, props, events and Pango `:markup` as glimmer-gtk (rendered as
  `NSAttributedString`); `:halign` takes `:fill :start :end :center`.
  `glimmer-appkit.widget/register-widget!` and `register-signal!` have the
  glimmer-gtk shape.
- Requires jolt 0.8.0+ (`:jolt/min-version`).

The counter in SKILL.md runs unchanged with `[glimmer-appkit.core]`, as a
plain `jolt -m` run, a `jolt build` binary and an `.app` bundle.

## glimmer-qt (Qt Quick)

```clojure
jolt-lang/glimmer-qt {:git/url "https://github.com/jolt-lang/glimmer-qt"
                      :git/tag "<latest>" :git/sha "<sha>"}
```

- Needs Python 3, a C++17 compiler, `make`, jolt 0.8.22+, and Qt 6 with Quick,
  Quick Controls and Multimedia (`brew install qt` on macOS). `qmake6`/`qmake`
  on `PATH`, Homebrew's, or `GLIMMER_QT_QMAKE`.
- The C++ bridge is built from source (`./build-native`, wrapped by its
  `native` task) into `build/libglimmer_qt.dylib|.so`. Its spec carries
  `:build "native"`, so on jolt 0.8.26+ (the first release after 0.8.25, which
  adds `:build` support, jolt#1571) a plain git dep builds the bridge in the
  gitlib checkout on first run. On jolt 0.8.25, run `jolt native` in the
  gitlib checkout yourself first (`cd "$(dirname "$(jolt -Spath | tr ':' '\n' | grep glimmer-qt | head -1)")" && jolt native`).

```bash
# deps.edn: jolt-lang/glimmer-qt {:git/url "https://github.com/jolt-lang/glimmer-qt" :git/tag "<latest>" :git/sha "<sha>"}
export QT_PLUGIN_PATH=$(qmake -query QT_INSTALL_PLUGINS) QML_IMPORT_PATH=$(qmake -query QT_INSTALL_QML)
jolt -m myapp.core
```

  The repo's own launchers set those two variables from the SDK that built the
  bridge; with Homebrew Qt a run also worked without them.
- Its vocabulary is Qt Quick, not GTK's: tags include `:vbox :hbox :label
  :button :entry :text-area :slider :progress :busy-indicator :image :scroll
  :toolbar :action-button :dialog :file-chooser :overlay :flow :rectangle
  :spacer :shortcut :pointer-area :video-player :window`. Props differ too
  (`:padding`, `:font-size`, `:id`, `:accessible-name`, `:mode "good"/"bad"`).
  Read `CONTROLS.md`, `KEYBOARD.md`, `VALUES.md`, `LIFECYCLE.md`, `TRAY.md`,
  `SERVICES.md`, `MEDIA.md` in the repo.

Counter, run on Qt 6.11 / macOS:

```clojure
(ns myapp.core
  (:require [glimmer.ratom :refer [atom]]
            [glimmer.core :as ui]
            [glimmer-qt.core]))

(defn counter []
  (let [count (atom 0)]
    (fn []
      [:vbox {:spacing 12 :padding 24 :hexpand true :vexpand true}
       [:label {:label (str "Count: " @count) :font-size 24}]
       [:hbox {:spacing 8}
        [:button {:label "- 1" :on-click #(swap! count dec)}]
        [:button {:label "+ 1" :on-click #(swap! count inc)}]]])))

(defn -main [& _]
  (ui/run counter :title "counter" :width 360 :height 180))
```

Beyond `ui/run`: `glimmer-qt.core/run-application!` runs a Qt session that
can open several windows (`open-window!`, `close-window!`, `reload-window!`),
timers (`later!`, `every!`, `cancel!`), tray icons (`glimmer-qt.tray`) and
clipboard/desktop services (`glimmer-qt.services`). Custom QML tags:
`glimmer-qt.widget/register!` with a QML `:source` and a typed `:props`
schema (`EXTENSIONS.md`). Before shipping a binary read `THIRD_PARTY.md`
(Qt/FFmpeg licensing obligations).

## glimmer-bui (Blender UI kit)

```clojure
io.github.jlt-commons/glimmer-bui {:git/url "https://github.com/jlt-commons/glimmer-bui"
                                   :git/tag "<latest>" :git/sha "<sha>"}
```

Not run here (needs BUI built from source). BUI is GPL-2.0-or-later, so a
program linking it is GPL too. Build `libbui.dylib` per the repo README
(clone ppmpreetham/BUI, cmake, link the three static archives into one
dylib). The repo's `:jolt/native` candidates are a bare `libbui.dylib` plus two
absolute paths under the author's home directory, so put your build where
dlopen finds the bare name (for example `/usr/local/lib`).

Its vocabulary is its own: `:vbox/:column :hbox/:row :frame :panel :box :tabs
:scroll`, leaves `:button :toggle :checkbox :radio :label :separator
:progress :entry :search :number :slider :dropdown :enum :swatch :meter
:textarea :image :canvas`; text is `:text` (not `:label`) on buttons; events
`:on-click :on-change :on-submit :on-wheel …`. README example:

```clojure
(defonce count* (atom 0))   ; glimmer.ratom/atom
(defn counter []
  [:vbox {:padding 12}
   [:slider {:label "count" :min -100 :max 100 :value @count*}]
   [:hbox {}
    [:button {:text "- 1" :on-click #(swap! count* dec)}]
    [:button {:text "+ 1" :on-click #(swap! count* inc)}]]])
```
