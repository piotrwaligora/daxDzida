# daxDzida

Research repository for one question:

> Does the simple DAX **08:55 morning-zone breakout** show a real positive
> mechanical edge after realistic execution costs — or is it not worth pursuing?

This is **Phase 1**: a fast but technically honest falsification attempt, not a
trading system. No optimisation, no parameter search, no discretionary filters.

**Status: implementation complete, no real backtest results yet.**

## Layout

| Path | What it is |
|---|---|
| `RESEARCH.md` | the Phase 1 pre-registration — read this first |
| `docs/MT5_SETUP.md` | installing, compiling and running a backtest |
| `docs/TIMEZONE.md` | Europe/Warsaw + broker server-time handling and its diagnostic |
| `MQL5/Include/daxDzida/DzTime.mqh` | calendar / DST / server-time mathematics |
| `MQL5/Include/daxDzida/DzCore.mqh` | the entire research state machine |
| `MQL5/Experts/daxDzida/DaxDzida_Phase1.mq5` | thin MT5 adapter: ticks in, orders and CSV out |
| `MQL5/Presets/` | the pre-registered A1/A2/B1/B2/C1/C2 + TZDIAG presets |
| `tests/` | deterministic regression tests and a mutation check |

## Tests

```bash
./tests/run_tests.sh        # behavioural tests + CSV schema + preset check
./tests/mutation_check.sh   # proves the suite actually catches broken logic
```

The research logic is written in the common subset of MQL5 and C++, so
`tests/run_tests.sh` compiles and exercises **the same source files** that
MetaEditor compiles into the Expert Advisor. No second implementation to drift.

## Ground rules

- The EA is research-only and refuses to run outside the MT5 Strategy Tester.
- MT5 results are produced by the user locally, in *Every tick based on real
  ticks* mode. Results are never estimated, simulated or invented here.
- Historical indicator markings are not evidence. Every session is replayed tick
  by tick, and a day that eventually touches a target is still a loss if the
  mechanical trade stopped out first.
