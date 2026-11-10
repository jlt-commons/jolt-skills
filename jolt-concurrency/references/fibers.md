# jolt.fibers

Built in. A fiber is a green thread on a carrier (an OS thread). User docs:
https://jolt-lang.net/docs/fibers.html. That page is
current except for one row: `Thread/sleep` **parks** a fiber since 0.8.16 (the
table says it pins).

```clojure
(require '[jolt.fibers :as fib] '[clojure.core.async :as a])

(fib/join (fib/spawn (fn [] (+ 1 2))))                 ;=> 3

(def dead (fib/spawn (fn [] (throw (ex-info "boom" {:why :demo})))))
(try (fib/join dead) (catch clojure.lang.ExceptionInfo e (ex-data e)))  ;=> {:why :demo}
(fib/state dead)                                       ;=> :dead

(fib/join (fib/spawn (fn [] (a/<!! (a/timeout 500)))) 50 :not-yet)  ;=> :not-yet

;; 10k fibers parked on one promise
(let [p  (promise)
      fs (mapv (fn [i] (fib/spawn (fn [] (+ i @p)))) (range 10000))]
  (deliver p 1)
  (reduce + (map fib/join fs)))                        ;=> 50005000
```

Public vars (from `(ns-publics 'jolt.fibers)`): `spawn` `join` `monitor!`
`interrupt!` `kill!` `masked` `unmasked` `state` `fiber?` `current-fiber`
`in-fiber?` `yield` `pool` `pool?` `pool-name` `pool-of` `pool-size`
`shutdown!` `carrier-count` `set-carrier-count!` `preempt-ticks`
`set-preempt-ticks!`.

## Cancelling

`interrupt!` raises a throwable in the fiber at its next park (or within one
preemption quantum if it is running); the fiber's own `catch` sees it.
`kill!` is the same but no `catch` of the fiber's can stop it; `finally` blocks
still run. Both return false if the fiber already finished.

```clojure
(let [ch (a/chan)
      f  (fib/spawn (fn [] (try (a/<! ch) (catch Exception e [:caught (ex-message e)]))))]
  (Thread/sleep 20)
  (fib/interrupt! f (ex-info "stop" {}))
  (fib/join f))                                        ;=> [:caught "stop"]

(let [log (atom []) ch (a/chan)
      f   (fib/spawn (fn [] (try (a/<! ch)
                                 (catch Throwable _ (swap! log conj :caught))
                                 (finally (swap! log conj :finally)))))]
  (Thread/sleep 20)
  (fib/kill! f (ex-info "kill" {}))
  [(try (fib/join f) (catch Exception e (ex-message e))) @log])  ;=> ["kill" [:finally]]
```

`(fib/masked (fn [] ... (fib/unmasked body) ... cleanup))` defers interrupts
and kills around cleanup that must not be torn.

`monitor!` calls back once with `nil` (clean) or the error, on the fiber's
carrier; keep it short:

```clojure
(let [p (promise)]
  (fib/monitor! (fib/spawn (fn [] (/ 1 0))) (fn [err] (deliver p (some-> err ex-message))))
  @p)                                                  ;=> "Divide by zero"
```

## Pools: isolate pinning work

A fiber stays on its carrier for life. Something that pins (file IO, FFI, a
blocking C driver) stalls every fiber queued on that carrier, and adding
carriers does not help them. Give such work its own pool:

```clojure
(def io (fib/pool {:name :io :size 4}))
(fib/join (fib/spawn (fn [] (slurp "deps.edn") (fib/pool-name (fib/pool-of (fib/current-fiber))))
                     {:pool io}))                      ;=> :io
(fib/shutdown! io)    ; no new spawns; running fibers finish
```

Or hand the blocking call to an OS thread and park on the result:
`(a/<! (a/thread (slurp f)))`.

Measured with one carrier: a fiber in `Thread/sleep 300` did not delay a second
fiber (25 ms); a fiber blocked reading a FIFO (`slurp`) delayed it until the
read finished (833 ms).

## Tuning

`(fib/set-carrier-count! n)` and `(fib/set-preempt-ticks! n)` (same settings
as `a/*fiber-carrier-count*` / `a/*fiber-preempt-ticks*`) are read once, when
the default pool starts: call them before the first fiber or `:fiber` go.
`(fib/carrier-count)` defaults to the processor count. Preemption cannot be
turned off.

## Virtual threads

`Thread/startVirtualThread` and `(.start (Thread/ofVirtual) f)` start fibers
(`.isVirtual` true, `fib/in-fiber?` true). On jolt 0.8.25
`Executors/newVirtualThreadPerTaskExecutor` does **not**: its tasks run on a
daemon cached OS-thread pool (`.isVirtual` false).
