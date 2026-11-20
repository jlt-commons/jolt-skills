---
name: jolt-debug
description: "Diagnosis loop for hard bugs and performance regressions in Jolt/Clojure code: build a red-capable feedback loop (a REPL call, a failing test, a script) before forming any hypothesis, minimise the repro, rank falsifiable hypotheses, instrument one variable at a time, then fix with a regression test. Use when the user says diagnose or debug this, or reports something broken, throwing, failing, flaky or slow, and the cause is not obvious from one read of the code."
---

<!-- Adapted from diagnosing-bugs in clojure-agent-starter (MIT, JoinIn AI),
     itself a fork of Matt Pocock's skills (MIT). -->

# Diagnosing bugs in Jolt code

A discipline for hard bugs. Skip a phase only when you can say why. The REPL
mechanics (captures, `*e`, redefining a fn in its ns) are in the `jolt-nrepl`
skill; this skill is the order to use them in.

## Phase 1: build a feedback loop

This is the skill. With a tight pass/fail signal that goes red on *this*
bug, bisection, hypotheses and instrumentation all just consume it. Without
one, reading code will not save you. Spend most of the effort here.

**The nREPL session is the first loop to reach for.** In `nrepl_eval`,
require the namespace and call the failing function with the real inputs;
the verdict comes back in milliseconds, with no boot. Query live state
(`@system`, a snapshot `def`) instead of adding logs.

Other loops, roughly in order:

1. A failing test at the seam that reaches the bug, run with `nrepl_test`.
2. An HTTP call (curl) against the running dev server.
3. The CLI or built binary run on a fixture input, diffing stdout against a
   known-good snapshot. For a bug only the binary shows (`jolt build`
   closed-world, natives, runtime `require`s), this is the loop.
4. A captured payload replayed through the code path in isolation.
5. A throwaway harness: one component, mocked deps, one call.
6. A property loop (writ, test.check) when the bug is "sometimes wrong".
7. A bisection harness for `git bisect run` when it appeared between two
   known states.
8. A differential loop: same input through old and new code, diffed.
9. Human in the loop, last: copy `scripts/hitl-loop.template.sh`, edit the
   steps, run it. The user follows the prompts and you parse the captured
   `KEY=VALUE` output.

Tighten the loop once you have one: faster (narrow scope, skip unrelated
init), sharper (assert the exact symptom, not "didn't throw"), deterministic
(pin time, seed randomness, isolate the filesystem). For a flaky bug, raise
the reproduction rate (loop the trigger 100 times, add load, narrow timing)
until it is debuggable.

If you cannot build a loop, stop and say so. List what you tried and ask
for access to an environment that reproduces it, a captured artifact (log,
payload, core dump), or permission for temporary instrumentation.

**Done when** you can name one command or eval you have already run, with
its output, that is:

- red-capable: it drives the real code path and checks the user's exact
  symptom,
- deterministic (or at a pinned, high reproduction rate),
- fast: seconds,
- runnable by you unattended.

Reading code to build a theory before this exists is the failure this skill
prevents.

## Phase 2: reproduce and minimise

Run the loop and watch it go red. Confirm it is the failure the user
described, not a nearby one, and capture the exact symptom (message, value,
timing).

Then shrink the repro: cut inputs, callers, config and steps one at a time,
re-running after each cut. Done when every remaining element is load-bearing.
The minimal repro narrows Phase 3 and becomes the regression test.

## Phase 3: hypothesise

Write 3 to 5 ranked hypotheses before testing any. Each states its
prediction: "if X is the cause, changing Y makes the bug disappear." A
hypothesis without a prediction is a guess; sharpen it or drop it.

Show the ranked list to the user before testing. They often re-rank it in
one line ("we changed #3 yesterday"). Don't block on an answer.

## Phase 4: instrument

Each probe tests one prediction; change one variable at a time.

1. REPL inspection first: a capture `(def x* x)` in a REPL-only
   redefinition, then inspect `x*`.
2. Targeted logs at the boundaries that separate hypotheses, only when the
   REPL cannot reach the code path.
3. Never log everything and grep.

Tag every temporary log with a unique prefix (`[DEBUG-a4f2]`) so cleanup is
one grep.

For a performance regression, logs mislead. Measure a baseline first
(`time`, `jolt.profile`, a benchmark task), then bisect.

## Phase 5: fix and regression test

Write the regression test before the fix, if there is a seam where the test
exercises the real bug pattern. A seam too shallow to replicate the chain
that caused the bug gives false confidence; if there is no correct seam,
that is a finding, so report it.

1. Turn the minimal repro into a failing test; watch it fail.
2. Try the fix in the REPL, then write it to the file and `nrepl_load_file`.
3. Watch the test pass.
4. Re-run the Phase 1 loop on the original, un-minimised scenario.

## Phase 6: clean up

- The original repro no longer reproduces.
- The regression test passes, or the missing seam is written down.
- `grep` for the `[DEBUG-` prefix finds nothing; capture defs are gone.
- The session and files agree (the `jolt-nrepl` skill's cold-load check).
- The commit message states the hypothesis that turned out right.
