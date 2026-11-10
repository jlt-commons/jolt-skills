# Native interop: jolt.ffi

Source: `native-interop.md` and `api/ffi.md` (the full API reference) in
https://jolt-lang.net/docs/. Real code:
https://github.com/yogthos/newsroom/blob/main/src/newsroom/tts.clj, and jolt-lang `db`, `http-client`,
`crypto`, `xml`, `glimmer-gtk`.

jolt has no `java.*` for the outside world, so C is reached directly. The layer
is thin and explicit: you declare the library, type each function, and manage
foreign memory yourself (no finalizers).

## 1. Declare the library in deps.edn

```clojure
:jolt/native [{:name "sqlite3"                              ; label for errors only
               :darwin ["libsqlite3.0.dylib" "libsqlite3.dylib"]   ; versioned name first
               :linux  ["libsqlite3.so.0" "libsqlite3.so"]
               :windows ["sqlite3.dll"]
               :static {:archive "/opt/homebrew/lib/libsqlite3.a"}} ; optional: link into `jolt build`
              {:name "pq" :darwin [...] :linux [...] :optional true} ; missing = skipped
              {:name "libc" :process true}]                          ; symbols already in the process
```

- A candidate with a `/` is a **path relative to the project** (`native/libshim.so`);
  a bare name goes through the loader search path.
- `:optional true`: check `(ffi/loaded? "libpq.so.5")` before use.
- A project inherits its dependencies' `:jolt/native`.
- `:static` can be per platform: `{:darwin {:archive "native/libx.a"} :linux {:lib "x" :libdir "native"}}`.
  `{:archive …}` force-loads the whole `.a` (the reliable form); `{:lib :libdir}` links `-lNAME`.
- Outside a project: `(ffi/load-library "libfoo.dylib")`, or
  `(ffi/load-library {:darwin "…" :linux "…"})`; `(ffi/load-library)` gives the
  process's own symbols. `(ffi/find-symbol "name")` checks a symbol exists.
- Plain libc symbols (`strlen`, `getpid`, `socket`) need no declaration.

## 2. Bind functions

```clojure
(require '[jolt.ffi :as ffi])

(ffi/defcfn sqlite3-open  "sqlite3_open"  [:string :pointer] :int)
(ffi/defcfn c-recv        "recv" [:int :pointer :size_t :int] :ssize_t :blocking)
(ffi/defcfn c-fcntl       "fcntl" [:int :int :& :int] :int)          ; variadic
(ffi/defcfn c-open        "open" [:string :int :& :int] :int {:capture-native-error true})
(def strlen (ffi/foreign-fn "strlen" [:string] :size_t))             ; anonymous
```

Types: `:int :uint :long :ulong :int64 :uint64 :int32 :uint16 :size_t :ssize_t
:iptr :uptr :double :float :char :uint8`(`:u8 :byte`) `:pointer`(`:void*`)
`:string :void`, plus `[:by-value <struct-layout>]`.
Pointers are plain integers. `:string` args are copied to a NUL-terminated
UTF-8 C string for the call; a `:string` return is read back.

- **`:blocking`** on anything that can wait (I/O, locks, sleeps, long compute
  like inference). Without it a thread parked in C pins the GC for every
  thread. `JOLT_GC_STALL=1` reports such stalls.
- **`:&` marks variadic C functions**, fixed params before it, the concrete
  variadic arg types after. Required on Apple arm64: a fixed-arity binding to
  a variadic function silently passes garbage. Not combinable with `:blocking`.
  One binding per tail shape.
- **errno**: `(ffi/errno)` / `(ffi/errno-message)` immediately after the call,
  or `{:capture-native-error true}` to get `[result errno]` back atomically
  (combine with `{:blocking true …}` as needed).

## 3. Memory

```clojure
(ffi/alloc n) (ffi/free p)            ; zeroed; you free it
(ffi/sizeof :pointer)
(ffi/read p :int [offset])            ; typed read
(ffi/write p :int value [offset])     ; VALUE before offset (changed in 0.8.0)
(ffi/string->ptr s) (ffi/ptr->string p)
(ffi/read-array p n)  (ffi/write-array p bytes)   ; binary-faithful byte arrays
(ffi/read-bytes p n)  (ffi/write-bytes p s)       ; UTF-8 strings
(ffi/null) (ffi/null? p) (ffi/address p)
```

Scope allocations instead of pairing alloc/free by hand:

```clojure
(ffi/with-out [pp :pointer]                 ; out-parameter cell
  (when-not (zero? (sqlite3-open path pp))
    (throw (ex-info "open failed" {:path path})))
  (ffi/read pp :pointer))

(ffi/with-alloc [buf 4096] ...)
(ffi/with-c-string [s "SELECT 1"] ...)
(ffi/with-c-string-array [argv 2] ["a" "b"] ...)

;; one lifetime for many allocations, strings and callbacks
(ffi/with-arena [a]
  (let [err  (ffi/alloc a 1024)
        path (ffi/string->ptr a "/tmp/x")]
    ...))
(with-open [a (ffi/confined-arena)] ...)    ; same idea as a closeable
```

Pointers are valid only inside the scope. Handles C gives you are still yours
to close (`sqlite3_close`, etc.).

## 4. Structs

Prefer layouts. Chez computes size, alignment and offsets:

```clojure
(def date (ffi/layout [:struct [[:year :int32] [:month :uint8] [:day :uint8]]]))
(ffi/layout-size date)                  ; 8
(ffi/with-layout [p date]
  (ffi/write-field p date :year 2026)
  (ffi/read-field p date :year))
;; nested: (ffi/read-field p event [:when :year]); arrays: [:array :double 3], path [:matrix 1 2]
;; by value: (ffi/defcfn f "f" [[:by-value [:struct [...]]]] :int64)  ; write the descriptor literally
```

Unions, bitfields and packing aren't modelled. Lay those out by byte offset
with `ffi/read`/`ffi/write`, and branch offsets per OS where the ABI differs.

## 5. Callbacks and calling into jolt

- `(ffi/callback arena f [:pointer :int] :void)` gives a C function pointer to a
  jolt fn (see `api/ffi.md` for `foreign-callable` and `:collect-safe` when C
  calls back from its own threads).
- `jolt build --library` makes a shared object; export with
  `(jolt.ffi/export! "add" add [:int :int] :int)`. C calls `jolt_library_init`,
  then `jolt_lookup("add")`. Same-thread rule, or `:collect-safe` exports +
  `jolt_library_release_thread()`.

## 6. Shipping your own C

Put the source and build product in `native/`, build it with a task, and name
that task in the spec's `:build` key so consumers can use the library as a
plain git dep:

```clojure
{:jolt/native [{:name "shim"
                :darwin ["native/libshim.dylib"]
                :linux  ["native/libshim.so"]
                :build  "native"                         ; task in THIS deps.edn that produces it
                :static {:archive "native/libshim.a"}}]   ; if you also build the .a for binaries
 :tasks
 {:requires ([babashka.fs :as fs])
  :init (def lib (str "native/libshim."
                      (if (re-find #"^Mac" (System/getProperty "os.name")) "dylib" "so")))
  native {:doc "compile native/shim.c"
          :task (when (seq (fs/modified-since lib ["native/shim.c"]))
                  (shell "cc" "-O2" "-fPIC" "-shared" "native/shim.c" "-o" lib))}}}
```

How `:build` behaves (jolt 0.8.26+, i.e. the first release after 0.8.25 that
includes jolt#1571; 0.8.25 and older ignore the key):

- When a declared file for this platform is missing, jolt runs `jolt run <task>`
  in the library's root (cwd and `JOLT_PWD`), then retries the load. Not when
  the file exists but fails to load, and not for `:optional` specs.
- Consumers add the git dep and nothing else: the first run (or `jolt build`)
  builds it inside `~/.jolt/gitlibs/...`. Task output goes to stderr.
- Once per process per task; concurrent processes serialize on a
  `.jolt-native-build.lock` dir in the library root.
- `JOLT_NATIVE_BUILD=0` turns it off (CI that prebuilds); the error then names
  the task and dir. A failed build names lib, task, dir and exit status.
- A project's OWN spec is auto-built for `run`/`-M`/`build` but not from its
  tasks: a task that needs the lib should `:depends` on the build task.
- Make the task idempotent (skip when up to date, as above), use only paths
  relative to the library root, and fetch external sources at a pinned commit
  into `vendor/` (or take a `*_HOME` env var), since it runs in a gitlib
  checkout with no sibling repos.

On jolt 0.8.25 and older, a consumer builds it by hand in the gitlib checkout:
`cd "$(dirname "$(jolt -Spath | tr ':' '\n' | grep LIBNAME | head -1)")" && jolt native`.

`.gitignore` the artifacts (`native/*.so native/*.dylib native/*.a native/*.dll`).
For a large native dependency (newsroom's llama.cpp), have the task fetch a
pinned commit into `native/` and run a build script there.

## Checklist

- Per-OS candidates, versioned names first; `:optional` for feature-gated libs.
- Exact C types; `:blocking` on anything that waits; `:&` for variadics.
- Every alloc freed: prefer `with-*` macros or an arena.
- Check return codes and NULLs; `throw (ex-info … {:errno (ffi/errno)})`.
- LP64-correct widths/offsets; macOS vs Linux struct differences in one seam.
- Test FFI code in a built binary too if it'll ship as one (static linking path).
