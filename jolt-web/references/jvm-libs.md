# JVM Clojure libraries for web apps

Pure-Clojure libraries load from git or Maven jars unchanged. All snippets here
were run on jolt 0.8.25. Fill tags with `jdep OWNER/REPO` (jolt skill,
deps-and-tasks.md); it skips pre-release tags such as hiccup's `2.0.0-alpha*`.

```clojure
ring/ring-core {:mvn/version "<latest>"}
weavejester/hiccup {:git/url "https://github.com/weavejester/hiccup"
                    :git/tag "<latest>" :git/sha "<sha>"}
selmer/selmer {:git/url "https://github.com/yogthos/Selmer"
               :git/tag "<latest>" :git/sha "<sha>"}
metosin/malli {:git/url "https://github.com/metosin/malli"
               :git/tag "<latest>" :git/sha "<sha>"}
;; Selmer and malli.transform need java.time.format:
io.github.jolt-lang/time {:git/url "https://github.com/jolt-lang/time"
                          :git/tag "<latest>" :git/sha "<sha>"}
```

Without `jolt-lang/time`, malli.transform fails with `No matching ctor found for
class DateTimeFormatterBuilder`, and `jolt build` of a Selmer app fails with `No
dependency provides java.time.format.FormatStyle`.

## ring-core

`ring.middleware.params`, `keyword-params`, `cookies`, `session`, `content-type`,
`not-modified`, `ring.util.response` work. Exceptions:
- `ring.middleware.multipart-params` (commons-fileupload): use
  `ring-chez.middleware.multipart`.
- session cookie store, anti-forgery: have `jolt-lang/jolt-crypto` and
  `jolt-lang/time` as deps; the classes autoload.
- `ring.middleware.resource`: newsroom serves assets with `io/resource` itself
  because Ring's resource middleware doesn't reach resources baked into a binary.
  reitit's `create-resource-handler` does (verified).
- ring-json / muuntaja (cheshire, Jackson): write a 10-line middleware on
  `clojure.data.json` (see SKILL.md `wrap-json-body`).

ring-defaults (latest, 0.7+) works (examples/ring-app) with
`(assoc-in site-defaults [:params :multipart] false)`: GET 200, a POST without
a CSRF token 403. 0.5.0 and older fail on commons-codec (`Base64/encodeBase64`).

## hiccup

```clojure
(require '[hiccup2.core :as h])
(str "<!DOCTYPE html>" (h/html [:ul (for [x ["a" "<b>"]] [:li x])]))   ; strings escaped
(h/raw "<b>trusted</b>")
```

`hiccup2.core/html` returns a RawString; `str` it for the body.
`hiccup.core/html` (1.x API, no escaping) also loads.

## Selmer

```clojure
(require '[selmer.parser :as s])
(s/render "{{x}}" {:x "<i>"})                          ; "&lt;i&gt;"
(s/render-file "templates/list.html" {:title "Notes" :notes [{:title "a<b"}]})
;; resources/templates/list.html, found via io/resource (also in a built binary)
```

jolt prints a warning that Selmer's `:deps/prep-lib` step is not run; harmless.
In dev, call `(selmer.parser/cache-off!)` to re-read edited templates.

## malli (request validation)

```clojure
(require '[malli.core :as m] '[malli.error :as me] '[malli.transform :as mt])
(def NewNote [:map [:title [:string {:min 1}]] [:body :string]])
(m/validate NewNote {:title "a" :body "b"})                ; true
(me/humanize (m/explain NewNote {:title ""}))
;; {:title ["should be at least 1 character"], :body ["missing required key"]}
(m/decode [:map [:n :int]] {:n "5"} mt/string-transformer) ; {:n 5}, query params
```

Compile a validator once for hot paths: `(def valid-note? (m/validator NewNote))`.

## Not on jolt

Jetty, http-kit, Aleph, Undertow (servers); cheshire, jsonista (JSON);
clj-http (Apache HttpClient); buddy-hashers (BouncyCastle). Use the jolt
libraries in the SKILL.md table instead.
