# glimmer on phones: glimmer-uikit (iPhone) and glimmer-android

Nothing here was run for this skill (it needs a simulator/emulator and a
cross-compile target pack); the snippets are from the repos' READMEs. Both
render the same hiccup vocabulary, so one set of components serves both, and
both are jolt 0.8.0+ (`jolt.ffi/write` argument order).

| | glimmer-uikit | glimmer-android |
|---|---|---|
| needs | Xcode (simulator, iOS SDK, clang); jolt target packs `tarm64ios` (simulator) and `tpb64l` (device; portable bytecode + libffi, iOS forbids JIT) | Apple Silicon Mac; `jolt pack` builds `tarm64le` Android pack from Chez v10.4.1; Android SDK with `ANDROID_HOME`, NDK r30, CMake 4.1.2; JDK 21+ for the Gradle demo |
| app loop | `ui/run` calls `UIApplicationMain` and never returns | the Java Activity owns the loop; your exported fn calls `ga/mount!` |
| build | `jolt bundle` (scripts/bundle; `TARGET=sim` or `device`, `NS=` your ns) → `build/Counter.app`; `jolt install`, `jolt launch`, `jolt console` via `xcrun simctl` | `jolt lib` builds your ns as an Android `.so` (`NS`, `OUT`, `ALIAS`); Gradle builds the APK with `-PglimmerAndroid=<checkout>` |
| recipe | statonjr/glimmer-ios-demo (packs, signing, an in-app nREPL) | the repo's `scripts/demo`, `android/` (Java + C half) |

```clojure
jolt-lang/glimmer-uikit   {:git/url "https://github.com/jolt-lang/glimmer-uikit"
                           :git/tag "<latest>" :git/sha "<sha>"}
jolt-lang/glimmer-android {:git/url "https://github.com/jolt-lang/glimmer-android"
                           :git/tag "<latest>" :git/sha "<sha>"}
```

glimmer-uikit loads UIKit inside the app loop, never at require time, so
`jolt build` and headless tests work on a Mac/Linux host. On a Mac desktop
`ui/run` fails with "cannot load …/UIKit.framework/UIKit": for macOS windows
use glimmer-appkit ([desktop.md](desktop.md)).

## iPhone

```clojure
(ns myapp
  (:require [glimmer.ratom :refer [atom]]
            [glimmer.core :as ui]
            [glimmer-uikit.core]))              ; installs the UIKit backend

(defn counter []
  (let [count (atom 0)]
    (fn []
      [:vbox {:spacing 12}
       [:label {:label (str "Count: " @count)}]
       [:hbox {:spacing 8}
        [:button {:label "- 1" :on-click #(swap! count dec)}]
        [:button {:label "+ 1" :on-click #(swap! count inc)}]]])))

(defn -main [& _]
  (ui/run counter))          ; :background "#rrggbb" colours the root view
```

No `:window` tag: the root mounts into the root view controller, pinned to the
safe area. Lifecycle hooks: `(glimmer-uikit.core/on-lifecycle! :background f)`
(`:resign-active :background :foreground :active :terminate`).
`glimmer-uikit.ffi` also has `load-framework!`, `make-block`, `timer!`,
`open-url!` for reaching other frameworks.

## Android

```clojure
(ns myapp.android
  (:require [glimmer.ratom :as r]
            [glimmer-android.core :as ga]      ; installs the Android backend
            [jolt.ffi :as ffi]))

(defonce taps (r/atom 0))

(defn counter []
  [:vbox {:spacing 12 :margin 16}
   [:label {:label (str "Tapped " @taps " times")}]
   [:button {:label "Tap" :on-click #(swap! taps inc)}]])

;; The Activity calls this export once per Activity; the manifest names it.
(defn- main [] (ga/mount! [counter]))
(ffi/export! "myapp_main" main [] :void :collect-safe)
```

`glimmer-android.core` also has `back!`/`take-back!` (Back handling),
`on-background!` (save state), `files-dir`, `version`, `debuggable?`,
`open-url!`, and `fetch!`/`cancel-fetch!` (HTTP GET off the UI thread,
answered on it). `glimmer-android.fake` runs tests against a fake C half, no
device.

## Shared vocabulary

Containers `:vbox :hbox :layers :scroll` (UIKit also `:box`); leaves `:label
:button :checkbutton :image :gradient`. No `:entry`. Common props `:width
:height` (points/dp), `:halign`, `:valign` (`:fill :top :bottom :center`),
`:hexpand :vexpand :background :alpha :center-y :sensitive :key`; on the root
`:vfill` and `:full-bleed`. Labels take Pango-style `:markup` hiccup and
`:date` (ms, locale-formatted). Events: `:on-click`, `:on-toggled`. An
unknown prop is ignored and printed once per tag/prop pair.
