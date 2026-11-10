---
name: jolt-concurrency
description: Build concurrent, async, streaming and long-running programs on Jolt (Clojure on Chez Scheme). Use when a jolt program needs threads, futures, promises, agents, atoms/refs/STM, clojure.core.async (go blocks, channels, pipelines), jolt.fibers (green threads, carrier pools, interrupt/kill), java.util.concurrent executors, scheduled jobs, blocking queues, worker pools, graceful shutdown, signal handling (SIGINT/SIGTERM, shutdown hooks, park-until-interrupt), servers that must stay up, Erlang-style actors and supervision trees (jlt-commons/ensemble: gen_server, gen_statem, supervisors), missionary-style tasks and reactive flows (jlt-commons/ebb), structured-concurrency helpers (jlt-commons/tapestry: fiber, parallelly, with-scope), or app lifecycle with mount or integrant. Also use when a jolt process exits too early, hangs on exit, or a fiber stalls.
---

# Concurrency on Jolt

Read the `jolt` skill first for projects, deps and builds. This skill picks the
concurrency tool and lists what behaves differently from the JVM. Everything
here was verified on jolt 0.8.25; behaviour that is specific to that release
says so.

## Facts to reason from (verified, not JVM folklore)

- **Process exit follows JVM rules** (since 0.8.16). `-main` returning waits for
  non-daemon threads: a started `Thread.` (inherits its creator's daemon flag,
  so from main it holds the exit), `future`/`send-off` workers (held for the
  60 s pool keep-alive unless you call `(shutdown-agents)`), and `Executors`
  pools (held until `.shutdown`). Daemons that never hold the exit:
  core.async `thread`/`go`/`io-thread`, fibers, ensemble actors, ebb processes,
  CompletableFuture's async pool, `.setDaemon true` threads.
  `jolt <task>` / `jolt run <task>` use babashka's rule instead: futures and
  agents are daemons there.
- **A long-running `-main` must park.** `jolt.host/park-until-interrupt` never
  returns on Ctrl-C: SIGINT/SIGTERM/SIGHUP run the shutdown hooks, then the
  process exits (130 / 143). Hooks also run on `System/exit` and on a normal
  return. Put cleanup in a hook, not after the park.
- **`go` runs on an OS thread per block by default** (`*go-backend*` is
  `:thread`). 2000 parked go blocks: 755 ms and ~780 MB RSS on threads, 6 ms on
  fibers. Switch with `(binding [a/*go-backend* :fiber] ...)` or globally with
  `(alter-var-root #'a/*go-backend* (constantly :fiber))`.
- **Fibers** run on carriers (OS threads; default = processor count). On a
  fiber these **park** (free the carrier): channel ops, `alts!`, `timeout`,
  promise/future/fiber deref, `Thread/sleep`, `jolt.socket`/`java.net` socket
  IO, `locking` (a lock may be held across a park). These **pin** the carrier
  (every fiber queued on it waits): file IO, `slurp`, FFI and other blocking
  foreign calls. Pinned work goes to `a/thread`, a fiber pool of its own, or an
  ensemble dispatcher. A fiber is never moved to another carrier.
  (The fibers doc page still says `Thread/sleep` pins; it parks since 0.8.16.)
- On a fiber `<!` and `<!!` both park, and parking works inside called
  functions (no lexical restriction as on the JVM). Off a fiber `<!` blocks.
- Compute-bound fibers are preempted (~0.45 ms quantum); they cannot starve a
  carrier, only share it.

## Which tool

| I need | Use |
| --- | --- |
| one background computation, get the value later | `future` + `deref` (with timeout `(deref f ms v)`) |
| shared mutable state | `atom`; coordinated multi-ref change: `ref` + `dosync` |
| serialized async updates to one value | `agent` + `send`/`send-off`, `await` |
| N workers draining a queue of blocking jobs | core.async channel + N `a/thread` (example below), or `Executors/newFixedThreadPool` |
| thousands of mostly idle processes on channels or sockets | core.async on `:fiber`, or `jolt.fibers/spawn` |
| run blocking IO / FFI from fiber code | `(a/<! (a/thread ...))`, or `(fib/spawn f {:pool io})` with `fib/pool` |
| periodic job | `Executors/newScheduledThreadPool` + `.scheduleAtFixedRate`, or a `go-loop` on `(a/timeout ms)` |
| cancel a fiber from outside | `jolt.fibers/interrupt!` (catchable) / `kill!` (not catchable, `finally` runs) |
| processes with links, monitors, selective receive, supervisors, restarts | **ensemble** ([references/ensemble.md](references/ensemble.md)) |
| composable cancellable tasks, backpressured streams, dataflow (missionary) | **ebb** ([references/ebb.md](references/ebb.md)) |
| futures with timeout/interrupt, bounded `pmap`, scopes that cancel siblings | **tapestry** ([references/tapestry.md](references/tapestry.md)); its "fibers" are OS threads |
| start/stop a system of components in dependency order | integrant or mount ([references/lifecycle.md](references/lifecycle.md)) |
| a server that stays up and shuts down cleanly | `block-sigint` + shutdown hook + `park-until-interrupt` |

Details: [references/core-async.md](references/core-async.md),
[references/fibers.md](references/fibers.md).

## deps.edn

Built in, no dependency: core.async, `jolt.fibers`, `jolt.host`,
`java.util.concurrent`. Libraries (fill each tag with `jdep OWNER/REPO`, see
the jolt skill's `references/deps-and-tasks.md`, "Depending on a library: use
the latest tag"; never copy a sha from docs):

```clojure
{:deps {io.github.jlt-commons/ebb      {:git/url "https://github.com/jlt-commons/ebb"
                                        :git/tag "<latest>" :git/sha "<sha>"}
        io.github.jlt-commons/ensemble {:git/url "https://github.com/jlt-commons/ensemble"
                                        :git/tag "<latest>" :git/sha "<sha>"}
        io.github.jlt-commons/tapestry {:git/url "https://github.com/jlt-commons/tapestry"
                                        :git/tag "<latest>" :git/sha "<sha>"}
        integrant/integrant {:mvn/version "<latest>"} ; upstream works as is
        mount/mount         {:mvn/version "<latest>"}} ; upstream works; no fork needed
 }
```

## Worked example: worker pool with graceful shutdown

Producer, bounded queue, 4 workers on real threads (the jobs block), drain on
Ctrl-C or SIGTERM. Verified: on SIGINT it prints `draining...`, finishes every
queued job, prints `stopped`, exits 130.

```clojure
(ns pool.main
  (:require [clojure.core.async :as a]))

(defn handle [job]
  (Thread/sleep 200)                       ; blocking work: fine on a/thread
  (println "done" job))

(defn start-workers
  "n workers draining jobs. Returns a channel that closes once every worker
  has seen jobs close and finished its last job."
  [n jobs]
  (a/merge
    (for [i (range n)]
      (a/thread
        (loop []
          (when-some [job (a/<!! jobs)]
            (try (handle job)
                 (catch Exception e (println "worker" i "failed:" (ex-message e))))
            (recur)))))))

(defn -main [& _]
  (jolt.host/block-sigint)                 ; before any thread starts
  (let [jobs  (a/chan 100)
        done  (start-workers 4 jobs)
        stop! (fn []
                (println "draining...")
                (a/close! jobs)            ; no new jobs; queued ones still run
                (a/<!! (a/into [] done))   ; wait for every worker
                (println "stopped"))]
    (jolt.host/add-shutdown-hook stop!)    ; ^C, SIGTERM, SIGHUP, System/exit
    (a/thread                              ; producer
      (loop [i 0]
        (when (a/>!! jobs i)               ; false once jobs is closed
          (Thread/sleep 50)
          (recur (inc i)))))
    (jolt.host/park-until-interrupt)))     ; never returns on a signal
```

For IO-bound jobs on sockets, make the workers `a/go-loop`s under
`*go-backend* :fiber` and keep the drain logic. The same shape with
`Executors/newFixedThreadPool` needs `.shutdown` + `.awaitTermination` in the hook.

## Actor example (ensemble)

A gen_server under a one-for-one supervisor; a crash restarts it with fresh state.

```clojure
(require '[ensemble.gen-server :as gs] '[ensemble.supervisor :as sup])

(defrecord Counter []
  gs/Server
  (init [_] [:ok 0])
  (handle-call [_ [op x] _from n]
    (case op
      :add  [:reply (+ n x) (+ n x)]
      :get  [:reply n n]
      :boom (throw (ex-info "boom" {}))))
  (handle-cast [_ _ n] [:noreply n])
  (handle-info [_ _ n] [:noreply n])
  (handle-timeout [_ n] [:noreply n])
  (terminate [_ _reason _n] nil))

(def tree (sup/start {:strategy :one-for-one :intensity 3 :period 5}
                     [{:id :counter
                       :start #(gs/start-link (->Counter) {:name :counter :trap true})}]))
(gs/call! :counter [:add 5])                        ;=> 5
(try (gs/call! :counter [:boom]) (catch Exception e (:reason (ex-data e))))
(gs/call! :counter [:get])                          ;=> 0, restarted
(sup/stop! tree)
```

A crash prints a report to `*err*`; `(ensemble.logger/set-handler! f)` routes them.

## Stream example (ebb)

```clojure
(require '[ebb.core :as m])

(defn ticks [ms]                         ; discrete flow 0, 1, 2, ...
  (m/ap (loop [i 0]
          (m/amb i (do (m/? (m/sleep ms)) (recur (inc i)))))))

(m/? (m/reduce conj []                   ; m/? runs a task, blocking or parking
       (m/eduction (map #(* % %)) (partition-all 2) (take 3) (ticks 5))))
;=> [[0 1] [4 9] [16 25]]

(defn fetch [x] (m/sleep (- 40 (* 10 x)) {:id x}))      ; any task
(m/? (m/reduce conj [] (m/ap (m/? (fetch (m/?> 4 (m/seed (range 4))))))))
;=> [{:id 3} {:id 2} {:id 1} {:id 0}]    4 in flight, completion order

(m/? (m/timeout (m/reduce conj [] (ticks 10)) 55 :deadline))  ;=> :deadline (stream cancelled)
```

## Built-ins in one screen (all verified)

```clojure
@(future (* 6 7))                         (deref (future (Thread/sleep 500)) 20 :timeout)
(future-cancel f)                         (let [p (promise)] (deliver p 1) @p)
(swap! a inc)  (dosync (alter r inc))     (send ag inc) (await ag)
(locking obj ...)                         (shutdown-agents)  ; at the end of a script using future/agents

(import '[java.util.concurrent Executors TimeUnit LinkedBlockingQueue CountDownLatch Semaphore
          ConcurrentHashMap CompletableFuture Callable])
(let [ex (Executors/newFixedThreadPool 4)]
  (.get (.submit ex ^Callable (fn [] 42))) (.shutdown ex) (.awaitTermination ex 1 TimeUnit/SECONDS))
(let [s (Executors/newScheduledThreadPool 1)
      h (.scheduleAtFixedRate s ^Runnable (fn [] (println :tick)) 0 10 TimeUnit/MILLISECONDS)]
  (.cancel h false) (.shutdownNow s))
```

Also present: `ArrayBlockingQueue`, `ConcurrentLinkedQueue`, `atomic.*`,
`locks.ReentrantLock`, `Thread/ofVirtual` / `Thread/startVirtualThread` (fibers),
`CompletableFuture` stages. On jolt 0.8.25 `Executors/newVirtualThreadPerTaskExecutor`
runs on a cached pool of daemon OS threads, not fibers.

## Gotchas

- A script that calls `future`/`pmap`/`send` sits for 60 s before exiting:
  end it with `(shutdown-agents)` (or run it as a task).
- Never block in a fiber or go-on-fiber body on files or FFI; wrap in `a/thread`.
- `fib/set-carrier-count!` / `a/*fiber-carrier-count*` are read once when the
  pool starts: set them before the first fiber. Use `alter-var-root`, not `binding`.
- A `go` body that throws closes its channel (reader sees `nil`) and prints the
  error to `*err*`; use `a/go-monitor` to get the throwable.
- ebb: don't deliver to a mailbox/dfv/rdv or run a task while holding a lock its
  receiver needs (deadlock); test cancellation with `m/cancelled?`.
- ensemble actors and ebb processes are fibers: same pinning rules; put a
  blocking driver on `(disp/define! :db {:size n})`.
- tapestry interruption only stops a body at an interruptible wait (sleep,
  deref, channel op); a CPU loop runs on, so check `(Thread/interrupted)`.
