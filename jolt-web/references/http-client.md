# http-client

The JVM networking classes Clojure HTTP clients use (`java.net.URL`,
`HttpURLConnection`, `java.net.http.HttpClient`, `WebSocket`, `javax.net.ssl`)
implemented over BSD sockets + OpenSSL via `jolt.ffi`. clj-http-lite runs on it
as `jolt.http-client`; babashka.http-client runs unmodified from Maven.
Source: https://github.com/jolt-lang/http-client (README has the full option list).

```clojure
;; needs jolt 0.8.25+, OpenSSL 3 for https
jolt-lang/http-client
{:git/url "https://github.com/jolt-lang/http-client"
 :git/tag "<latest>" :git/sha "<sha>"}
```

Fill tags with `jdep OWNER/REPO` (jolt skill, deps-and-tasks.md). It brings jolt-crypto as `jolt-lang/jolt-crypto`.

## jolt.http-client (clj-http-lite API)

`get head post put patch delete` take `(url & [req])`; `request` takes a map
with `:method :url`. Response: `{:status :headers :body}`, headers keyed by
lowercase strings.

```clojure
(require '[jolt.http-client :as http] '[clojure.data.json :as json])

(http/get "https://example.com" {:conn-timeout 5000 :socket-timeout 10000})
(http/get url {:query-params {:a 1}})                         ; ?a=1
(http/post url {:body (json/write-str {:a 1}) :content-type :json})
(http/post url {:form-params {:a "b c"}})                     ; a=b+c, urlencoded
(http/post url {:multipart [{:name "title" :content "Hi"}
                            {:name "photo" :content (io/file "beach.png")}]})
(http/get url {:headers {:authorization "Bearer t"} :basic-auth {:user "u" :pass "p"}})
(http/get url {:as :byte-array})                              ; or :as :bytes, :as :stream
@(http/get url {:async true})                                 ; a future
```

Non-2xx throws `ex-info` with the response in `ex-data` (`(:status (ex-data e))`);
pass `:throw false` (or `:throw-exceptions false`) to get it back instead.

Timeouts are off unless given. `:conn-timeout` bounds each connect,
`:socket-timeout` each read. For a total cap on a body that keeps trickling:
`(jolt.http.platform/set-max-response-ms! ms)` (process-wide).

`:as :stream` returns as soon as headers arrive (SSE, LLM token streams). Read
it with `.readLine` on a `BufferedReader`, not `line-seq` (which reads to the
end on jolt), and `.close` it if you stop early so the connection is released.

Connections are pooled per origin. Knobs (process-wide atoms):
`jolt.http.core/pool-enabled?`, `pool-idle-ms`, `pool-max-per-key`, and
`(jolt.http.core/pool-clear!)`.

Verified on jolt 0.8.25 against a local ring-chez server: get with
query-params, JSON post, form post, 404 throwing and `:throw false`, timeouts,
`:async`, `:as :byte-array`; and `https://example.com`.

## babashka.http-client

```clojure
;; deps: org.babashka/http-client {:mvn/version "<latest>"}
(require '[jolt.http.platform])                  ; installs the shims
(require '[babashka.http-client :as bb])
(bb/get "https://example.com" {:query-params {"q" "jolt"}})
```

Client options honoured: `:proxy`, `:cookie-handler`, `:ssl-context`
(`{:insecure true}` or PKCS#12 stores), `:authenticator`, `:follow-redirects`,
`:connect-timeout`. No HTTP/2 (accepted, sent as HTTP/1.1).

## Websocket client

Useful for testing a ring-chez `:ws-handler` (verified):

```clojure
;; deps: org.babashka/http-client {:mvn/version "<latest>"}
(require '[jolt.http.platform] '[babashka.http-client.websocket :as client])
(let [got (promise)
      sock (client/websocket {:uri "ws://127.0.0.1:3000/ws"
                              :on-message (fn [_ws data _last?] (deliver got (str data)))})]
  (client/send! sock "hi")
  (deref got 3000 :timeout)
  (client/close! sock))
```

## Propagating traces

With otel: `(http/get url {:headers (otel.propagation/inject-current {})})`
sends `traceparent` for the current span (see [otel.md](otel.md)).
