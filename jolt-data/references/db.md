# jolt-lang/db: SQLite and PostgreSQL

Source: https://github.com/jolt-lang/db (README, `clj/db/*.clj`, `clj/next/jdbc*.clj`,
`clj-test/`). Depend on its newest tag (`jdep jolt-lang/db`, see the jolt
skill's `references/deps-and-tasks.md`).

db binds libsqlite3 and libpq through `jolt.ffi` (`db.sqlite`, `db.pg`), installs a
`java.sql` shim (`db.jdbc-shim`) and runs the real
[clojure.jdbc](https://github.com/yogthos/clojure.jdbc) (`jdbc.core`) on it, plus a
`next.jdbc` surface. Layout:

| ns | what |
|---|---|
| `db.jdbc` | explicit entry point; optional, the shim autoloads via `:jolt/provides` |
| `jdbc.core` | clojure.jdbc: `connection`, `fetch`, `fetch-one`, `execute!`, `insert!`, `insert-multi!`, `update!`, `delete!`, `atomic`, `prepared-statement` |
| `next.jdbc` | `get-datasource`, `get-connection`, `execute!`, `execute-one!`, `plan`, `execute-batch!`, `with-transaction`, `transact*` |
| `next.jdbc.sql` | `query`, `insert!`, `delete!` |
| `db.datasource` | `open-datasource`, `acquire`, `release`, `close-datasource`, `datasource?` |
| `db.sqlite` / `db.pg` | raw drivers (`open`/`query`/`last-insert-rowid`, `connect`/`exec`/`all`) |

## Connection specs

```clojure
"sqlite:app.db"  "sqlite::memory:"  "app.db"          ; a string without a scheme is a sqlite path
"postgres://user:pw@127.0.0.1:5432/app"
{:vendor "sqlite" :name "app.db"}
{:vendor "postgresql" :host "127.0.0.1" :port 5432 :user "u" :password "pw" :dbname "app"}
{:subprotocol "postgresql" :subname "//127.0.0.1:5432/app" :user "u" :password "pw"}
;; next.jdbc also accepts {:dbtype "sqlite" :dbname "app.db"}, {:jdbcUrl "jdbc:..."},
;; {:connection-uri "sqlite:app.db"}
```

A connection that fails to open throws `ex-info "sqlite open failed: <path>"`
with `{:rc 14 :jdbc/sql-error true}` (14 = SQLITE_CANTOPEN, usually a missing directory).

## jdbc.core (ran)

```clojure
(ns app.db
  (:require [jdbc.core :as jdbc]))

(with-open [conn (jdbc/connection "sqlite:app.db")]
  (jdbc/execute! conn "create table account (id integer primary key, name text not null, balance real not null default 0)")
  (jdbc/insert! conn :account {:name "ada" :balance 100.0} {:returning true})
  ;; => ({:id 1, :name "ada", :balance 100.0})
  (jdbc/insert-multi! conn :account [{:name "bob" :balance 5.0} {:name "cy" :balance 7.5}]) ; => (1 1)
  (jdbc/update! conn :account {:balance 50.0} ["name = ?" "bob"])                           ; => 1
  (jdbc/atomic conn                                     ; commits on normal exit
    (jdbc/execute! conn ["update account set balance = balance - ? where name = ?" 10.0 "ada"])
    (jdbc/execute! conn ["update account set balance = balance + ? where name = ?" 10.0 "cy"]))
  (try (jdbc/atomic conn
         (jdbc/execute! conn ["delete from account where name = ?" "ada"])
         (throw (ex-info "boom" {})))                   ; rolls back, rethrows
       (catch Exception _))
  (jdbc/fetch conn "select * from account order by id")
  ;; => [{:id 1, :name "ada", :balance 90.0} {:id 2, :name "bob", :balance 50.0} {:id 3, :name "cy", :balance 17.5}]
  (jdbc/fetch-one conn ["select count(*) as n from account"])   ; => {:n 3}
  (jdbc/delete! conn :account ["name = ?" "cy"]))               ; => 1
```

- Nested `atomic` is a savepoint: an inner throw rolls back only the inner block
  (if you catch it).
- `insert!` without `:returning` answers the update counts `(1)`;
  `{:returning true}` (or `:all`) gives whole rows (it appends `RETURNING *`;
  sqlite 3.35+ / postgres); a column list, `{:returning [:id]}`, gives just
  those columns: `({:id 1})`.
- Placeholders are JDBC `?`; they are rewritten to `$N` for postgres.
- Byte arrays bind as blob/bytea and read back as byte arrays.
- `last_insert_rowid()`: `(:id (jdbc/fetch-one conn "select last_insert_rowid() as id"))`.

Errors:

```clojure
(try (jdbc/execute! conn ["insert into account (name) values (?)" nil])
     (catch java.sql.SQLException e (ex-message e)))
;; => "sqlite step failed: NOT NULL constraint failed: account.name"
```

A bare string to `execute!` goes through JDBC batching; when it fails it throws
`java.sql.BatchUpdateException`, which jolt 0.8.25 does not treat as a SQLException
subclass, so `(catch java.sql.SQLException _)` misses it. Use sqlvecs, or catch
`Exception`.

## next.jdbc + honeysql (ran)

```clojure
(ns app.hsql
  (:require [next.jdbc :as jdbc]
            [next.jdbc.sql :as sql]
            [honey.sql :as hsql]
            [honey.sql.helpers :as h]))

(def ds (jdbc/get-datasource "sqlite:hsql.db"))   ; a factory, not a pool

(jdbc/execute! ds ["create table todo (id integer primary key, title text not null, done integer not null default 0)"])
(jdbc/execute! ds (hsql/format {:insert-into :todo :values [{:title "write"} {:title "test"}]}))
;; => [#:next.jdbc{:update-count 2}]
(jdbc/execute! ds (-> (h/update :todo) (h/set {:done 1}) (h/where [:= :title "write"]) hsql/format))
(jdbc/execute! ds (hsql/format {:select [:id :title :done] :from [:todo] :order-by [:id]}))
;; => [{:id 1, :title "write", :done 1} {:id 2, :title "test", :done 0}]
(jdbc/execute-one! ds (hsql/format {:select [[:%count.* :n]] :from :todo}))   ; => {:n 2}
(reduce (fn [acc row] (+ acc (:done row))) 0 (jdbc/plan ds ["select done from todo"]))  ; => 1
(jdbc/execute-batch! ds "insert into todo (title) values (?)" [["a"] ["b"]])  ; => [1 1]

(with-open [conn (jdbc/get-connection ds)]
  (jdbc/with-transaction [tx conn {:rollback-only false}]
    (jdbc/execute! tx ["delete from todo where done = 1"]))
  (sql/insert! conn :todo {:title "via sql"})          ; => {:id 3, :title "via sql"} (generated keys)
  (sql/insert! conn :todo {:title "x"} {:return-keys false})   ; => #:next.jdbc{:update-count 1}
  (sql/query conn ["select * from todo where title = ?" "via sql"]))
```

- Every call on a datasource or spec opens and closes its own connection. For
  `:memory:` that means a fresh empty db per call: open one connection instead.
- `plan` reduces an already-materialized result; it does not stream.
- `with-transaction` options: `:isolation`, `:read-only`, `:rollback-only`.

## migratus (ran)

migratus runs on db's `next.jdbc`. Exclude the Maven next.jdbc so db's copy is the
only one, and replace tools.logging (whose JVM factory lookup fails) with
jolt-lang/logging:

```clojure
{:paths ["src" "resources"]
 :deps {io.github.jolt-lang/db {:git/url "https://github.com/jolt-lang/db"
                                :git/tag "<latest>" :git/sha "<sha>"}
        migratus/migratus {:git/url "https://github.com/yogthos/migratus"
                           :git/tag "<latest>" :git/sha "<sha>"
                           :exclusions [com.github.seancorfield/next.jdbc]}
        org.clojure/tools.logging {:git/url "https://github.com/jolt-lang/logging"
                                   :git/tag "<latest>" :git/sha "<sha>"}}}
```

`resources/migrations/20260101000000-create-users.up.sql` / `.down.sql`, then:

```clojure
(ns app.mig
  (:require [next.jdbc] [migratus.core :as migratus]))

(def config {:store :database
             :migration-dir "migrations"
             :db {:connection-uri "sqlite:mig.db"}})

(migratus/migrate config)          ; applies pending ups, logs INFO lines to stderr
(migratus/completed-list config)   ; => ["create-users" "add-email"]
(migratus/rollback config)         ; runs the last down
```

Without the tools.logging override: `RuntimeException: Valid logging implementation
could not be found`. Migrations embed in a `jolt build` binary when `resources` is
in `:jolt/build {:embed [...]}`.

## PostgreSQL (not run here: no server was reachable)

Adapted from db's `clj-test/jdbc/core_test.clj`, which runs when
`JOLT_TEST_PG_URI` is set:

```clojure
(with-open [conn (jdbc/connection "postgres://user:pw@127.0.0.1:5432/app")]
  (jdbc/execute! conn "create table if not exists person (id serial primary key, name text, zip integer)")
  (first (jdbc/insert! conn :person {:name "hopper" :zip 3} {:returning true}))  ; => {:id .. :name "hopper" :zip 3}
  (jdbc/fetch conn ["select * from person where name = ?" "hopper"])
  (jdbc/execute! conn ["select * from person where tags && ?::text[]" ["a" "b"]]))  ; vector -> array literal
```

Value mapping on read: `uuid` -> uuid, `numeric` -> bigdec, `date` -> LocalDate,
`time` -> LocalTime, `timestamp` -> LocalDateTime, `timestamptz` -> OffsetDateTime,
arrays -> vectors, unparseable (e.g. `infinity`) -> text. Uuids and java.time
values bind as text and postgres infers the type.

libpq: declared `:optional` by db, so a sqlite-only app runs without it. When it is
missing, a postgres connect fails. On macOS with Homebrew's keg-only libpq run
with `DYLD_LIBRARY_PATH=/opt/homebrew/opt/libpq/lib` (checked:
`(jolt.ffi/loaded? "libpq.5.dylib")` goes false -> true). Linux: install
`libpq5`. Check with `(require '[jolt.ffi :as ffi]) (ffi/loaded? "libpq.5.dylib")`.

## SQLite practice

```clojure
(jdbc/fetch conn "pragma journal_mode=wal")           ; => [{:journal_mode "wal"}]
(jdbc/execute! conn "pragma foreign_keys=on")         ; per connection
(mapv :name (jdbc/fetch conn "pragma table_info(note)"))
```

- One connection per database file, shared, with a lock around writes (sqlite
  writes one at a time anyway). This is what newsroom does.
- Additive schema change: `alter table x add column y ...` inside a try (it throws
  when the column exists), or check `pragma table_info` first.
- `jolt build` binaries load the system libsqlite3 at startup the same way
  (checked on macOS).
