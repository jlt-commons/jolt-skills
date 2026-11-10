# doltera: Dolt over the MySQL wire protocol

Source: https://github.com/jolt-lang/doltera (README, `src/doltera/core.clj`,
`test/doltera/test.clj`). Use its newest tag (`jdep jolt-lang/doltera`, see the jolt skill's `references/deps-and-tasks.md`).
Pure Clojure over `java.net.Socket`; no native library. Talks to
`dolt sql-server` (MySQL protocol, `mysql_native_password` auth). Not a general
MySQL driver: tested only against Dolt.

```clojure
{:deps {io.github.jolt-lang/doltera {:git/url "https://github.com/jolt-lang/doltera"
                                     :git/tag "<latest>" :git/sha "<sha>"}}}
```

Server (Dolt needs `dolt config --global --add user.name/user.email` once):

```sh
mkdir mydb && cd mydb && dolt init
dolt sql-server --host 127.0.0.1 --port 3306
```

## API (ran against dolt sql-server on port 33061)

```clojure
(require '[doltera.core :as dolt])

(def conn (dolt/connect {:port 3306 :db "mydb"}))  ; :host 127.0.0.1 :user "root" :password "" defaults
(dolt/execute! conn "create table if not exists person (id int primary key, name varchar(100), zip int)")
(dolt/execute! conn ["insert into person values (?, ?, ?)" 1 "ada" 94546])   ; => 1 (affected rows)
(dolt/query conn ["select * from person where name = ?" "ada"])            ; => [{:id 1, :name "ada", :zip 94546}]
(dolt/fetch-one conn "select count(*) as n from person")                   ; => {:n 1}
;; dolt/fetch is an alias of query

;; transaction: f takes NO arguments; use the outer conn
(dolt/transaction conn (fn [] (dolt/execute! conn "insert into person values (2, 'bob', 10001)")))
(try (dolt/transaction conn (fn [] (dolt/execute! conn "delete from person") (throw (ex-info "no" {}))))
     (catch Exception _ :rolled-back))

;; version control
(dolt/dolt-commit conn "add person table")   ; stages everything (-A); => [{:hash "..."}]
(first (dolt/dolt-log conn))                 ; => {:commit_hash "..." :message "add person table" :author "root" ...}
(dolt/dolt-status conn)                      ; => [] when clean
(dolt/dolt-branch conn "feature")
(dolt/dolt-checkout conn "feature")
(dolt/close conn)
```

## Types

Every statement goes through prepared statements (cached, 64 per connection, LRU),
so results are typed: integers -> long (unsigned bigint past 2^63 -> bignum),
floats -> double, NULL -> nil, VARCHAR/TEXT/JSON/ENUM/SET -> string,
DECIMAL/DATE/DATETIME/TIME/TIMESTAMP -> **string** (`"2024-01-02 03:04:05"`;
parse with jolt-lang/time), YEAR/BIT -> long, BLOB/BINARY -> byte array.

## Notes

- An unknown `:db` is rejected at connect. `use` is not preparable; switch
  databases with `doltera.protocol`'s `select-db!` (it clears the statement cache).
- Users created `IDENTIFIED WITH caching_sha2_password` get `Access denied`.
- A connection is not thread-safe: one per thread, or a lock.
- `doltera.protocol` exposes the raw layer (`open-conn`, `handshake!`,
  `query-text`, `prepare-stmt`, `execute-stmt`, `clear-stmt-cache!`).
