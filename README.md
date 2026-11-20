# jolt-skills

Agent skills for building apps on [Jolt](https://jolt-lang.net) with the jolt-lang and jlt-commons library stack.

| Skill | Covers |
|---|---|
| `jolt` | The base: projects, deps.edn, tasks, `jolt build`, FFI, where jolt differs from JVM Clojure, and a catalog of every jolt-lang / jlt-commons library (`jolt/references/ecosystem.md`) |
| `jolt-nrepl` | REPL-driven work through the [jolt-nrepl-mcp](https://github.com/jlt-commons/jolt-nrepl-mcp) tools |
| `jolt-debug` | Diagnosing hard bugs: a red-capable feedback loop first (REPL, test, script), then minimise, ranked falsifiable hypotheses, one-variable instrumentation, a regression test |
| `jolt-style` | Style review against a written guide (`jolt-style/references/style-guide.md`, or the project's own) |
| `clj-refactor` | Review for mechanism/policy separation |
| `jolt-lsp` | Navigation, diagnostics, syntax repair, structural edits, refactors, namespace restructuring and structural diff through the [jolt-lsp](https://github.com/jlt-commons/jolt-lsp) MCP tools |
| `jolt-web` | HTTP servers and web apps: ring-chez-adapter, router (reitit), http-client, multipart, glimmer-datastar, transit, logging, otel, mulog, crypto |
| `jolt-data` | Persistence and formats: db (SQLite/Postgres, next.jdbc, honeysql, migratus), doltera, duratom, time/tick, JSON/EDN/YAML/XML/Transit/Fressian, instaparse |
| `jolt-gui` | Desktop, terminal and mobile UIs: glimmer and its backends, glitter + nexus, ftxui |
| `jolt-games` | Games and graphics: raylib-jlt, raygui, ents (flecs), slipstream, raylib on iOS/Android, per-frame performance |
| `jolt-concurrency` | Futures, core.async, jolt.fibers, ebb, ensemble actors, tapestry, lifecycle and shutdown |

Each skill is a directory with a `SKILL.md` and optional `references/`. The
domain skills assume the `jolt` skill is installed too.

## Install

Copy the skill files to wherever your harness looks for them. For Claude
Code, `cp -R jolt-skills/jolt* ~/.claude/skills/` (the jolt-nrepl plugin
already brings `jolt-nrepl` and `clj-refactor`). To install Kimi Code
skills, for all projects:

```bash
git clone https://github.com/jlt-commons/jolt-skills
cp -R jolt-skills/jolt* jolt-skills/clj-refactor ~/.kimi-code/skills/
```

Or per project, into `.kimi-code/skills/`. `jolt-nrepl` needs the jolt-nrepl MCP
server and `jolt-lsp` needs the jolt-lsp MCP server (`jolt-lsp mcp`); see their
repos for setup. In Kimi Code, the
[nrepl-kimi-code-plugin](https://github.com/jlt-commons/nrepl-kimi-code-plugin)
registers both servers from `PATH` and ships `jolt-nrepl` and `jolt-lsp`.

## One copy of each skill

This repo is the source for every skill here. jolt-nrepl-mcp ships
`jolt-nrepl` and `clj-refactor`, and nrepl-kimi-code-plugin ships those plus
`jolt-lsp`; their copies are written from here. Edit the skill in this repo,
then run `./sync.sh` with the plugins checked out alongside (`./sync.sh
--check` fails if a copy has drifted).

`jolt-debug` and `jolt-style` are adapted from
[clojure-agent-starter](https://github.com/JoinIn-AI/clojure-agent-starter)
(MIT, JoinIn AI); `jolt-debug` traces back to Matt Pocock's skills (MIT).
`clj-refactor` comes from humorless/clj-native-agent (MIT).

## License

EPL 2.0, the same license as Jolt and Clojure. See [LICENSE](LICENSE).
