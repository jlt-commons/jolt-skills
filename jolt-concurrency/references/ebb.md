# ebb (jlt-commons/ebb): missionary on jolt

A port of missionary. Every missionary public var exists in `ebb.core`; port
missionary code by changing the require. Source of truth:
https://github.com/jlt-commons/ebb (README, `doc/conformance.md`).

```clojure
io.github.jlt-commons/ebb {:git/url "https://github.com/jlt-commons/ebb"
                           :git/tag "<latest>" :git/sha "<sha>"}
```

Fill with `jdep jlt-commons/ebb` (jolt skill, `references/deps-and-tasks.md`).

Model: a **task** is `(fn [success failure] cancel-fn)` and yields one value; a
**flow** is `(fn [notifier terminator] iterator)` and yields many, with
backpressure. Both are inert values until run. `m/?` runs a task (blocks a
thread, parks a fiber). `sp`/`ap` bodies run on fibers, so `?` works at any call
depth, unlike missionary.

```clojure
(require '[ebb.core :as m])

(m/? (m/join vector (m/sleep 100 :a) (m/sleep 200 :b)))   ;=> [:a :b]  (concurrent, ~200 ms)
(m/? (m/race (m/sleep 100 :a) (m/sleep 20 :b)))           ;=> :b       (loser cancelled)
(m/? (m/timeout (m/sleep 1000 :slow) 50 :timed-out))      ;=> :timed-out

(defn helper [ms v] (m/? (m/sleep ms v)))                 ; plain fn that parks
(m/? (m/sp (inc (helper 10 5))))                          ;=> 6

(try (m/? (m/sp (throw (ex-info "bad" {:k 1}))))
     (catch Exception e (ex-data e)))                     ;=> {:k 1}
(try ((m/? (m/attempt (m/sp (throw (ex-info "x" {:k 1}))))))  ; attempt: value-or-rethrow thunk
     (catch Exception e (ex-data e)))                     ;=> {:k 1}

(m/? (m/via m/blk (Thread/sleep 20) :io-done))            ;=> :io-done  blocking call on a thread pool
```

Use `m/via m/blk` for file IO, FFI and other calls that would pin a fiber;
`m/via m/cpu` for heavy compute. Neither pool holds the process open.

## Running a task by hand and cancelling it

```clojure
(let [p (promise)
      cancel ((m/sleep 10000 :x) #(deliver p [:ok %]) #(deliver p [:err (m/cancelled? %)]))]
  (cancel)
  @p)                                                     ;=> [:err true]
```

Cancellation is an `ex-info`, not a class: test it with `m/cancelled?`.

## Flows

```clojure
(m/? (m/reduce conj [] (m/eduction (filter odd?) (map inc) (m/seed (range 10)))))  ;=> [2 4 6 8 10]
(m/? (m/reduce conj [] (m/zip vector (m/seed [1 2 3]) (m/seed [:a :b :c]))))       ;=> [[1 :a] [2 :b] [3 :c]]
(m/? (m/reduce conj [] (m/reductions + 0 (m/seed [1 2 3]))))                       ;=> [0 1 3 6]

;; ap forks per value; (m/?> n flow) runs up to n branches at once
(m/? (m/reduce + 0 (m/ap (let [x (m/?> 4 (m/seed (range 10)))]
                           (m/? (m/sleep (- 50 (* x 5))))
                           (* x x)))))                    ;=> 285

;; an infinite ticker; reduced stops (and cancels) the flow
(defn ticks [ms] (m/ap (loop [i 0] (m/amb i (do (m/? (m/sleep ms)) (recur (inc i)))))))
(m/? (m/reduce (fn [acc x] (if (= x 3) (reduced acc) (conj acc x))) [] (ticks 10)))  ;=> [0 1 2]
```

Other flow operators: `amb=` (concurrent branches), `?<` (switch to latest),
`latest`, `sample`, `relieve`, `buffer`, `group-by`, `cp` (continuous),
`signal`/`stream` (share one run), `reactor`, `store`, `none`, `never`.

## State as flows

```clojure
(let [!x (atom 1) !y (atom 10)
      sum (m/latest + (m/watch !x) (m/watch !y))          ; continuous flow
      t (future (m/? (m/reduce conj [] (m/eduction (take 3) sum))))]
  (Thread/sleep 20) (swap! !x inc) (Thread/sleep 20) (swap! !y inc)
  @t)                                                     ;=> [11 12 13]
```

## Callback sources

`m/observe` turns a subscribe/unsubscribe API into a flow; the fn it is given
returns the cleanup, which runs when the flow is cancelled or finishes.
The emit call returns once the value has been taken by the consumer.

```clojure
(def unsubscribed (atom false))
(let [!emit (promise)
      events (m/observe (fn [emit!] (deliver !emit emit!) #(reset! unsubscribed true)))
      done (promise)]
  ((m/reduce conj [] (m/eduction (take 3) events)) #(deliver done %) #(deliver done %))
  (doseq [e [:a :b :c]] (@!emit e))
  [@done @unsubscribed])                                  ;=> [[:a :b :c] true]
```

## Ports (coordination)

```clojure
(let [v (m/dfv)] (future (Thread/sleep 10) (v 42)) (m/? v))       ;=> 42   dataflow variable
(let [mb (m/mbx)] (mb 1) (mb 2) (m/? (m/join vector mb mb)))      ;=> [1 2] mailbox
(let [lock (m/sem) n (atom 0)]                                    ; semaphore as a lock
  (m/? (apply m/join vector
              (repeat 10 (m/sp (m/holding lock
                                 (let [x @n] (m/? (m/sleep 1)) (reset! n (inc x))))))))
  @n)                                                             ;=> 10
```

`m/rdv` is a rendezvous. Delivering to a port runs the receiver's continuation
on its own fiber and waits for it, so **never deliver while holding a lock the
receiver takes**: both sides hang. Collect inside the critical section, send
after it.

## Differences from missionary (README)

`?` parks at any depth; deliveries are not run inline on the delivering thread;
`Cancelled` is an `ex-info` (`m/cancelled?`); `publisher` returns an
`ebb.rs/Publisher` protocol value instead of a Reactive Streams interface.
Full list: `doc/conformance.md` in the repo.
