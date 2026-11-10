# glimmer: the reactive core

Source: `github.com/jolt-lang/glimmer`. Namespaces: `glimmer.ratom`, `glimmer.core`, `glimmer.table`,
`glimmer.backend`. No dependencies, no natives; the suite runs headless
through an in-memory backend. Needs jolt 0.8.22+ (older releases hash every
atom alike and the reconciler goes quadratic).

## Reactive cells (`glimmer.ratom`)

```clojure
(require '[glimmer.ratom :as r :refer [atom cursor reaction]])

(let [state (atom {:count 0 :name "x"})
      count (cursor state [:count])            ; writable lens: get-in / assoc-in
      label (reaction (str "count is " @count))] ; read-only, recomputed on change
  @label                                       ; => "count is 0"
  (swap! count inc)
  [@label @state])                             ; => ["count is 1" {:count 1, :name "x"}]

(let [a (atom 1) b (atom 2)]
  (r/capture #(+ @a @b)))                      ; => [3 [a b]]  value + cells read
```

(Run on jolt 0.8.25.)

- `atom`, `cursor`, `reaction` (macro over `make-reaction`) all read with `@`.
- Requiring `glimmer.ratom` rebinds `clojure.core/deref`, `reset!` and `swap!`
  (once, via `alter-var-root`). For a non-reactive reference they delegate to
  the host fn, so plain atoms, futures and delays are unaffected.
- `r/*current-watcher*`, `r/watch-scope`, `r/clear-subscriptions!`,
  `r/unwatch!` are the tracking internals backends and caches use.
- A reaction is read-only: `reset!` on it throws.

### Your own cell type

Implement `glimmer.ratom/IReactiveCell` and `@`, `reset!`, `swap!`, `cursor`
and `reaction` work on it (`jlt-commons/duratom` does this for a durable atom):

```clojure
(defrecord DurableAtom [id db state watches]
  r/IReactiveCell
  (-value [_] @state)                                  ; no watcher registration
  (-reset! [this v]
    (let [old @state]
      (when (not= old v)
        (reset! state v)
        (swap! db assoc id v)                          ; persist here
        (r/-notify-watches! this))
      v))
  (-add-watch! [_ w] (swap! watches conj w))
  (-remove-watch! [_ w] (swap! watches disj w))
  (-notify-watches! [this] (doseq [w @watches] (w this))))
```

(From the glimmer README; `IAtomicSwap` is the optional protocol `swap!` uses
for an atomic apply.)

## Incremental tables (`glimmer.table`)

A `reaction` over a big collection recomputes everything. A table's derived
cells process only the rows that changed (DBSP-style):

```clojure
(require '[glimmer.table :as t])

(def todos (t/table {1 {:title "a" :done false}}))
(def open (t/view todos (fn [_k v] (when-not (:done v) v))))   ; nil drops the row
(def open-count (t/aggregate open t/count-of))
(def by-done (t/aggregate todos t/count-of (fn [_k v] (:done v)))) ; grouped

(t/put! todos 2 {:title "b" :done true})
[@open-count @by-done]   ; => [1 {false 1, true 1}]
(t/delete! todos 1)
[@open-count @by-done]   ; => [0 {true 1}]
```

(Run.) An aggregate is `{:init x :add (fn [acc row]) :sub (fn [acc row])}`;
`t/count-of` and `(t/sum-of f)` exist. Max or sort has no inverse: use a
reaction. `def` derived cells at top level; they stay registered on the source.

## Components

- **Form-1**: a fn returning hiccup, re-invoked on every render.
- **Form-2**: a fn returning a render fn. The outer body runs once at mount
  (local atoms persist), the inner fn renders.

Invoke as `[my-comp arg ...]`. A component is its own reactive unit: a cell
read during its render re-runs only that component. Its subscriptions are
exactly the cells its latest render read. Rendering `nil` removes what it drew.
A throwing re-render keeps its subscriptions and retries on the next change; a
failing mount is unwound before the error propagates.

## Hiccup and reconciliation

`[:tag props? & children]`. Children: elements, component vectors, strings or
numbers (labels), `nil` (skipped), seqs (spliced), so `(when …)` and
`(for …)` work inline. Tags and props are the backend's vocabulary.

Children match by position (same tag: reuse and re-apply props; different:
replace). When **every** child has a `:key` (`{:key id}` in props or
`^{:key id}` metadata) they match by key, so widgets, signal handlers and
Form-2 state follow the item through inserts, removes and reorders:

```clojure
(into [:vbox {}]
      (for [{:keys [id text]} @items]
        [task-row {:key id} id text]))
```

A list mixing keyed and unkeyed children falls back to positional.

## Running (`glimmer.core`)

| fn | does |
|---|---|
| `(run root-fn & opts)` | mount `[root-fn]` in a new window and run the backend's loop until quit. Opts every backend reads: `:app-id :title :width :height :auto-quit-ms`; backends add their own |
| `(reload!)` / `(reload! new-root-fn)` | re-mount the running root in the same window, on the UI thread |
| `(on-gui thunk)` | run on the UI thread (inline when no loop runs) |
| `(mount container tag hiccup)` | mount into a container; returns the root instance atom |
| `(unmount! root container tag)` / `(abandon! root)` | tear down with / without touching native widgets |

Ratom writes from other threads (nREPL, a future) are deferred onto the UI
thread when the backend sets `glimmer.backend/loop-running?`; with no loop
running, renders are synchronous, which is what keeps tests deterministic.

## Writing a backend (`glimmer.backend`)

A backend is a map passed to `glimmer.backend/register!` (the backend ns does
this when required). Required: `:create! :apply-props! :append-child!
:remove-child! :replace-child!`. Optional: `:reorder-child! :schedule :run
:run-lifecycle :dispose! :text->element`. The `glimmer.backend` ns docstring
is the contract; `glimmer-tui` is the most complete pure-Clojure example, and
glimmer's own `test/glimmer/mock_backend.clj` is the smallest.
