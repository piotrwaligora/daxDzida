# MT5 setup and how to run a Phase 1 backtest

The repository mirrors MetaTrader's own folder layout, so the files can be linked
straight into the MT5 data folder and edited in place.

```
MQL5/
  Experts/daxDzida/DaxDzida_Phase1.mq5
  Include/daxDzida/DzTime.mqh
  Include/daxDzida/DzCore.mqh
  Presets/A1.set A2.set B1.set B2.set C1.set C2.set TZDIAG.set
```

---

## 0. The one command

Everything in sections 1 and 2 is automated. From the repository root:

```bat
tools\compile.cmd
```

or equivalently:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Compile-DaxDzida.ps1
```

It locates the MT5 data folder belonging to your MetaEditor install, creates the
junctions below if they are missing, compiles the EA, writes the compiler log to
`build\metaeditor-compile.log`, reports errors and warnings **separately**, runs
whatever of the test suite exists on Windows, and exits non-zero on any error.

Useful switches:

| Switch | Effect |
|---|---|
| `-MetaEditor "<path>"` | use a different MetaEditor (default: Tickmill Europe MT5 Terminal) |
| `-DataFolder "<path>"` | skip auto-detection (use the path from File → Open Data Folder) |
| `-SkipTests` | compile only |
| `-NoLink` | assume the junctions already exist |

The script refuses to continue if it finds a **real directory** where a junction
should be — that would mean MT5 is compiling a *copy* of the sources rather than
the repository, which is how a build silently drifts from the code under test.

Sections 1 and 2 describe what it does, for when it has to be done by hand.

## 1. Link the repository into the MT5 data folder

In MetaTrader 5: **File → Open Data Folder**. That opens something like
`C:\Users\pwali\AppData\Roaming\MetaQuotes\Terminal\<HASH>`.

Open an **Administrator** Command Prompt and create three junctions (adjust
`<HASH>`; the target folders must not already exist):

```bat
set MT5=%APPDATA%\MetaQuotes\Terminal\<HASH>\MQL5
set REPO=C:\Users\pwali\src\daxDzida\MQL5

mklink /J "%MT5%\Experts\daxDzida"  "%REPO%\Experts\daxDzida"
mklink /J "%MT5%\Include\daxDzida"  "%REPO%\Include\daxDzida"
mklink /J "%MT5%\Presets\daxDzida"  "%REPO%\Presets"
```

If junctions are inconvenient, copying the three folders works too — but then
every code change has to be re-copied before recompiling, which is exactly the
kind of mistake that silently invalidates a run.

## 2. Compile

Either press **F7** in MetaEditor, or use the command line, which is what
`tools\compile.cmd` runs:

```
"C:\Program Files\Tickmill Europe MT5 Terminal\MetaEditor64.exe" ^
    /compile:"<DATA FOLDER>\MQL5\Experts\daxDzida\DaxDzida_Phase1.mq5" ^
    /inc:"<DATA FOLDER>\MQL5" ^
    /log:"<REPO>\build\metaeditor-compile.log"
```

Compiling *through the junction* matters: `/inc:` pointing at the terminal's
`MQL5` folder is what lets `#include <daxDzida/DzCore.mqh>` and
`#include <Trade/Trade.mqh>` both resolve, and it puts the `.ex5` exactly where
the Strategy Tester expects it.

Expected: **0 errors**. Warnings are reported separately and should be
investigated rather than ignored.

MetaEditor's exit code is not trusted — some builds return 0 regardless — so the
log itself is parsed. That parser has its own tests
(`pwsh -NoProfile -File tools\Test-MetaEditorLog.ps1`), because a parser bug
would report a clean build on a broken one.

## 3. Make sure real ticks exist

In MT5: **View → Symbols → <your DAX symbol> → Ticks**, request the research
period, and let the download finish. "Every tick based on real ticks" silently
falls back to worse modelling if the ticks are not there.

---

## 4. Strategy Tester settings

| Setting | Value |
|---|---|
| Expert | `daxDzida\DaxDzida_Phase1` |
| Symbol | your broker's DAX / DE40 / GER40 **cash** symbol |
| Period | **M1** (the EA is tick-driven; the timeframe only affects tester overhead) |
| Modelling | **Every tick based on real ticks** |
| Forward | **No** |
| Optimisation | **Disabled** — Phase 1 never runs the optimiser |
| Deposit / leverage | broker default is fine (fixed volume, no risk sizing) |
| Inputs | **Load** the relevant `.set` from `MQL5\Presets\daxDzida\` |

---

## 5. The pre-registered presets

| Preset | Run mode | SL | Reversals | Hard exit | Purpose |
|---|---|---|---|---|---|
| `TZDIAG.set` | diagnostic, **no orders** | — | — | — | establish the server↔Warsaw mapping |
| `A1.set` | research | opposite zone edge | 0 | 09:30 | primary baseline |
| `A2.set` | research | opposite zone edge | 0 | 10:00 | baseline, longer hold |
| `B1.set` | research | none | 0 | 09:30 | source-like, no fixed stop |
| `B2.set` | research | none | 0 | 10:00 | source-like, longer hold |
| `C1.set` | research | none | 1 | 09:30 | double-breakout diagnostic |
| `C2.set` | research | none | 1 | 10:00 | double-breakout, longer hold |

The `.set` files are generated from `MQL5/Presets/generate_presets.py` and the
test suite fails if they are edited by hand — that keeps a run from drifting away
from what `RESEARCH.md` pre-registers. If a parameter genuinely needs to change,
change the generator and regenerate.

Only two inputs are expected to need adjusting per broker:

- `InpServerTzMode` — `0` = server follows the EU DST rule (EET/EEST style,
  the common case), `1` = server clock is a constant UTC offset.
- `InpServerBaseUtcOffsetHrs` — the server's UTC offset **in winter**
  (`2` for a typical EET/EEST broker).

Both are confirmed by the TZ diagnostic run before any research run.

---

## 6. Where the output lands

With `InpCsvToCommonFolder = true` (the default) files are written to the shared
common folder, which every tester agent can reach:

```
%APPDATA%\MetaQuotes\Terminal\Common\Files\
```

| Run | File |
|---|---|
| TZ diagnostic | `daxDzida_TZDIAG_<SYMBOL>_days.csv` |
| Research run | `daxDzida_<CONFIG>_<SYMBOL>_sessions.csv` |

The CSV delimiter is `;`.

## 7. What to send back after a run

1. The CSV named above.
2. The Strategy Tester **Journal** tab (it contains the environment block: symbol
   spec, session times, timezone model, and the end-of-run summary).
3. For research runs, the Strategy Tester **Report** (Backtest tab → right-click
   → Report) and the **Trades/Deals** list.

Nothing is analysed from anything else. No result is ever estimated or simulated.
