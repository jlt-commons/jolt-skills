# mulog

BrunoBonacci/mulog 0.9.0 with its Java classes (`Flake`, thread-local context,
timer pool) supplied as jolt shims. Flakes are bit-compatible with the JVM.
Source: https://github.com/jlt-commons/mulog (its README says
`github.com/jolt-lang/mulog`, which redirects here). No tags: pin HEAD's sha
(`jdep jlt-commons/mulog`, jolt skill, deps-and-tasks.md).

```clojure
com.brunobonacci/mulog
{:git/url "https://github.com/jlt-commons/mulog"
 :git/sha "<sha>"}
```

```clojure
(require '[com.brunobonacci.mulog :as u])

(def stop (u/start-publisher! {:type :console}))   ; returns a stop fn
(u/set-global-context! {:app "notes" :env "dev"})
(u/log ::user-login :user "ada")
(u/with-context {:request-id 7}
  (u/log ::step :n 1))
;; {:request-id 7, :mulog/trace-id #mulog/flake "5DP-...", :mulog/timestamp 1794263105508,
;;  :mulog/event-name :libs-check/step, :mulog/namespace "libs-check", :n 1}
(stop)
```

Verified: `:console` publisher, `log`, `with-context`. Events are published
asynchronously (default delay ~1 s), so call the stop fn before exiting.

Publishers in the source: `:console`, `:console-json`, `:simple-file`
(`{:type :simple-file :filename "..."}`), `:file-json`, `:multi`, `:inline`
(a `PPublisher` reify, used by the tests), `:custom`. Others (`:elasticsearch`,
`:jvm-metrics`, cloud publishers) need JVM libraries and won't load.
Also: `trace` (macro, times a body as an event), `update-global-context!`,
`local-context`, `global-context`.

Per-request context middleware:

```clojure
(defn wrap-mulog [handler]
  (fn [{:keys [request-method uri] :as req}]
    (u/with-context {:uri uri :method request-method}
      (u/trace ::http-request [] (handler req)))))
```
