---
name: jolt-gui
description: Build desktop, terminal and mobile user interfaces on Jolt (Clojure on Chez Scheme, no JVM). Use when the user wants a GUI app, window, widget tree, TUI, terminal dashboard, iPhone/Android screen, OpenGL pane or macOS .app in a jolt project; or mentions glimmer (glimmer.ratom, glimmer.core, reagent-style ratoms/cursors/reactions), its backends glimmer-gtk, glimmer-appkit, glimmer-qt, glimmer-tui, glimmer-uikit, glimmer-android, glimmer-gl, glimmer-bui; glitter (Replicant-style, glitter.core/set-dispatch!, glitter.gtk/mount!), glitter-core, glitter-uikit, glitter-gl; nexus-jolt (nexus.registry actions/effects/placeholders); or ftxui-jolt (ftxui.core).
---

# Jolt GUIs

Two UI families run on jolt. Both take hiccup and drive real native widgets
through `jolt.ffi`; neither involves a browser or a JVM.

- **glimmer** (jolt-lang): the Reagent model. Reactive atoms, cursors and
  reactions; components are fns (Form-1) or fns returning render fns (Form-2,
  local state); handlers are closures. One portable core, one backend per
  toolkit: GTK4, AppKit, Qt Quick, ncurses TUI, UIKit (iPhone), Android, BUI,
  plus OpenGL panes.
- **glitter** (jlt-commons): the Replicant model. One plain `atom` of app
  state, a pure `state -> hiccup` view, full re-render on every change, and
  handlers that are *data* (`:on {:click [[:counter/add 1]]}`) routed through
  one dispatch fn, usually nexus-jolt. GTK4 and AppKit.
- **ftxui-jolt** (jlt-commons): a Reagent-shaped API over the C++ FTXUI
  terminal library. Its own atoms, not glimmer's.

Read the `jolt` skill first for project layout, `:jolt/native`, tasks, `jolt
build` and the REPL. Browser UIs (glimmer ratoms over Datastar SSE) are the
`jolt-web` skill.

## Which to pick

| You want | Use | Reference |
|---|---|---|
| Component-local state, closures as handlers, Reagent habits | glimmer + a backend | [glimmer.md](references/glimmer.md) |
| One state atom, pure view, actions as data, easy to test and log | glitter + nexus-jolt | [glitter.md](references/glitter.md), [nexus.md](references/nexus.md) |
| Linux/macOS/Windows desktop with GTK4 | glimmer-gtk, or glitter (43 tags, the richest widget set) | [desktop.md](references/desktop.md) |
| Native macOS, nothing to install | glimmer-appkit, or glitter-uikit (AppKit despite the name) | [desktop.md](references/desktop.md) |
| Qt Quick look, tray, media, multi-window | glimmer-qt (builds a C++ bridge) | [desktop.md](references/desktop.md) |
| Terminal UI, no build step, testable as text | glimmer-tui (ncursesw) | [tui.md](references/tui.md) |
| Terminal UI with FTXUI widgets (menus, splits, canvas, floating windows) | ftxui-jolt (cmake builds a C++ shim) | [ftxui.md](references/ftxui.md) |
| iPhone / Android | glimmer-uikit / glimmer-android (cross-compiled; target packs, SDKs) | [mobile.md](references/mobile.md) |
| OpenGL pane, meshes, shaders as data | glimmer-gl (glimmer) / glitter-gl (glitter), both GTK4 | [gl.md](references/gl.md) |
| Blender-style widgets | glimmer-bui (GPL BUI, built from source) | [desktop.md](references/desktop.md) |

Same hiccup across glimmer backends, mostly: `:vbox :hbox :label :button
:checkbutton` with `:on-click :on-toggled` work on GTK, AppKit, TUI, UIKit and
Android; `:entry`/`:on-change` on all but the two phone backends. Units differ:
`:spacing`/`:margin` are pixels on GTK/AppKit and character cells in the
terminal. Only the backend `require` names the toolkit, so state and
components can live in a toolkit-free ns.

## deps.edn

Fill each `<latest>`/`<sha>` with `jdep OWNER/REPO` (newest tag, or HEAD for
an untagged repo); see "Depending on a library: use the latest tag" in the
`jolt` skill's references/deps-and-tasks.md. Never copy a sha from docs.

Use the coordinate names below. They are what the libraries themselves use for
their transitive deps; `jolt-lang/glimmer` and `io.github.jolt-lang/glimmer`
would be two libs, both on the classpath.

```clojure
{:jolt/min-version "0.8.25"
 :paths ["src"]
 :deps {;; each backend brings glimmer transitively; a top-level dep wins,
        ;; so list it here to get the newest
        jolt-lang/glimmer {:git/url "https://github.com/jolt-lang/glimmer"
                           :git/tag "<latest>" :git/sha "<sha>"}
        ;; then ONE (or more) backend:
        jolt-lang/glimmer-gtk    {:git/url "https://github.com/jolt-lang/glimmer-gtk"
                                  :git/tag "<latest>" :git/sha "<sha>"}
        ;; jolt-lang/glimmer-appkit {:git/url "https://github.com/jolt-lang/glimmer-appkit"
        ;;                           :git/tag "<latest>" :git/sha "<sha>"}
        ;; jolt-lang/glimmer-tui    {:git/url "https://github.com/jolt-lang/glimmer-tui"
        ;;                           :git/tag "<latest>" :git/sha "<sha>"}
        }}
```

glitter family (untagged; `jdep` gives the HEAD sha):

```clojure
io.github.jlt-commons/glitter        {:git/url "https://github.com/jlt-commons/glitter"
                                      :git/sha "<sha>"} ; GTK4
io.github.jlt-commons/glitter-uikit  {:git/url "https://github.com/jlt-commons/glitter-uikit"
                                      :git/sha "<sha>"} ; AppKit
;; both bring glitter-core and nexus-jolt; don't add those unless you need a newer one
```

Natives come with the dependency: a project inherits each dep's
`:jolt/native`. Nothing to declare yourself.

| Backend | macOS | Linux |
|---|---|---|
| glimmer-gtk, glitter, *-gl | `brew install gtk4` | `apt install libgtk-4-1` (`libgtk-4-dev` to build) |
| glimmer-appkit, glitter-uikit | nothing (Xcode CLT for clang) | n/a |
| glimmer-tui | nothing (system ncurses) | `libncursesw6` on minimal images |
| glimmer-qt | Qt 6 (Quick, Controls, Multimedia), Python 3, C++17, make; first run builds it (`:build`) | same |
| ftxui-jolt | cmake 3.14+, C++17; first run builds it (`:build`) | same |
| glimmer-uikit / -android | Xcode + jolt target pack / Android SDK+NDK + pack | n/a |

## A complete app (glimmer; run on GTK4, AppKit and the TUI)

`src/myapp/core.clj`:

```clojure
(ns myapp.core
  (:require [glimmer.ratom :refer [atom]]
            [glimmer.core :as ui]
            [glimmer-gtk.core]))          ; or glimmer-appkit.core

(defn counter []
  (let [count (atom 0)]                   ; Form-2: runs once, state persists
    (fn []                                ; re-runs when @count changes
      [:vbox {:spacing 12 :margin 12}
       [:label {:label (str "Count: " @count)}]
       [:hbox {:spacing 8}
        [:button {:label "- 1" :on-click #(swap! count dec)}]
        [:button {:label "+ 1" :on-click #(swap! count inc)}]
        [:button {:label "reset" :on-click #(reset! count 0)}]]])))

(defn -main [& args]
  (apply ui/run counter :title "counter" :width 320 :height 160
         ;; `jolt -m myapp.core 2000` closes after 2s: a smoke test
         (when-let [ms (first args)] [:auto-quit-ms (parse-long ms)])))
```

`jolt -m myapp.core` opens the window and blocks until it closes. For the
terminal, require `glimmer-tui.core` instead and use cell units
(`{:spacing 1 :margin 1}`, `{:spacing 2}`); a 12-cell margin leaves an 80x24
screen blank. Tab moves focus, Enter presses, ctrl-c quits;
`glimmer-tui.core/quit!` as an `:on-click` makes a quit button.

The glitter version of the same app is in [glitter.md](references/glitter.md).

## Core API in one screen

glimmer (`glimmer.ratom`, `glimmer.core`):

```clojure
(r/atom x)  (r/cursor src [:path])  (r/reaction (expr @a @b))   ; all read with @
(r/capture f)                       ; => [result cells-read]
(ui/run root-fn & {:keys [title width height app-id auto-quit-ms]})
(ui/reload!)  (ui/reload! new-root) ; re-mount in the same window (REPL)
(ui/on-gui thunk)                   ; run on the UI thread
(ui/mount container tag [comp]) (ui/unmount! root container tag)
```

Requiring `glimmer.ratom` rebinds `clojure.core/deref`, `reset!` and `swap!`
so `@` tracks reactive cells; plain atoms behave as before. `glimmer.table`
gives keyed tables with incremental views and aggregates.

glitter (`glitter.core`, `glitter.gtk` / `glitter-uikit.appkit`):

```clojure
(core/set-dispatch! (fn [event actions] ...))       ; once, before the first render
(app/run (fn [window] (gtk/mount! window view state-atom)) :title "x" :auto-quit-ms 2000)
```

ftxui (`ftxui.core`): `(ui/atom x)`, `(ui/run comp :mode :fit-component)`,
`(ui/exit!)`, `(ui/refresh!)`, `(ui/with-screen [s comp] (ui/render-text s w h))`.

## Testing without a display

- glimmer core: pure ratom/reaction tests need no backend.
- glimmer-tui: `glimmer-tui.screen/buffer-screen` + `glimmer-tui.core/attach!`
  mounts a real app into a text grid; press keys, assert on `scr/lines`
  ([tui.md](references/tui.md)).
- glitter: the view is a pure fn; `glitter.test-renderer/renderer` records every
  widget operation; dispatch actions straight into `nexus.registry/dispatch`.
- ftxui: `ui/with-screen` drives real FTXUI widgets headless.
- Window backends: `ui/run` (GTK, AppKit, Qt, TUI) and glitter's `app/run`
  take `:auto-quit-ms` (ftxui: `:auto-exit-ms`), so a smoke run is
  `jolt -m myapp.core 2000` plus a check of the exit status. A TUI needs a pty
  (`python3 -c 'import pty; pty.spawn(...)'`); `script -q /dev/null cmd` fails
  when stdin is not a terminal.

## Live development

Under `jolt nrepl-server`, GTK, AppKit and BUI hop their loop onto the
process main thread and `ui/run` returns at once, so the session stays usable.
Keep state in top-level `defonce` cells; after redefining components call
`(glimmer.core/reload!)`. Component-local `let` state resets on reload. A
`swap!` from the REPL thread is marshalled onto the UI thread for you; for
direct widget calls use `ui/on-gui`. glimmer-tui: `(tui/run-async app)`;
ftxui: `(ui/run app :async true)`, then `(ui/reload!)`; both share the
server's terminal, so print with `tap>`.

## Shipping

`jolt build -m myapp.core -o target/myapp` makes one binary. GTK/Qt libs stay
dynamic (the user needs them installed); AppKit and ncurses come with the OS;
ftxui-jolt links its static archive. Verified: GTK, AppKit, TUI and ftxui
binaries run.

A macOS `.app` is a folder whose executable is the built binary (a script
there is refused by LaunchServices with -10669):

```bash
mkdir -p Counter.app/Contents/MacOS
cat > Counter.app/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Counter</string>
  <key>CFBundleIdentifier</key><string>com.example.counter</string>
  <key>CFBundleExecutable</key><string>counter</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
jolt build -m myapp.core -o Counter.app/Contents/MacOS/counter
rm -rf Counter.app/Contents/MacOS/counter.build
open Counter.app            # open -W Counter.app --args 2000  waits for it
```

Finder launches start with `cwd /` and a minimal `PATH`, and stdout goes to
the unified log (`log stream --process counter`). Sign/notarize before handing
it to someone else. iOS and Android builds are cross-compiles; see
[mobile.md](references/mobile.md).

## Gotchas

- **Handlers close over cells, not values** (glimmer). Signals are wired once
  at mount; a handler that captured a value goes stale.
- **Lists need `:key`** on every child (`^{:key id}` or `{:key id}`) or they
  match by position and per-row state follows the slot, not the item.
- **glitter: `set-dispatch!` before the first reconcile.** A data handler with
  no dispatch fn throws "Cannot use non-function event handler". It is one
  global, so one app per process. Event values come in through a placeholder
  you register (`:glitter/value`), not in the action vector.
- **glitter: removing a prop does nothing.** GTK has no "unset"; set the
  value explicitly (`:sensitive true`).
- **glitter-uikit is AppKit (macOS), glimmer-uikit is UIKit (iPhone).** The
  `examples/todomvc-uikit` app uses glimmer-uikit on a Mac and dies loading
  UIKit; use glimmer-appkit for macOS.
- **Natives built from source** (glimmer-qt, ftxui-jolt): their specs name a
  `:build` task. On jolt 0.8.26+ (the first release after 0.8.25, which adds
  `:build` support, jolt#1571) a plain git dep builds the library in its
  gitlib checkout on first run. On jolt 0.8.25, build inside it yourself:
  `cd "$(dirname "$(jolt -Spath | tr ':' '\n' | grep ftxui-jolt | head -1)")" && jolt native`.
- **GTK on macOS** runs its loop on the main thread; a Gdk-WARNING about
  "skipped frame" on quit is noise.
- **TUI and the REPL share a terminal**: anything printed lands in the frame.
- Pick one family per app: glimmer components cannot appear in a glitter
  view or the reverse; each has its own reconciler and widget registry.
