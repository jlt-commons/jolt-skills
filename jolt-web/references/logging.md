# logging (clojure.tools.logging)

Port of `org.clojure/tools.logging` with one backend: stderr, `:info` and above.
Use the real coordinate name so libraries that depend on tools.logging get this.
Source: https://github.com/jolt-lang/logging

```clojure
org.clojure/tools.logging
{:git/url "https://github.com/jolt-lang/logging"
 :git/tag "<latest>" :git/sha "<sha>"}
```

Fill tags with `jdep jolt-lang/logging` (jolt skill, deps-and-tasks.md). Keep the `org.clojure/tools.logging` key.

```clojure
(require '[clojure.tools.logging :as log] '[clojure.tools.logging.impl :as impl])

(log/info "started" {:port 3000})        ; INFO user - started {:port 3000}
(log/infof "port %d" 3000)
(log/error ex "failed")                  ; ERROR user - failed clojure.lang.ExceptionInfo: boom {:a 1}
(log/enabled? :debug)                    ; false

;; threshold (default :info)
(alter-var-root #'impl/*level* (constantly :debug))

;; your own backend: any LoggerFactory
(alter-var-root #'log/*logger-factory*
  (constantly
   (reify impl/LoggerFactory
     (name [_] "edn")
     (get-logger [_ logger-ns]
       (reify impl/Logger
         (enabled? [_ level] true)
         (write! [_ level throwable msg]
           (binding [*out* *err*] (prn {:level level :ns (str logger-ns) :msg msg}))))))))
```

All verified on jolt 0.8.25. Also available: `trace debug warn fatal`, the `f`
variants, `logp`, `logf`, `spy`, `spyf`, `with-logs`, `log-capture!`. There is
no slf4j/log4j/logback; the `clojure.tools.logging.factory` system property is
ignored. For OTLP export of log lines see [otel.md](otel.md) (`:logs? true`).
