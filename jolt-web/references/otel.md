# otel (OpenTelemetry)

OpenTelemetry API + SDK for jolt: traces, metrics, logs; OTLP/HTTP export (JSON
encoding) over http/https; W3C trace-context propagation; runtime metrics from
Chez's collector; a `clojure.tools.logging` bridge. No gRPC.
Source: https://github.com/jolt-lang/otel (README covers samplers, exemplars,
runtime metrics, clocks).

```clojure
;; short form: url inferred from io.github, sha prefix + tag (as in the README)
io.github.jolt-lang/otel {:git/tag "<latest>" :git/sha "<sha>"}
```

Fill tags with `jdep OWNER/REPO` (jolt skill, deps-and-tasks.md). It brings http-client, jolt-crypto, logging, data.json and
jolt-lang/time at older pins; a top-level coordinate (same lib key) for any of
them wins. Add `io.github.jolt-lang/time` at the newest tag: otel's own time pin
fails to load on jolt 0.8.25.

## Setup

```clojure
(require '[otel.sdk :as sdk] '[otel.trace :as trace] '[otel.metrics :as metrics]
         '[otel.propagation :as propagation])

(def otel (sdk/init! {:service-name "notes"}))   ; once, in start!; reads OTEL_* env
(def tracer (sdk/tracer "notes.http"))
(def meter (sdk/meter "notes"))
;; in stop!, so batched spans are flushed:
(sdk/shutdown! otel)
```

`init!` options (env fallback): `:service-name` (`OTEL_SERVICE_NAME`),
`:endpoint` (`OTEL_EXPORTER_OTLP_ENDPOINT`, default `http://localhost:4318`),
`:headers`, `:sampler`, `:exporter` (`:otlp` default, `:console`, `:json`,
`:none`, or an exporter instance), `:processor` (`:batch`/`:simple`),
`:metrics?` (true), `:runtime-metrics?` (true), `:metric-interval-ms` (60000),
`:logs?` (false), `:bridge-logging?` (true), `:insecure?`.
`OTEL_SDK_DISABLED=true` installs nothing. Without `init!` every API call is a
no-op, so libraries can instrument unconditionally.

## Server middleware (verified with the memory exporter)

```clojure
(defn wrap-tracing [handler tracer]
  (let [requests (metrics/counter (sdk/meter "notes.http") "http.server.requests")]
    (fn [{:keys [request-method uri headers] :as req}]
      (let [parent (propagation/extract-context headers)]   ; incoming traceparent
        (trace/with-span [sp tracer (str (name request-method) " " uri)
                          {:kind :server :parent parent}]
          (let [resp (handler req)]
            (trace/set-attribute! sp :http.response.status_code (:status resp))
            (metrics/add! requests 1 {:route uri :status (:status resp)})
            resp))))))
```

`with-span` makes the span current, ends it, and on a throw records the
exception, sets status `:error` and rethrows. Nested spans become children.
Span fns: `set-attribute!`, `set-attributes!`, `add-event!`, `add-link!`,
`set-status!`, `update-name!`, `record-exception!`, `end!`; `current-span`,
`start-span` for manual control.

Outgoing calls: `(http/get url {:headers (propagation/inject-current {})})`.

Metrics: `counter`/`add!`, `up-down-counter`/`add-delta!`,
`histogram`/`record!`, `gauge`/`set-value!`, and `observable-counter`,
`observable-up-down-counter`, `observable-gauge` with a callback.

## Logs

```clojure
(sdk/init! {:service-name "notes" :logs? true})
(trace/with-span [sp tracer "work"] (log/info "inside span"))
```

The bridge wraps the existing tools.logging factory (stderr keeps working) and
adds trace/span ids to the exported record. With `:exporter :console` the run
printed both the stderr line and `INFO inside span trace=dbb5... span=5245...`.

## Tests

```clojure
(require '[otel.exporter.memory :as memory])
(let [exp (memory/exporter)
      otel (sdk/init! {:service-name "t" :exporter exp :processor :simple :metrics? false})]
  (app {:request-method :get :uri "/x"
        :headers {"traceparent" "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"}})
  (let [s (first (memory/spans exp))]
    [(:name s) (:parent-span-id s) (-> s :span-context :trace-id) (:attributes s)])
  ;; => ["get /x" "b7ad6b7169203331" "0af7651916cd43dd8448eb211c80319c" {"http.response.status_code" 200}]
  (sdk/shutdown! otel))
```

`memory/metric-exporter` + `memory/metrics`, `memory/log-exporter` +
`memory/records` do the same for the other signals.
