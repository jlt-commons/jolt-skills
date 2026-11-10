# Process lifetime, shutdown and app lifecycle

## When does a jolt process exit?

As on the JVM (jolt >= 0.8.16), measured with a 1 s background job and `-main`
returning at once:

| started from `-main` | exit waits? |
| --- | --- |
| `(.start (Thread. f))` | yes, until it finishes (inherits creator's daemon flag) |
| `(doto (Thread. f) (.setDaemon true) .start)` | no |
| `future`, `send`/`send-off`, `pmap` | yes, ~60 s pool keep-alive; `(shutdown-agents)` ends it |
| `Executors/newFixedThreadPool` etc. | yes, forever, until `.shutdown` |
| `a/thread`, `a/go`, `a/io-thread`, `jolt.fibers/spawn` | no (daemons) |
| ensemble actors, ebb `sp`/`ap`/`via`, tapestry fibers | no |

Exceptions: `jolt <task>` / `jolt run <task>` make futures and agents daemons
(babashka's rule); `System/exit`, `Runtime.halt` and an uncaught error end the
process at once (hooks still run on `System/exit`).

## Shutdown hooks and parking

```clojure
(jolt.host/add-shutdown-hook (fn [] ...))                       ; jolt form
(.addShutdownHook (Runtime/getRuntime) (Thread. (fn [] ...)))   ; JVM form, same registry
```

Hooks run once, in registration order, each isolated from the others' throws,
on: a normal end, `System/exit`, SIGINT, SIGTERM, SIGHUP. They run on a watcher
thread while your threads are still running, so a hook can drain them.

The server `-main`:

```clojure
(defn -main [& _]
  (jolt.host/block-sigint)            ; first, so threads started next inherit a blocked SIGINT
  (let [system (start!)]
    (jolt.host/add-shutdown-hook #(stop! system))
    (jolt.host/park-until-interrupt)))
```

`park-until-interrupt` does not return on a signal: hooks run, then the process
exits with 130 (SIGINT) or 143 (SIGTERM). Code placed after it never runs on
Ctrl-C. Verified with `kill -INT` / `kill -TERM` (under `bash -c 'set -m; ...'`;
a background job in a non-interactive shell ignores SIGINT, so test that way).
The main thread parked there also serves `jolt.host/call-on-main-thread` (UI
event loops).

## integrant (upstream `integrant/integrant`, latest Maven version)

Works unchanged. `halt!` runs in reverse dependency order, so the worker
component drains before the queue it reads is closed.

```clojure
(ns app.ig
  (:require [integrant.core :as ig]
            [clojure.core.async :as a]))

(def config
  {::jobs    {:size 16}
   ::workers {:n 3 :jobs (ig/ref ::jobs)}})

(defmethod ig/init-key ::jobs [_ {:keys [size]}] (a/chan size))
(defmethod ig/halt-key! ::jobs [_ ch] (a/close! ch))

(defmethod ig/init-key ::workers [_ {:keys [n jobs]}]
  {:jobs jobs
   :done (a/merge (for [_ (range n)]
                    (a/thread (loop [c 0] (if-some [_ (a/<!! jobs)] (recur (inc c)) c)))))})
(defmethod ig/halt-key! ::workers [_ {:keys [jobs done]}]
  (a/close! jobs)                                  ; drain, then wait
  (println :handled (reduce + (a/<!! (a/into [] done)))))

(defn -main [& _]
  (jolt.host/block-sigint)
  (let [system (ig/init config)]
    (jolt.host/add-shutdown-hook #(ig/halt! system))
    (dotimes [i 10] (a/>!! (::jobs system) i))
    (jolt.host/park-until-interrupt)))
```

On SIGTERM this prints `:handled 10` and exits 143.

## mount (upstream `mount/mount`, latest Maven version)

Upstream mount runs as is; no fork is needed. States start in namespace-load order and stop in reverse.

```clojure
(ns app.mnt
  (:require [mount.core :as mount :refer [defstate]]
            [clojure.core.async :as a]))

(defn start-workers [n jobs]
  (a/merge (for [_ (range n)]
             (a/thread (loop [c 0] (if-some [_ (a/<!! jobs)] (recur (inc c)) c))))))

(defstate jobs
  :start (a/chan 16)
  :stop  (a/close! jobs))

(defstate workers                       ; started after jobs, stopped before it
  :start (start-workers 2 jobs)
  :stop  (do (a/close! jobs)
             (println :handled (reduce + (a/<!! (a/into [] workers))))))

(defn -main [& _]
  (jolt.host/block-sigint)
  (mount/start)
  (jolt.host/add-shutdown-hook #(do (mount/stop) (println :stopped)))
  (dotimes [i 10] (a/>!! jobs i))
  (jolt.host/park-until-interrupt))
```

On SIGTERM: `:handled 10`, `:stopped`, exit 143.

## ensemble applications

`ensemble.application/start!` / `stop!` own an actor tree; register
`#(app/stop! :name)` as the hook. See ensemble.md.

## Scripts

A script (`jolt foo.clj`) that used `future`, `pmap` or agents lingers for the
60 s keep-alive after its last form: end it with `(shutdown-agents)`. An
executor it created must be `.shutdown`.
