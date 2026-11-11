---
name: jolt-lsp
description: "Navigate, check and refactor Jolt/Clojure source through the jolt-lsp MCP tools (jolt_index, jolt_context, jolt_definition, jolt_references, jolt_hover, jolt_impact, jolt_diagnostics, jolt_check, jolt_replace_form, jolt_insert_form, jolt_rename, jolt_clean_ns, jolt_add_require, jolt_refactor, jolt_format). Use when working on Jolt or Clojure code and you need to find where something is defined or used, see what a change affects, check or repair syntax, make a structural edit that Edit can't match, rename a var, fix a ns form, or lint a file."
---

# jolt-lsp tools

The `jolt-lsp` MCP server (`jolt-lsp mcp`) keeps an in-memory index of the
project: namespaces, vars, aliases, refers, keywords, locals, and the Clojure
sources of dependencies. Use it for questions about the code as text and
structure; use the `jolt-nrepl` tools for questions about what the code does
when it runs. Jolt only: `.clj`, `.cljc`, `.edn`. No ClojureScript, no Java
navigation.

Source and releases: https://github.com/jlt-commons/jolt-lsp. Register it with
`claude mcp add --scope user jolt-lsp -- /path/to/jolt-lsp mcp`.

## Conventions

- Positions are **1-based** `line`/`col`. Results carry `file`, `line`, `col`,
  `end-line`, `end-col` (end exclusive), plus `source` text.
- A symbol may be a fqn (`app.core/run`) or a bare name. An ambiguous bare
  name returns `ok: false` with `candidates`; retry with the fqn.
- Paths may be relative to `root`. Pass `root` on the first call.
- The index follows the disk: files changed by any tool (Edit included) are
  re-read on the next call. `refresh: true` on `jolt_index` rebuilds.
- **Edits preview by default.** The result has a `diff` per file. Read it, then
  repeat the call with `apply: true`. An edit that would make a readable file
  unreadable is refused with line/col; nothing is written.
- `ok: false` results are flagged as errors.

## Tools

| Tool | Use |
|---|---|
| `jolt_index` | Once at start: counts, and the files that don't read. |
| `jolt_context` | `ns` or `file`: requires, vars and signatures of the ns you're about to change. |
| `jolt_search` | Fuzzy symbol search: `query`, `limit`. |
| `jolt_definition` / `jolt_references` | `symbol`, or `file`+`line`+`col`. |
| `jolt_hover` | Doc, arglists and full source (`code`) of a var. Use instead of reading the file. |
| `jolt_symbols` | Outline of one file. |
| `jolt_form` | The form at `file`+`line`/`col`; `mode: "top"` for the enclosing top-level form. |
| `jolt_call_hierarchy` | `symbol`, `direction`: `callers` or `callees`. |
| `jolt_impact` | Transitive callers of a var, with distance. Run before changing a public var. |
| `jolt_deps` | `ns`, `direction`: `dependencies`, `dependents` or `cycles`. |
| `jolt_diagnostics` | `file`, or none for the whole project. Unresolved symbols/namespaces, unused requires/refers/bindings/privates, duplicate requires, syntax errors; clj-kondo findings when installed (`kondo`). |
| `jolt_check` | Syntax check of a `file` or `code`; `fix: true` applies only safe repairs. |
| `jolt_replace_form` | `file`, `old_form`, `new_text`; `occurrence` or `all`. |
| `jolt_insert_form` | `file`, `new_text`, `after`/`before` a form. |
| `jolt_rename` | `file`, `line`, `col`, `to`. Renames the var and every reference. |
| `jolt_clean_ns` | Drop unused requires/refers, sort the ns form. |
| `jolt_add_require` | `file`, `symbol` (e.g. `clojure.set/union`), `alias`. Returns the `use` form to write. |
| `jolt_refactor` | `kind`: `sort-requires`, `cycle-keyword`, `inline-symbol`, `destructure-keys`, `restructure-keys`, `move-form` (`target_file`). |
| `jolt_format` | cljfmt the whole file. |
| `jolt_batch` | `ops: [{tool, args}]`, read-only tools only. Several lookups in one call. |

## Workflow

1. `jolt_index` once; note any files that don't read.
2. `jolt_context` on the namespace you're changing; `jolt_hover` for a var's
   source rather than reading the whole file.
3. `jolt_impact` (or `jolt_references`) before changing a public var's
   signature or behaviour.
4. Reproduce and try the fix in the REPL (`jolt-nrepl` skill), then write it.
5. Write with `jolt_replace_form` / `jolt_insert_form` / `jolt_rename` /
   `jolt_refactor`: preview, check the diff, `apply: true`. Plain Edit is fine
   when the text matches exactly.
6. `nrepl_load_file` the file, then `jolt_diagnostics` on it. Fix unused or
   unresolved names with `jolt_clean_ns` / `jolt_add_require`.

## Structural replace

`jolt_replace_form` matches a form by what it reads as, at any depth, so
`old_form` may differ from the file in whitespace and line breaks. Strings and
comments never match. Use it when Edit fails on whitespace, or when a form is
easier to name than to copy. Several matches come back with line/col: pick
one with `occurrence`, or pass `all: true`.

## Syntax repair

`jolt_check` reports unbalanced delimiters (both ends of a mismatch),
unterminated strings (at the line the string opened), and balanced text that
still doesn't read. `fix: true` repairs only what can't re-parent code: a
dropped trailing closer, extra trailing closers, a closer the indentation
places. Anything else is reported with line/col; fix the text yourself. A
broken file still indexes: the broken top-level form is masked and
`jolt_diagnostics` reports a `syntax-error`.

## Project settings

`.jolt-lsp/config.edn` (and `.clj-kondo/config.edn` for `:lint-as` and
`:unresolved-symbol {:exclude ...}`):

```clojure
{:kondo true                 ; nil = on when clj-kondo is installed
 :custom-linters [{:file "linters/my.clj" :fn "my.linters/analyze"}]
 :clj-depend {:rules [{:from "app.ui.*" :to "app.db.*"}]}}
```

A macro that defines vars or binds names will show up as unresolved symbols
until it is mapped with `:lint-as` (e.g. `{my.ns/defthing clojure.core/def}`).
