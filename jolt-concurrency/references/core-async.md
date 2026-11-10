# clojure.core.async on jolt

Built in (`(require '[clojure.core.async :as a])`, no dependency). The whole
API is there: `chan` + buffers, `go`/`go-loop`, `<!`/`>!`/`<!!`/`>!!`,
`alts!`/`alts!!`, `poll!`/`offer!`, `timeout`, `promise-chan`, `close!`,
`thread`, `io-thread`, `pipe`, `pipeline`/`-blocking`/`-async`, `split`,
`reduce`/`transduce`/`into`/`take`, `mult`/`tap`, `mix`, `pub`/`sub`, `merge`,
`to-chan!`, plus jolt's `go-monitor`.

## Backends

| construct | runs on | daemon |
| --- | --- | --- |
| `go` (default `*go-backend* :thread`) | a new OS thread per block | yes |
| `go` under `*go-backend* :fiber` | a fiber | yes |
| `io-thread` | a fiber, always | yes |
| `thread` | a real OS thread, always | yes |

```clojure
(require '[clojure.core.async :as a] '[jolt.fibers :as fib])
(a/<!! (a/go (fib/in-fiber?)))                                   ;=> false
(binding [a/*go-backend* :fiber] (a/<!! (a/go (fib/in-fiber?)))) ;=> true
(alter-var-root #'a/*go-backend* (constantly :fiber))            ; every go from now on
(a/<!! (a/thread (fib/in-fiber?)))                               ;=> false
```

`*go-backend*` is read when a `go` spawns, so a `binding` covers go blocks
started by functions called inside it. Cost of 2000 go blocks parked on one
channel then released: 755 ms / ~780 MB RSS on `:thread`, 6 ms on `:fiber`;
100 000 on `:fiber` is fine. Use `:fiber` for anything with more than a few
dozen go blocks, and keep file IO / FFI out of them.

## Differences from JVM core.async

- Parking works through function calls on both backends; `<!` in a helper
  called from `go` is fine. Outside any go, `<!` blocks like `<!!`.
- On a fiber `<!!` parks too (the JVM throws for `<!!` in go).
- A throwing go body closes its channel, prints the error to `*err*`, and
  `go-monitor` returns the throwable:

```clojure
(a/<!! (a/go-monitor (a/go (throw (ex-info "boom" {})))))  ;=> #error {... "boom"}
```

## Patterns (verified)

```clojure
;; bounded parallel blocking transform, order preserved
(let [out (a/chan 10)]
  (a/pipeline-blocking 3 out (map (fn [x] (Thread/sleep 10) (inc x))) (a/to-chan! (range 6)))
  (a/<!! (a/into [] out)))                                ;=> [1 2 3 4 5 6]

;; helper that parks
(defn read-one [ch] (a/<! ch))
(let [ch (a/to-chan! [1 2])] (a/<!! (a/go [(read-one ch) (read-one ch)])))  ;=> [1 2]

;; timeout on a take
(let [ch (a/chan)]
  (a/<!! (a/go (let [[v port] (a/alts! [ch (a/timeout 50)])]
                 (if (= port ch) v :timed-out)))))        ;=> :timed-out
```

Worker pool with drain-on-shutdown: see the worked example in SKILL.md.
Producers stop when `>!!` returns false (channel closed); consumers stop when
`<!!` returns nil.

## Periodic work without a thread

```clojure
(defn every [ms f]
  (let [stop (a/chan)]
    (binding [a/*go-backend* :fiber]
      (a/go-loop []
        (let [[_ port] (a/alts! [stop (a/timeout ms)])]
          (when-not (= port stop) (f) (recur)))))
    #(a/close! stop)))

(let [n (atom 0) cancel (every 10 #(swap! n inc))]
  (Thread/sleep 105) (cancel) (<= 8 @n 11))               ;=> true
```
