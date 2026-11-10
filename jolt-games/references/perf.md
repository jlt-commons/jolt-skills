# Per-frame performance

At 60 fps a frame is 16.6 ms. On jolt the cost in a frame loop is almost
always **allocation and sequence machinery**, not FFI calls and not boxed
arithmetic in small amounts. Background: the user docs
`performance-idioms.md` and `numeric-performance.md` in
https://jolt-lang.net/docs/.

## Measured on an M-series Mac (jolt 0.8.25)

10,000 particles, position += velocity * dt, one frame:

| representation | time/frame | allocated/frame |
|---|---|---|
| vector of maps, `mapv` + `assoc` | ~2.0 ms | 4.2 MB |
| four `double-array`s, hinted `loop` | ~0.06 ms | ~200 B |

```clojure
(defn step-arrays! [^doubles xs ^doubles ys ^doubles vxs ^doubles vys ^double dt]
  (let [n (alength xs)]
    (loop [i 0]
      (when (< i n)
        (aset xs i (+ (aget xs i) (* (aget vxs i) dt)))
        (aset ys i (+ (aget ys i) (* (aget vys i) dt)))
        (recur (inc i))))))
```

Maps are fine for a few hundred game objects; switch the hot set (particles,
bullets, boids) to struct-of-arrays when the count grows. The draw loop then
reads the arrays by index and calls the positional `rl/draw-*` bindings.

## Rules for the frame loop

- **Indexed `loop`/`recur` over vectors or arrays**, not `doseq` over
  `map-indexed`/`partition`/`for` per element. On iOS this alone took a scene
  from 14 to 52 fps with the same draw calls (raylib-ios perf guide).
- **Don't allocate per element**: a helper returning `[x y]` is a vector per
  call. Inline the arithmetic in the hot path; keep the readable helper for tests.
- **Hoist constants**: colors (`rl/rgba` calls), uniform locations, layouts,
  scratch native buffers (`defonce` one `ffi/alloc` and reuse it, as
  raylib-jlt and raygui do).
- **Positional bindings in hot loops**: `(rl/draw-circle (int x) (int y) (double r) color)`
  skips the kwargs map that `rl/circle!` builds.
- **Hints where inference can't see**: `^double`/`^long` on params and `let`
  bindings, `^doubles`/`^longs` on arrays, `^double` on the defn name for the
  return. A hint is an assertion: hinting a boxed integer as `^double` can give
  a different result than the JVM. `JOLT_CHECK=1 jolt play` lints provably wrong arithmetic.
- `Math/sqrt`, `Math/sin`, `Math/atan2`, ... lower to native flonum ops when
  the operands are proven doubles. Pass `2.0`, not `2`, where it matters.
- **`swap!` once per frame** on the whole world, not per entity.
- Integer overflow promotes to bignum instead of throwing or wrapping. For
  hashes and RNGs that need 64-bit wrapping use `unchecked-multiply`/
  `unchecked-add`, or `jolt-lang/primitive-math`.
- Don't tune the GC; reduce allocation instead.

## Measuring

```clojure
(require '[jolt.profile :as prof])
(prof/measure (step-world w))
;=> {:result ... :real-ms 2.3 :cpu-ms 1.3 :allocated-bytes 1650800 :gc-count 0 :gc-ms 0.0}
```

`allocated-bytes` is deterministic and the best single number. For timings,
warm up, then time a few hundred iterations and take the minimum of several
rounds, comparing variants A/B/A in one session. `rl/fps!` on screen is a
coarse check; the frame cap hides headroom, so raise `set-target-fps` while
measuring.

Records vs maps: https://github.com/jolt-lang/examples/tree/main/ray-tracer has a map version and a
record+protocol version of the same renderer. Its README says records are
about 2.6x faster; on this machine with jolt 0.8.25 the record version was
slower (A/B/A: maps 2.3 s / 1.6 s, records 2.8 s / 2.7 s). Don't convert to
records on faith: measure your own hot path.

## primitive-math

`jolt-lang/primitive-math` (untagged) is
clj-commons/primitive-math on jolt: `clj-commons.primitive-math` with 64-bit
wrapping `+ - *`, JVM-style narrowing casts (`(p/byte 200)` => -56),
`>>>`, `int->uint`, `byte->ubyte`, ... Its README is explicit: it exists so
code written against primitive-math runs unchanged, **not for speed** (jolt has
no primitive types for it to unlock).

```clojure
{:deps {primitive-math/primitive-math
        {:git/url "https://github.com/jolt-lang/primitive-math"
         :git/sha "<sha>"}}}   ; full HEAD sha: `jdep jolt-lang/primitive-math`
```

## Build modes and live code

`jolt build` (release) and `JOLT_DIRECT_LINK=1` can inline across call sites
and const-link vars; that is where whole-program speedups come from, and it
is also why a REPL redefinition may not reach a loop in such a build. Profile
the build you ship, and develop live from source runs.
