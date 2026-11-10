# Data formats: JSON, EDN, YAML, XML, Transit, Fressian

All snippets ran on jolt 0.8.25 with each library's newest tag.

| format | dep | ns | native lib |
|---|---|---|---|
| JSON | built in | `clojure.data.json` | none |
| EDN | built in | `clojure.edn` | none |
| YAML | `jolt-lang/yaml` | `jolt.yaml`, `clj-yaml.core` | libyaml |
| XML read | `jolt-lang/xml` | `clojure.xml`, `jolt.xml` (StAX shim) | libxml2 |
| XML write | `jolt-lang/xml` | `clojure.data.xml` | none |
| Transit JSON | `jolt-lang/transit-jolt` | `jolt.transit` | none |
| Fressian | `jolt-lang/jolt-fressian` (untagged, sha) | `fress.api` | none |

## JSON (built in)

```clojure
(require '[clojure.data.json :as json])
(json/read-str "{\"a\":1,\"b\":[true,null]}" :key-fn keyword)   ; => {:a 1, :b [true nil]}
(json/read-str "{\"a\":1}")                                      ; => {"a" 1}
(json/write-str {:a 1 :b [true nil] :c "x"})                     ; => "{\"a\":1,\"b\":[true,null],\"c\":\"x\"}"
(json/write-str {:b "é"} :escape-unicode false)
(json/read (java.io.StringReader. "[1,2]"))                      ; => [1 2]; also (json/write x writer)
(json/pprint {:a 1 :b [1 2]})
```

Writing a `java.time.Instant` (or anything java.time) needs jolt-lang/time on the
classpath; without it: `No dependency provides java.time.format.DateTimeFormatter`.
With it: `(json/write-str {:at (java.time.Instant/parse "2024-01-01T00:00:00Z")})`
=> `"{\"at\":\"2024-01-01T00:00:00Z\"}"`.

## EDN (built in)

```clojure
(require '[clojure.edn :as edn])
(edn/read-string "{:a #{1 2} :b #inst \"2024-01-01T00:00:00Z\" :c #uuid \"00000000-0000-0000-0000-000000000001\"}")
(edn/read-string {:readers {'my/thing (fn [x] [:thing x])}} "#my/thing 5")   ; => [:thing 5]
(edn/read-string (slurp "config.edn"))
(spit "state.edn" (pr-str data))
```

`#inst` reads as `java.util.Date`; convert with `(tick.core/instant d)`. EDN is
the safest config/persistence format on jolt (no native lib, exact round trip).

## YAML: jolt-lang/yaml

Source: https://github.com/jolt-lang/yaml. Needs libyaml: Homebrew `libyaml`
(found at `/opt/homebrew/opt/libyaml/lib/libyaml.dylib`), Linux `libyaml-0-2`.

```clojure
(require '[jolt.yaml :as yaml])
(yaml/load "foo: 1\nbar: [a, b]\n")               ; => {"foo" 1, "bar" ["a" "b"]}
(yaml/load "hello: world\n" {:keywords true})     ; => {:hello "world"}
(yaml/load-all "---\na: 1\n---\nb: 2\n")          ; => [{"a" 1} {"b" 2}]
(yaml/dump {:a [1 2 3] :b {:c "x"}})              ; => "a:\n- 1\n- 2\n- 3\nb:\n  c: x\n"

(require '[clj-yaml.core :as cy])                 ; clj-commons/clj-yaml API, keywords on by default
(cy/parse-string "a: 1\nb: {c: true}\n")          ; => {:a 1, :b {:c true}}
(cy/generate-string {:hello "world"})             ; => "hello: world\n"
;; also cy/parse-stream
```

`false` and null values are kept (`(yaml/load "a: false\nq: ~\nr:")` =>
`{"a" false, "q" nil, "r" nil}`), quoted scalars stay strings. Unlike SnakeYAML,
`yes`/`no`/`on`/`off` read as strings, not booleans.

`jolt.yaml.snakeyaml` registers the `org.snakeyaml.engine.v2` low-level classes
(LoadSettings, Parse, event types) for libraries such as yamlscript; app code
should use `jolt.yaml`.

## XML: jolt-lang/xml

Source: https://github.com/jolt-lang/xml. libxml2 ships with macOS; Linux
`libxml2.so.2`/`.so.16`.

```clojure
(require 'clojure.xml)                  ; loads jolt.xml for you
(clojure.xml/parse "<a x=\"1\"><b>hi</b></a>")   ; String, Reader or org.xml.sax.InputSource
;; => {:tag :a, :attrs {:x "1"}, :content [{:tag :b, :attrs nil, :content ["hi"]}]}

(require '[clojure.data.xml :as dx])    ; generation only, pure Clojure
(dx/emit-str (dx/element :rss {:version "2.0"}
               (dx/element :channel nil (dx/element :title nil "Hi & bye"))))
;; => "<?xml version=\"1.0\" encoding=\"UTF-8\"?><rss version=\"2.0\"><channel><title>Hi &amp; bye</title></channel></rss>"
(dx/emit-str (dx/element :a nil (dx/cdata "<b>hi</b>")))
```

- `:content` is a vector as on the JVM (nil for an empty element); adjacent
  text and CDATA are joined into one string. clojure.zip / data.zip work on it.
- `clojure.data.xml` here is the 0.0.8 generation API (`element`, `cdata`,
  `emit-str`); there is no `parse`/`parse-str`. Read with `clojure.xml/parse`.
- `emit-str` has no newlines or indentation; empty elements render `<a></a>`.
- Streaming: `(require 'jolt.xml)` installs `javax.xml.stream.XMLInputFactory`
  (`newInstance`, `createXMLStreamReader` over a Reader/String) and the
  `XMLStreamReader` methods `hasNext`, `next`, `getLocalName`, `getText`,
  `getAttributeCount`, `getAttributeLocalName`, `getAttributeValue`; event codes
  1 = START_ELEMENT, 2 = END_ELEMENT, 4 = CHARACTERS.

## Transit: transit-jolt

Source: https://github.com/jolt-lang/transit-jolt. Transit 0.8 JSON only (no
msgpack); two functions, no reader/writer objects.

```clojure
(require '[jolt.transit :as transit])
(def s (transit/write {:name "transit" :tags #{:a :b} :at #inst "2024-01-01T00:00:00Z"}))
;; => "[\"^ \",\"~:name\",\"transit\",\"~:tags\",[\"~#set\",[\"~:b\",\"~:a\"]],\"~:at\",\"~m1704067200000\"]"
(transit/read s)  ; => {:name "transit", :tags #{:b :a}, :at #inst "2024-01-01T00:00:00.000-00:00"}
```

Round-trips keywords, symbols, sets, lists, uuids, `java.net.URI`, `#inst`,
bigints (`~n`), ratios (transit-clj's `"ratio"` tag), BigDecimal (`~f`) and byte
arrays (`~b`).
Unknown tags read as `jolt.transit.TaggedValue` and are re-emitted on write.

## Fressian: jolt-fressian

Source: https://github.com/jolt-lang/jolt-fressian (no tags; pin a sha).
Byte-compatible with Datomic's / `clojure.data.fressian` (checked by its JVM
cross-gate).

```clojure
(require '[fress.api :as fress])
(def b (fress/write {:a 1 :b [1 2 3] :s #{"x"}}))   ; => byte array (26 bytes)
(fress/read b)                                       ; => {:a 1, :b [1 2 3], :s #{"x"}}

;; several objects on one stream
(let [out (fress/byte-stream)
      w   (fress/create-writer out)]
  (fress/write-object w 1)
  (fress/write-object w "two")
  (fress/read-batch (fress/create-reader @out)))      ; => [1 "two"]
```

Lists and seqs read back as vectors, sets as hash sets. Records need
`:record->name` / `:name->map-ctor` options, keyed by `(class (->Rec ...))`, not
the bare record name. Every float is written as a double; `(bigint 0)`-sized
bigints are written as plain ints.
