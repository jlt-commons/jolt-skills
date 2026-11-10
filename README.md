# jolt-skills

Agent skills for building apps on [Jolt](https://jolt-lang.net), the Clojure
implementation on Chez Scheme, with the jolt-lang and jlt-commons library stack.

| Skill | Covers |
|---|---|
| `jolt` | The base: projects, deps.edn, tasks, `jolt build`, FFI, where jolt differs from JVM Clojure, and a catalog of every jolt-lang / jlt-commons library (`jolt/references/ecosystem.md`) |
| `jolt-nrepl` | REPL-driven work through the [jolt-nrepl-mcp](https://github.com/jlt-commons/jolt-nrepl-mcp) tools |
| `jolt-web` | HTTP servers and web apps: ring-chez-adapter, router (reitit), http-client, multipart, glimmer-datastar, transit, logging, otel, mulog, crypto |
| `jolt-data` | Persistence and formats: db (SQLite/Postgres, next.jdbc, honeysql, migratus), doltera, duratom, time/tick, JSON/EDN/YAML/XML/Transit/Fressian, instaparse |
| `jolt-gui` | Desktop, terminal and mobile UIs: glimmer and its backends, glitter + nexus, ftxui |
| `jolt-games` | Games and graphics: raylib-jlt, raygui, ents (flecs), slipstream, raylib on iOS/Android, per-frame performance |
| `jolt-concurrency` | Futures, core.async, jolt.fibers, ebb, ensemble actors, tapestry, lifecycle and shutdown |

Each skill is a directory with a `SKILL.md` and optional `references/`. The
domain skills assume the `jolt` skill is installed too.

## Install

Claude Code, for all projects:

```bash
git clone https://github.com/jlt-commons/jolt-skills
cp -R jolt-skills/jolt* ~/.claude/skills/
```

Or per project, into `.claude/skills/`. `jolt-nrepl` needs the jolt-nrepl MCP
server; see its repo for setup.

## Versions

Library coordinates are pinned to the commits current when the skills were
written (checked 2026-11-09 against jolt 0.8.25). Re-check before pinning:
`git ls-remote --tags https://github.com/OWNER/REPO`.
