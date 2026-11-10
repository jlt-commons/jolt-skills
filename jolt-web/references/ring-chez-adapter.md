# ring-chez-adapter

Ring HTTP/1.1 server over jolt's fd-level sockets (`jolt.socket.native`), no
java.net. Synchronous Ring handlers on a worker pool or on fibers. macOS, Linux,
Windows. Source: https://github.com/jolt-lang/ring-chez-adapter (README is long
and accurate; read it for edge cases).

```clojure
jolt-lang/ring-chez-adapter
{:git/url "https://github.com/jolt-lang/ring-chez-adapter"
 :git/tag "<latest>" :git/sha "<sha>"}
```

Fill tags with `jdep OWNER/REPO` (jolt skill, deps-and-tasks.md). Brings `jolt-lang/jolt-crypto` and `jolt-lang/multipart`
transitively. Needs jolt 0.8.22+.

## Namespaces

| ns | public fns |
|---|---|
| `ring-chez.adapter` | `run-server`, `stop-server`, `server-stats`, `swap-handler!`, `swap-ws-handler!` |
| `ring-chez.sse` | `event-response`, `format-event`, `send!` |
| `ring-chez.websocket` | `recv!`, `send!`, `send-binary!`, `close!` (session fns) |
| `ring-chez.fault` | `fault-handler` (ready-made `:on-failure`) |
| `ring-chez.middleware.multipart` | `wrap-multipart-params`, `multipart-params-request` |
| `ring-chez.middleware.static` | `wrap-static`, `file-response`, `new-cache` |
| `ring-chez.middleware.gzip` | `wrap-gzip`, `gzip-response`, `gzip-acceptable?` |
| `ring-chez.middleware.proxy` | `wrap-forwarded-remote-addr`, `forwarded-remote-addr` |
| `ring-chez.zlib` | `deflater`, `deflate-chunk!`, `deflate-finish!` |

## run-server options

`(adapter/run-server handler opts)` returns a handle map (`(:port handle)` is the
bound port). Options are validated before binding; a bad value throws with
`{:key :given :expected}` in `ex-data`, a taken port throws with
`:errno-name "EADDRINUSE"`.

| key | default | meaning |
|---|---|---|
| `:port` | 3000 | `0` = kernel picks |
| `:host` | `"127.0.0.1"` | IPv4/IPv6 literal or hostname (every address it resolves to is bound; `"localhost"` = `::1` + `127.0.0.1`) |
| `:strategy` | `:threads` | `:threads` (worker pool) or `:fibers` (core.async go per connection on one poll thread; idle connections pin no thread) |
| `:worker-threads` | cores | `:threads` only |
| `:keep-alive-timeout-ms` | 30000 | idle keep-alive, also websocket idle read |
| `:request-timeout-ms` | 60000 | time for a request to arrive; 408 past it; 0 disables |
| `:write-timeout-ms` | 30000 | slow reader drops the connection |
| `:max-request-bytes` | 1048576 | head + body; 413 past it. Bounds uploads too |
| `:max-header-bytes` | 8192 | 431 past it |
| `:handler-timeout-ms` | 0 (none) | handler deadline; answered via `:on-failure`, then 503. Costs ~15% on `:threads`, free on `:fibers` |
| `:handler-on-fiber` | false | `:fibers` only: run the handler on the connection fiber. Only for handlers that never block in FFI. Not combinable with `:handler-timeout-ms` |
| `:on-failure` | plain 500 | `(fn [req ex])` for handler throw, nil response, timeout, ws failures; return a response map to serve it. `(:ring-chez/failure req)` is `{:kind :crash|:nil-response|:timeout|:ws-guard|:ws-session|:stream}` |
| `:ws-handler` | none | `(fn [session])`, enables websocket upgrades |
| `:ws-guard` | none | `(fn [req])` before the 101: truthy non-map = accept, response map = serve it, nil = 403 |
| `:tls` | none | `{:cert-file "fullchain.pem" :key-file "privkey.pem"}` |
| `:reuse-port` | false | `SO_REUSEPORT` |

Running server:

```clojure
(adapter/server-stats s)    ; {:connections :active :requests :uptime-ms :faults :last-fault}
(adapter/swap-handler! s new-handler)          ; next request, open connections included
(adapter/stop-server s)                        ; stop accepting, drain up to 5 s, close all
(adapter/stop-server s {:drain-timeout-ms 0})  ; close now
```

`:faults` counts the server's own failures and should stay 0.

Request map extras: `:uri` is normalized (`//`, `.`, `..` resolved; raw value in
`:ring-chez/raw-uri`), `:remote-addr` is the peer, `:scheme :https` under TLS.
Repeated request headers are comma-joined into one value.

## Error handling

```clojure
(require '[ring-chez.fault :as fault])
(adapter/run-server handler {:on-failure (fault/fault-handler) :handler-timeout-ms 1000})
;; crash   -> 503 {"fault":"crash","elapsed-ms":0,"retryable":false}
;; timeout -> 503 {"fault":"timeout","elapsed-ms":1001,"retryable":true}
(fault/fault-handler {:status 500 :retryable? (constantly false)})
```

## Streaming responses

A core.async channel as `:body` is sent chunked; each value (String or byte
array) is one chunk; close the channel to end. When the client goes away the
channel is closed, so the producer's next put returns false. A value that
can't be framed (a map on a plain stream, a number) goes to `:on-failure`
with `:kind :stream` and ends the response.

```clojure
(require '[clojure.core.async :as async])
(fn [_]
  (let [ch (async/chan)]
    (async/go (async/>! ch "first\n") (async/>! ch "second\n") (async/close! ch))
    {:status 200 :headers {"Content-Type" "text/plain"} :body ch}))
```

## Server-Sent Events

Each channel value is one event: a map (`:data`, optional `:id`, `:event`,
`:retry`), formatted for you, or a string from `sse/format-event`. In a go block
put maps with `>!`; `sse/send!` formats and does a blocking put, so call it from
a thread, not a go block:

```clojure
(require '[ring-chez.sse :as sse])
(defn events [_]
  (let [ch (async/chan 8)]
    (async/thread
      (sse/send! ch {:id 1 :event "greet" :data "hello\nworld"})  ; false once the client left
      (sse/send! ch {:data "bye"})
      (async/close! ch))
    (sse/event-response ch)))   ; 200, text/event-stream, no-cache
;; wire: "id: 1\r\nevent: greet\r\ndata: hello\r\ndata: world\r\n\r\ndata: bye\r\n\r\n"
```

## WebSocket

```clojure
(require '[ring-chez.websocket :as ws])
(adapter/run-server handler
  {:port 3000
   :ws-guard (fn [req] (or (= "/ws" (:uri req)) {:status 404 :body "no"}))
   :ws-handler (fn [session]
                 (loop []
                   (let [m (ws/recv! session)]       ; blocks; answers pings
                     (when-not (= :close (:type m))
                       (ws/send! session (str "echo:" (:data m)))
                       (recur)))))})
```

- `recv!` returns `{:type :text :data s}`, `{:type :binary :data bytes}` or
  `{:type :close}` (peer close, timeout, protocol error).
- `send!` text, `send-binary!` bytes, `close!` `[session]`, `[session code]`,
  `[session code reason]`; all return false once the peer is gone.
- `(:request session)` is the upgrade request. The session runs on a worker
  thread; returning from the fn closes the connection.
- Limits: 1 MiB per frame, 8 MiB per message.
- The handshake does its own SHA-1; websockets don't need `jolt.crypto` or
  OpenSSL.

A client for tests: `babashka.http-client.websocket` over jolt-lang/http-client
(see [http-client.md](http-client.md)).

## TLS

```clojure
(adapter/run-server handler {:port 8443 :tls {:cert-file "cert.pem" :key-file "key.pem"}})
```

PEM files, chain leaf first. Missing files or a mismatched key throw at start.
TLS needs OpenSSL 3 at runtime (a plain-HTTP server starts without it) (Homebrew `openssl@3` on macOS, `libssl.so.3` on
Linux). TLS 1.2 minimum; no client certs, no SNI with several certs, no ALPN
(HTTP/1.1 only). Certificate change needs a restart. Throw-away cert for local use:

```bash
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout key.pem -out cert.pem -days 30 -subj /CN=localhost
```

## Middleware

```clojure
(require '[ring-chez.middleware.multipart :as multipart]
         '[ring-chez.middleware.static :as static]
         '[ring-chez.middleware.gzip :as gzip]
         '[ring-chez.middleware.proxy :as proxy])

(-> handler
    multipart/wrap-multipart-params                       ; :multipart-params, merged into :params
    (static/wrap-static "public" {:prefix "/assets"})     ; disk dir, cached, ETag/304
    (proxy/wrap-forwarded-remote-addr {:trust-proxy 1})   ; X-Forwarded-For, counted from the right
    gzip/wrap-gzip)                                       ; outermost
```

- Multipart: a text field is a string; an upload is
  `{:filename :content-type :bytes :size}`; repeated names become a vector.
  Buffered in memory, so `:max-request-bytes` bounds uploads.
  `curl -F title=Hi -F file=@up.bin` gives `(get multipart-params "file")`.
- `wrap-static` opts: `:prefix`, `:index-files?` (true), `:cache-control`,
  `:max-cache-file-bytes` (1 MiB; larger files stream from disk), `:gzip?`.
  Misses, unsafe paths and non-GET/HEAD fall through to the handler. It reads
  the filesystem only, not resources embedded in a binary.
- `wrap-gzip` opts: `:min-size` (1024), `:level`, `:types`, `:stream?` (true:
  channel bodies such as SSE are compressed as one stream with sync flushes),
  `:window-bits`, `:mem-level`. No-op where zlib can't be bound.
- `:trust-proxy n` must match the real number of proxies you run.

Ring's own params, cookies, session, ring-defaults run unchanged (see
[jvm-libs.md](jvm-libs.md)).

## Tuning `:fibers`

```clojure
(alter-var-root #'clojure.core.async/*fiber-carrier-count* (constantly 4))  ; before run-server
```

Fewer carriers help cheap non-blocking handlers. A blocking FFI call (a DB
driver) inside a `:handler-on-fiber` handler stalls its carrier; wrap it in
`async/thread` and take the result.
