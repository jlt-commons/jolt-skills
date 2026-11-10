# tapestry (jlt-commons/tapestry): futures with cancellation

A jolt fork of teknql/tapestry. Despite the name, a tapestry `fiber` is **an
OS daemon thread**, not a jolt fiber; the substrate is core.async. Use it for
futures with interrupt and timeout, bounded `pmap`-style helpers, and
structured scopes. For thousands of lightweight processes use `jolt.fibers` or
core.async on `:fiber` instead. Needs jolt >= 0.8.16. Source:
https://github.com/jlt-commons/tapestry (the README names `jolt-lang/tapestry`,
which redirects there).

```clojure
io.github.jlt-commons/tapestry {:git/url "https://github.com/jlt-commons/tapestry"
                                :git/tag "<latest>" :git/sha "<sha>"}
```

Fill with `jdep jlt-commons/tapestry` (jolt skill, `references/deps-and-tasks.md`).

```clojure
(require '[tapestry.core :as t :refer [fiber fiber-loop interrupt! alive? errored? timeout!
                                       with-timeout parallelly asyncly pfor]]
         '[tapestry.experimental.scope :refer [with-scope]]
         '[tapestry.queue :as q]
         '[clojure.core.async :as a])

@(fiber (Thread/sleep 50) :done)                          ;=> :done
(deref (fiber (Thread/sleep 10000)) 100 :timed-out)       ;=> :timed-out
@(fiber-loop [i 0] (if (= i 5) (* 2 i) (do (Thread/sleep 10) (recur (inc i)))))  ;=> 10

(let [f (fiber (Thread/sleep 10000))]
  (interrupt! f)                                          ; the sleep throws, body stops
  [(errored? f) (try @f (catch clojure.lang.ExceptionInfo e (:type (ex-data e))))])
;=> [true :tapestry.core/interrupted]

(let [f (fiber (Thread/sleep 10000))] (timeout! f 50 :default) @f)   ;=> :default
(try (with-timeout 50 @(fiber (Thread/sleep 10000)))
     (catch Exception e (:type (ex-data e))))             ;=> :tapestry.core/timeout
```

## Bounded parallel helpers

```clojure
(parallelly 3 #(do (Thread/sleep (- 50 (* 10 %))) (* % %)) (range 5))  ;=> [0 1 4 9 16] input order
(sort (asyncly 3 inc (range 5)))                          ;=> (1 2 3 4 5)  completion order
(vec (pfor [x (range 4)] (* 10 x)))                       ;=> [0 10 20 30]
(a/<!! (a/into [] (parallelly 2 inc (a/to-chan! [1 2 3]))))  ;=> [2 3 4]   channel in, channel out
```

`(t/with-max-parallelism n body)` caps how many fibers spawned inside run at
once. `(t/periodically ms f)` returns a channel of `(f)` results; close it to stop.
In channel mode errors go to `t/set-stream-error-handler!`.

## Scopes (experimental)

```clojure
(with-scope {:shutdown :on-failure :timeout 1000}
  (let [a (fiber (Thread/sleep 20) 1) b (fiber 2)] (+ @a @b)))   ;=> 3

(try (with-scope {:shutdown :on-failure}                  ; a failure interrupts siblings
       (let [a (fiber (Thread/sleep 5000) 1) b (fiber (throw (ex-info "bad" {})))] (+ @a @b)))
     (catch Exception e (ex-message e)))                  ;=> "bad" (returns at once)
```

## Queues

```clojure
(let [qq (q/queue 2)]                                     ; capacity 2; (q/queue) is a rendezvous
  (q/put! qq :a) (q/put! qq :b)
  [(q/try-put! qq :c 0) (q/take! qq)])                    ;=> [false :a]
```

`q/close!` stops puts (they return false) while queued items still drain.

Interruption only lands at an interruptible wait (sleep, deref, channel op,
join). A CPU loop keeps running and its result is reported as cancelled;
check `(Thread/interrupted)` in long loops.
