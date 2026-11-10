# ents (flecs ECS)

Repo: `jlt-commons/ents` (tagged). A
vybe-style API over [flecs](https://github.com/SanderMertens/flecs), through a
small C shim (`native/flecs_shim.c`) compiled together with flecs' amalgamated
`distr/flecs.c` into `native/libflecs_ents.dylib`. Namespace `ents.core`.

## Getting it built

Needs clang. Add it as a plain git dep; its `:jolt/native` spec carries
`:build "native"`, so on the jolt release after 0.8.25 that adds `:build` support (0.8.26+, jolt#1571) the first run compiles
`native/libflecs_ents.dylib` in the gitlib checkout (~20 s). The `native` task fetches flecs at a pinned commit
into `vendor/flecs`, or uses `FLECS_HOME` if set.

```clojure
{:deps {io.github.jlt-commons/ents {:git/url "https://github.com/jlt-commons/ents"
                                    :git/tag "<latest>" :git/sha "<sha>"}}}
```

Fill the tag with `jdep jlt-commons/ents` (jolt skill, `references/deps-and-tasks.md`).

On jolt 0.8.25 (no `:build`), build once inside the gitlib checkout:
`cd "$(dirname "$(jolt -Spath | tr ':' '\n' | grep /ents | head -1)")" && jolt native`.

## API (verified)

```clojure
(ns ecsapp.main
  (:require [ents.core :as ec]))

(def Position (ec/component Position [:x :double] [:y :double]))
(def Velocity (ec/component Velocity [:x :double] [:y :double]))
(def Health   (ec/component Health [:hp :int32]))

(ec/with-world w                                   ; or (ec/make-world) ... (ec/destroy! w)
  (dotimes [i 3]
    (ec/anon! w :enemy Position {:x (* i 10) :y 0} Velocity {:x 1 :y 2}))
  (ec/entity! w :player Position {:x 0 :y 0} Health {:hp 10})

  (ec/system! w :move [p Position v Velocity e :ent dt :dt]
    (ec/set-c! w e Position {:x (+ (:x p) (* (:x v) dt 60))
                             :y (+ (:y p) (* (:y v) dt 60))}))
  (ec/observer! w :hurt [h Health e :ent :events #{:set}]
    (println "health now" (:hp h)))

  (dotimes [_ 2] (ec/progress w (/ 1.0 60)))      ; runs systems
  (ec/set-c! w :player Health {:hp 7})             ; fires the observer
  (ec/count-q w "enemy, Position")                 ;=> 3   (raw flecs query DSL)
  (ec/with-query w [p Position e :ent] [(ec/ent-name-of w e) (:x p)])
  ;=> [["491" 2.0000001043081284] ... ["player" 0.0]]
  (ec/query w [Position Velocity]))                ;=> [{:e 491 :Position {...} :Velocity {...}} ...]
```

- `component` field types: `:float :double :int8 :uint8 :int16 :uint16
  :int32 :uint32 :int64 :uint64`. New components start zeroed; `set-c!`
  merges. Values come back as maps; `:float` fields come back as
  `java.lang.Float`, as on the JVM. Widen with `double` before comparing with
  `=` against doubles you put in sets or map keys (or use `:double` fields).
- Entities: keywords are literal names (`:a.b` is the name `"a.b"`); strings
  are flecs paths. `entity!` finds or creates by name; `anon!` creates
  unnamed (its `ent-name-of` is the id). Extra args: tag keywords, `[Rel Tgt]`
  pairs, a Component, or a Component followed by a value map.
- `get-c has? add! remove! delete! alive? valid? target ent`.
  Hierarchy: `(ec/entity! w :kid [:ChildOf :parent])`, then the child is
  `"parent.kid"`, and `(ec/target w "parent.kid" :ChildOf)` returns the parent id.
- `system!` options inside the binding vector: `:phase :on-load|:post-load|
  :pre-update|:on-update|:post-update|:on-store`. `run-system!` runs one now.
- `observer!` events: `:add :set :remove` (default `#{:set}`); `:event` binds
  the event id.
- `:dt` is flecs' single-precision delta, so expect float noise
  (`2.0000001...` above).
- Redefining a system/observer by name replaces it, which is what you want
  from a REPL. An exception inside a system is rethrown from `progress`; the
  world stays usable. Ops on a dead entity throw `ex-info`.

## In a raylib game

Run `(ec/progress w dt)` in the frame loop with `(rl/get-frame-time)`, and
draw with `ec/with-query` over the render components (systems can draw too,
since `progress` runs on the loop's thread). Keep the world in a `defonce`
so it survives namespace reloads. Each `set-c!` and component read crosses
the FFI and builds a map, so for tens of thousands of entities per frame
measure before choosing ents over plain arrays (see `perf.md`).
