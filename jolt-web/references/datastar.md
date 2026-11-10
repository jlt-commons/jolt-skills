# glimmer-datastar

Server side of the Datastar v1.0 wire protocol. Page state lives in
`glimmer.ratom` atoms; each open page holds an SSE stream that re-renders the
handler when a ratom it read changes and sends `datastar-patch-elements`.
Source: https://github.com/jolt-lang/glimmer-datastar. Working app:
https://github.com/jolt-lang/examples/tree/main/glimmer-datastar; large real app: https://github.com/yogthos/newsroom.

```clojure
;; brings glimmer, data.json, jolt-lang/time
jolt-lang/glimmer-datastar
{:git/url "https://github.com/jolt-lang/glimmer-datastar"
 :git/tag "<latest>" :git/sha "<sha>"}
```

Fill tags with `jdep OWNER/REPO` (jolt skill, deps-and-tasks.md).

The Datastar JS client is not included. Vendor the bundle into
`resources/public/js/datastar.js` and serve it with `(slurp (io/resource ...))`
so a built binary finds it (the example app reads it from a disk path instead).

## How a page works

1. `GET /` renders the full page. The root element carries `(ds/init-opts ...)`:
   `data-signals` (your signals + a per-tab id) and `data-init`, which opens
   `GET <same path>?datastar-sse=true&datastar-selector=...`.
2. That SSE request reaches your handler with `:jolt.datastar/sse-request` true.
   Return the fragment that goes *inside* the selector element. It is re-rendered
   at most once per `:tick-ms` after any ratom it dereffed changes.
3. Actions (`@get`/`@post` from `data-on:click`) arrive with the client's
   signals parsed into `:jolt.datastar/signals`. Change a ratom (all open pages
   update), and answer `{:status 204}` or `(ds/patch-signals {...})`.

## Example (verified: page, SSE frames before/after an action, patch-signals)

```clojure
(ns counter.core
  (:require [jolt.datastar.core :as ds]
            [jolt.datastar.html :as h]
            [glimmer.ratom :as ratom]
            [ring-chez.adapter :as adapter]
            [ring-chez.middleware.gzip :as gzip]))

(defonce state (ratom/atom {:count 0 :items []}))

(defn item-row [i] [:li {:id (str "item-" i)} "item " i])  ; component: cached, patched by id

(defn fragment []                                  ; contents of #app
  (let [{:keys [count items]} @state]
    [:div
     [:button {:data-on:click "@post('/inc')"} "+"]
     [:span#count count]
     [:ul (for [i items] [item-row i])]]))

(defn page []
  (str "<!DOCTYPE html>"
       (h/html
        [:html
         [:head [:script {:type "module" :src "/js/datastar.js"}]]
         [:body [:div#app (ds/init-opts {:selector "#app" :signals {:name ""}})
                 (fragment)]]])))

(defn app [{:keys [uri request-method] :jolt.datastar/keys [sse-request signals] :as req}]
  (cond
    (and sse-request (= uri "/")) {:status 200 :body (h/html (fragment))}
    (= uri "/") {:status 200 :headers {"Content-Type" "text/html"} :body (page)}
    (and (= uri "/inc") (= request-method :post))
    (do (ds/tx! req #(swap! state (fn [s] (-> s (update :count inc) (update :items conj (:count s))))))
        {:status 204})
    (= uri "/hello") (ds/patch-signals {:greeting (str "hi " (:name signals))})
    :else {:status 404 :body "not found"}))

(def handler (-> app (ds/wrap-datastar {:tick-ms 15}) gzip/wrap-gzip))  ; gzip outermost

(defn -main [& _]
  (jolt.host/block-sigint)
  (let [server (adapter/run-server handler {:port 3000 :strategy :fibers})]  ; one SSE per tab
    (jolt.host/add-shutdown-hook #(adapter/stop-server server))
    (jolt.host/park-until-interrupt)
    (adapter/stop-server server)))
```

Testing without a server, as the example app does:

```clojure
(let [sse (handler {:request-method :get :uri "/" :query-string "datastar-sse=true" :headers {}})]
  (async/<!! (:body sse))          ; "event: datastar-patch-elements\n...data: elements <div>..."
  (handler {:request-method :post :uri "/inc" :headers {"datastar-request" "true"}})
  (async/alts!! [(:body sse) (async/timeout 2000)])   ; next frame
  (async/close! (:body sse)))
```

Signals on a GET action come in the `datastar` query param as JSON
(`?datastar=%7B%22name%22%3A%22bob%22%7D`), on other methods in the JSON body.

## API (`jolt.datastar.core`)

- `(wrap-datastar handler opts)`: `:tick-ms` (15; `:rate-limit-ms` is the old
  name), `:render-threads` (2), `:batch-fn` `(fn [thunks])`, `:cache` (opts map or
  false), `:scheduler`, `:sse-param` ("datastar-sse"), `:component-patches` (true).
- `(init-opts {:signals m :selector "#id" :anti-forgery-token t})`: attribute map
  for the root element.
- `(patch-signals m)`: 200 JSON response that patches client signals.
- `(tx! req-or-scheduler thunk)`: run a write at the start of the next tick,
  before renders; returns a promise. A plain `swap!` also works.
- `(scheduler opts)`, `(stop! sched)`: a render loop shared with code outside
  requests (pass as `:scheduler`).
- `(cache-stats req-or-sched)`, `(patch-elements-event html selector [mode])`,
  `signal-name`, `signals-json`, `wrap-signals` (parse signals only).
- Request keys: `:jolt.datastar/signals`, `:jolt.datastar/sse-request`,
  `:jolt.datastar/selector`, `:jolt.datastar/tab-id`, `:jolt.datastar/scheduler`.

Signal names: `:foo/bar` is `foo_bar` on the wire; underscores in keyword names
are rejected; a dotted namespace becomes nesting.

## `jolt.datastar.html`

`(h/html hiccup)` renders `[:tag#id.class {attrs} & children]`, escapes strings
(`h/raw` opts out), splices seqs, renders `:style` maps as CSS and other map
attributes as JSON. A vector headed by a function, `[row item]`, is a component:
its HTML is cached by fn + args and shared across connections. A component
whose root has an `:id` is a part: when only parts changed, the stream sends just
those. Ids must be unique in the page. A component must depend only on its args
and the ratoms it reads. Hiccup's own `hiccup.core/html` also works (the example
app uses it), but without the cache or part patches.
