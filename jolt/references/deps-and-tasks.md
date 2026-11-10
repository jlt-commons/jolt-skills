# deps.edn and tasks on jolt

Source: `building-and-deps.md`, `tools-deps.md`, `api/deps.md` in
https://jolt-lang.net/docs/.

jolt reads `deps.edn` itself (no Clojure CLI, no JVM). The resolver is a port of
tools.deps, so selection, exclusions and alias merging behave the same. The
resolution is just an ordered list of source directories.

## Top-level keys

| key | meaning |
|---|---|
| `:paths` | project source dirs (default `["src"]`) |
| `:deps` | coordinates: git, local, Maven |
| `:aliases` | `-A`/`-M`/`-X`/`-T` argument maps, tools.deps semantics |
| `:tasks` | babashka-style tasks, run as `jolt <name>` |
| `:mvn/repos`, `:mvn/local-repo` | extra Maven repos / relocate `~/.m2/repository` |
| `:jolt/native` | C shared libraries to load before any code (see ffi.md) |
| `:jolt/build` | `jolt build` options (see build.md) |
| `:jolt/min-version` | oldest jolt the project/library supports; older runtimes refuse to load |
| `:jolt/provides` | (libraries) `{ns ["java.Fq.Class" …]}`: classes this lib's ns installs, autoloaded on first use |
| `:jolt/features` | widen reader-conditional features, e.g. `[:bb]` (project only) |
| `:jolt/tree-shake` | `{:allow-dynamic [ns/def …]}` vouch for dead `resolve` sites |
| `:nrepl/middleware` | middleware a library contributes |

A user-level deps.edn (`$CLJ_CONFIG` / `~/.clojure`) merges underneath;
`JOLT_NO_USER_DEPS=1` ignores it (useful when it holds JVM-only aliases).

## Coordinates

```clojure
{:deps
 {;; git, with tag + full commit sha (preferred: readable and pinned)
  jolt-lang/http-client {:git/url "https://github.com/jolt-lang/http-client"
                         :git/tag "<latest>" :git/sha "<sha>"}
  ;; io.github.OWNER/REPO derives the URL
  io.github.weavejester/medley {:git/sha "<full-sha>"}
  ;; subdirectory of a repo
  ring/ring-core {:git/url "https://github.com/ring-clojure/ring" :git/sha "…" :deps/root "ring-core"}
  ;; Maven: the jar's .clj/.cljc source is what runs; pure-Java jars contribute nothing
  ring/ring-codec {:mvn/version "<latest>"}
  ;; local dir or jar
  my/helpers {:local/root "../helpers"}}}
```

`:git/sha` must be the full commit SHA, or a prefix (7+ chars, verified
against the tag) when paired with `:git/tag`; jolt rejects a `:git/tag` with no
sha. Fill both with `jdep` below.

## Depending on a library: use the latest tag

Every coordinate in these skills is written `{:git/tag "<latest>" :git/sha
"<sha>"}`. Resolve it when you add the dep:

```sh
# print a deps.edn coordinate for the newest release tag of OWNER/REPO
# (pre-release tags skipped; HEAD if untagged)
jdep() {
  u="https://github.com/$1"
  t=$(git ls-remote --tags --refs --sort=-v:refname "$u" | sed 's#.*refs/tags/##' \
      | grep -viE '[-.](alpha|beta|rc|pre|snapshot)' | head -1)
  if [ -n "$t" ]; then
    s=$(git ls-remote "$u" "refs/tags/$t^{}" | cut -f1); [ -n "$s" ] || s=$(git ls-remote "$u" "refs/tags/$t" | cut -f1)
    echo "io.github.$1 {:git/tag \"$t\" :git/sha \"$(echo $s | cut -c1-7)\"}"
  else
    echo "io.github.$1 {:git/sha \"$(git ls-remote "$u" HEAD | cut -f1)\"}"
  fi
}
jdep jolt-lang/db   # => io.github.jolt-lang/db {:git/tag "v0.4.3" :git/sha "009e2b2"}
```

- Always resolve the newest tag when adding a dep. Never copy a sha from docs,
  an old project or memory.
- `jdep` prints an `io.github.OWNER/REPO` key. When the library's README uses
  another key (`com.github.seancorfield/honeysql`, `jolt-lang/time`, ...),
  keep that key (and its `:git/url`) and take only the tag and sha.
- If the library is also a transitive dep of another library you use, keep the
  SAME lib key that library uses, and only take the tag/sha from `jdep`. For
  example ring-chez-adapter and http-client depend on crypto as
  `jolt-lang/jolt-crypto {:git/url "https://github.com/jolt-lang/crypto" ...}`;
  adding it as `io.github.jolt-lang/crypto` gives two copies of the same repo.
  `jolt -Stree` shows the keys in play.
- `jolt -Soutdated` only reports Maven updates. To update a git dep, re-run
  `jdep` and replace the tag and sha.

Needs at resolve time: `git` for git deps; system OpenSSL (`brew install
openssl@3` on macOS) and `unzip` for Maven. Git clones are cached in
`~/.jolt/gitlibs` (`$JOLT_GITLIBS`) and Maven jars in `~/.m2/repository`
(`JOLT_LOCAL_REPO`).

Not supported: `:deps/prep-lib` (warned, never run; a library that builds C
names its build task in `:jolt/native` `:build` instead, see ffi.md), Maven classifiers,
`pom.xml` as manifest. `org.clojure/clojure` is terminal: declare
`org.clojure/spec.alpha` + `org.clojure/core.specs.alpha` yourself if needed.

## Inspecting

```bash
jolt -Spath        # roots, ':'-joined (jolt path is the same)
jolt -Stree        # tools.deps expansion trace (who lost and why)
jolt -Sgraph       # selected dependency graph
jolt -Soutdated    # graph + "-> newer" for Maven libs (hits the network)
jolt -Sdescribe    # environment as edn
jolt -P            # fetch everything, run nothing
JOLT_DEBUG=1 jolt …   # verbose resolution
```

## Aliases

`:extra-paths`/`:extra-deps` accumulate, `:replace-paths`/`:replace-deps`
replace, `:override-deps`, `:default-deps`, `:main-opts` (last wins), `:exec-fn`
+ `:exec-args` + `:ns-default`. An undeclared alias is an error.

```bash
jolt -M:test                     # run :main-opts
jolt -A:dev repl                 # add paths/deps, then any command
jolt -X:build :env '"prod"'      # call :exec-fn with a map
jolt -T:tool                     # -X without the project's paths/deps
jolt -Sdeps '{:deps {...}}' -M:x # merge an extra map
```

## Tasks

Tasks go in `deps.edn` `:tasks` (or `bb.edn`; both merge, bb.edn wins on
name clashes). Babashka semantics plus two jolt forms:

```clojure
:tasks
{:requires ([babashka.fs :as fs] [clojure.string :as str])   ; for every task
 :init     (def os (System/getProperty "os.name"))            ; evaluated once
 ;; :enter / :leave run around each task

 clean "rm -rf target"                                  ; string = shell command line (jolt-only)
 serve {:doc "run the server" :main-opts ["-m" "app.core"]}   ; map + :main-opts = like an alias (jolt-only)
 test  {:doc "tests" :task (jolt "-M:test")}            ; `jolt` re-invokes this CLI (`clojure` is an alias of it)
 dist  {:doc "binary" :depends [clean native]
        :task (shell "jolt" "build" "-m" "app.core" "-o" "target/app")}
 -helper {:task (println "private: hidden from `jolt tasks`")}
 lint  {:extra-deps {…} :extra-paths ["dev"] :task …}}
```

- Bodies run in `user` with `clojure.core` and `babashka.tasks` referred:
  `shell`, `jolt`, `clojure`, `run`, `current-task`. A non-zero `shell` fails the task.
- Pass args to `shell` **separately**, not as one string, when they hold
  `$ORIGIN` or spaces. `(shell {:dir "x" :out :string} "cmd" "arg")` captures output.
- Args after the task name are `*command-line-args*`. `jolt run --parallel t`
  runs independent `:depends` concurrently.
- Each dependency runs once per invocation; a cycle is an error.
- A task run doesn't require `:jolt/native` libraries to be loadable, so a
  `native` task can build the shim the rest of the project loads.
- **Names that collide with built-ins lose** (`run`, `build`, `repl`, `path`,
  `tasks`, `help`, `version`, `completions`, `nrepl-server`): pick another name
  or set `:override-builtin true`.
- `:exec-fn`/`:cmd` tasks get `babashka.cli` arg parsing, `--help`, and shell completion.
- `:pods` are unsupported.

Real examples: https://github.com/yogthos/newsroom/blob/main/deps.edn has tasks that fetch a pinned git
checkout, build a C++ engine, locate a dependency's checkout via `jolt path`
and build its kernels, and run golden tests through `uv`.

## Deps from a script, no deps.edn

```clojure
#!/usr/bin/env jolt
(when (System/getProperty "jolt.version")
  ((requiring-resolve 'jolt.deps/add-deps)
   '{:deps {medley/medley {:mvn/version "<latest>"}}}))
(ns main (:require [medley.core :as m]))
```

`clojurestar.deps/add-deps` is the dialect-neutral spelling (jolt, bb, …).
`JOLT_PATH=dir1:dir2 jolt run f.clj` adds roots with no deps machinery at all.
