---
name: jolt-web
description: "Build HTTP servers, JSON APIs and server-rendered or hypermedia web apps on Jolt (Clojure on Chez Scheme, no JVM). Use when the user wants a web server, REST/JSON API, HTML pages, SSE, websockets, file uploads, TLS, outbound HTTP calls, Datastar live pages, request validation, logging or tracing in a jolt project; or mentions ring-chez-adapter (`ring-chez.adapter/run-server`), jolt-lang/router or reitit on jolt, jolt-lang/http-client (`jolt.http-client`), glimmer-datastar (`jolt.datastar.core`), jolt-lang/multipart, transit-jolt, jolt-lang/logging (`clojure.tools.logging`), jolt-lang/otel, mulog, jolt-lang/crypto, or ring-core, hiccup, Selmer or malli on jolt."
---

# Jolt web apps

Ring is the model and `ring-chez.adapter/run-server` the server. Pure-Clojure
Ring middleware, reitit, hiccup, Selmer and malli run unchanged. Anything on a
JVM library (Jetty, http-kit, commons-fileupload, cheshire, ring-json) does not;
this stack replaces those.

Read the `jolt` skill first (layout, deps, tasks, `jolt build`, REPL). Databases
are the `jolt-data` skill; here there is only a hook point for one.

## Which library for which job

| Job | Use | Reference |
|---|---|---|
| HTTP/1.1 server, streaming, SSE, websockets, TLS, gzip, static files, multipart | `jolt-lang/ring-chez-adapter` | [ring-chez-adapter.md](references/ring-chez-adapter.md) |
| Routing | `jolt-lang/router` (makes reitit-core load) + `reitit-ring` | [router.md](references/router.md) |
| Live hypermedia pages over SSE | `jolt-lang/glimmer-datastar` | [datastar.md](references/datastar.md) |
| Outbound HTTP (clj-http-lite API, babashka.http-client, websocket client) | `jolt-lang/http-client` | [http-client.md](references/http-client.md) |
| Parsing multipart / urlencoded bodies yourself | `jolt-lang/multipart` | [multipart.md](references/multipart.md) |
| Transit-JSON on the wire | `jolt-lang/transit-jolt` | [transit.md](references/transit.md) |
| Logging (`clojure.tools.logging` API, stderr) | `jolt-lang/logging` | [logging.md](references/logging.md) |
| Structured events | `jlt-commons/mulog` | [mulog.md](references/mulog.md) |
| Traces, metrics, logs over OTLP/HTTP | `jolt-lang/otel` | [otel.md](references/otel.md) |
| SHA-256, HMAC, AES, signatures, cert parsing | `jolt-lang/crypto` | [crypto.md](references/crypto.md) |
| HTML: hiccup, Selmer; params/cookies/session: ring-core; validation: malli | JVM libs from git/Maven | [jvm-libs.md](references/jvm-libs.md) |
| JSON | built-in `clojure.data.json` | — |

## deps.edn

Fill each `<latest>`/`<sha>` with the newest tag: `jdep OWNER/REPO` (the
`jolt` skill's references/deps-and-tasks.md, "Depending on a library: use the
latest tag"). Never copy a sha from docs or memory. Each reference file has its
library's coordinate.

```clojure
{:jolt/min-version "0.8.25"
 :paths ["src" "resources"]
 :deps {jolt-lang/ring-chez-adapter
        {:git/url "https://github.com/jolt-lang/ring-chez-adapter"
         :git/tag "<latest>" :git/sha "<sha>"}
        ;; brings reitit-core + meta-merge; reitit-ring at the same reitit sha
        ;; router's deps.edn uses (see `jolt -Stree`)
        jolt-lang/router
        {:git/url "https://github.com/jolt-lang/router"
         :git/tag "<latest>" :git/sha "<sha>"}
        metosin/reitit-ring
        {:git/url "https://github.com/metosin/reitit"
         :git/sha "<reitit sha from router's deps.edn>"
         :deps/root "modules/reitit-ring"}
        ring/ring-core {:mvn/version "<latest>"}
        weavejester/hiccup
        {:git/url "https://github.com/weavejester/hiccup"
         :git/tag "<latest>" :git/sha "<sha>"}
        metosin/malli
        {:git/url "https://github.com/metosin/malli"
         :git/tag "<latest>" :git/sha "<sha>"}
        ;; java.time.format classes: malli.transform, Selmer, data.json need them
        io.github.jolt-lang/time
        {:git/url "https://github.com/jolt-lang/time"
         :git/tag "<latest>" :git/sha "<sha>"}
        org.clojure/tools.logging
        {:git/url "https://github.com/jolt-lang/logging"
         :git/tag "<latest>" :git/sha "<sha>"}}
 :jolt/build {:embed ["resources"]}
 :aliases {:test {:extra-paths ["test"] :main-opts ["-m" "notes.test-runner"]}}
 :tasks {serve {:doc "run the server" :main-opts ["-m" "notes.core"]}
         test  {:doc "run the tests" :task (jolt "-M:test")}
         dist  {:doc "build the binary"
                :task (shell "jolt" "build" "-m" "notes.core" "-o" "target/notes")}}}
```

## Skeleton: JSON API + HTML page

`src/notes/db.clj`, the storage hook point (replace the atom with a real
store from the `jolt-data` skill; handlers only call these fns):

```clojure
(ns notes.db)
(defn open [_config] (atom {:next-id 1 :notes (sorted-map)}))
(defn close [_db] nil)
(defn list-notes [db] (vec (vals (:notes @db))))
(defn add-note! [db note]
  (let [s (swap! db (fn [{:keys [next-id] :as s}]
                      (-> s (assoc-in [:notes next-id] (assoc note :id next-id))
                            (update :next-id inc))))]
    (get-in s [:notes (dec (:next-id s))])))
```

`src/notes/web.clj`:

```clojure
(ns notes.web
  (:require [reitit.ring :as rr]
            [ring.middleware.params :refer [wrap-params]]
            [ring.middleware.keyword-params :refer [wrap-keyword-params]]
            [clojure.data.json :as json]
            [clojure.tools.logging :as log]
            [hiccup2.core :as h]
            [malli.core :as m]
            [malli.error :as me]
            [notes.db :as db]))

(def NewNote [:map [:title [:string {:min 1}]] [:body :string]])

(defn json-response [status data]
  {:status status :headers {"Content-Type" "application/json; charset=utf-8"}
   :body (json/write-str data)})

(defn html-response [hiccup]
  {:status 200 :headers {"Content-Type" "text/html; charset=utf-8"}
   :body (str "<!DOCTYPE html>" (h/html hiccup))})

(defn wrap-json-body [handler]          ; ring-json needs cheshire: write your own
  (fn [{:keys [headers body] :as req}]
    (if (and body (some-> (get headers "content-type") (.startsWith "application/json")))
      (let [parsed (try (json/read-str (slurp body) :key-fn keyword) (catch Exception _ ::bad))]
        (if (= parsed ::bad)
          (json-response 400 {:error "malformed JSON"})
          (handler (assoc req :body-params parsed))))
      (handler req))))

(defn wrap-log [handler]
  (fn [{:keys [request-method uri] :as req}]
    (let [resp (handler req)]
      (log/info (name request-method) uri (:status resp))
      resp)))

(defn wrap-db [handler db] (fn [req] (handler (assoc req :db db))))

(defn list-notes [{:keys [db]}] (json-response 200 (db/list-notes db)))

(defn create-note [{:keys [db body-params]}]
  (if (m/validate NewNote body-params)
    (json-response 201 (db/add-note! db (select-keys body-params [:title :body])))
    (json-response 422 {:errors (me/humanize (m/explain NewNote body-params))})))

(defn index-page [{:keys [db]}]
  (html-response
   [:html [:head [:meta {:charset "utf-8"}] [:title "Notes"]
           [:link {:rel "stylesheet" :href "/css/style.css"}]]
    [:body [:h1 "Notes"]
     [:ul (for [{:keys [id title]} (db/list-notes db)] [:li {:id (str "n" id)} title])]]]))

(defn app [db]
  (rr/ring-handler
   (rr/router [["/" {:get index-page}]
               ["/api/notes" {:get list-notes :post create-note}]])
   (rr/routes (rr/create-resource-handler {:path "/"})  ; resources/public, also from a built binary
              (rr/create-default-handler))              ; 404 / 405 / 406
   {:middleware [wrap-log [wrap-db db] wrap-params wrap-keyword-params wrap-json-body]}))
```

`src/notes/core.clj`, start/stop and `-main`:

```clojure
(ns notes.core
  (:require [clojure.tools.logging :as log]
            [ring-chez.adapter :as adapter]
            [notes.db :as db]
            [notes.web :as web]))

(defonce system (atom nil))

(defn start! [{:keys [port] :or {port 3000} :as config}]
  (let [db (db/open config)
        server (adapter/run-server (web/app db)
                                   {:port port
                                    :on-failure (fn [_req ex] (log/error ex "handler failed")
                                                  {:status 500 :body "internal error"})})]
    (reset! system {:db db :server server})
    (log/info "listening on port" (:port server))
    @system))

(defn stop! []
  (when-let [{:keys [db server]} @system]
    (adapter/stop-server server)        ; stops accepting, drains in-flight (5 s cap)
    (db/close db)
    (reset! system nil)))

(defn -main [& _]
  (jolt.host/block-sigint)
  (start! {:port (or (some-> (System/getenv "PORT") parse-long) 3000)})
  (jolt.host/add-shutdown-hook stop!)
  (jolt.host/park-until-interrupt)      ; threads are daemons: -main must not return
  (stop!))
```

`test/notes/web_test.clj` calls the handler directly, no server or port:

```clojure
(ns notes.web-test
  (:require [clojure.test :refer [deftest is testing]]
            [clojure.data.json :as json]
            [notes.db :as db]
            [notes.web :as web]))

(defn- json-req [method uri body]
  {:request-method method :uri uri :headers {"content-type" "application/json"}
   :body (java.io.ByteArrayInputStream. (.getBytes (json/write-str body) "UTF-8"))})

(deftest api
  (let [app (web/app (db/open {}))]
    (testing "create + list"
      (is (= 201 (:status (app (json-req :post "/api/notes" {:title "hi" :body "there"})))))
      (is (= 1 (count (json/read-str (:body (app {:request-method :get :uri "/api/notes"})))))))
    (testing "validation" (is (= 422 (:status (app (json-req :post "/api/notes" {:title ""}))))))
    (testing "html + 404"
      (is (re-find #"<li id=\"n1\">hi</li>" (:body (app {:request-method :get :uri "/"}))))
      (is (= 404 (:status (app {:request-method :get :uri "/nope"})))))))
```

With the `jolt` skill's test runner as `notes.test-runner`:

```bash
jolt test                       # handler tests
PORT=3917 jolt serve            # curl localhost:3917/api/notes; Ctrl-C stops cleanly
jolt dist && ./target/notes     # ~56 MB binary, resources/ embedded
```

## Gotchas

- Header keys in requests are lowercase strings (`(get headers "content-type")`).
  `:body` is an `InputStream` or nil; `slurp` it once. Response bodies may be a
  String, bytes, `File`, `InputStream`, seq, or a core.async channel (streamed).
- `run-server` binds `127.0.0.1`; pass `:host "0.0.0.0"` to serve the network.
  `:port 0` picks a free port: read `(:port server)`.
- jolt-lang/router declares `reitit.Trie` in `:jolt/provides`, so reitit loads
  its matcher on first use; no `(require 'reitit.trie-jolt)` needed (an explicit
  one is harmless).
- Resources in a built binary: `io/resource` and reitit's `create-resource-handler`
  see the embedded copies. `ring-chez.middleware.static/wrap-static` and
  `(slurp "resources/...")` read the disk and won't.
- ring-chez-adapter brings jolt-crypto, whose OpenSSL natives are `:optional`:
  OpenSSL 3 is opened at startup when present, and a server that never uses
  TLS, sessions/CSRF or `javax.crypto` also starts on a host without it (crypto
  calls then fail at first use). TLS needs OpenSSL. If another dep (e.g.
  http-client, otel) pins an older crypto, add a top-level `jolt-lang/jolt-crypto`
  at the newest tag (see [crypto.md](references/crypto.md)).
- Uploads: `ring-chez.middleware.multipart`, never ring's (commons-fileupload).
  ring-defaults (latest) works with `jolt-lang/jolt-crypto` and `jolt-lang/time`
  as deps (their classes autoload) and `[:params :multipart] false`; 0.5.0 and
  older pull an anti-forgery that calls commons-codec and fails.
- malli.transform, Selmer and data.json from git need `io.github.jolt-lang/time`
  (java.time.format); keep it at the newest tag at top level, since some
  libraries (otel) still pin an older time that fails to load on jolt 0.8.25.
- Handlers run on a worker pool (`:threads`, one worker per busy connection);
  for many idle keep-alive or SSE connections use `:strategy :fibers`. A handler
  that never returns holds a worker: set `:handler-timeout-ms` or time out
  outbound calls.
- SSE channel values are event maps (formatted for you) or strings from
  `ring-chez.sse/format-event` (see [ring-chez-adapter.md](references/ring-chez-adapter.md)).
