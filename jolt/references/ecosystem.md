# The jolt-lang / jlt-commons ecosystem

Every non-archived repo in the two GitHub orgs: what it is,
what to require, how to depend on it, maturity, and which skill has the API
detail. `jolt-lang` = runtime + first-party libs; `jlt-commons` = community.

Columns: **tagged** = the repo has release tags (`no`: depend on a commit
sha). **T** = test suite (`y`), only CI checks (`CI`), or none (`-`).
The covering skill (`jolt-web`, `jolt-data`, `jolt-gui`, `jolt-games`,
`jolt-concurrency`, or `here`) is in each section heading.

Coordinates below write `"<latest>"`/`"<sha>"`. Fill them with `jdep OWNER/REPO`
(deps-and-tasks.md, "Depending on a library: use the latest tag"); it prints
the newest tag with its sha, or HEAD for an untagged repo.

The coordinate key names the lib: `jolt-lang/time` and
`io.github.jolt-lang/time` are two libs, and both land on the classpath. When
you override a transitive dep, reuse the key the depending library uses
(`jolt -Stree` shows it). Old URLs in some READMEs (`jolt-lang/jolt-crypto`,
`jolt-lang/duratom`, `jolt-lang/mulog`, `jolt-lang/instaparse`,
`jolt-lang/tapestry`) still work because GitHub redirects them.

## Install, CI, CLI parsing

**Install** (jolt-lang/homebrew-jolt):
`brew install jolt-lang/jolt/jolt` (bottles for macOS arm64 and Linux x86_64;
Intel macs build from source). Or use
`curl -sL https://raw.githubusercontent.com/jolt-lang/jolt/main/install | bash`.

**CI: jlt-commons/setup-jolt** (use the moving tag `v1`). A composite action that
downloads a jolt release and verifies its sha256. It covers Linux x86_64 and
macOS x86_64/arm64 but not Windows (for Windows, copy the curl/unzip step from
`jlt-commons/augur/.github/workflows/test.yml`). The README says "proof of
concept", but raylib-jolt-demo, jolt-openldk and ci-builds use it.

```yaml
jobs:
  test:
    strategy: {matrix: {os: [ubuntu-latest, macos-latest]}}
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: jlt-commons/setup-jolt@v1
        with: {version: '<jolt version>'}   # omit = latest; step output `version` = resolved
      - run: jolt -M:test           # exit status is the gate
```

Pin `version` and set `:jolt/min-version`. jolt 0.8.0 swapped
`jolt.ffi/write`'s argument order without any error, and projects tracking
`latest` moved onto it unnoticed. **jlt-commons/ci-builds** is the org's fleet
CI. Nothing depends on it. It dispatches each member's `ci.yml` with a
`jolt-version` input, tabulates the results, and runs a canary hourly against
the pinned and latest jolt. It also hosts the reusable docs `site.yml`.

**CLI parsing.** Two options:

```clojure
(require '[babashka.cli :as cli])          ; built in, also as jolt.cli; no dep
(cli/parse-opts ["--port" "3000" "--verbose"] {:coerce {:port :long}}) ;=> {:port 3000, :verbose true}
(cli/dispatch [{:cmds ["serve"] :fn (fn [{:keys [opts]}] (start! opts))}] *command-line-args*)

;; upstream clojure/tools.cli, unmodified: {org.clojure/tools.cli {:mvn/version "<latest>"}}
(require '[clojure.tools.cli :refer [parse-opts]])
(parse-opts ["-p" "3000" "serve"] [["-p" "--port PORT" "Port" :default 8080 :parse-fn parse-long]])
;=> {:options {:port 3000} :arguments ["serve"] :errors nil ...}
```

Use babashka.cli for new code. There is no jolt fork of tools.cli; upstream
`clojure/tools.cli` runs unchanged.

## Catalog

### Web: `jolt-web`

| repo | what | require | tagged | T |
|---|---|---|---|---|
| jolt-lang/ring-chez-adapter | Ring HTTP/1.1 server; SSE, websockets, TLS, gzip, static | `ring-chez.adapter` | yes | y |
| jolt-lang/http-client | `java.net`/HttpClient/TLS shims; clj-http-lite, babashka.http-client | `jolt.http-client` | yes | y |
| jolt-lang/router | `reitit.Trie` in Clojure so reitit-core loads unmodified | `reitit.core` (Trie autoloads) | yes | y |
| jolt-lang/multipart | RFC 7578 multipart parser | `multipart.core` | yes | y |
| jolt-lang/glimmer-datastar | Datastar v1 server side, SSE re-render from ratoms | `jolt.datastar.core` | yes | y |

### Data: `jolt-data`

| repo | what | require | tagged | T |
|---|---|---|---|---|
| jolt-lang/db | clojure.jdbc / next.jdbc over libsqlite3, libpq | `jdbc.core`, `next.jdbc` | yes | CI |
| jolt-lang/doltera | MySQL-protocol client for `dolt sql-server` | `doltera.core` | yes | y |
| jolt-lang/time | `java.time` shim + juxt/tick | `jolt.time` | yes | y |
| jolt-lang/transit-jolt | Transit 0.8 JSON | `jolt.transit` | yes | y |
| jolt-lang/jolt-fressian | Fressian | `fress.api` | no | y |
| jolt-lang/yaml | libyaml; clj-yaml + SnakeYAML-engine surface | `jolt.yaml` | yes | y |
| jolt-lang/xml | libxml2 as `javax.xml.stream`; data.xml emit | `jolt.xml` | yes | y |
| jlt-commons/duratom | durable atom, glimmer `IReactiveCell` | `duratom.core` | yes | y |
| jlt-commons/instaparse | instaparse port | `instaparse.core` | yes | y |

### GUI / TUI: `jolt-gui`

| repo | what | require | tagged | T |
|---|---|---|---|---|
| jolt-lang/glimmer | reagent-style core: ratoms, reconciler, no natives | `glimmer.core`, `glimmer.ratom` | yes | y |
| jolt-lang/glimmer-gtk | GTK4 backend | `glimmer-gtk.core` | yes | y |
| jolt-lang/glimmer-tui | ncursesw backend | `glimmer-tui.core` | yes | y |
| jolt-lang/glimmer-appkit | macOS AppKit backend | `glimmer-appkit.core` | yes | y |
| jolt-lang/glimmer-uikit | iPhone UIKit backend | `glimmer-uikit.core` | yes | y |
| jolt-lang/glimmer-android | Android Views backend | `glimmer-android.core` | yes | y |
| jolt-lang/glimmer-qt | Qt Quick backend; `./build-native` | `glimmer-qt.core` | yes | y |
| jolt-lang/glimmer-gl | geometry + shaders-as-data in GtkGLArea | `glimmer-gl.*` | yes | y |
| jlt-commons/glimmer-bui | Blender-look BUI backend | `glimmer-bui.core` | yes | y |
| jlt-commons/glitter | Replicant-style GTK4 renderer (one state atom) | `glitter.app` | no | y |
| jlt-commons/glitter-core | glitter reconciler, natives-free, test renderer | `glitter.core` | no | y |
| jlt-commons/glitter-uikit | glitter on AppKit | `glitter-uikit.app` | no | y |
| jlt-commons/glitter-gl | glitter GL geometry, `:gl-area` | `glitter-gl.*` | no | y |
| jlt-commons/nexus-jolt | cjohansen/nexus action/effect dispatch | `nexus.core` | no | y |
| jlt-commons/ftxui-jolt | reagent-style API over C++ FTXUI | `ftxui.core` | yes | y |
| jlt-commons/slipstream | GPU vector rendering (Slughorn), glimmer backend | `slipstream.core` | yes | y |
| jlt-commons/uikit-demo | glitter-uikit demo app | (app) | no | - |

### Games: `jolt-games`

| repo | what | require | tagged | T |
|---|---|---|---|---|
| jlt-commons/raylib-jlt | raylib 6 bindings (`net.b12n/raylib` key) | `net.b12n.raylib.*` | no | CI |
| jlt-commons/raylib-jolt-demo | 187 raylib examples, one sub-project each | (apps) | no | CI |
| jlt-commons/raygui-jlt | 24 raygui examples | (apps) | no | y |
| jlt-commons/raylib-ios | raylib + SDL2 on iPhone | `net.b12n.raylib-ios.*` | yes | y |
| jlt-commons/raylib-ios-demo | 137 scenes as iPhone apps | (apps) | no | CI |
| jlt-commons/raylib-android | raylib on Android; README: "not yet run on hardware" | `raylib.*` | no | y |
| jlt-commons/ents | flecs ECS, vybe-style API | `ents.core` | yes | y |
| jlt-commons/upbge-jolt | nREPL scripting for UPBGE/Blender | `upbge-jolt.bridge` | no | y |
| jlt-commons/graviton | physics game on raylib, writ specs | (app) | no | y |

### Concurrency: `jolt-concurrency`

| repo | what | require | tagged | T |
|---|---|---|---|---|
| jlt-commons/ebb | missionary port on fibers | `ebb.core` | yes | y |
| jlt-commons/ensemble | Erlang processes + OTP behaviours | `ensemble` | yes | y |
| jlt-commons/tapestry | structured concurrency over core.async | `tapestry.core` | yes | y |

### Observability, security, interop: `here`

| repo | what | require | tagged | T |
|---|---|---|---|---|
| jolt-lang/logging | tools.logging port, stderr backend; use key `org.clojure/tools.logging` | `clojure.tools.logging` | yes | y |
| jolt-lang/otel | OpenTelemetry traces/metrics/logs, OTLP/HTTP | `otel.sdk`, `otel.trace` | yes | y |
| jlt-commons/mulog | mulog 0.9.0 + shims; key `com.brunobonacci/mulog` | `com.brunobonacci.mulog` | no | y |
| jolt-lang/crypto | libcrypto as `javax.crypto`/`java.security`; require once to install | `jolt.crypto` | yes | y |
| jolt-lang/primitive-math | clj-commons/primitive-math on shims (compat, not speed) | `clj-commons.primitive-math` | no | y |
| jlt-commons/aws-api-jolt | stock cognitect aws-api | `cognitect.aws.client.api` | no | y |
| jlt-commons/jolt-openldk | Java jars via OpenLDK on SBCL (**alpha**) | `net.b12n.jolt.openldk` | no | y |
| jolt-lang/jolt-diplomat | Rust crates → bindings via Diplomat | `diplomat.runtime` | yes | - |

### Stats, ML, geo, transpiling: `here`

| repo | what | require | tagged | T |
|---|---|---|---|---|
| jlt-commons/augur | forecasting stats: posteriors, ledger, calibration, scoring | `augur.*` | yes | y |
| jlt-commons/lev | decision engine: typed questions → calibrated probabilities | `lev.agent` | yes | y |
| jlt-commons/overseer | local agent: sensors → lev → code | `overseer.core` | no | y |
| jlt-commons/dodeca | A5 pentagonal global grid | `dodeca.core` | yes | y |
| jlt-commons/clj-to-ys | Clojure → YAMLScript | `clj-to-ys.core` | no | y |

### Tooling, docs, meta: `here`

| repo | what | tagged | T |
|---|---|---|---|
| jlt-commons/writ | spec + proof gate for LLM-written code | yes | y |
| jlt-commons/jolt-metrics | code metrics, refactoring queue | yes | y |
| jolt-lang/nrepl | nREPL middleware + cider ops + client | yes | y |
| jlt-commons/jolt-nrepl-mcp | MCP server: agent in a persistent nREPL | yes | y |
| jlt-commons/jolt-lsp | LSP + MCP server + JSON CLI: navigation, diagnostics, refactors | yes | y |
| jlt-commons/nrepl-kimi-code-plugin | same, for Kimi Code | no | y |
| jlt-commons/setup-jolt, ci-builds | CI (above) | yes (`v1`) / no | CI |
| jlt-commons/docs-engine | static-site generator for project docs | yes | y |
| jlt-commons/awesome-jolt | curated list (~160 links) | no | - |
| jolt-lang/examples | example projects (below) | no | - |
| jolt-lang/clojure-test-suite | cross-dialect clojure.core suite, run against a baseline | no | y |
| jolt-lang/homebrew-jolt | Homebrew tap | no | - |
| jlt-commons/jlt-commons.github.io, meta, .github | org site content, proposal queue, community files | no | - |

The `jolt` skill covers `jolt-lang/jolt` and `jolt-lang/jolt-lang.github.io`
(user docs, https://jolt-lang.net/docs/).

## Libraries in detail

### writ: specs and proofs for code an agent writes

The spec namespace states signatures (`ann`), a state graph (`graph`),
refinements (`refine`) and laws (`law`). writ checks the code against it with
static rules, test.check generation and proofs. The code never mentions writ.
Use it as a test dependency only. Its README (2200 lines), `docs/` and
`skills/` have the rest.

```clojure
;; deps.edn  :test alias
:extra-deps {io.github.jlt-commons/writ {:git/url "https://github.com/jlt-commons/writ"
                                         :git/tag "<latest>" :git/sha "<sha>"}}

;; src/my/sort.clj
(ns my.sort)
(defn insert [x xs]
  (if (seq xs)
    (if (<= x (first xs)) (cons x xs) (cons (first xs) (insert x (rest xs))))
    (list x)))
(defn isort [xs] (if (seq xs) (insert (first xs) (isort (rest xs))) ()))

;; test/my/sort_spec.clj
(ns my.sort-spec (:require [writ.spec :refer [spec ann law graph refine]]))
(spec my.sort)                    ; unquoted. {:require :proved} as 2nd arg demands proofs
(ann insert [Nat (List Nat) -> (List Nat)])
(ann isort  [(List Nat) -> (List Nat)])
(defn ascending? [xs] (or (empty? xs) (apply <= xs)))
(refine Sorted [xs (List Nat)] (ascending? xs))
(graph sorting {:states {:unsorted (List Nat), :sorted Sorted}
                :edges  {:unsorted {[isort] #{:sorted}} :sorted {[insert Nat _] #{:sorted}}}})
(defn occurrences [x xs] (count (filter #(= x %) xs)))
(law permutation (forall [x Nat, xs (List Nat)]
                   (= (occurrences x (isort xs)) (occurrences x xs))))
```

`(spec ...)` defines a `writ-check` deftest, so
`(clojure.test/run-tests 'my.sort-spec)` runs the check. Checked: 1 assertion
passed (the first run takes about 60s to fetch test.check and core.logic).
`(writ.spec/check 'my.sort-spec)` (quoted) returns the report, and
`(writ.spec/plan 'my.sort-spec)` prints the plan. Runners that discover tests
by name must include `*-spec` namespaces.

### aws-api-jolt: AWS

Runs the **unmodified** Maven aws-api 0.8.847. This library adds the HTTP client
and host classes. All four AWS protocols were tested live upstream. No
streaming (bodies are held in memory), no redirects, no default timeout.

```clojure
{:deps {jlt-commons/aws-api-jolt {:git/url "https://github.com/jlt-commons/aws-api-jolt"
                                  :git/sha "<sha>"}   ; untagged: HEAD
        ;; REQUIRED until aws-api-jolt bumps its jolt-lang/time pin (the pinned
        ;; commit fails to load). Same key as aws-api-jolt uses:
        jolt-lang/time {:git/url "https://github.com/jolt-lang/time"
                        :git/tag "<latest>" :git/sha "<sha>"}
        com.cognitect.aws/endpoints {:mvn/version "1.1.12.772"}
        com.cognitect.aws/s3        {:mvn/version "868.2.1580.0"}}}         ; one jar per service

(require '[cognitect.aws.client.api :as aws])
(def s3 (aws/client {:api :s3 :region "us-east-1"}))   ; no :http-client needed
(aws/invoke s3 {:op :ListBuckets})
```

Checked with fake credentials: `aws/ops` works, and `invoke` sends a signed
request and gets AWS's `InvalidAccessKeyId` anomaly back. Never declare
`org.clojure/tools.logging` at the top level, because jolt-lang/logging supplies
that namespace.

### jolt-openldk: Java jars without a JVM (alpha)

It loads SBCL as a shared library and runs OpenLDK (bytecode → Lisp → machine
code) inside the jolt process. The README warns **alpha**: the API can change
without notice. Use it only for one irreplaceable Java library. Requirements:
JDK 25 at run time, a `bb build` that builds SBCL 2.6.9, OpenLDK and a 146 MB
core (needs sbcl, ocicl, cc), and jolt ≥ 0.8.22. There is no documented git-dep
coordinate: clone it and build. Not run here. From its README:

```clojure
{:jolt-openldk/deps {commons-codec/commons-codec {:mvn/version "1.17.1"}}} ; jars via jolt's resolver

(require '[net.b12n.jolt.openldk :as ldk])
(ldk/init!)
(ldk/call-static "java.lang.Math" "sqrt" "(D)D" 2.0)   ;=> 1.4142135623730951
(ldk/with-ref [xs (ldk/new-object "java.util.ArrayList" "()V")]
  (ldk/call xs "add" "(Ljava/lang/Object;)Z" "a")
  (ldk/to-string xs))                                  ;=> "[a]"
```

Methods are addressed by JNI descriptor. Objects are JavaRefs (`release!` or
`with-ref`). `implement` lets Java call Clojure fns.

### jolt-diplomat: Rust crates

`bind.clj` turns a `#[diplomat::bridge]` cdylib crate into
`generated/diplomat/*.clj` plus a C shim and its dylib. Needs Rust,
`cargo install jolt-diplomat-backend`, `diplomat-tool` 0.14–0.15 and cc. Not
run here. From its README:

```clojure
;; after: ./bind.clj path/to/my_capi --release   (bind.clj fetched from the repo's main)
{:paths ["src" "../generated"]
 :deps {jolt-diplomat-runtime/jolt-diplomat-runtime
        {:git/url "https://github.com/jolt-lang/jolt-diplomat"
         :git/tag "<latest>" :git/sha "<sha>" :deps/root "runtime"}}}

(require '[diplomat.runtime :as dr])
(dr/load! demo-dir "my_capi")
(require '[diplomat.my-type :as mt])
(dr/with-opaque [x (mt/parse "hello")] (println (mt/value x)))
```

Examples: url, regex, semver, base64, json, chrono, markdown, callback, sdl3,
tantivy. An opaque error type must define `message(&self, write: &mut DiplomatWrite)`,
or the first call fails at run time.

### augur: forecasting statistics

Pure functions over EDN, with no dependencies and no IO. Every parameter is
passed explicitly. Namespaces: `beta`, `gamma`, `layer`, `ledger`,
`calibrate`, `logit`, `hier`, `dynamic`, `enkf`, `pool`, `score`, `ftest`,
`changepoint`, `trees`, `analog`, `special`, `math`.

```clojure
{:deps {io.github.jlt-commons/augur {:git/url "https://github.com/jlt-commons/augur"
                                     :git/tag "<latest>" :git/sha "<sha>"}}}

(require '[augur.beta :as beta] '[augur.layer :as layer])
(def project (-> (beta/jeffreys) (beta/observe true {:forget 0.95}) (beta/observe false {:forget 0.95})))
(def machine (beta/from-counts 39 44 (beta/jeffreys)))
(layer/explain [project machine] {:strength 20.0 :level 0.9})
;=> {:mean 0.843 :interval [0.702 0.948] :evidence 1.95 :own 0.0888 :by-layer [...]}
```

Checked, along with the README's `ledger` example.

### dodeca: A5 global grid

Port of A5 v1.0.0-beta.4 covering indexing, hierarchy, measures and grid
disks. Coverings and polygon fill are not ported. IDs are unsigned 64-bit
values in a `long`, so compare them with
`dodeca.utils.unsigned/unsigned-compare` and exchange them as hex.

```clojure
{:deps {io.github.jlt-commons/dodeca {:git/url "https://github.com/jlt-commons/dodeca"
                                      :git/tag "<latest>" :git/sha "<sha>"}}}

(require '[dodeca.core :as a5])
(def cell (a5/lon-lat->cell [-0.1276 51.5074] 10))     ; [lon lat], res -1..30
(a5/cell->hex cell)                    ;=> "6397248000000000"
(a5/cell->hex (a5/cell->parent cell))  ;=> "6397260000000000"
(a5/cell->lon-lat cell)                ;=> [-0.15971839880376137 51.511842921513406]
```

Checked. Also `cell->boundary`, `cell->children`, `resolution`, `num-cells`
and `cell-area`.

### lev and overseer: local decision engine

**lev** answers typed questions (`noul` yes/no, `choice`, `score`) over a
state with calibrated probabilities. Backends: ModernBERT/mmBERT encoders, a
GGUF thinker via llama.cpp, Clef, and TinyDecide. It needs native builds and
checkpoints: `jolt kernels`, `jolt llama`, `jolt mlx` and `jolt prepare`, run
in lev's checkout or gitlib. Each encoder takes about 1.7 GB. It serves HTTP
and MCP. Depend on `io.github.jlt-commons/lev` (tagged; `jdep jlt-commons/lev`).
Not run here (no checkpoints).
From its README:

```clojure
(require '[lev.agent :as ag] '[lev.workflows :as wf])
(def agent (ag/load-agent "data"))
(def email (wf/load-workflow "workflows/email.clj"))
(ag/system-one agent (wf/state email {"subject" "Duplicate billing" "body" raw-body}) (wf/questions email))
```

Question and option order are model input, so pass `array-map`s. A workflow
file defines `questions` and, optionally, `state`. Run one with
`jolt -M:run <name> '{"text": ...}'`.

**overseer** (untagged; depend on HEAD's sha) builds
on lev. An agent is a map of `:sensors`, a `:prompt` with `$SENSOR` slots, a
`:decision` and a `:code` fn. Checked: `jolt -m overseer.core list`. The other
commands need `OVERSEER_DATA` set to a prepared lev data dir.

### clj-to-ys: Clojure → YAMLScript

Uses the idioms from yamlscript.org's tutorial. Forms outside its grammar
raise a parse error. The README gives no coordinate, so use
`io.github.jlt-commons/clj-to-ys {:git/sha "<sha>"}` (untagged: HEAD).

```clojure
(require '[clj-to-ys.core :as c2y])
(c2y/translate "(doseq [x (range 1 101)] (println x))")
;=> "!ys-0\neach x (1 .. 100):\n  say: x\n"
;; CLI: jolt -m clj-to-ys.main file.clj | --string '(...)' | stdin
```

Checked (library and `--string`).

### jolt-metrics

Complexity, Halstead, maintainability, coupling and git hotspots for
Clojure/jolt/Scheme, led by a ranked refactoring queue. To work on the
library, load the **`jolt-metrics` skill** (`~/.claude/skills/jolt-metrics/`).
To use it, run `jolt -m metrics.cli src [report.html|--format json|edn] [--top N] [--no-git]`
from a checkout of its newest tag, or the
release binary `jolt-metrics`. Checked with `--no-git --top 3`.

### jolt-lang/nrepl

Core jolt's `jolt nrepl-server` handles eval, load-file, clone and close. This
library adds sessions, interrupt, completion, lookup, the cider-nrepl op set
and a client.

```clojure
{:deps {jolt-lang/nrepl {:git/url "https://github.com/jolt-lang/nrepl"
                         :git/tag "<latest>" :git/sha "<sha>"}}
 :nrepl/middleware [nrepl.middleware/default-middleware
                    cider.nrepl/cider-middleware]}      ; drop cider for eval-only

(require '[nrepl.core :as nrepl])                       ; client
(let [t (nrepl/connect "127.0.0.1" 7888) s (nrepl/new-session t)]
  (nrepl/response-values (nrepl/message t {:op "eval" :code "(+ 1 2)" :session s}))  ;=> [3]
  (nrepl/close t))
```

Checked: the server with both middlewares, client eval `[3]`, and the
`complete` op. In editors, connect (jack-in starts a JVM; see the `jolt` skill).

### jolt-nrepl-mcp

An MCP server written in jolt that gives an agent a persistent nREPL session:
`nrepl_eval`, `nrepl_load_file`, and `nrepl_start`/`stop`/`connect`/
`status`/`interrupt`/`disconnect`. Eval and load-file input is syntax-checked
and safely repaired first (via jolt-lsp's `jolt-lsp.syntax`). Since v0.3.0 the
standalone `clj_check` and `clj_replace` tools are gone: use jolt-lsp's
`jolt_check` and `jolt_replace_form`. It ships as a Claude Code plugin,
`jolt-nrepl`, whose skill covers the workflow. Install it with
`claude plugin marketplace add <checkout> && claude plugin install jolt-nrepl@jolt-nrepl-mcp`.
Release binaries don't need jolt installed.

### jolt-lsp

One engine over an in-memory index, with three transports: `jolt-lsp lsp`
(editors), `jolt-lsp mcp` (agents) and `jolt-lsp --json <command>` (CLI).
MCP tools: index, search, definition, references, hover (with source),
symbols, diagnostics (built-in + clj-kondo), call hierarchy, impact, ns deps
and cycles, forms, context packs, syntax check/repair, rename, clean-ns,
add-require, structural replace/insert, refactors (sort-requires,
inline-symbol, destructure-keys, move-form, …), namespace rename with file
moves, extraction into a new namespace, declare cleanup, structural diff
(against text or a git revision), cljfmt formatting, and batch reads. As a
library: `jolt-lsp.api`, `jolt-lsp.syntax` (check and repair),
`jolt-lsp.surgeon` (restructuring plans) and `jolt-lsp.sdiff` (structural
diff); EPL-2.0 with GPL-2.0-or-later as a Secondary License. Edits preview as diffs and need `apply: true`. Register with
`claude mcp add --scope user jolt-lsp -- /path/to/jolt-lsp mcp`; release
binaries for macOS arm64 and Linux x86_64. See the `jolt-lsp` skill.

### docs-engine, awesome-jolt, clojure-test-suite

- **docs-engine** turns a project's `docs/` (`site.edn`,
  `guide/*.md`, optional `templates/home.html`) into a Pages site through
  ci-builds' reusable `site.yml`. Build with `jolt run build ../proj` (bare
  `jolt build` is the compiler); `test` and `serve` need `bb`. Set
  `:base-path "/proj"`, or every link breaks.
- **awesome-jolt**: about 160 curated links: official and community libs,
  apps, JVM libs known to run on jolt, guides. Check it before binding
  something yourself. See also the user docs page `libraries.md`.
- **clojure-test-suite**: the cross-dialect `clojure.core` suite (owned by
  jank; 238 core test files). jolt fails parts of it on purpose, so
  `jolt.yml` fails only when a namespace regresses against
  `jolt/baseline.txt`. Run it with `jolt -M:jolt --report`. Useful for edge
  cases.

### jolt-lang/examples

Run with `jolt run -m app.core` unless noted. Checked on jolt 0.8.25:
commonmark-app, hiccup-app, basic-example, malli-app, markdown-app,
http-client-app.

| example | shows |
|---|
| basic-example | smallest app, `jolt build` to a binary |
| commonmark-app | dependency-free Markdown → HTML with its own tests |
| hiccup-app, markdown-app, malli-app | hiccup / markdown-clj / malli from git, unmodified |
| http-client-app | jolt-lang/http-client on real HTTPS: TLS, redirects, gzip, JSON POST |
| ring-app | guestbook: ring-defaults, reitit, Selmer, honeysql, tick, SQLite on ring-chez-adapter |
| glimmer-datastar | counter + list over SSE |
| reactive-dashboard | live `/proc` monitor: datastar + ebb + domino + babashka.process (Linux) |
| nrepl-example | app embedding nREPL and parking (headless-device pattern) |
| ffi-examples | struct-by-value, libffi, PortAudio callback (`jolt check`/`structs`/`libffi`/`portaudio`) |
| glimmer-app, glimmer-tui-example, todomvc-uikit | glimmer on GTK4 / terminal / AppKit |
| glimmer-gl-app, fps-demo | 3D cathedral with shadows; q1k3 FPS in GtkGLArea |
| image-dump-example | `jolt.image`: save and restore a running glimmer program |
| ray-tracer, ray-tracer-multi | compute benchmark; namespace-boundary cost; PNG output |

fps-demo, glimmer-app, glimmer-gl-app and image-dump-example use
`:local/root "../../glimmer*"` and need sibling checkouts of those repos
(switched to git deps in examples#48, not merged yet).

## Known issues

Open upstream fixes; drop an item once its fix is merged.

- **aws-api-jolt** pins a `jolt-lang/time` commit whose `locale_data.clj`
  fails to load (`analyze/invalid-ns-form ... got: Mar`). Override
  `jolt-lang/time` with its latest tag, as shown above, until the bump lands.
- **examples**: the README lists only some of the dirs, and some READMEs still
  say the HTTP client/server/SQLite are built into jolt (they are git deps).
  A few apps name a task `run`, which the built-in shadows (with a warning).
  Fixes are in examples#48, not merged yet.
- **docs-engine** README says jolt doesn't bundle `clojure.test`. It does.
- **clojure-test-suite** `doc/jolt.md` says glibc ≥ 2.35. The release floor is 2.17.
- **homebrew-jolt** says there's no Intel-mac build, but jolt releases ship
  `x86_64-macos`.
