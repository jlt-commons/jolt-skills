# instaparse: grammar-based parsers

Source: https://github.com/jlt-commons/instaparse (the README's
`io.github.jolt-lang/instaparse` redirects there). Use its newest tag
(`jdep jlt-commons/instaparse`, see the jolt skill's `references/deps-and-tasks.md`).
This is upstream Engelberg instaparse with jolt fixes; the upstream README (1200
lines, in the repo) is the full manual and applies as written, except
`instaparse.viz` (no graphviz/rhizome).

```clojure
{:deps {io.github.jlt-commons/instaparse {:git/url "https://github.com/jlt-commons/instaparse"
                                          :git/tag "<latest>" :git/sha "<sha>"}}}
```

For small hand-rolled parsers, jolt also ships `jolt.parser` (parser combinators,
no dependency); reach for instaparse when you have an EBNF/ABNF grammar.

## API (all ran)

```clojure
(require '[instaparse.core :as insta :refer [defparser]])

(def arith
  (insta/parser
    "expr = add-sub
     <add-sub> = mul-div | add | sub
     add = add-sub <'+'> mul-div
     sub = add-sub <'-'> mul-div
     <mul-div> = term | mul | div
     mul = mul-div <'*'> term
     div = mul-div <'/'> term
     <term> = number | <'('> add-sub <')'>
     number = #'[0-9]+'"
    :auto-whitespace :standard))          ; <rule> hides the node, <'x'> hides the token

(arith "1 + 2 * (3 - 1)")
;; => [:expr [:add [:number "1"] [:mul [:number "2"] [:sub [:number "3"] [:number "1"]]]]]
(insta/transform {:number parse-long :add + :sub - :mul * :div / :expr identity}
                 (arith "1 + 2 * (3 - 1)"))     ; => 5

(let [r (arith "1 + * 2")]
  (insta/failure? r)                            ; => true
  (println (pr-str (insta/get-failure r))))
;; Parse error at line 1, column 5:
;; 1 + * 2
;;     ^
;; Expected one of:
;; "("
;; #"[0-9]+"

(defparser kv "pairs = pair (<','> pair)*
               pair = key <'='> val
               key = #'[a-z]+'
               val = #'[^,]*'")                 ; grammar compiled at load time
(into {} (insta/transform {:pairs vector :pair vector :key keyword :val identity}
                          (kv "a=1,b=two")))    ; => {:a "1", :b "two"}
(kv "a=1" :start :pair)                         ; parse from another rule
(insta/parse kv "x=y")                          ; same as (kv "x=y")
(kv "a=1,=" :total true)                        ; failure embedded in the tree instead of returned

((insta/parser "S = A B\nA = 'a'+\nB = 'b'+" :output-format :enlive) "aabb")
;; => {:tag :S, :content ({:tag :A, :content ("a" "a")} {:tag :B, :content ("b" "b")})}

(insta/parses (insta/parser "S = A A ; A = 'a' | 'aa' | ''") "aa")   ; all parses (3)

(insta/parser "greeting = \"hi\" SP name\nname = 1*ALPHA" :input-format :abnf)

(insta/span (second (arith "12")))              ; => [0 2]  source position of a node
```

Other options from the upstream manual (`:string-ci`, `:optimize :memory`,
`:unhide`, `insta/add-line-and-column-info-to-metadata`, the
`instaparse.combinators` namespace) are present in the source.

## Notes

- Regexes in grammars go through jolt's Java-regex translator (irregex);
  standard character classes and quantifiers work, exotic Java-only constructs
  may not. Test each terminal.
- Grammar compilation costs tens of milliseconds; build parsers once (`def` or
  `defparser`), not per call.
