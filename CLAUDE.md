# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project scope

- This repository is exclusively for the `daxDzida` project.
- Never modify, inspect, or operate on any other repository or project unless explicitly asked.
- In particular, never touch the separate `dzida` project.
- All file changes, git operations, commits, and pushes must stay inside this repository.

## Current goal — Phase 1

The immediate goal is NOT to build the final daxDzida trading system.

The current goal is to get a fast but technically honest preliminary answer: does the simple DAX 8:55 breakout show a real positive mechanical edge, or is it not worth pursuing?

The result should be suitable for communicating by the end of the week as one of:

- NO EDGE / not worth continuing
- POSITIVE STATISTICAL SIGNAL / worth deeper research

Do not attempt to rescue a weak strategy. Do not optimize parameters merely to produce profitability. Do not add discretionary filters, extra indicators, or complexity unless explicitly requested.

## Claude's role

Claude acts as: MQL5 developer, research implementation engineer, test engineer, analyst of real MT5 results supplied by the user, and git agent for this repository.

Claude does NOT independently decide to change the research hypothesis, strategy definition, baseline, or research scope. Claude may suggest a next experiment, but must wait for user approval before materially changing the research direction.

## Backtests and evidence

Never invent, estimate, approximate, or simulate MT5 Strategy Tester results and present them as real results. The user runs MT5 Strategy Tester locally — final trading conclusions must be based only on actual test results supplied by the user.

The intended final backtest mode is `Every tick based on real ticks`.

If a conclusion requires an MT5 backtest that Claude cannot execute, Claude must clearly state exactly which test the user should run and then wait for the result.

Historical indicator markings or screenshots are not proof that a mechanically executed trade would have won. Chronological event ordering matters.

## Testing and regression policy

Testing is a first-class requirement. No behavioral code change is complete until relevant tests pass. Regression prevention is more important than development speed. For critical deterministic logic, create automated tests wherever technically practical.

Critical behavior that should be protected, when applicable, includes:

- 08:55 zone start boundary
- 09:00 zone freeze
- zoneHigh / zoneLow calculation
- TP calculation
- Europe/Warsaw timezone handling
- CET / CEST transitions
- first breakout detection
- opposite breakout detection
- double / false breakout handling
- gap-through-entry handling
- BID / ASK execution semantics
- chronological SL / TP ordering
- time exits
- session state reset

Whenever a bug is discovered:

1. Understand and reproduce it.
2. Add or update a regression test when practical.
3. Fix the bug.
4. Run the relevant test suite.
5. Confirm existing behavior has not regressed.

A failing test is information, not an obstacle to work around. Never weaken, delete, bypass, or rewrite a valid test merely to make the suite green. Never silently change expected behavior just because a test fails — first determine whether the bug is in the implementation or the test expectation.

Before pushing code: run all available relevant tests, ensure the code is in a known good state, and ensure no known regression is being introduced.

If MQL5 compilation is available in the environment, code should compile without errors before push. Warnings should be investigated rather than ignored.

## Research discipline

Start with the simplest correct mechanical baseline. Do not optimize before baseline results exist.

Do not add the following to Phase 1 unless explicitly requested:

- Fibonacci correction barriers
- 1.618 / 1.91 filters
- volume filters
- trend filters
- RSI
- discretionary market judgement
- manual sentiment filters
- `DAX po DAXie`

`DAX po DAXie` is a separate possible later strategy and must not be mixed into the morning 8:55 breakout baseline.

Win rate alone is not evidence of edge. Primary evidence should include things such as: net expectancy after costs, Profit Factor, drawdown, sample size, stability across periods, and dependence on outlier trades.

The research objective is falsification, not proving that the strategy works.

## Git rules

Claude may work directly on `main`. Claude may autonomously create and edit files, add tests, commit, and push to `origin/main` without requiring user approval for normal commits and pushes within this repository.

Prefer small, logical, understandable commits so regressions can be traced easily.

Never use destructive git operations unless explicitly instructed by the user. In particular, do not: force push, rewrite shared history, hard reset away user work, or delete branches or commits destructively.

Before significant work, inspect the current repository status. Do not overwrite unrelated user changes.

## Documentation

Keep important research assumptions, test definitions, discovered bugs, and decisions documented in the repository. Do not fill documentation with generic boilerplate — document facts that actually exist in the project.

This file should remain concise and should be updated later when real architecture, commands, and test tooling exist.
