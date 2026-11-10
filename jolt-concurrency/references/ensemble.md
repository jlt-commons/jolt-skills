# ensemble (jlt-commons/ensemble): Erlang/OTP processes

Erlang processes and OTP behaviours on jolt fibers: links, exit signals,
monitors, selective receive, gen_server, gen_statem, gen_event, supervisors,
applications, timers, `sys`, plus nodes over a pluggable transport (loopback
only ships). Needs jolt >= 0.8.21. Source: https://github.com/jlt-commons/ensemble
(its README is the full reference).

```clojure
io.github.jlt-commons/ensemble {:git/url "https://github.com/jlt-commons/ensemble"
                                :git/tag "<latest>" :git/sha "<sha>"}
```

Fill with `jdep jlt-commons/ensemble` (jolt skill, `references/deps-and-tasks.md`).

Namespaces: `ensemble.actor` (spawn, `!`, `receive`, links, monitors),
`ensemble.gen-server`, `ensemble.gen-statem`, `ensemble.gen-event`,
`ensemble.supervisor`, `ensemble.application`, `ensemble.timer`,
`ensemble.dispatcher`, `ensemble.sys`, `ensemble.logger`, `ensemble.node`,
`ensemble.rpc`, `ensemble.global`, `ensemble.pg`.

Actors are fibers, so daemons: a `-main` that starts actors must park.

## Processes and selective receive

```clojure
(require '[ensemble.actor :as act :refer [receive]]
         '[ensemble.logger :as log])

(log/set-handler! (fn [_] nil))     ; crash reports go to *err* by default

(def echo (act/spawn (fn [] (loop [] (receive [[from ref msg] (act/! from [:reply ref msg]) (recur)])))))

(act/join (act/spawn (fn []
                       (let [ref (act/make-ref)]
                         (act/! echo [(act/self) ref :hi])
                         (receive [[:reply ref v] v]         ; ref is bound: matches its value
                                  [:after 1000 :timeout])))))  ;=> :hi

;; state by handler: (handler state msg) -> next state
(def counter (act/spawn-actor (fn [n [op x]] (case op :add (+ n x) :get (do (act/! x n) n))) 0))
(act/! counter [:add 3])
(Thread/sleep 10)
(act/state counter)                                          ;=> 3
```

`receive` clauses: `[pattern body]`, `[pattern :when guard body]`, `[x x]`
(equal values), `[:args h & t]`, map patterns, `[:after ms body]`. `act/join`
and `act/exit-reason` wait for an actor from outside the actor world.

## Links, trap-exit, monitors, timers

```clojure
(require '[ensemble.timer :as timer])

(act/join (act/spawn (fn []
                       (act/trap-exit! true)
                       (let [w (act/spawn-link (fn [] (throw (ex-info "crash" {}))))]
                         (receive [[:EXIT w reason] [:child-died (ex-message reason)]])))))
;=> [:child-died "crash"]

(act/join (act/spawn (fn [] (let [t (act/spawn (fn [] (act/exit! :bye)))
                                  r (act/monitor! t)]
                              (receive [[:DOWN r :process _ reason] reason])))))   ;=> :bye

(act/join (act/spawn (fn [] (timer/send-after 20 (act/self) :wake)
                       (receive [:wake :woke] [:after 1000 :late]))))           ;=> :woke

(act/exit-reason (act/spawn (fn [] (act/exit! :done))))                         ;=> :done
```

## gen_server + supervisor

See SKILL.md for a gen_server (`gs/Server` protocol: `init`, `handle-call`,
`handle-cast`, `handle-info`, `handle-timeout`, `terminate`) restarted by
`sup/start`. Return shapes are OTP's: `[:ok st]`, `[:reply r st]`,
`[:noreply st]`, `[:stop reason st]`. `gs/call!` (default timeout 5000 ms,
failures are ex-info with `:reason` `:noproc`/`:timeout`/the crash),
`gs/cast!`, `gs/stop!`, `gs/reply!`. Supervisor child specs: `:id`, `:start`
(a fn returning a linked process; pass `{:trap true}` so the server runs
`terminate` on shutdown), `:restart`, `:shutdown`, `:type`. Strategies:
`:one-for-one`, `:one-for-all`, `:rest-for-one`, `:simple-one-for-one`. API:
`start-child!`, `terminate-child!`, `restart-child!`, `delete-child!`,
`which-children`, `count-children`, `stop!`.

## gen_statem

```clojure
(require '[ensemble.gen-statem :as sm] '[ensemble.gen-server :as gs])

(defrecord Door []
  sm/Machine
  (init [_] [:ok :locked nil])
  (handle-event [_ type content state data]
    (cond
      (and (= type :cast) (= state :locked))        [:next-state :open data [[:state-timeout 50 :lock]]]
      (and (= type :state-timeout) (= state :open)) [:next-state :locked data]
      (and (vector? type) (= :call (first type)))   [:keep-state-and-data [[:reply (second type) state]]]
      :else                                         [:keep-state-and-data]))
  (terminate [_ _ _ _] nil))

(def door (sm/start (->Door) {}))
(gs/cast! door :push)
(Thread/sleep 10)
(gs/call! door :state?)          ;=> :open
(Thread/sleep 80)
(gs/call! door :state?)          ;=> :locked  (state timeout fired)
(gs/stop! door)
```

A call event's type is `[:call from]`; reply with the `[:reply from v]` action.

## Dispatchers: keep blocking work off the shared carriers

An actor that calls a blocking C driver or reads files pins its carrier and
every actor on it. Run those on a dispatcher of their own (`:blocking`, 16
carriers, exists already):

```clojure
(require '[ensemble.dispatcher :as disp])
(disp/define! :db {:size 2})
(act/join (act/spawn (fn [] (slurp "deps.edn") :read) {:dispatcher :db}))   ;=> :read
```

gen_server/gen_statem take `:dispatcher` as a start option.

## Applications

`:start` is a 0-arg fn returning the top supervisor; `:stop` gets what
`:prep-stop` returned (nil without one). `:applications` lists dependencies
(`ensure-all-started!` starts them first).

```clojure
(require '[ensemble.application :as app] '[ensemble.supervisor :as sup])

(app/load! {:name :shop
            :env {:port 8080}
            :start (fn [] (sup/start {:strategy :one-for-one}
                                     [{:id :w :start #(act/spawn-link (fn [] (receive [:never nil])))}]))
            :stop (fn [_] (println "shop stopped"))})
(app/start! :shop)                      ;=> :ok
(app/get-env :shop :port)               ;=> 8080
(app/stop! :shop)                       ; prints "shop stopped", => :ok
```

In a server `-main`: `(jolt.host/add-shutdown-hook #(app/stop! :shop))`, then
`(jolt.host/park-until-interrupt)` (see lifecycle.md).

## Notes

- Exit signals are fiber kills: they land even in a busy loop; `finally` runs,
  `catch` does not. `(act/exit! reason)` on yourself is a catchable throw.
- The README's first paragraph says distribution is not part of the first
  pass, but `ensemble.node` and the Distribution section exist.
