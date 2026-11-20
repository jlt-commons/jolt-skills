# Jolt house style

The rulebook `jolt-style` reviews against. A project's own guide (for
example `docs/style/CLOJURE-STYLE.md`) wins over this one; the community
guide (<https://guide.clojure.style>) is the fallback for anything neither
covers. Adapted from clojure-agent-starter's house guide (MIT, JoinIn AI).

## Layout

- One binding pair per line in `let`, `loop`, `binding`, `with-open`.
- Multi-line docstrings: continuation lines indented two spaces; the
  closing `"` is present.
- Functions stay small: aim for 10 lines or fewer. The test is whether the
  function can be evaluated alone in the REPL; if not, it is too big.
- Three or four positional parameters at most; past that, take a
  destructured map.
- `(comment ...)` at the bottom of a namespace holds runnable examples.
- Formatting is cljfmt's (`jolt_format`); don't review what it fixes.

## Namespaces

- Alias = the last segment, or the last two joined when that is ambiguous
  (Stuart Sierra's guideline). One alias per namespace across the project.
  Common ones: `clojure.string` `str`, `clojure.set` `set`,
  `clojure.data.json` `json`, `clojure.edn` `edn`, `babashka.fs` `fs`,
  `babashka.process` `p`, `clojure.core.async` `a`, `integrant.core` `ig`,
  `malli.core` `m`.
- `:require :as` over `:refer`; `:refer` is fine for a few names (test
  macros). Never `:refer :all` or `:use` in new code.
- No single-segment namespaces.

## Data and state

- Plain maps for data. Records and deftypes only for protocol dispatch on
  a hot path; protocols only for real polymorphism.
- Pure functions, side effects at the edges, so the pure part evaluates in
  the REPL with no setup.
- Destructure at the boundary: `(defn handle [{:keys [id body]}] ...)`
  shows the expected shape in the signature.
- Threading for data flow (`(-> req :body :items)`), not nested `get`s.
  Don't thread a single call; use a `let` when `->` and `->>` would mix.
- Atoms for mutable state. A running system lives in a top-level
  `defonce` atom the start fn `reset!`s, so the REPL can reach it.
- Validate data where it crosses a boundary (HTTP, files, queues, the
  database) with malli or clojure.spec; inside, trust the shape.
- Keywords for map keys past the boundary that read strings.

## Jolt

- No Java interop beyond Jolt's `java.*` shims. Use `jolt.fs` /
  `babashka.fs`, `babashka.process` / `jolt.process`, `clojure.data.json`
  (built in).
- `clojure.edn/read-string` for data, never `read-string`, `eval` or
  `load-string` on input. jolt-lsp's `:presets [:security]` enforces it.
- Logging through `clojure.tools.logging` (jolt-lang/logging) or mulog,
  never `println`. `tap>` is fine while debugging, not in a commit.

## Naming

- `lisp-case` for vars and fns; `CamelCase` for protocols, records, types.
- Predicates end in `?`, side-effecting fns that are unsafe to retry end
  in `!`, conversions read `a->b`.
- Don't shadow `clojure.core` names (`name`, `type`, `key`, `val`, `map`,
  `count`) with locals or vars.
- Prefer `when` to a one-armed `if`; `if-let` / `when-let` where they
  remove a binding plus a test; `cond` ends with `:else`.

## Comments

- Comments say what the code can't: constraints, the reason for an odd
  choice. Not what the next line does.
- No provenance comments ("ported from foo.py:120") and no file:line
  references to live code; name the namespace and var instead.
- `TODO` / `FIXME` carry enough context for someone else to act on.

## Tests

- `my.ns` is tested in `my.ns-test`, at `test/my/ns_test.clj`.
- `deftest` names describe the behaviour (`expired-tokens-are-rejected`);
  the namespace already says `-test`.
- An error a test surfaces is a bug, not noise.
