---
name: jolt-style
description: "Review Jolt/Clojure code against a written style guide (the project's own if it has one, else references/style-guide.md): naming, namespace aliases, layout, data and state discipline, Jolt-specific idioms, comments and tests. Use when the user asks for a style review or style check of a diff, file, directory or whole project, or asks to check code against the style guide. Not a bug hunt and not a formatter."
---

<!-- Adapted from style-review in clojure-agent-starter (MIT, JoinIn AI). -->

# Style review

Review code against a written rulebook, so deviations are findings rather
than taste. This covers what the linter can't: naming, structure, idiom,
alias consistency, boundary discipline. Formatting belongs to cljfmt
(`jolt_format`) and syntax and arity to jolt-lsp's diagnostics; bugs belong
to a code review. For mechanism/policy separation, use the `clj-refactor`
skill instead.

## Scope

From the arguments:

- nothing, on a branch with changes: the `.clj` / `.cljc` files changed
  against the base branch;
- a file or directory: those files;
- `all`: every project source directory.

## Method

1. **Load the rulebook.** The project's own guide if there is one (look for
   `docs/style/`, `STYLE.md`, `CONTRIBUTING.md`, a style section in
   `AGENTS.md` / `CLAUDE.md`); otherwise read `references/style-guide.md`
   in full. Project rules win; the community guide fills gaps.

2. **Mechanical checks first**, over the whole scope, before reading files:
   - `jolt-lsp lint --root .` (or `jolt_diagnostics` per file) for
     unused requires and bindings, unresolved names, arity, and
     `:discouraged-var` hits. Report only what the scope contains.
   - Alias drift: tally `[ns :as alias]` pairs
     (`grep -rhoE '\[[a-z][a-z0-9._-]+ :as [a-z0-9.-]+\]' <scope> | sort | uniq -c`);
     flag a namespace with two aliases, or an alias that differs from the
     guide's table.
   - `:refer :all` or `:use` in ns forms.
   - `println` / `prn` outside `(comment ...)`, scripts and `-main`.
   - Provenance comments: references to old source files in comments or
     docstrings (`\.py:`, `\.ts:`, `ported from`).
   - `read-string`, `eval`, `load-string` in application code.

3. **Read each file** against the guide's sections: layout, function size
   (over 10 lines is a flag; judge whether splitting helps), naming, data
   and state (records where maps would do, side effects mixed into pure
   logic, missing validation at a boundary), Jolt rules, comments, tests.

   For `all`, fan out one subagent per top-level source area. Give each the
   rulebook and ask for findings only, as `file:line — rule — note`, no
   rewrites.

4. **Filter.** Keep only findings a reviewer would act on. Drop formatting
   the tools fix, taste the guide doesn't rule on, and vendored or generated
   code. When the codebase consistently departs from the guide, report it
   once as a decision (change the code or the guide), not once per file.

5. **Report**, in three groups:
   - **Violations**: `file:line`, the rule, a one-line note.
   - **Drift**: the same thing done two ways (aliases, key styles, test
     names).
   - **Guide gaps**: recurring decisions the guide should rule on, with a
     proposed rule.

   A diff review goes in the conversation. A directory or project review
   also goes to `docs/style/reviews/<YYYY-MM-DD>-<scope>.md`.

## Fixing

Only when asked. Mechanical fixes first (aliases with `jolt_rename` /
`jolt_clean_ns`, refers, `println`), one commit. Structural findings
(splitting a function, moving I/O to the edge) one per commit, each tried in
the REPL before it is written (the `jolt-nrepl` workflow).
