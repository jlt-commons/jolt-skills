---
name: jolt-lsp
description: "Navigate, check and refactor Jolt/Clojure source through the jolt-lsp MCP tools (jolt_index, jolt_context, jolt_definition, jolt_references, jolt_hover, jolt_impact, jolt_diagnostics, jolt_check, jolt_replace_form, jolt_insert_form, jolt_rename, jolt_clean_ns, jolt_add_require, jolt_refactor, jolt_format, jolt_rename_namespace, jolt_extract, jolt_fix_declares, jolt_structural_diff, jolt_deps_list, jolt_deps_grep, jolt_deps_read). Use when working on Jolt or Clojure code and you need to find where something is defined or used, see what a change affects, check or repair syntax, make a structural edit that Edit can't match, rename a var or a namespace, move forms into a new namespace, fix a ns form, lint a file, review what a change did form by form, or search and read the source of a dependency."
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
| `jolt_deps_list` | The libraries the project resolves to (transitively): lib, version, kind and the directory their files are in. `pattern` filters names; `aliases` adds an alias's extra deps. |
| `jolt_deps_grep` | Regex `pattern` over the dependencies' files (ripgrep when installed): `library` (group/artifact, group or artifact), `glob` (`*.clj`), `case_insensitive`, `files_only`, `limit` (default 50; `truncated` when cut). Hits give `lib`, `file`, `path`, `line`, `text`. |
| `jolt_deps_read` | A dependency file by the `file` grep returned, or `library` + `path`; `offset`/`limit` for a line range. Paths outside the project's dependencies are refused. |
| `jolt_diagnostics` | `file`, or none for the whole project. Unresolved symbols/namespaces, unused requires/refers/bindings/privates, duplicate requires, syntax errors; clj-kondo findings when installed (`kondo`). |
| `jolt_check` | Syntax check of a `file` or `code`; `fix: true` applies only safe repairs. |
| `jolt_replace_form` | `file`, `old_form`, `new_text`; `occurrence` or `all`. |
| `jolt_insert_form` | `file`, `new_text`, `after`/`before` a form. |
| `jolt_rename` | `file`, `line`, `col`, `to`. Renames the var and every reference. |
| `jolt_clean_ns` | Drop unused requires/refers, sort the ns form. |
| `jolt_add_require` | `file`, `symbol` (e.g. `clojure.set/union`), `alias`. Returns the `use` form to write. |
| `jolt_refactor` | `kind`: `sort-requires`, `cycle-keyword`, `inline-symbol`, `destructure-keys`, `restructure-keys`, `move-form` (`target_file`). |
| `jolt_format` | cljfmt the whole file. |
| `jolt_rename_namespace` | `from`, `to`. Renames a namespace (or a prefix): its files move to the paths the new name implies, and every ns form, require and qualified reference follows. Returns `moves`, `created`, `deleted`. |
| `jolt_extract` | `file`, `forms` (names), `to_ns`. Moves those top-level forms, with the private helpers only they use, into a namespace created at the path its name implies. `callers` lists files that still call a moved var; give each a require for the new namespace. |
| `jolt_fix_declares` | `file`. Drops `declare`s a reordering makes unnecessary by moving each definition above its first use; a declare that breaks a real cycle stays. |
| `jolt_structural_diff` | `file`, and the old side as `old` (text), `old_file`, or `rev` (git, default `HEAD`). What changed, by form and by where inside it: behaviour changes told apart from renames, extractions, moves, wrapping and comment- or whitespace-only edits, with changed forms grouped by the calls between them. Read-only. |
| `jolt_batch` | `ops: [{tool, args}]`, read-only tools only. Several lookups in one call. |

## Workflow

1. `jolt_index` once; note any files that don't read.
2. `jolt_context` on the namespace you're changing; `jolt_hover` for a var's
   source rather than reading the whole file.
3. `jolt_impact` (or `jolt_references`) before changing a public var's
   signature or behaviour. To see how a library does something, or what a
   dependency's function really expects, `jolt_deps_grep` its sources and
   `jolt_deps_read` the hit instead of guessing from memory.
4. Reproduce and try the fix in the REPL (`jolt-nrepl` skill), then write it.
5. Write with `jolt_replace_form` / `jolt_insert_form` / `jolt_rename` /
   `jolt_refactor`: preview, check the diff, `apply: true`. Plain Edit is fine
   when the text matches exactly.
6. `nrepl_load_file` the file, then `jolt_diagnostics` on it. Fix unused or
   unresolved names with `jolt_clean_ns` / `jolt_add_require`.
7. Before calling the work done, `jolt_structural_diff` each changed file
   against `HEAD`: it says which forms changed behaviour and which only
   moved, were renamed or were reformatted, so an unintended change stands
   out.

## Restructuring

Use the project-level tools rather than moving text by hand: they rewrite
every caller at once and refuse a change that would leave a file unreadable.
To split a namespace, `jolt_extract` the forms (preview, then `apply: true`)
and add the new require to each file in `callers`. To rename one,
`jolt_rename_namespace` moves its files too. After either, `jolt_diagnostics`
on the affected files. The planning library behind them is
`jolt-lsp.surgeon`, and the diff is `jolt-lsp.sdiff`, if you need them from
code.

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
