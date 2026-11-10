# glitter: Replicant-style UIs (GTK4 and AppKit)

The model: one plain Clojure `atom` holds all app state; `view` is a pure
`state -> hiccup` fn; every state change re-renders from the top and the
reconciler (ported from Replicant) patches the widgets; event handlers are data
(`:on {:click [[:action/inc]]}`) handed to one global dispatch fn. No
component-local state anywhere. Pair it with nexus-jolt ([nexus.md](nexus.md))
for the actions.

| repo | what | main nss |
|---|---|---|
| jlt-commons/glitter-core | reconciler, `IRender`/`IMemory` protocols, aliases, in-memory test renderer; no natives | `glitter.core`, `glitter.alias`, `glitter.test-renderer`, `glitter.protocols` |
| jlt-commons/glitter | GTK4 renderer, 43 widget tags | `glitter.app`, `glitter.gtk`, `glitter.widget` |
| jlt-commons/glitter-uikit | **AppKit** (macOS) renderer, despite the name | `glitter-uikit.app`, `glitter-uikit.appkit` |
| jlt-commons/glitter-gl | OpenGL `:gl-area`, geometry, shaders for glitter | see [gl.md](gl.md) |
| jlt-commons/uikit-demo | larger glitter-uikit app: hub, currency converter, live HTTPS fetch, CALayer particles | — |

Untagged; pin the HEAD sha (`jdep jlt-commons/glitter`, see the jolt skill's
deps-and-tasks.md):

```clojure
io.github.jlt-commons/glitter       {:git/url "https://github.com/jlt-commons/glitter"
                                     :git/sha "<sha>"}
io.github.jlt-commons/glitter-uikit {:git/url "https://github.com/jlt-commons/glitter-uikit"
                                     :git/sha "<sha>"}
```

Both bring glitter-core and nexus-jolt at the commits they were tested with.
`glitter` declares the GTK4/GLib natives (needs `brew install gtk4` /
`libgtk-4-1`) and jolt-lang/time, hiccup and jolt-lang/logging; glitter-uikit
needs only macOS. Depend on glitter-core alone for a natives-free library or
test suite. jolt 0.8.0+.

## One state ns, two toolkits (run on GTK4 and AppKit)

`src/myapp/state.clj` knows nothing about the toolkit:

```clojure
(ns myapp.state
  (:require [glitter.core :as core]
            [nexus.registry :as nxr]))

(defonce state (atom {:count 0}))

(defn view [{:keys [count]}]
  [:vbox {:spacing 12 :margin 12}
   [:label {:label (str "Count: " count)}]
   [:hbox {:spacing 8}
    [:button {:label "- 1" :on {:click [[:counter/add -1]]}}]
    [:button {:label "+ 1" :on {:click [[:counter/add 1]]}}]
    [:button {:label "reset" :on {:click [[:effect/assoc-in [:count] 0]]}}]]])

;; effects are the only fns that touch the atom
(nxr/register-effect! :effect/assoc-in
  (fn [_ctx system path v] (swap! system assoc-in path v)))

;; actions are pure: (state & args) -> more actions
(nxr/register-action! :counter/add
  (fn [state n] [[:effect/assoc-in [:count] (+ (:count state) n)]]))

(nxr/register-system->state! deref)

;; every data handler lands here; must be set before the first render
(core/set-dispatch! (fn [event actions] (nxr/dispatch state event actions)))
```

GTK4 entry point (`glitter` dep):

```clojure
(ns myapp.gtk
  (:require [glitter.app :as app]
            [glitter.gtk :as gtk]
            [myapp.state :refer [state view]]))

(defn -main [& args]
  (apply app/run (fn [window] (gtk/mount! window view state))
         :title "counter" :width 320 :height 160
         (when-let [ms (first args)] [:auto-quit-ms (parse-long ms)])))
```

AppKit entry point (`glitter-uikit` dep): the same with
`[glitter-uikit.app :as app]` and `[glitter-uikit.appkit :as appkit]`, calling
`(appkit/mount! window view state)`. `app/run` options: `:title :width
:height :auto-quit-ms :app-id` (ignored on AppKit). Under nREPL it hops onto
the main thread and returns, like glimmer.

`mount!` is one-way: it watches the atom under a fixed key, returns nil, has
no unmount, and a second mount on the same atom replaces the first watcher.

## Events carry data, values come by placeholder

Hiccup is fixed when `view` runs, so a typed value cannot be in the action
vector. It arrives on the event, and a placeholder you register pulls it out
(glitter does not register one for you):

```clojure
(nxr/register-placeholder! :glitter/value
  (fn [event] (get-in event [:glitter/dom-event :glitter/value])))

[:entry {:text (:draft state) :placeholder "type here"
         :on {:change [[:effect/assoc-in [:draft] [:glitter/value]]]}}]
```

Which signals carry a value, per tag, is the table in glitter's
`docs/guide/widgets.md`.

## GTK4 widget set (glitter)

`window box hbox vbox button label entry checkbutton separator frame
scrolled`, display `:spinner :progress-bar :image :level-bar :picture
:inscription`, buttons `:toggle-button :link-button :switch :menu-button`,
text `:password-entry :search-entry :editable-label :search-bar`, values
`:scale :spin-button :scale-button :calendar :drop-down`, containers
`:revealer :center-box :paned :overlay :aspect-frame :expander
:window-handle`, multi-child `:list-box :flow-box :grid :stack :notebook`,
chrome `:header-bar :action-bar :popover`.

Every tag: `:margin*`, `:halign`/`:valign`, `:hexpand`/`:vexpand`,
`:width-request`/`:height-request`, `:class ["suggested-action"]` (real GTK CSS
classes); `:sensitive false` on interactive tags. `:style` is accepted and does
nothing. The four galleries `jolt -M:gallery-inputs|-layout|-display|-chrome`
in the glitter repo use all 43 tags and are written to be copied from.

glitter-uikit implements the glimmer-appkit vocabulary (`:vbox :hbox :label
:button :entry :checkbutton …`) with `:on {:click …}` instead of `:on-click`;
`:class` and `:style` are inert.

## Aliases (reusable view pieces)

```clojure
(require '[glitter.alias :as alias])

(alias/defalias badge [{:keys [n]} _children]
  [:label {:label (str "badge:" n)}])

(defn view [{:keys [n]}] [:box {:spacing 4} [badge {:n n}]])
```

`gtk/mount!` passes every registered alias to the reconciler. When calling
`core/reconcile` yourself, pass `{:aliases (alias/get-registered-aliases)}`.

## Testing (run)

The view is a pure fn: assert on its hiccup. Dispatch actions straight into
nexus to test behaviour, and reconcile into the in-memory renderer to see
widget operations:

```clojure
(require '[glitter.core :as core] '[glitter.test-renderer :as tr]
         '[nexus.registry :as nxr] '[myapp.state :refer [state view]])

(nxr/dispatch state {} [[:counter/add 1] [:counter/add 1]])
@state                                   ; => {:count 2}

(let [r (tr/renderer)]
  (core/reconcile r (atom {:tag-name "window" :children []}) (view @state))
  (take 2 (tr/events r)))
;; => ([:create-element "vbox"] [:set-attribute "vbox" "spacing" 12])
```

`tr/reset-events!` clears the log between two reconciles (to see only an
update's mutations). Requiring the ns that calls `set-dispatch!` matters here
too: reconciling a view with data handlers and no dispatch fn throws.

## Limits worth knowing (from glitter's limitations.md)

- Dropping a prop leaves the widget's last value; set it explicitly.
- `IMemory` (`:glitter/remember`) never evicts.
- `:center-box`, `:paned`, `:overlay`, `:header-bar`/`:action-bar` can't swap a
  slot's tag while all slots are filled; change props, or wrap in a stable tag.
- A `:notebook` or `:stack` mounted with pages dispatches once at mount (GTK
  auto-selects page 0).
