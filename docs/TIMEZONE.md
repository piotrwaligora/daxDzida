# Timezone handling

A timezone error invalidates the entire study — the strategy is defined by a
five-minute window, so being one hour out means measuring a completely different
part of the day. This file records what is assumed, what is computed, and how it
is verified.

## The strategy clock

Europe/Warsaw wall-clock time, with the EU rule:

- **CET = UTC+1** in winter, **CEST = UTC+2** in summer.
- Summer time runs from **01:00 UTC on the last Sunday of March** to
  **01:00 UTC on the last Sunday of October** (Directive 2000/84/EC).

Implemented in `DzTime.mqh` as pure integer arithmetic (no library calls, no
platform locale), so it behaves identically in MetaEditor and in the tests.

Boundary dates asserted by the regression suite:

| Year | Summer time starts | Summer time ends |
|---|---|---|
| 2025 | 30 March | 26 October |
| 2026 | 29 March | 25 October |

The Phase 1 research window (2025-12-01 →) contains exactly one transition:
**2026-03-29**.

## Broker server time — never guessed

`TimeGMT()` and `TimeLocal()` are **modelled** inside the MT5 Strategy Tester and
are not a trustworthy historical server→UTC mapping. The EA therefore does not
use them for anything except logging, and takes the mapping from explicit inputs:

| Input | Meaning |
|---|---|
| `InpServerTzMode = 0` (`SRVTZ_EU_DST`) | server clock follows the EU DST rule — e.g. EET/EEST, the common MT5 broker setup |
| `InpServerTzMode = 1` (`SRVTZ_FIXED`) | server clock is a constant UTC offset all year |
| `InpServerBaseUtcOffsetHrs` | the server's UTC offset **in winter** (2 = EET) |

### The useful invariant

For a broker whose server follows the EU DST rule with a winter offset of +2
(EET/EEST — the most common case), server time is **always Warsaw + 1 hour**,
in both winter and summer, because both clocks switch at the same UTC instant.

So `08:55 Warsaw = 09:55 server` on every single day of the year. If the
diagnostic shows the gap changing across 2026-03-29, the broker is **not** an
EU-DST server and `InpServerTzMode` must be `1` with the correct fixed offset.

For a fixed UTC+2 server, the gap is +1h in winter and 0 in summer — the zone
window moves by an hour across the switch, which is exactly the failure mode this
diagnostic exists to catch. A regression test covers both cases end to end.

### Ambiguous and non-existent wall-clock times

An EU-DST server clock repeats one hour each autumn and skips one hour each
spring, both around 03:00 local. The conversion detects and flags these
(`tzFlag`: 0 = ok, 1 = ambiguous, 2 = non-existent) and resolves them
deterministically. A regression test walks the whole 08:00–11:00 band on both
2026 switch days and asserts the flag is always 0 — the trading window is never
inside an ambiguous hour.

## The diagnostic run

`MQL5/Presets/TZDIAG.set` runs the EA in diagnostic mode. It places **no orders**
and writes one row per **server** calendar day to
`daxDzida_TZDIAG_<SYMBOL>_days.csv`:

| Column | What it tells you |
|---|---|
| `serverDate`, `serverDow` | the broker's own calendar day |
| `tickCount` | whether the day has usable data at all |
| `firstTickServer`, `lastTickServer` | the broker's trading session in **server** time |
| `firstTickWarsaw`, `lastTickWarsaw` | the same session translated to Warsaw |
| `utcOffsetServerSec` | server offset applied |
| `utcOffsetWarsawSec` | Warsaw offset applied |
| `serverMinusWarsawSec` | the invariant above — should be constant for an EU-DST broker |
| `tzFlag` | 0 everywhere is what we want |

Reading it: compare `firstTickWarsaw` / `lastTickWarsaw` against the DAX cash
session you expect from the broker's contract specification. If the translated
session sits where it should on **both sides of 2026-03-29**, the mapping is
right. If it jumps by an hour on one side, the server timezone model is wrong.

The Journal for the same run additionally prints the symbol specification, MT5's
own `TimeCurrent` / `TimeTradeServer` / `TimeGMT` / `TimeLocal` values, and the
broker's declared trading sessions per weekday in server time.

**This run happens before any research run.** No Phase 1 result is produced on an
unverified clock.
