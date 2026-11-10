---
name: jolt-data
description: "Persistence, databases, data formats and time for Jolt (Clojure on Chez Scheme, no JVM) apps. Use when a jolt program needs SQLite or PostgreSQL (jolt-lang/db, jdbc.core / clojure.jdbc, next.jdbc, honeysql, migratus migrations), Dolt (jolt-lang/doltera), a durable atom persisted to a file or sqlite (jlt-commons/duratom), dates, times, zones and formatting (jolt-lang/time, java.time, juxt/tick), JSON (clojure.data.json), EDN (clojure.edn), YAML (jolt-lang/yaml, clj-yaml), XML (jolt-lang/xml, clojure.xml, clojure.data.xml), Transit (transit-jolt), Fressian (jolt-fressian), or a grammar-based parser (jlt-commons/instaparse). Also when choosing where a jolt app should keep its data."
---

# jolt-data

How a jolt app stores, encodes and timestamps data. Build/deps/FFI basics are in
the `jolt` skill; read it first. The snippets below were run on jolt 0.8.25
(macOS arm64) unless marked otherwise.

References (API detail, more snippets):
- `references/db.md`: jdbc.core, next.jdbc, honeysql, migratus, postgres, native libs
- `references/time.md`: tick, java.time, formatters, zones
- `references/formats.md`: JSON, EDN, YAML, XML, Transit, Fressian
- `references/duratom.md`: durable atoms, custom backends
- `references/doltera.md`: Dolt over the MySQL protocol
- `references/instaparse.md`: EBNF/ABNF parsers

## Which library for which job

| Need | Use | Notes |
|---|---|---|
| Relational data in memory, constraints, queries, graphs | relatum | Has its own skill (`relatum`); the default in-process data model |
| SQL on disk, one process | `jolt-lang/db` + SQLite | `jdbc.core` (clojure.jdbc) or `next.jdbc`; system libsqlite3 |
| SQL server | `jolt-lang/db` + PostgreSQL | needs libpq at runtime |
| Build SQL from data | honeysql (git dep) | `honey.sql/format` -> sqlvec for db |
| Schema migrations | migratus (git dep) | over db's `next.jdbc`; see references/db.md |
| Versioned SQL (branch/commit) | `jolt-lang/doltera` | pure-Clojure MySQL client for `dolt sql-server` |
| One value that survives restarts | `jlt-commons/duratom` | `file-atom` (EDN file) or `sql-atom` (sqlite/pg) |
| Dates, zones, formatting | `jolt-lang/time` | gives `tick.core` and `DateTimeFormatter`/`ZoneId` |
| JSON | `clojure.data.json` | built in; writing an `Instant` needs jolt-lang/time |
| EDN, config files | `clojure.edn` | built in |
| YAML | `jolt-lang/yaml` | libyaml via FFI; `jolt.yaml` and `clj-yaml.core` |
| XML read / write | `jolt-lang/xml` | libxml2 via FFI; `clojure.xml/parse`, `clojure.data.xml/emit-str` |
| Clojure values over the wire | `transit-jolt` (JSON) / `jolt-fressian` (binary) | |
| Parse a custom language | `jlt-commons/instaparse` | EBNF/ABNF, `insta/parser` |

No JVM drivers: JDBC jars, HikariCP, H2, `next.jdbc` from Maven and clj-yaml's
SnakeYAML do not load. The libraries above replace them.

## deps.edn

Fill each `<latest>`/`<sha>` with `jdep OWNER/REPO` (the jolt skill's
`references/deps-and-tasks.md`, "Depending on a library: use the latest tag");
never copy a sha from docs or memory.

```clojure
{:paths ["src" "resources"]
 :deps
 {io.github.jolt-lang/db   {:git/url "https://github.com/jolt-lang/db"
                            :git/tag "<latest>" :git/sha "<sha>"}
  io.github.jolt-lang/time {:git/url "https://github.com/jolt-lang/time"
                            :git/tag "<latest>" :git/sha "<sha>"}
  ;; add as needed
  io.github.jolt-lang/yaml {:git/url "https://github.com/jolt-lang/yaml"
                            :git/tag "<latest>" :git/sha "<sha>"}
  io.github.jolt-lang/xml  {:git/url "https://github.com/jolt-lang/xml"
                            :git/tag "<latest>" :git/sha "<sha>"}
  io.github.jolt-lang/transit-jolt {:git/url "https://github.com/jolt-lang/transit-jolt"
                                    :git/tag "<latest>" :git/sha "<sha>"}
  io.github.jolt-lang/jolt-fressian {:git/url "https://github.com/jolt-lang/jolt-fressian"
                                     :git/sha "<sha>"} ; untagged: jdep prints the full HEAD sha
  io.github.jolt-lang/doltera {:git/url "https://github.com/jolt-lang/doltera"
                               :git/tag "<latest>" :git/sha "<sha>"}
  io.github.jlt-commons/duratom {:git/url "https://github.com/jlt-commons/duratom"
                                 :git/tag "<latest>" :git/sha "<sha>"}
  io.github.jlt-commons/instaparse {:git/url "https://github.com/jlt-commons/instaparse"
                                    :git/tag "<latest>" :git/sha "<sha>"}
  com.github.seancorfield/honeysql {:git/url "https://github.com/seancorfield/honeysql"
                                    :git/tag "<latest>" :git/sha "<sha>"}}}
```

Native libraries are declared by the libraries themselves (`:jolt/native`); you
add nothing. libsqlite3 and libxml2 ship with macOS. libyaml comes from Homebrew
(`brew install libyaml`) or `libyaml-0-2` on Linux. libpq is optional and
keg-only on Homebrew: `brew install libpq`, then run with
`DYLD_LIBRARY_PATH=/opt/homebrew/opt/libpq/lib` (Linux: `libpq5`).

## App skeleton: a sqlite store

`src/notes/store.clj` (ran, plus a test against `":memory:"` and a `jolt build`
binary):

```clojure
(ns notes.store
  (:require [jdbc.core :as jdbc]       ; the java.sql shim autoloads
            [clojure.edn :as edn]
            [tick.core :as t]))

(def schema
  ["create table if not exists note (
      id integer primary key,
      body text not null,
      tags text not null,             -- EDN
      created_at text not null)"
   "create index if not exists note_created on note (created_at)"])

(defn open
  "path is a file, or \":memory:\". One connection, writes serialized by a lock."
  [path]
  (let [conn (jdbc/connection (str "sqlite:" path))]
    (jdbc/fetch conn "pragma journal_mode=wal")
    (doseq [s schema] (jdbc/execute! conn s))
    {:conn conn :lock (Object.)}))

(defn close [{:keys [conn]}] (.close conn))

(defn- row->note [r] (update r :tags edn/read-string))

(defn add! [{:keys [conn lock]} body tags]
  (locking lock
    (row->note (first (jdbc/insert! conn :note {:body body :tags (pr-str tags)
                                                :created_at (str (t/now))}
                                    {:returning true})))))

(defn retag! [{:keys [conn lock]} id f]
  (locking lock
    (jdbc/atomic conn
      (when-let [n (jdbc/fetch-one conn ["select * from note where id = ?" id])]
        (let [tags (f (edn/read-string (:tags n)))]
          (jdbc/execute! conn ["update note set tags = ? where id = ?" (pr-str tags) id])
          tags)))))

(defn recent [{:keys [conn]} n]
  (mapv row->note (jdbc/fetch conn ["select * from note order by id desc limit ?" n])))
```

```clojure
(ns notes.main
  (:require [notes.store :as store] [clojure.data.json :as json]))

(defn -main [& [path]]
  (let [db (store/open (or path "notes.db"))]
    (try
      (let [{:keys [id]} (store/add! db "buy milk" #{:home})]
        (store/retag! db id #(conj % :urgent)))
      (println (json/write-str (store/recent db 5)))
      (finally (store/close db)))))
;; [{"id":1,"body":"buy milk","tags":["home","urgent"],"created_at":"2026-01-02T22:28:59.616Z"}]
```

This is the shape newsroom (https://github.com/yogthos/newsroom/blob/main/src/newsroom/store.clj) uses: one
connection, a lock around writes, `jdbc/atomic` for multi-statement changes,
`create table if not exists` + `alter table add column` for schema growth (or
migratus for real migrations).

## jdbc.core in five lines

```clojure
(jdbc/connection "sqlite:app.db")              ; also "sqlite::memory:", "postgres://u:pw@host:5432/db",
                                               ; {:vendor "sqlite" :name "app.db"}
(jdbc/execute! conn ["update t set x = ? where id = ?" 1 2])   ; -> rows affected
(jdbc/fetch conn ["select * from t where x > ?" 0])          ; -> vector of maps, lower-case keyword keys
(jdbc/fetch-one conn "select count(*) as n from t")          ; -> {:n 3}
(jdbc/insert! conn :t {:x 1} {:returning true})              ; -> ({:id 1 :x 1}); without opts -> (1)
(jdbc/insert! conn :t {:x 1} {:returning [:id]})             ; -> ({:id 1})
(jdbc/insert-multi! conn :t [{:x 1} {:x 2}])                 ; -> (1 1)
(jdbc/update! conn :t {:x 9} ["id = ?" 1])  (jdbc/delete! conn :t ["id = ?" 1])
(jdbc/atomic conn ...)                                       ; transaction; nested = savepoint; throw rolls back
```

`next.jdbc` (`execute!`, `execute-one!`, `plan`, `execute-batch!`,
`with-transaction`, `get-datasource`) is also provided by db; it is what
honeysql examples and migratus use. See `references/db.md`.

## Gotchas

- **`(require 'db.jdbc)` is optional.** db declares the `java.sql` shim via
  `:jolt/provides`, so requiring `jdbc.core` or `next.jdbc` is enough, for uri
  strings and map dbspecs (`{:vendor "sqlite" :name ":memory:"}`) alike.
  Requiring `db.jdbc` first is harmless.
- **On jolt 0.8.25 a failing plain-string `jdbc/execute!` escapes
  `(catch java.sql.SQLException _)`.** clojure.jdbc runs a bare string as a
  batch, the shim throws `java.sql.BatchUpdateException`, and jolt 0.8.25 does
  not model it as a SQLException subclass. Pass a sqlvec (`["insert ..."]`) for anything that can fail, or catch
  `Exception`. Errors from `fetch` and sqlvec `execute!` are SQLExceptions.
- **No pool.** `next.jdbc/get-datasource` is a connection factory: each call on a
  datasource opens and closes a connection. Keep one connection (sqlite) or a few
  long-lived ones, and serialize writers yourself.
- **Rows are unqualified lower-case keyword maps** (`:user_id`, not `:user/id`);
  next.jdbc's `:builder-fn` is accepted and ignored. Booleans are 0/1 in sqlite;
  store dates as ISO text (`(str (t/now))`) or epoch millis.
- **Postgres values**: `uuid` -> uuid, `numeric` -> bigdec, `date`/`timestamp(tz)`
  -> `java.time` values (not `java.sql.Timestamp`), arrays -> vectors; bind a
  vector with a cast (`?::text[]`).
- **java.time beyond the base value types needs jolt-lang/time**:
  `DateTimeFormatter`, `ZoneId`, `ZonedDateTime`, `Locale`, and
  `json/write-str` of an `Instant` all fail with "No dependency provides ..."
  without it.
- **On jolt 0.8.25, tick's `(t/month a-local-date)` throws** (`java.time.Month/from` is missing);
  use `(.getMonth d)` / `(.getMonthValue d)`. `t/month` on a date-time works.
- **YAML `yes`/`no`/`on`/`off` read as strings** (YAML 1.2 rules); SnakeYAML on
  the JVM makes them booleans. Write `true`/`false` in config you share.
