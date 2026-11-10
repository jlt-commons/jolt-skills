# router (reitit on jolt)

reitit-core's matcher is a Java class, `reitit.Trie`. `jolt-lang/router`
reimplements it in Clojure (`reitit.trie-jolt`) and declares that class in
`:jolt/provides`, so reitit-core and reitit-ring load unmodified from git and
the trie loads on first reference.
Source: https://github.com/jolt-lang/router

```clojure
;; router's deps.edn brings reitit-core + meta-merge.
jolt-lang/router
{:git/url "https://github.com/jolt-lang/router"
 :git/tag "<latest>" :git/sha "<sha>"}
;; optional, for ring-handler/ring-router. Keep the same reitit sha router uses
;; (see `jolt -Stree`), or reitit-core and reitit-ring will disagree.
metosin/reitit-ring
{:git/url "https://github.com/metosin/reitit"
 :git/sha "<reitit sha from router's deps.edn>"
 :deps/root "modules/reitit-ring"}
```

Fill tags with `jdep OWNER/REPO` (jolt skill, deps-and-tasks.md).

Nothing to require first: `:clj` is a default reader feature and the
`reitit.Trie` declaration autoloads `reitit.trie-jolt`. Older examples that
`(require 'reitit.trie-jolt)` or call `__reader-features-set!` still work; neither
is needed.

## reitit-ring (preferred for apps)

```clojure
(require '[reitit.ring :as rr]
         '[ring.middleware.params :refer [wrap-params]])   ; ring-core

(defn wrap-auth [h]
  (fn [req] (if (get-in req [:headers "authorization"]) (h req) {:status 401 :body "no"})))

(def app
  (rr/ring-handler
   (rr/router
    [["/api" {:middleware [wrap-auth]}            ; route-data middleware, inherited
      ["/me" {:get {:handler (fn [_] {:status 200 :body "me"})}}]
      ["/x/:id" {:get (fn [r] {:status 200 :body (-> r :path-params :id)})}]]])
   (rr/routes
    (rr/create-resource-handler {:path "/"})       ; resources/public
    (rr/create-default-handler                     ; 404 / 405 / 406
     {:not-found (constantly {:status 404 :body "nope"})}))
   {:middleware [wrap-params]}))                   ; top-level, runs for every request
```

Verified on jolt 0.8.25: path params, 405 for a wrong method, route-level and
top-level `:middleware`, `create-default-handler` options, and
`create-resource-handler` serving from resources embedded by `jolt build`.

## reitit-core only

Match and dispatch yourself (what examples/ring-app does):

```clojure
(require '[reitit.core :as r])

(def router
  (r/router [["/api/users"     ::users]
             ["/api/users/:id" ::user]
             ["/files/*path"   ::files]]))

(r/match-by-path router "/files/a/b.txt")       ; Match, :path-params {:path "a/b.txt"}
(r/match->path (r/match-by-name router ::user {:id 42}))   ; "/api/users/42"
(map first (r/routes router))                    ; ("/api/users" "/api/users/:id" "/files/*path")

(defn handler [{:keys [request-method uri] :as req}]
  (if-let [m (r/match-by-path router uri)]
    (if-let [h (get (:data m) request-method)]
      (h (assoc req :path-params (:path-params m)))
      {:status 405 :body "method not allowed"})
    {:status 404 :body "not found"}))
```

(Here route data must be maps like `{:get handler}` for that dispatch.)

Other reitit modules (coercion, malli, swagger) were not tested here; they are
pure Clojure but may reach for JVM classes. Try them in `jolt -e` before
depending on them.
