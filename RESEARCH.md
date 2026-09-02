# daxDzida — Phase 1 pre-registration

**Status: implementation complete, no real backtest results exist yet.**

This document is written *before* any MT5 results are seen. It fixes what will be
tested, how it will be measured and what will count as a positive or negative
answer, so that the verdict cannot be quietly reshaped by whatever the data turns
out to look like.

Nothing in this repository contains, estimates or simulates MetaTrader 5 results.
All numbers used for the verdict will come from Strategy Tester runs executed by
the user and supplied back as reports, CSVs and logs.

---

## 1. The one question

> Does the simple DAX 08:55 morning-zone breakout show a real positive mechanical
> edge after realistic execution costs?

The job is **falsification**. No optimisation, no parameter search, no filters
added to rescue a weak result. If the setup is bad, Phase 1 should establish that
quickly and cheaply.

Permitted answers (§10):

- `NO EDGE`
- `INCONCLUSIVE`
- `POSITIVE STATISTICAL SIGNAL — WORTH DEEPER RESEARCH`

---

## 2. Instrument and data

| Item | Value |
|---|---|
| Instrument | DAX / DE40 / GER40 cash CFD, broker symbol chosen in the tester |
| Symbol handling | The EA uses the chart symbol; `InpRequireSymbolSubstring` can pin it |
| Modelling mode | **Every tick based on real ticks** (mandatory) |
| Signal / chart price | broker **BID** |
| Position size | fixed research volume, broker minimum by default (`InpVolume = 0`) |
| Risk sizing | none in Phase 1, deliberately |

The EA refuses to start outside the Strategy Tester (`MQL_TESTER`) and refuses to
send an order even if that guard were ever bypassed.

---

## 3. Research period

**2025-12-01 → the latest date with high-quality real ticks.**

Treated as the current-regime window. Older history is *not* mixed in.

All eligible trading weekdays are used. Nothing is excluded by hand — not
Fridays, not holidays with trading, not low-volume days, not days that look like
losers. Where the market produced no usable ticks, the session is *recorded* as
such (`NO_TICKS`), never replaced by a fabricated trade.

### 3.1 What could and could not be verified about 2025-12-01

The brief asked to check whether 2025-12-01 corresponds to a relevant Deutsche
Börse / Xetra opening-auction schedule change.

**Verified:** Deutsche Börse did introduce the *Extended Xetra Retail Service*
effective **1 December 2025**, extending Xetra trading to roughly **08:00–22:00**
for retail investors in stocks, ETFs and ETPs. There is a Deutsche Börse circular
titled "Introduction of the Extended Xetra Retail Service (early and late
trading): Planned changes to the trading process valid from 1 December 2025".

**Not verified:** that this moved the **opening auction** or the 09:00 CET start
of core Xetra continuous trading. Deutsche Börse's public trading-hours pages
still describe Xetra trading as 09:00–17:30 CET, and the primary circular could
not be retrieved directly (the site returned HTTP 403 to automated fetches).

**Therefore:** 2025-12-01 is documented here as a **research-window assumption
supplied by the user**, which happens to coincide with a real and documented
Xetra schedule change of a different kind (retail hours extension, not the
opening auction). A retail session starting at 08:00 is a plausible mechanism for
different pre-09:00 behaviour, but this study does **not** assert that and does
not depend on it. The window is simply "current regime".

Sources consulted:
- <https://www.cashmarket.deutsche-boerse.com/cash-en/Stay-Informed/circulars-newsletters/deutsche-boerse-circulars/Introduction-of-the-Extended-Xetra-Retail-Service-early-and-late-trading-Planned-changes-to-the-trading-process-valid-from-1-December-2025-4793480> (403 to automated fetch, title only)
- <https://www.marketsmedia.com/deutsche-borse-extends-retail-trading-hours-on-xetra/>
- <https://www.eurexgroup.com/xetra-en/trading/trading-calendar-and-trading-hours>

---

## 4. Strategy definition

All times are **Europe/Warsaw** wall-clock, with correct CET/CEST handling.

### 4.1 Morning zone

- Window: `08:55:00.000` inclusive → `08:59:59.999` inclusive
  (implemented as the half-open interval `[08:55:00.000, 09:00:00.000)`).
- `zoneHigh` = maximum **BID** during the window.
- `zoneLow` = minimum **BID** during the window.
- `range = zoneHigh - zoneLow`.
- The zone is **frozen** by the first tick at or after `09:00:00.000`.
  That same tick is already eligible to trigger a breakout.

### 4.2 Targets

```
TP_LONG  = zoneHigh + tpMult * range
TP_SHORT = zoneLow  - tpMult * range
```

Baseline `tpMult = 1.0`.

Validated against both source examples in the regression suite:

| zoneHigh | zoneLow | range | TP_LONG | TP_SHORT |
|---|---|---|---|---|
| 26498.9 | 26483.4 | 15.5 | 26514.4 | 26467.9 |
| 26510.3 | 26481.3 | 29.0 | 26539.3 | 26452.3 |

### 4.3 Stops

- `SL_LONG  = zoneLow`
- `SL_SHORT = zoneHigh`

Present in the A variants, absent in the B and C variants (§6).

### 4.4 Entry — intratick, no candle close

After the zone is frozen:

- first **BID > zoneHigh** → LONG signal
- first **BID < zoneLow**  → SHORT signal

Strictly beyond. A tick that only *touches* an edge is not a breakout.

Execution:

- LONG fills at the **ASK** available on that tick.
- SHORT fills at the **BID** available on that tick.

There is no fill at the zone boundary. If price has already moved through the
level, the fill is wherever the market actually is.

### 4.5 Exit

Evaluated on every tick, in chronological order, on tradable prices:

- LONG: TP and SL are evaluated on **BID**; the exit fills at that BID.
- SHORT: TP and SL are evaluated on **ASK**; the exit fills at that ASK.

Exits fill at the **real tick price, not at the level**. A gap through TP exits
better than TP; a gap through SL exits worse than SL. Both are recorded as they
happened.

Within one tick the order of evaluation is: **SL → TP → hard cutoff → reversal**.
SL is checked first as the pessimistic choice. (For a valid zone the SL and TP
conditions are mutually exclusive on a single tick, so this ordering cannot
manufacture a different P&L — it only fixes the label deterministically.)

### 4.6 Hard session exit

Anchored to **09:00, not to entry time**. A 30-minute variant expires at 09:30
even if the entry happened at 09:17. No new position is opened at or after the
cutoff.

### 4.7 Double / false breakouts

Every session is processed tick by tick. Breakout events are tracked from 09:00
until the cutoff **regardless of trade state**, so a day is fully described even
after its single trade has closed.

A breakout is registered when the BID leaves the zone on a side different from
the previously registered side. The following are always logged: first breakout
time, first breakout direction, first opposite-breakout time, total breakout
count and the ordered breakout sequence (e.g. `U>D>U`).

**A day is never classified as profitable merely because a TP was eventually
touched.** The A-variant regression test explicitly covers the case: break up →
stop out → break down → break back up → reach the long TP, and the recorded
result is a loss.

`2026-04-24` is named in the brief as a double-breakout reference day. If the
broker's real-tick history covers it, it should be checked as a behavioural
validation case once results exist.

---

## 5. Explicitly excluded from Phase 1

Fibonacci correction filters, 1.618 / 1.91 barriers, volume filters, trend
filters, RSI, manual sentiment, manual market judgement, weekday exclusions,
`DAX po DAXie`.

We are testing the dumb mechanical setup first, on purpose.

---

## 6. Pre-registered test matrix

Six configurations. No optimiser. Nothing else without explicit approval.

| Id | Entry | TP | SL | Reversal | Hard exit |
|---|---|---|---|---|---|
| **A1** | first breakout only | 1.0 × range | opposite zone edge | no | 09:30 |
| **A2** | first breakout only | 1.0 × range | opposite zone edge | no | 10:00 |
| **B1** | first breakout only | 1.0 × range | none | no | 09:30 |
| **B2** | first breakout only | 1.0 × range | none | no | 10:00 |
| **C1** | first breakout, reverse once | 1.0 × range | none | max 1 | 09:30 |
| **C2** | first breakout, reverse once | 1.0 × range | none | max 1 | 10:00 |

A = primary baseline. B = source-like no-fixed-SL diagnostic.
C = double-breakout diagnostic; after the reversal the TP is the original zone TP
for the new direction.

One `.set` preset per configuration lives in `MQL5/Presets/`, generated from a
single source of truth (`generate_presets.py`) and checked by the test suite, so
a run cannot silently drift from what is pre-registered here.

---

## 7. Decisions taken where the brief was ambiguous

These were resolved before any data was seen. Each is testable and reversible.

**D1 — C variants carry no fixed stop loss.**
A stop at the opposite zone edge fires on `bid <= zoneLow`, while the reversal
fires on `bid < zoneLow`. With both active the stop always wins and the reversal
could never happen, making C identical to A. The brief's own wording ("close the
current trade and reverse") makes the opposite edge itself the exit. The EA
*refuses to start* if a stop at the opposite edge is combined with reversals.

**D2 — a fill already at or beyond TP is not traded.**
The session is recorded as `ENTRY_OVERSHOOT_BEYOND_TP` with zero P&L and reported
separately. This follows "do not award a fictional win". The behaviour is
switchable (`InpSkipEntryOnOvershoot`) purely so the size of the effect can be
measured later; the pre-registered runs all skip.

**D3 — a fill already at or beyond the SL is not traded** either
(`ENTRY_BEYOND_SL`, reachable when the spread is wider than the zone).

**D4 — a touch is not a breakout.** `bid > zoneHigh` strictly.

**D5 — gross vs net.**
`netPnLPoints` is the tradable-price result (ASK in / BID out for a long).
`grossPnLPoints` is the BID-to-BID "chart price" result a naive backtest would
report. The difference is exactly the execution cost paid, and both are in the
CSV so the cost can be quantified rather than assumed.

**D6 — breakout counting** counts side alternations, so price sitting outside the
zone counts once, and out-the-top → out-the-bottom counts twice even without a
tick back inside the zone.

**D7 — a position still open at the Warsaw day boundary** is closed at the **last
price actually seen on that day**, flagged `FORCED_NO_TICKS`. Using the next
day's price would be a look-ahead fill.

**D8 — exits are managed by the EA on ticks, not by broker-side SL/TP orders.**
This makes the BID/ASK evaluation semantics in §4.5 exact and deterministic
rather than dependent on the tester's own order-trigger model.

**D9 — MAE / MFE** are measured on the tradable exit price of the open leg,
relative to that leg's entry price. MAE is the most negative excursion (a trade
starts one spread under water), MFE the most positive.

**D10 — missing weekdays are not fabricated.** Days with no ticks produce no row.
Reconciling the CSV's dates against a real trading calendar is part of the
analysis step, and a large number of missing weekdays is itself a data-quality
finding. Conversely, brokers that quote on Sunday evening can produce a Saturday
or Sunday row in state `NO_TICKS`; the `dayOfWeek` column exists so those are
filtered in analysis rather than silently dropped by the EA.

---

## 8. Timezone handling

A timezone error invalidates the entire study, so it is treated as a first-class
risk. See `docs/TIMEZONE.md`.

- The strategy clock is Europe/Warsaw with the EU DST rule (summer time from
  01:00 UTC on the last Sunday of March to 01:00 UTC on the last Sunday of
  October). CET = UTC+1, CEST = UTC+2.
- Broker server time is **never guessed**. It is configured explicitly
  (`InpServerTzMode`, `InpServerBaseUtcOffsetHrs`), because `TimeGMT()` and
  `TimeLocal()` are *modelled* inside the Strategy Tester and are not a reliable
  historical server→UTC mapping.
- Every session row logs the server timestamp, the Warsaw timestamp, the server
  UTC offset and the Warsaw UTC offset that were in force at the 09:00 freeze.
- A dedicated **timezone diagnostic run** (`TZDIAG.set`, places no orders) must
  be executed and reviewed **before** the first research run.

The research window contains exactly one DST transition: **2026-03-29**.

---

## 9. Metrics (computed only from real MT5 output)

Per configuration:

valid sessions · trades · no-breakout sessions · LONG count · SHORT count ·
double-breakout count · win rate · TP hit rate · average win · average loss ·
net expectancy after actual BID/ASK execution · Profit Factor · net result ·
max drawdown · relative drawdown · longest losing streak · MAE · MFE · average
spread at entry · average holding time · results by weekday · results by month.

Plus outlier dependence: full result vs result without the single best trade vs
result without the top five trades.

Win rate alone is not evidence. The primary evidence is **net expectancy, Profit
Factor, drawdown, sample size, stability and outlier dependence.**

Real-tick BID/ASK spread is part of the test. If the tester includes commission
it is included in the financial conclusion; if it does not, that limitation is
stated explicitly rather than silently ignored. **No invented slippage** is added
in Phase 1.

---

## 10. Verdict rules (fixed in advance)

**NO EDGE** — the simple setup generally shows negative net expectancy, PF ≤ 1,
or apparent profitability that is clearly unstable or outlier-dependent.

**INCONCLUSIVE** — results are mixed, or sample size / data quality is
insufficient to say either way.

**POSITIVE STATISTICAL SIGNAL — WORTH DEEPER RESEARCH** — reasonable
pre-registered variants show positive net expectancy after available costs,
PF > 1, a meaningful sample, and the result is not obviously produced by a few
isolated trades or one short period.

This is a **preliminary signal only**. It will not be called a robust edge, a
proven edge, a holy grail, or production ready. Those require out-of-sample and
robustness work that Phase 1 does not do.

---

## 11. Known limitations of Phase 1

1. Single broker, single symbol, single tick source. No cross-broker check.
2. One short, recent window. No out-of-sample period, by design.
3. Fixed volume, no risk sizing — P&L in money is a scale, not a strategy result.
4. No modelled slippage beyond what the tester's real-tick spread produces.
5. Commission/swap inclusion depends on the broker's tester configuration and
   must be read from the actual report.
6. MQL5 compilation happens on the user's Windows machine (`tools\compile.cmd`);
   the development workspace is Linux with no MetaEditor. The EA source is
   pre-flight parsed against MT5 API stubs there, which catches ordinary compile
   failures but not MQL5-only rules.
7. The `DAX po DAXie` idea and every discretionary filter the source trader uses
   are deliberately absent, so this measures the mechanical core only.

---

## 12. Test coverage

`tests/run_tests.sh` compiles the exact same `DzTime.mqh` / `DzCore.mqh` sources
that MetaEditor compiles into the EA, and runs deterministic tests over authored
tick streams. Behaviour protected today:

08:55 window start · 08:59:59.999 window end · 09:00 freeze · zoneHigh/zoneLow ·
range and TP calculation (both source examples) · zone built from BID only ·
Europe/Warsaw DST and both switch instants · EU DST boundary dates for 2025 and
2026 · server→UTC mapping for EET/EEST and fixed-offset brokers · absence of
ambiguity at 08:55 on switch days · Warsaw↔server round trip · session reset ·
first breakout · no look-ahead · opposite breakout · one allowed reversal ·
reversal cap · gap-through entry · entry-at/beyond-TP overshoot · entry beyond SL
· long BID/ASK semantics · short BID/ASK semantics · SL/TP chronological ordering
· 09:30 cutoff · 10:00 cutoff · no entry at/after cutoff · MAE/MFE · gross-vs-net
decomposition · zero-range zone rejection · no-ticks states · forced close at a
day boundary · CSV schema · preset/matrix agreement.

`tests/mql5_syntax_check.py` additionally parses the real EA source against MT5
API stubs (`tests/shim/mt5_api_shim.h`), catching typos, unbalanced braces,
undeclared identifiers, wrong argument counts and wrong return types without a
Windows round trip. It cannot check MQL5-only rules — `input` / `input group`
syntax, `#property` directives, MQL5's struct-by-reference requirement or its
conversion warnings — so a green pre-flight means "worth compiling", never
"compiles".

`tools/Test-MetaEditorLog.ps1` covers the MetaEditor log decoder and parser in
the build script, across UTF-16LE (with and without BOM) and UTF-8, because a
parser bug there would report a clean build on a broken one.

`tests/mutation_check.sh` deliberately breaks fourteen critical behaviours one at
a time and asserts the suite goes red for each, so the suite cannot rot into
something that passes vacuously.

---

## 13. Change log

- **2026-09-02** — Phase 1 pre-registration written; research EA, portable core,
  regression suite, mutation check and presets implemented. No backtest results
  exist yet.
- **2026-09-02** — Added the Windows command-line build (`tools/compile.cmd`),
  an MQL5 pre-flight syntax check and tests for the MetaEditor log parser.
  No trading behaviour changed.
