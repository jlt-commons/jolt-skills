---
name: jolt-native
description: "Write native regions on Jolt (Clojure on Chez Scheme): blocks of numeric code that `jolt build` compiles to C and links into the binary, borrow-checked at compile time so the arrays they create are freed deterministically and nothing leaks. Use when a jolt program has a hot numeric loop that hints and primitive arrays have not made fast enough (array kernels, simulation steps, n-body, DSP, codec inner loops); when the user mentions jolt.native, `native`, `defnative`, native regions, `^:hold-gc`, or compiling a Clojure function to C; or when a native region refuses to compile and the message needs explaining."
---

# Native regions on jolt

Read the `jolt` skill first for projects, deps.edn and `jolt build`. This skill
covers `jolt.native`: a `native` form whose body is compiled to C at build time.

```clojure
(require '[jolt.native :refer [native defnative]])

(defn norm [^doubles xs]
  (native [^doubles xs]
    (loop [i 0 s 0.0]
      (if (< i (alength xs))
        (recur (inc i) (+ s (* (aget xs i) (aget xs i))))
        (Math/sqrt s)))))
```

- In a binary from `jolt build` the body runs as C, linked in. The build needs
  a C compiler (`JOLT_CC`, or `cc` on `PATH`).
- Under `jolt run`, in tests and in the REPL the same checked program runs as
  Jolt (the fallback), with the same results and exceptions. Develop and test
  it like any other Clojure code; the C only exists in the built binary.
- The region is checked when it is compiled, in the REPL too. A region that
  would misuse an array is a compile error, not a crash.
- Check that `(require 'jolt.native)` works; older jolt releases do not have it.

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
- `aget`, `aset`, `alength`; `double-array`, `long-array`, `aclone` create arrays the region **owns**
- `Math/sqrt`, `sin`, `cos`, `tan`, `exp`, `log`, `floor`, `ceil`, `pow`, `atan2`
- your own macros (they expand inside the region) and `defnative` helpers

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

## Pinned (default) vs ^:hold-gc

Both are memory safe. The choice is what other threads' GC does while the C runs.

- Default (pinned): other threads keep running and collecting; the borrowed
  arrays are pinned for the call. About 45ns a call.
- `(native ^:hold-gc [^double x] (* x x))`: a plain call, about 2.5ns, that
  holds every other thread's collection until the region returns. Only for
  regions that finish in microseconds; a long one stalls the whole process's GC.

## Semantics that differ from plain Jolt

Regions follow the JVM's primitive semantics, in both the C and the fallback:

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
| `not allowed in a native region: f` | not in the subset; compute it outside and pass it in, or write a `defnative` |
| `native helper f never returns` | the helper needs a base case that doesn't recurse |

## Testing and checking it runs as C

- Unit-test the function normally (`jolt test`); that exercises the fallback,
  which runs the same checked program.
- `jolt build -m app.main -o target/app` prints `compiled N native region(s)`.
- `(jolt.native/linked-regions)` maps each loaded region's C symbol to whether
  it runs as C in this process: true in a built binary, false under `jolt run`.
  Print it from the binary to confirm the C path was taken.
- A benchmark needs the built binary; timing under `jolt run` measures the
  fallback.

Full reference: the "Native regions" page on jolt-lang.net (`/docs/native-regions`).
