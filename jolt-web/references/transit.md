# transit-jolt

Transit 0.8, JSON encoding only. Two functions, no reader/writer objects.
Source: https://github.com/jolt-lang/transit-jolt

```clojure
jolt-lang/transit-jolt
{:git/url "https://github.com/jolt-lang/transit-jolt"
 :git/tag "<latest>" :git/sha "<sha>"}
```

Fill tags with `jdep OWNER/REPO` (jolt skill, deps-and-tasks.md). It brings data.json and jolt-lang/time.

```clojure
(require '[jolt.transit :as t])
(t/write {:name "transit" :tags #{:a}})
;; => "[\"^ \",\"~:name\",\"transit\",\"~:tags\",[\"~#set\",[\"~:a\"]]]"
(t/read (t/write {:name "transit" :tags #{:a}}))   ; => {:name "transit", :tags #{:a}}
```

Types round-trip: integers and decimals as numbers; bigints past 64 bits as
`~n` (read back as BigInt); BigDecimal as `~f`; ratios with transit-clj's
`ratio` tag (`["~#ratio",["~n1","~n3"]]`, read back as a Ratio); byte arrays as
`~b` base64; `time` as an inst, `uuid` as a uuid, `uri` as `java.net.URI`.
Chars read as `jolt.transit.CharV`, unknown tags as `jolt.transit.TaggedValue`
(written back unchanged).

As Ring middleware:

```clojure
(defn wrap-transit [handler]
  (fn [{:keys [headers body] :as req}]
    (let [req (if (and body (some-> (get headers "content-type") (.startsWith "application/transit+json")))
                (assoc req :body-params (t/read (slurp body)))
                req)
          resp (handler req)]
      (if (contains? resp :transit)
        (-> resp (dissoc :transit)
            (assoc :body (t/write (:transit resp)))
            (assoc-in [:headers "Content-Type"] "application/transit+json"))
        resp))))
```
