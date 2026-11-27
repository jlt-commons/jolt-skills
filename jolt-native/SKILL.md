---
name: jolt-native
description: "Write native regions on Jolt (Clojure on Chez Scheme): blocks of numeric code compiled to C (linked in by `jolt build`, JIT-compiled in process by MIR under `jolt run` and in the REPL), borrow-checked at compile time so the arrays they create are freed deterministically and nothing leaks. Use when a jolt program has a hot numeric loop that hints and primitive arrays have not made fast enough (array kernels, simulation steps, n-body, DSP, codec inner loops, binary record parsing); when the user mentions jolt.native, `native`, `defnative`, `defextern`, `native-fn`, `:specialize`, `jolt.native.layout`, native regions, `^:hold-gc`, or compiling a Clojure function to C; when choosing between `defextern` and `jolt.ffi` to call a C function; or when a native region refuses to compile and the message needs explaining."
---

# Native regions on jolt

Read the `jolt` skill first for projects, deps.edn and `jolt build`. This skill
covers `jolt.native`: a `native` form whose body is compiled to C, and the
tools around it (`defnative`, `defextern`, `native-fn`, `jolt.native.layout`).

```clojure
(require '[jolt.native :refer [native defnative]])

(defn norm [^doubles xs]
  (native [^doubles xs]
    (loop [i 0 s 0.0]
      (if (< i (alength xs))
        (recur (inc i) (+ s (* (aget xs i) (aget xs i))))
        (Math/sqrt s)))))
```

- A region always runs as native code, from the same generated C:
  - In a binary from `jolt build` it is compiled by the C compiler and linked
    in. The build needs one (`JOLT_CC`, or `cc` on `PATH`).
  - Under `jolt run`, in tests and in the REPL, jolt compiles it in process
    with MIR (a vendored C JIT) when its call site loads, so a hot loop runs
    at native speed while you tune it. `(jolt.native/jit?)` says whether this
    process can.
  - Where there is no native path (the gambit target, a platform MIR does not
    support) calling a region raises `UnsupportedOperationException`.
- Develop and test it like any other Clojure code: the REPL runs the real
  native path, not an emulation.
- The region is checked when it is compiled, in the REPL too. A region that
  would misuse an array, or uses anything outside the subset, is a compile
  error at load time, before any call.
- Needs jolt 0.8.31+ for the JIT, `native-fn`, `:specialize`, `^bytes` and
  `jolt.native.layout`; older releases ran regions as interpreted Jolt outside
  a build. Check that `(require 'jolt.native)` works.

## When to reach for it

First try plain Clojure with `^double`/`^long` hints and primitive arrays (the
`jolt` skill's `performance-idioms`). Use a region when that is still too slow
and the work is numeric over arrays: a region ran an n-body step about 5.5x
faster than the same hinted Jolt in an optimized build, bit-identical.

Pay attention to what one call costs. The boundary itself is a few nanoseconds
(a borrowed array is the Chez flvector itself, no copy) plus about 45ns for the
default pinned call. Converting a persistent vector to an array costs about
14ns an element, so keep the data in `double-array`/`long-array` across calls
and give each region enough work per call. A region per element of a seq is
slower than the Jolt it replaces.

## The binding vector: the only hints

The vector names the locals the region reads from the enclosing scope. Each
needs a hint; an unhinted name is a compile error.

| Hint | Crosses as |
|---|---|
| `^long`, `^double` | a scalar, converted as `long`/`double` would |
| `^boolean` | must be a boolean |
| `^doubles`, `^longs` | an array the region **borrows**: reads and writes the caller's array in place, cannot keep or return it |
| `^bytes` | a `byte-array` the region only reads, each element a signed byte as a long; `aset` and `aclone` on it are compile errors |

Everything inside is inferred. Do not add hints inside the body.

- literal: `1` long, `1.0` double, `true` boolean
- `let` binding: its value's type; `loop` var: its initial value's type
- arithmetic: long if all operands are long, double once one is double, folded
  left pair by pair
- comparisons, `zero?`/`pos?`/`neg?`, `not`/`and`/`or`: boolean
- `aget`: the array's element type
- helper call: what the helper returns for those argument types

## What the body may use

- `let`, `if`, `when`, `when-not`, `do`, `loop`/`recur`, `dotimes`, `and`, `or`, `not`
- `+ - * /`, `inc`, `dec`, `quot`, `rem`, `mod`, `< <= > >= == = not=`, `zero?`, `pos?`, `neg?`
- `long`, `double`
- `bit-and`, `bit-or`, `bit-xor`, `bit-not`, `bit-shift-left`, `bit-shift-right`,
  `unsigned-bit-shift-right` (JVM masked shift counts). A mask by a
  non-negative constant bounds an index, so `(aget xs (bit-and i 3))` drops
  its bounds check.
- `aget`, `aset`, `alength`; `double-array`, `long-array`, `aclone` create arrays the region **owns**
- `Math/sqrt`, `sin`, `cos`, `tan`, `exp`, `log`, `floor`, `ceil`, `pow`, `atan2`
- your own macros (they expand inside the region), `defnative` helpers, and C
  functions declared with `defextern`

Nothing else: no maps, vectors, seqs, strings, closures, `fn`, interop, or calls
to ordinary functions. No destructuring in `let`/`loop`. Do the non-numeric work
outside and pass arrays and scalars in.

A region returns a long, double, boolean, `nil`, or an array it owns, which
arrives as a fresh `double-array`/`long-array`.

## Ownership (Carp's rules)

An array has one owner. Binding it to another name, returning it, or passing it
to `recur` gives it away (moves it). `aget`, `aset`, `alength`, `aclone` and
helper calls borrow it. When the owner's scope ends the array is freed.

- To keep using an array after giving it away, give away `(aclone a)` instead.
- A region cannot return an array it borrowed (a `^doubles` param). Return
  `(aclone xs)`, or write into the caller's array with `aset` and return `nil`.
- Inside a `loop`, an iteration that continues (`recur`) may not give away an
  array from outside the loop, since the next iteration would use it again. The
  exit path may.

## Helpers: defnative

```clojure
(defnative sum-sq [xs]
  (loop [i 0 s 0.0]
    (if (< i (alength xs)) (recur (inc i) (+ s (* (aget xs i) (aget xs i)))) s)))

(defn norm [^doubles xs] (native [^doubles xs] (Math/sqrt (sum-sq xs))))
```

- Parameters take no hints. The helper is compiled once per combination of
  argument types it is called with, so one helper serves `doubles` and `longs`.
- Its result type comes from the body. Recursive and mutually recursive helpers
  are solved from the base case (use `declare` for mutual recursion as usual).
  A return hint `(defnative ^long fib [n] ...)` is optional and checked.
- A helper borrows its array arguments unless its body gives one away (returns
  it, or passes it to a helper that takes it). Then it takes ownership and the
  caller's binding is moved. This is inferred; nothing is annotated.
- Outside a region the name is an ordinary function over the same body.

A helper can give a body per platform, chosen by the C compiler:

```clojure
(defnative sum [xs]
  (on "defined(__aarch64__)" ...)
  (on :default ...))
```

The first guard (a C preprocessor condition) that holds is compiled; with no
`:default`, an uncovered platform fails the build. The bodies must compute the
same thing, and agree on result type and on which arguments they take. Outside
a region the helper's plain-Clojure fn runs the `:default` body (or the first).

Guards can test CPU features too (`"defined(__AVX2__)"`). `jolt build`
compiles for the C compiler's default target, usually the baseline, so those
macros are off there. The JIT compiles for the CPU it runs on, as
`cc -march=native` would, so it picks the SIMD body where the machine has it.
`(jolt.native/cpu-features)` lists what the JIT targets (`:avx2`, `:fma`,
`:neon` ...); `JOLT_MIR_CPU=baseline` makes it target the baseline (to check
the portable body). MIR has no SIMD intrinsics: a SIMD body calls C that has
them, through `defextern`.

## Calling C: defextern

```clojure
(defextern ^double fast-erf [^double x])
(defextern ^long next-seed [^long s] {:c "xs_next" :header "xorshift.h"})
```

- Scalars `^long ^double ^boolean`; no result hint means void. Array params
  `^doubles`/`^longs` arrive in C as `(double *xs, int64_t n)` /
  `(int64_t *xs, int64_t n)`, valid for the call only. A borrowed `^longs`
  region param must be passed as `(aclone xs)` (it is stored as fixnums).
- Declared from the hints, or `#include`d via `:header` (`"x.h"` or
  `"<math.h>"`). Use `:header` for anything libc/libm already declares, so the
  prototype can't conflict (`int64_t` is `long long` on macOS, `long` on Linux).
- Outside a region the name calls the same function through `jolt.ffi`. With
  scalar params it expands to exactly `(jolt.ffi/defcfn name "c_name" [...] ...)`,
  so it costs nothing over plain FFI. Array params are copied into foreign
  memory and back on every call outside a region.
- `jolt build` links it: it must come from a `:static` `:jolt/native` entry (or
  libc/libm). The JIT finds it among the libraries this process has loaded, so
  a dynamic-only library works under `jolt run` but not in a binary.
- The JIT reads a `:header` with MIR's C compiler, which cannot parse every
  system's headers (Android's bionic). A header that only declares the
  function can be swapped for the hinted prototype.
- The checker can't see into C: the region is only as safe as the function.

### defextern or jolt.ffi?

`defextern` is a narrow front end on `jolt.ffi` that region code can also call.

| | `defextern` | `jolt.ffi/defcfn` |
|---|---|---|
| Types | `^long ^double ^boolean`, `^doubles`/`^longs` arrays | all: `:int32`, `:float`, `:pointer`, `:string`, structs by value, callbacks, `:blocking`, variadics |
| Callable in a region | yes, a direct C call with no marshalling | no |
| Arrays outside a region | copied in and back per call | you manage pointers and memory |
| In a `jolt build` binary | must be statically linked (libc/libm or a `:static` lib) | can load a shared library at runtime |

- Numbers in, a number out, and the function might be called from a region
  (`cbrt`, `erf`, a kernel in your own C): `defextern`, with `:header` when
  libc/libm already declares it. Same cost as `defcfn` from plain Clojure.
- Strings, pointers, handles, structs or callbacks (sqlite, GTK, OpenSSL), or
  a library only available as a `.so`/`.dylib`: `jolt.ffi` (the `jolt`
  skill's `references/ffi.md`).
- A hot loop calling a C function with arrays from plain Clojure: move the
  loop into a region rather than paying the per-call array copy.

## Pinned (default) vs ^:hold-gc

Both are memory safe. The choice is what other threads' GC does while the C runs.

- Default (pinned): other threads keep running and collecting; the borrowed
  arrays are pinned for the call. About 45ns a call.
- `(native ^:hold-gc [^double x] (* x x))`: a plain call, about 2.5ns, that
  holds every other thread's collection until the region returns. Only for
  regions that finish in microseconds; a long one stalls the whole process's GC.

## Specializing on runtime values

```clojure
(defn msum [^long n ^doubles m]
  (native ^{:specialize [n]} [^long n ^doubles m]
    ...))
```

- The JIT compiles a variant per distinct value of the named scalar params
  that the call site sees, with the value as a constant, so the range analysis
  can drop checks it could not for an unknown `n` (a 512x512 matrix sum ran
  about 1.7x faster).
- Budget: `:max-variants` in the same map (8 by default). Values past it, and
  a `jolt build` binary (no JIT), run the region as written; the answers are
  the same either way.
- Only `^long ^double ^boolean` params; to specialize on an array's size,
  pass the size as a long.
- `(jolt.native/specializations)` lists the variants each site has.

## Regions from data: native-fn

```clojure
(def sq (jolt.native/native-fn '[^long n] '((* n n))))
(sq 7) ;=> 49
```

- Compiles a region at runtime from a params vector and body forms, with the
  JIT, and returns a fn that runs it natively. Use it for code generated from
  what the program only learns at runtime: a schema, a record layout, a size.
- Compile errors throw from `native-fn` itself. Names in the body resolve in
  `*ns*` (or pass an ns as the third argument).
- Each distinct region is kept for the life of the process. Generate one per
  shape and pass the values that vary as parameters; one per request grows
  without bound.
- Needs the JIT: a `jolt build` binary raises `UnsupportedOperationException`.

## Binary record layouts: jolt.native.layout

```clojure
(require '[jolt.native.layout :as layout])

(def header [[:magic :u32] [:version :u8] [:pad 1] [:count :u16] [:size :i64]])
(def parse (layout/parser header))          ; or (layout/parser header :endian :big)
(vec (parse buf 0))                          ;=> [magic version count size]
(def sizes (layout/column header :size))
(vec (sizes buf))                            ;=> :size of every whole record in buf
```

- Field types `:u8 :i8 :u16 :i16 :u32 :i32 :i64`, `[:pad n]` to skip bytes;
  little-endian by default. Offsets, widths and sign extension become
  constants in the region's C.
- `buf` is a `byte-array`. A read past its end raises
  `ArrayIndexOutOfBoundsException`.
- Built on `native-fn`, so it needs the JIT.

## What the compiler does for you

- Checks it can prove never fire are dropped: loop counters, `(< i (alength a))`
  scans, indexes built from them. Facts that depend on an array argument's
  length run behind one guard, so a short array still gets the exact exception.
  Write the natural `(< i (alength xs))` loop; don't hand-hoist bounds.
- A constant-size array of up to 256 elements that stays in the function (not
  returned, not carried by `recur`, not taken by a helper) lives on the C stack.
  A scratch `(double-array 3)` inside a loop costs no allocation, and if it is
  only indexed by constants it becomes plain C variables (registers).

## Semantics that differ from plain Jolt

Regions follow the JVM's primitive semantics, whichever compiler built the C:

- Long overflow raises `ArithmeticException` ("integer overflow"). Plain Jolt
  promotes to a bignum; a region does not.
- Out-of-range index: `ArrayIndexOutOfBoundsException`. Sizes go through
  `intValue` like the JVM.
- A borrowed `long-array` stores Chez fixnums: storing a value outside
  -2^60..2^60-1 raises. Owned long arrays have no such limit.
- Floating point matches Jolt bit for bit (the C is built with `-ffp-contract=off`).

## Compile errors and fixes

Every message starts `native region:`.

| Message (abridged) | Fix |
|---|---|
| `parameter x needs a type hint` | hint it on the vector: `^double x` |
| `(/ long long) is a ratio in Clojure` | `quot`, or make an operand a double |
| `= compares two values of the same scalar type` | use `==` across number types |
| `a test must be a boolean` | `(pos? n)`, `(not (zero? n))`, not `(if n ...)` |
| `recur passes :double for loop var s` (declared long) | start the loop var as `0.0` |
| `if branches have different types` | make both branches the same type, e.g. `(double x)` |
| `uses a after it was given away (moved)` | give away `(aclone a)`, or reorder uses before the move; if a helper took it the message names the helper and the argument |
| `a region cannot return an array it borrowed` | return `(aclone xs)` |
| `loop iteration` ... gives away an outer value | move only on the exit path, or `aclone` |
| `not allowed in a native region: f` | not in the subset (also for keywords, strings, vectors, interop, `fn`, ordinary functions); compute it outside and pass it in, write a `defnative`, or declare C with `defextern` |
| `unknown name y (a region sees only its parameters ...)` | a closed-over local: add it to the binding vector with a hint |
| `native helper f never returns` | the helper needs a base case that doesn't recurse |
| `platform bodies return different types` / `take different arguments` | make every `(on ...)` body agree |
| `f takes :long here, got :double` (a `defextern`) | convert with `(long x)`; a long passes where C takes a double |
| build error `... Not Supported on This Platform` | add an `(on :default ...)` body |

## Testing and checking it runs as C

- Unit-test the function normally (`jolt test`); that runs the region as
  JIT-compiled native code.
- `jolt build -m app.main -o target/app` prints `compiled N native region(s)`.
- `(jolt.native/linked-regions)` maps each loaded region's C symbol to how it
  runs in this process: `:linked` (in a built binary), `:jit` (compiled by
  MIR here), or `nil` (no native path; calling it raises).
- Timing under `jolt run` measures MIR's code. Numbers you ship should come
  from the built binary, which uses the C compiler's code and the build
  target's CPU features.

Full reference: the "Native regions" page on jolt-lang.net (`/docs/native-regions`).
