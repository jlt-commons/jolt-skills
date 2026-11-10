---
name: jolt
description: Build, run, test and ship Clojure projects on Jolt, the Clojure implementation on Chez Scheme (no JVM). Use whenever the user wants to make, scaffold, extend or debug a jolt project, app, library, script, CLI or native binary; mentions jolt, `jolt build`, `jolt.ffi`, `:jolt/native` or jolt tasks; wants to bind a C library from Clojure; or wants a Clojure script/task where babashka would otherwise be used.
---

# Jolt

Jolt reads Clojure, compiles it to Scheme and runs it on Chez. Portable Clojure
runs unchanged. **There is no JVM underneath**, and most mistakes come from
forgetting that. One `jolt` binary is the runtime, the REPL, the `deps.edn`
resolver, the task runner and the AOT compiler.

Read the relevant doc page before guessing:
- https://jolt-lang.net/docs/: user docs
  (`getting-started`, `differences`, `building-and-deps`, `tools-deps`,
  `native-interop`, `host-interop`, `testing`, `repl-driven-development`,
  `cljc-interop`, `fibers`, `performance-idioms`, `embedded-resources`,
  `libraries`, `api/*.md` for `jolt.ffi`, `jolt.fs`, `jolt.deps`, `jolt.time`,
  `jolt.profile`, `jolt.image`, `jolt.debug`, …)
- https://jolt-lang.net/llms.txt and the jolt repo `README.md`: orientation; the
  full divergence list is `test/conformance/known-divergences.edn` in the jolt repo
- https://github.com/yogthos/newsroom: a large, idiomatic jolt application (web server, sqlite,
  HTTP client, FFI to a C++ engine, tasks that build natives, CI + releases)

Reference files in this skill:
- `references/deps-and-tasks.md`: deps.edn keys, coordinates, aliases, tasks
- `references/ffi.md`: binding C, memory, structs, callbacks, shipping your own C
- `references/build.md`: `jolt build`, binary modes, static natives, resources, CI
- `references/differences.md`: where jolt differs from JVM Clojure, and what is shimmed
- `references/ecosystem.md`: every jolt-lang / jlt-commons library, its require, coordinate and domain skill

## Golden rules

1. **No Java interop beyond the shims.** `(Foo.)`, `Foo/bar` and `.method`
   resolve against a hand-written subset of `java.*` in Scheme (strings, math,
   collections, `java.util.concurrent`, `java.io`/`java.nio.file`, `java.net`
   sockets/URI, base `java.time`, `ProcessBuilder`, `Base64`, `UUID`, …). No
   reflection, no `gen-class`, no classloaders, no `.class` files, no pure-Java
   Maven jars. Never pull a Java library; use a jolt library or bind C via FFI.
2. **Never reason from JVM runtime behaviour.** Threads don't keep the process
   alive, there is no `-Xmx` (it's `JOLT_MAX_HEAP`), the stack is deep (millions
   of frames), strings are codepoint-indexed, regex is irregex behind a
   Java-grammar translator. If a diagnosis needs JVM semantics, it is wrong.
3. **Check, don't guess.** `jolt -e '...'` answers "does X exist/work here" in a
   fraction of a second. `(resolve 'ns/sym)`, `(System/getProperty "jolt.version")`,
   `jolt -Spath`, `jolt -Stree`. Read the jolt source when in doubt:
   https://github.com/jolt-lang/jolt/tree/main/host/chez/java/ holds the shims, `stdlib/` the libs.
4. **Pin versions from the source, never from memory.** For a git dep, resolve
   the newest tag and its sha with the `jdep` helper in
   references/deps-and-tasks.md ("Depending on a library: use the latest
   tag"); snippets in these skills write `"<latest>"`/`"<sha>"` for you to fill.
   For Maven, `jolt -Soutdated` reports newer releases.
5. **Platform branches go in a seam**, never `os.name` checks spread through
   logic: one helper or `:darwin`/`:linux`/`:windows` keys in `:jolt/native`.

## Scaffolding a project

There is no `jolt new`. Lay a project out by hand, cargo-style:

```
myapp/
  deps.edn
  src/myapp/core.clj        ; (ns myapp.core) with (defn -main [& args] ...)
  test/myapp/core_test.clj
  test/myapp/test_runner.clj
  resources/                ; embedded into the binary via :jolt/build :embed
  native/                   ; optional: C shims + their build products
  .gitignore                ; target/ .cpcache/ .jolt/ *.build/ native/*.{so,dylib,a,dll} .nrepl-port
```

Minimal `deps.edn`:

```clojure
{:jolt/min-version "0.8.25"            ; the oldest jolt this needs (check `jolt --version`)
 :paths ["src" "resources"]
 :deps {}
 :jolt/build {:embed ["resources"]}
 :aliases {:test {:extra-paths ["test"]
                  :main-opts ["-m" "myapp.test-runner"]}}
 :tasks {serve {:doc "run the app" :main-opts ["-m" "myapp.core"]}
         test  {:doc "run the tests" :task (jolt "-M:test")}
         dist  {:doc "build the binary" :task (shell "jolt" "build" "-m" "myapp.core" "-o" "target/myapp")}
         clean "rm -rf target"}}
```

**Don't name a task after a built-in command** (`run`, `build`, `repl`, `path`,
`tasks`, `help`, `version`, `completions`, `nrepl-server`). The command wins and
jolt warns. Use `serve`/`start`/`dist`, or add `:override-builtin true`.

Test runner, with no dependency (newsroom's pattern):

```clojure
(ns myapp.test-runner
  (:require [clojure.test :as t] myapp.core-test))

(defn -main [& _]
  (let [{:keys [fail error]} (t/run-tests 'myapp.core-test)]
    (System/exit (if (zero? (+ fail error)) 0 1))))
```

Or use `io.github.cognitect-labs/test-runner` unmodified (`jolt -M:test:runner`,
see `testing.md`). `run-tests` with no args runs *every* registered test.

For a long-running server, `-main` should park until Ctrl-C and shut down cleanly:

```clojure
(defn -main [& _]
  (jolt.host/block-sigint)
  (start!)
  (jolt.host/add-shutdown-hook stop!)
  (jolt.host/park-until-interrupt))
```

On SIGINT/SIGTERM the hooks run and the process exits (130/143); code after
`park-until-interrupt` does not run, so cleanup belongs in the hook.

## Everyday commands

```bash
jolt -e '(+ 1 2)'                 # eval; also the fastest way to check a fact
jolt                              # REPL (resolves deps.edn first)
jolt nrepl-server [port]          # nREPL on 7888, writes .nrepl-port
jolt -m myapp.core args           # run -main (same as: jolt run -m ...)
jolt script.clj args              # run a file; #!/usr/bin/env jolt makes it a script
jolt -M:test  /  -X:alias k v     # aliases, as with the Clojure CLI
jolt tasks  /  jolt <task> args   # deps.edn or bb.edn :tasks
jolt -Spath -Stree -Sgraph -Soutdated -P   # inspect / prefetch the resolution
jolt build -m myapp.core -o target/myapp   # standalone native binary
```

Dev runs (`-m`, `-M`, REPL) compile namespaces on the fly and cache them in
`~/.jolt/aot-cache`. Startup is about 0.17s, so a script that runs in a hot loop
should become a built binary.

## REPL-driven work

`jolt nrepl-server` from the project root loads deps and natives and writes
`.nrepl-port`. Editors **connect** (CIDER `cider-connect`, Calva "connect to
running REPL", Cursive remote). Their jack-in would start a JVM. Calva can use a
custom connect sequence with `"customJackInCommandLine": "jolt nrepl-server"`.
For completion/lookup middleware, add `jolt-lang/nrepl`
(`:nrepl/middleware`). An app can embed a server with `(jolt.nrepl/start port)`,
which returns a stop fn.

**Work through the REPL yourself.** For anything iterative, use the
`jolt-nrepl` MCP tools (plugin source: https://github.com/jlt-commons/jolt-nrepl-mcp)
instead of repeated `jolt -e` runs: the session keeps vars, loaded namespaces
and the current ns, so each step costs one eval, not a process start. Load the
`jolt-nrepl` skill for the full workflow. In short:

- `nrepl_start` (pass the project dir as `cwd`) starts or reuses the server;
  `nrepl_eval` then connects lazily via `.nrepl-port`.
- Try code in `nrepl_eval` first, then write it to the file and
  `nrepl_load_file` it. Edit forms with `clj_replace` (`load: true` reloads),
  which matches by structure, not whitespace.
- Run tests in the session: `(require 'x-test :reload) (clojure.test/run-tests 'x-test)`.
  Still run the project's test task as the final gate.
- Debug by capturing values with an inline `(def x* x)` in a REPL-only
  redefinition, then inspect; don't add `println`. After an error: `*e`,
  `(ex-data *e)`.
- Discover APIs with `clojure.repl/doc`, `apropos`, `dir`, `find-doc`,
  `(meta #'ns/f)` and `macroexpand-1`. There is no `clojure.repl/source`.
- A dropped trailing paren is auto-closed and reported; other syntax problems
  come back with line/col before anything runs. `clj_check` does the same for
  a file (`fix: true` writes safe repairs).
- The built-in server has no `interrupt`; a timed-out eval drops the
  connection and may still be running. Add `nrepl.middleware/default-middleware`
  for interrupt. Timed-out forms are never replayed.

## Choosing libraries

Prefer, in order: what ships with jolt → jolt-lang / jlt-commons libraries →
pure-Clojure JVM libraries known to work (`libraries.md`) → binding C yourself.

Built in, no dependency needed: `clojure.string/set/walk/edn/pprint/test/zip`,
`clojure.data.json`, `clojure.core.async` (plus opt-in fibers), `babashka.fs`
(alias `jolt.fs`), `babashka.cli` (alias `jolt.cli`), `jolt.process`, `jolt.ffi`,
`jolt.deps/add-deps`, `jolt.profile`, `jolt.debug`, `jolt.continuations`,
`jolt.image`, `jolt.infix`, `jolt.parser`, the base `java.time` value types,
sockets (`java.net.Socket`/`ServerSocket`).

First-party (git deps from `github.com/jolt-lang/<name>`): `http-client`
(clj-http-lite API as `jolt.http-client`, also babashka.http-client), `db`
(`jdbc.core`/`next.jdbc` over libsqlite3/libpq; a map dbspec such as
`{:vendor "sqlite" :name "app.db"}` works directly),
`ring-chez-adapter` (`ring-chez.adapter/run-server`, SSE, websockets, multipart,
TLS), `router` (makes reitit work), `time` (DateTimeFormatter/zones + tick),
`crypto`, `xml`, `yaml`, `logging`, `otel`, `transit-jolt`, `jolt-fressian`,
`nrepl`, `glimmer` (+ `-gtk`, `-tui`, `-gl`, `-datastar`), `multipart`. Community:
`jlt-commons/*` (ebb = missionary, instaparse, mulog, raylib-jlt, writ, …).

Known-good JVM libs include ring-core (`:deps/root "ring-core"`), reitit-core,
integrant, mount, malli, honeysql, spec.alpha (declare `spec.alpha` and
`core.specs.alpha` explicitly; `org.clojure/clojure` brings no transitive deps),
core.match/cache/memoize/logic, test.check, tools.cli, rewrite-clj, Selmer,
hiccup, markdown-clj, aero, medley.

A library that needs a missing `java.*` class or method can often be made to
work from your own code: register the shim at load time
(`jolt.host/extend-class!`, `__register-class-ctor!`, …; see `host-interop.md`)
in a `myapp.shims` namespace required first.

## Portability and jolt-specific code

- Reader conditionals are read in **every** file type; the feature set is
  `#{:jolt :clj :default}`. Put `:jolt` **before** `:clj` to take a jolt branch.
  `:bb` is not matched (opt in with `:jolt/features [:bb]` in the project).
- A whole namespace can be swapped with `foo.jolt`, which wins over
  `foo.clj`/`foo.cljc`. It is the same language; the extension marks it non-portable.
- Detect jolt at runtime with `(System/getProperty "jolt.version")`.
  `java.version` is nil on purpose.

## Gotchas worth remembering

- `compare-and-set!` compares by **value**, not identity.
- `^:private` isn't enforced across namespaces (still excluded from `ns-publics`).
- `(class (int 5))` is `Long`: one integer type, narrowing is a no-op.
- `(count "😀")` is 1 (codepoints). `(str lazy-seq)` prints contents.
- `-main` returning exits once non-daemon threads finish; `go`/`a/thread`/fibers don't keep it alive. Park a server.
- `Exception` doesn't catch `StackOverflowError`/`OutOfMemoryError` (they are `Error`s).
- Performance: build strings with `StringBuilder` or `str/join`, not `str` in a
  loop; use `(?:…)` for groups you don't read; prefer literal keyword maps; use
  `^double`/`^long` hints or casts in numeric hot paths (see `performance-idioms.md`).
- Diagnostics: `JOLT_DIAG=edn` (machine-readable errors), `JOLT_CHECK=1` (type
  lint), `JOLT_DEBUG=1` (dep resolution), `JOLT_WARNINGS=1`, `JOLT_TRACE=0`
  (turn off source-mode tracing for microbenchmarks), `JOLT_GC_LOG=1`.
- Bound memory with `JOLT_MAX_HEAP=2g` (default 25% of RAM; raise it for big
  builds or test suites). Stack depth is `JOLT_STACK_LIMIT`.

## Working on a jolt project: checklist

1. Read `deps.edn` first: `:jolt/native`, `:tasks` and `:jolt/build` tell you how
   the project is built and what C it needs. `jolt tasks` lists the entry points.
2. Start a REPL with `nrepl_start` and iterate there (see REPL-driven work).
   Before using an API, confirm it exists: `(some? (resolve 'z/f))` in the
   session, or `jolt -e "(require '[x.y :as z]) (some? (resolve 'z/f))"`.
3. TDD with the project's test alias/task (`jolt test` or `jolt -M:test`). Exit
   status is the gate. Don't pipe it through `tail` without capturing the status.
4. If the project ships a binary, build it (`jolt build …`) and run it after any
   change that touches natives, resources, `require`s computed at runtime, or
   `resolve`: a source run can pass where the closed-world binary fails.
5. For any FFI work, read `references/ffi.md` first.
