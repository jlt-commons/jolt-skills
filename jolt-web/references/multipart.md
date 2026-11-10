# multipart

RFC 7578 `multipart/form-data` parser in pure Clojure (port of defnull/multipart).
`ring-chez.middleware.multipart` is built on it, so in a Ring app you normally
use that middleware (see [ring-chez-adapter.md](ring-chez-adapter.md)) and never
require this directly. Use it to stream a body or to read part headers the Ring
shape drops. Source: https://github.com/jolt-lang/multipart

```clojure
;; ring-chez-adapter already brings it.
jolt-lang/multipart
{:git/url "https://github.com/jolt-lang/multipart"
 :git/tag "<latest>" :git/sha "<sha>"}
```

Fill tags with `jdep OWNER/REPO` (jolt skill, deps-and-tasks.md).

`multipart.core` re-exports everything.

```clojure
(require '[multipart.core :as mp])

;; :body is a byte array, an InputStream or a read-fn
(mp/parse-form-data {:headers {"content-type" "multipart/form-data; boundary=b"} :body body})
;; => {:params {"user" "alice"}
;;     :files {"file" {:name "file" :filename "a.txt" :content-type "text/plain"
;;                     :charset nil :headerlist [...] :bytes #bytes ...}}}

;; urlencoded bodies too
(mp/parse-form-data {:headers {"content-type" "application/x-www-form-urlencoded"}
                     :body (.getBytes "a=1&b=x%20y" "UTF-8")})
;; => {:params {"a" "1", "b" "x y"}, :files {}}

(mp/is-form-request? "multipart/form-data; boundary=x")   ; true
```

Verified on jolt 0.8.25. Part maps also carry `:disposition`, `:complete`
(true for a finished part) and `:bytes-received` (the part's body size).

Options for `parse-form-data` / `parse-multipart`: `:charset` ("utf-8"),
`:strict`, `:ignore-errors`, `:memory-limit` (total bytes), `:check-complete`
(true; false tolerates a missing closing delimiter), plus the parser limits
`:max-header-size` (4224), `:max-header-count` (8), `:max-segment-size`,
`:max-segment-count`.

Streaming:

```clojure
(mp/parse-multipart boundary input-stream)        ; vector of part maps
(let [p (mp/make-parser "b")]
  (mp/parse-stream p read-fn))                    ; lazy seq of [:segment m] [:body bytes] [:end]
;; or step by step: (mp/parse-chunk parser chunk) -> [parser events]; empty chunk ends
```

Errors are `ex-info` with `:type`; test with `multipart-error?`,
`parser-error?`, `strict-parser-error?`, `parser-limit-reached?`,
`parser-state-error?`. Header helpers: `parse-content-disposition`,
`parse-options-header`, `header-quote`, `header-unquote`,
`content-disposition-quote`, `content-disposition-unquote`.

Everything is buffered in memory; there is no temp-file spooling.
