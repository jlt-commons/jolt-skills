# Time: jolt core java.time, jolt-lang/time, tick

Source: https://github.com/jolt-lang/time (README, `src/jolt/time*.clj`, deps.edn).
Use its newest tag (`jdep jolt-lang/time`, see the jolt skill's `references/deps-and-tasks.md`).

## What lives where

- **jolt core** (no dependency): the value types `Instant`, `LocalDate`,
  `LocalTime`, `LocalDateTime`, `Duration`, `Period`, `Year`, `YearMonth`,
  `MonthDay`, `Month`, `DayOfWeek`, `ChronoUnit`, `ChronoField`,
  `TemporalAdjusters` (ns `jolt.time.base`, autoloaded on first use).
- **jolt-lang/time**: everything that formats or names a zone:
  `DateTimeFormatter(Builder)`, `FormatStyle`, `TextStyle`, `ZoneId`,
  `ZoneOffset`, `ZonedDateTime`, `OffsetDateTime`, `OffsetTime`, `Clock`,
  `java.util.Locale`; plus juxt/tick (`tick.core`) and the `#time/...` literals.
  Declared via `:jolt/provides`, so writing `ZoneId` or requiring `tick.core` is
  enough; `(require 'jolt.time)` forces the install explicitly.

Without the library, those classes fail with `No dependency provides
java.time.format.DateTimeFormatter ...`. `clojure.data.json` needs it to write an
`Instant`, and db needs it internally (`Locale/US`).

Zones: IANA names resolve through libc (`jolt.host/tz-offset-seconds`), falling
back to a built-in DST table (US/EU/AU/NZ). `ZoneId/systemDefault` reads `TZ`,
then `/etc/localtime`. No native library to install.

```clojure
{:deps {io.github.jolt-lang/time {:git/url "https://github.com/jolt-lang/time"
                                  :git/tag "<latest>" :git/sha "<sha>"}}}
```

## tick (all ran)

```clojure
(require '[tick.core :as t])

(t/now)  (t/today)                                   ; Instant, LocalDate
(t/instant "2024-03-10T06:30:00Z")  (t/date "2024-02-29")  (t/time "09:15")
(t/date-time "2024-03-05T14:07")
(t/zoned-date-time "2024-03-10T09:15:00-05:00[America/New_York]")
(t/new-date 2024 3 10) (t/new-time 9 15) (t/epoch)

(def i (t/instant "2024-03-10T06:30:00Z"))
(t/>> i (t/new-duration 90 :minutes))      ; => #time/instant "2024-03-10T08:00:00Z"
(t/<< i (t/new-duration 1 :days))          ; => #time/instant "2024-03-09T06:30:00Z"
(t/>> (t/date "2024-01-31") (t/new-period 1 :months))   ; => #time/date "2024-02-29"
(t/+ (t/new-duration 1 :hours) (t/new-duration 30 :minutes))  ; + / - add amounts, not time points
(t/truncate i :hours)                      ; => #time/instant "2024-03-10T06:00:00Z"

(t/in i "Europe/Paris")                    ; Instant -> ZonedDateTime
(t/date (t/in i "America/New_York"))       ; => #time/date "2024-03-10"
(t/zone (t/in i "America/New_York"))       ; => #time/zone "America/New_York"
(t/at (t/date "2024-03-10") (t/time "09:15"))           ; => #time/date-time "2024-03-10T09:15"
(t/instant (t/in (t/date-time "2024-03-10T09:15") "Europe/London"))

(t/between (t/instant "2024-01-01T00:00:00Z") (t/instant "2024-01-01T01:30:00Z")) ; => #time/duration "PT1H30M"
(t/minutes (t/between a b))  (t/seconds d)  (t/millis d)
(t/< (t/date "2024-01-01") (t/date "2024-06-01"))  (t/max a b)
(t/day-of-week (t/date "2024-03-05"))      ; => #time/day-of-week "TUESDAY"
(t/year (t/date "2024-03-05"))             ; => #time/year "2024"

(t/format (t/formatter "yyyy-MM-dd HH:mm") (t/date-time "2024-03-05T14:07"))  ; => "2024-03-05 14:07"
(t/format :iso-local-date (t/date "2024-03-10"))
(t/parse-date "10/03/2024" (t/formatter "dd/MM/yyyy"))  ; => #time/date "2024-03-10"

(t/inst i)                                 ; java.util.Date (inst? true), for EDN/#inst
(t/instant (t/inst i))
```

Literals work in source once the library is on the classpath:
`#time/date "2024-01-01"`, `#time/instant "..."`, `#time/duration "PT1H"`.

**Broken on jolt 0.8.25:** `(t/month a-local-date)` throws `No matching field or method:
java.time.Month/from` (jolt 0.8.25 core lacks `Month/from` and `DayOfWeek/from`).
`(t/month a-date-time)` works. For a date use `(.getMonth d)` or
`(.getMonthValue d)`.

## java.time interop (ran)

```clojure
(import '(java.time Instant LocalDate LocalDateTime ZonedDateTime ZoneId Duration Period)
        '(java.time.format DateTimeFormatter)
        '(java.time.temporal ChronoUnit))

(.format (DateTimeFormatter/ofPattern "EEE, dd MMM yyyy HH:mm:ss z")
         (ZonedDateTime/of 2024 3 5 14 7 0 0 (ZoneId/of "America/New_York")))
;; => "Tue, 05 Mar 2024 14:07:00 EST"
(.format DateTimeFormatter/ISO_LOCAL_DATE (LocalDate/of 2024 3 5))     ; => "2024-03-05"
(.format DateTimeFormatter/RFC_1123_DATE_TIME (ZonedDateTime/of 2024 3 10 9 15 0 0 (ZoneId/of "GMT")))
;; => "Sun, 10 Mar 2024 09:15:00 GMT"
(.format (DateTimeFormatter/ofPattern "MMMM d, yyyy" java.util.Locale/FRENCH) (LocalDate/of 2024 3 10))
;; => "mars 10, 2024"
(LocalDate/parse "05/03/2024" (DateTimeFormatter/ofPattern "dd/MM/yyyy"))
(.atZone (Instant/parse "2024-07-01T12:00:00Z") (ZoneId/of "Asia/Tokyo"))
(.plus (LocalDateTime/parse "2024-01-31T10:00") (Duration/ofHours 36))  ; => 2024-02-01T22:00
(.until (LocalDate/of 2024 1 1) (LocalDate/of 2024 3 10) ChronoUnit/DAYS) ; => 69
(.toEpochMilli i)  (Instant/ofEpochMilli 1710052200000)  (Instant/ofEpochSecond 0)
(.getOffset (.getRules (ZoneId/of "America/New_York")) i)                ; => -05:00
(str (ZoneId/systemDefault))
```

## Storing time

- SQLite: ISO-8601 text (`(str (t/now))` sorts correctly) or epoch millis
  (`(.toEpochMilli (t/now))`, `(System/currentTimeMillis)`).
- Postgres (db): `timestamptz` reads back as `OffsetDateTime`, `timestamp` as
  `LocalDateTime`, `date` as `LocalDate`; bind java.time values directly.
- EDN: `(t/inst x)` prints as `#inst`, which `clojure.edn` reads back as a Date;
  convert with `t/instant`. Transit carries `#inst` natively.
