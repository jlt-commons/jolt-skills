# jolt vs JVM Clojure

Source: `differences.md`, `host-interop.md`, `getting-started.md` (Memory,
Stack depth). The authority is https://github.com/jolt-lang/jolt/blob/main/test/conformance/known-divergences.edn.

## Same as the JVM

Persistent collections (incl. RRB vectors), the numeric tower (bigints, ratios,
`BigDecimal` with `M` literals and `with-precision`), lazy seqs, transducers,
destructuring, multimethods + hierarchies, protocols, records, `deftype`,
`reify`, `proxy` (against modelled interfaces), metadata, atoms/refs/STM/agents,
`future`/`promise`/`pmap`, core.async, `eval`/`load-string`/`defmacro` at
runtime, `clojure.test`, `=` vs `==` semantics.

## Runtime differences (no JVM)

- **Process lifetime** (JVM rules since 0.8.16): a non-daemon `Thread.`
  holds the exit until it finishes; futures/agents/`pmap` hold it ~60 s (call
  `shutdown-agents`); executors until `.shutdown`. `a/thread`, `go` blocks and
  fibers do not hold it. A server should park (`jolt.host/park-until-interrupt`).
- **No classloaders**: `Class/forName` knows only shimmed classes. No service
  loaders, no classpath scanning.
- **Memory**: heap ceiling defaults to 25% of RAM (container-aware); exceeding it
  throws a catchable `OutOfMemoryError`. `JOLT_MAX_HEAP=2g|512m|off`. GC knobs are
  `JOLT_*` env vars named after JVM flags; `JOLT_GC_LOG=1` ≈ `-verbose:gc`.
- **Stack**: lives on the heap; millions of frames are fine. The limit is 80% of
  the heap ceiling (`JOLT_STACK_LIMIT`). Overflow throws `StackOverflowError`.
- **Tail calls are guaranteed** (Chez). `(.getStackTrace (Thread/currentThread))`
  is empty; exceptions still carry traces (`.printStackTrace` works).
- **Reflection** answers from jolt's registries: hierarchy (`supers`, `isa?`,
  `instance?`) is modelled, member lists mostly aren't.

## Language-level divergences

- One integer type: `(class (int 5))` → `Long`; `(instance? Float 1.5)` → true.
- `(format "%x" -1)` → `"ff"`.
- All lazy seqs are one class; chunking differs (mapcat/dedupe realize nothing on construction).
- Strings index codepoints: `(count "😀")` → 1.
- Regex: irregex with a Java-grammar translator. Capturing groups use a
  backtracker, group-free patterns a DFA. `UNICODE_CHARACTER_CLASS` not applied.
- Reader: `#?()` read in every file type; features `#{:jolt :clj :default}`;
  `(read-string "")` → nil; unknown tags read as inert tagged literals in
  `read-string` (an error in compiled source); `#$"…~{x}"` string interpolation
  is jolt-only syntax.
- `^:private` not enforced across namespaces.
- A `require` cycle on one thread loads (partial ns) instead of erroring.
- `compare-and-set!` compares by value.
- Lazy seqs print by content (`(str (map inc [1 2]))` → `"(2 3)"`); records print `user.R{:a 1}`.
- More permissive: `(.-field a-map)` reads the key, `(keys [[:a 1]])` works,
  `line-seq`/`file-seq` take paths, `spit` is atomic, `with-open` closes anything
  with `:close`.
- `run-tests` with no args runs every registered test.
- `java.version` property is nil; branch on `jolt.version`.

## What is shimmed (summary; full list in host-interop.md)

- `Math`, boxed numbers and parse methods, `Character`, `System` (properties
  `os.name` = "Mac OS X"/"Linux"/"Windows", `os.arch`, `user.home`, `user.dir`,
  `jolt.version`, …), `Thread/sleep`.
- `String`/`String/format` (full `java.util.Formatter`), `StringBuilder`
  (chunked: O(1) append).
- `java.util` collections (ArrayList, HashMap, Linked*, ArrayDeque,
  PriorityQueue, …), `java.util.concurrent` (Executors, queues, atomics,
  ConcurrentHashMap, Semaphore, locks, ThreadLocal).
- `Pattern`/`Matcher` (regions, `find(int)`), `java.io` readers, writers and
  streams, `File`, `java.nio.file` `Path`/`Files`, `RandomAccessFile`.
- `Date`/`Calendar`/`SimpleDateFormat`, base `java.time` (Instant, Local*,
  Duration, Period, …). Formatting and zones need `jolt-lang/time`.
- `URI`/`URL`, `Socket`/`ServerSocket`/`InetAddress`, `UUID`, `Base64`,
  `Properties`, charsets, `Normalizer`, `ProcessBuilder`/`Process`,
  `Runtime.exec`, the standard exception classes.
- Absent: `gen-class`, most `java.math.BigDecimal` methods, JDBC
  `DriverManager` (use `jolt-lang/db`), `javax.net.ssl` (use `http-client`),
  `java.net.http` client (use `http-client`), anything AWT/Swing.

## Making a JVM library work

Run it and read the error. Each missing-host error maps to one registration in
`jolt.host` (`extend-class!`, `register-class-supers!`, `register-enum!`, or the
`__register-class-ctor!`/`__register-class-methods!`/`__register-class-statics!`/
`__register-instance-check!` seams). Put them in a `myapp.shims` ns required
first. Worked example (`java.util.StringJoiner`) in host-interop.md.

## Concurrency extras

- core.async `go` runs on OS threads by default. Bind
  `clojure.core.async/*go-backend*` to `:fiber` for green threads (hundreds of
  thousands are fine). See `fibers.md`.
- `jolt.continuations/letcc` gives escape continuations (cheap early exit).
- `jolt.image` dumps and restores program state, closures included.
