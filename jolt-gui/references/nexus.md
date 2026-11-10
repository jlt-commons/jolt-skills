# nexus-jolt: actions, effects and placeholders as data

A port of cjohansen/nexus. Toolkit-agnostic; glitter apps use it as their
dispatch fn, and it works for any "event -> state change" code (a CLI, a
glimmer app, a server).

```clojure
io.github.jlt-commons/nexus-jolt {:git/url "https://github.com/jlt-commons/nexus-jolt"
                                  :git/sha "<sha>"}
```

(Untagged, no deps; `jdep jlt-commons/nexus-jolt` gives the HEAD sha. glitter
and glitter-uikit already bring it at the commit they were tested with.) Namespaces: `nexus.core` (the engine: pass a
registry map) and `nexus.registry` (a global registry atom over it; what apps
use). The repo is `nexus-jolt`, the namespaces are `nexus.*`.

## The four concepts

| concept | register with | signature | may side-effect? |
|---|---|---|---|
| effect | `register-effect!` | `(fn [ctx system & args])` | yes: the only place |
| action (expansion) | `register-action!` (= `register-expansion!`) | `(fn [state & args]) -> [actions…]` | no |
| placeholder | `register-placeholder!` | `(fn [dispatch-data & args]) -> value` | no |
| interceptor | `register-interceptor!` | `{:before-dispatch f :after-effect f …}` | logging, tracing |

An action is a vector `[:kind & args]`; `dispatch` takes a vector of them.
Actions expand recursively until only effects remain. `system` is whatever
you pass to `dispatch` (usually the state atom); `register-system->state!`
says how an action gets its `state` from it (`deref` for an atom).

## Example (run)

```clojure
(require '[nexus.registry :as nxr])

(defonce state (atom {:count 0}))

(nxr/register-effect! :effect/assoc-in
  (fn [_ctx system path v] (swap! system assoc-in path v)))

(nxr/register-action! :counter/add
  (fn [state n] [[:effect/assoc-in [:count] (+ (:count state) n)]]))

(nxr/register-placeholder! :glitter/value
  (fn [event] (get-in event [:glitter/dom-event :glitter/value])))

(nxr/register-system->state! deref)
(nxr/on-error (fn [ctx {:keys [err phase]}] (println "nexus" phase (ex-message err))))

(nxr/dispatch state {} [[:counter/add 1] [:counter/add 1]])
@state   ; => {:count 2}

;; a placeholder in an action is replaced from the dispatch data
(nxr/dispatch state {:glitter/dom-event {:glitter/value "hi"}}
              [[:effect/assoc-in [:draft] [:glitter/value]]])
@state   ; => {:count 2, :draft "hi"}
```

Placeholders can take arguments and nest: glitter's temperature demo uses
`[:fmt/number [:glitter/value]]` with
`(nxr/register-placeholder! :fmt/number (fn [_ s] (parse-number s)))`.

An action whose kind has neither an expansion nor an effect is reported as an
error ("No effect handler for …") through `on-error`, not thrown. Exceptions
inside handlers are caught the same way; `dispatch` returns a map with
`:errors` and `:results` for inspection in tests.

## Wiring into glitter

```clojure
(glitter.core/set-dispatch! (fn [event actions] (nxr/dispatch state event actions)))
```

The event map glitter passes has the signal's value under
`[:glitter/dom-event :glitter/value]`. Keep registration and `set-dispatch!` in
a ns the view ns or entry point requires, so it runs before the first render.

`glitter.nexus.action-log` (in glitter-core) is an interceptor that records
dispatched actions with timestamps, for a debug panel or a replay log.

Older glitter docs (`docs/guide/nexus.md`) still say `glitter.nexus` and
`glitter.nexus.registry`; those namespaces are now `nexus.core` and
`nexus.registry` here.
