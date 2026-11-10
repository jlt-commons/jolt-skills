# duratom: durable atoms

Source: https://github.com/jlt-commons/duratom (README, `src/duratom/*.clj`).
The README's `io.github.jolt-lang/duratom` coordinate redirects to jlt-commons.
Use its newest tag (`jdep jlt-commons/duratom`, see the jolt skill's `references/deps-and-tasks.md`). It brings
jolt-lang/glimmer and jolt-lang/db transitively.

```clojure
{:deps {io.github.jlt-commons/duratom {:git/url "https://github.com/jlt-commons/duratom"
                                       :git/tag "<latest>" :git/sha "<sha>"}}}
```

A duratom is a glimmer reactive cell: `@`, `reset!`, `swap!` (plain
`clojure.core` ones work), `glimmer.ratom/reaction` and `cursor`; every change is
written to its backend before the call returns. Use it for small app state
(settings, counters, a cache index) that must survive a restart. For many rows or
queries use db (or relatum, saved as EDN).

## API (all ran)

```clojure
(require '[duratom.core :as d])

(def counts (d/file-atom "counts.edn" {:clicks 0}))   ; EDN file; init ignored if file exists
(swap! counts update :clicks inc)
@counts                        ; => {:clicks 1}
(d/backend-snapshot counts)    ; => {:clicks 1}  read back from the backend
(slurp "counts.edn")           ; => "{:clicks 1}"
@(d/file-atom "counts.edn")    ; => {:clicks 1}  a new atom over the same path
(d/destroy counts)             ; delete the file, close the backend

;; sqlite / postgres via jolt-lang/db: one EDN value per (id integer, value text) row
(def settings (d/sql-atom "sqlite:state.db" "kv" 1 {:theme "dark"}))   ; dbspec table row-id init
(d/sql-atom "sqlite:state.db" "counters" {:n 0})                       ; row-id defaults to 0
;; table is created if missing; the connection stays open for the atom's lifetime,
;; so "sqlite::memory:" works. row-id must be an integer.
```

`init` may be a value, a no-arg fn, or a delay. It is used only when the backend
holds nothing. A stored `false` or `nil` is kept, not replaced by `init` (`nil`
needs the backend to report a stored value: the file and sql backends do; a
custom backend whose `load-state` returns nil counts as empty).

## With glimmer reactions

```clojure
(require '[glimmer.ratom :as r])
(def a  (d/file-atom "n.edn" (fn [] 2)))
(def sq (r/reaction (* @a @a)))
@sq            ; => 4
(reset! a 5)
@sq            ; => 25, and "5" is on disk
```

## Custom backend

```clojure
(require '[duratom.backends :as b])

(defrecord MemBackend [store]
  b/StorageBackend
  (load-state [_] @store)            ; persisted value or nil
  (persist! [_ v] (reset! store v) v)
  (clear! [_] (reset! store nil) nil)
  (close-backend [_] nil))

(def a (d/make-duratom (->MemBackend (atom nil)) {:initial true}))
(swap! a assoc :n 1)                 ; => {:initial true, :n 1}
```

Built-in backends: `(b/file-backend path)`, `(b/sql-backend dbspec table row-id)`.

## Concurrency

`swap!` is atomic: 8 futures x 200 `(swap! a inc)` end at 1600. Each change is
persisted before the call returns, so heavy write rates pay one backend write per
swap.
