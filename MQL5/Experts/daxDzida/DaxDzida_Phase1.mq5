//+------------------------------------------------------------------+
//| DaxDzida_Phase1.mq5                                              |
//| daxDzida - Phase 1 research Expert Advisor                       |
//|                                                                  |
//| RESEARCH ONLY. Refuses to run outside the MT5 Strategy Tester.   |
//|                                                                  |
//| This EA is a thin adapter. All research logic lives in           |
//| Include/daxDzida/DzCore.mqh and is covered by the deterministic  |
//| regression tests under tests/.                                   |
//|                                                                  |
//| Intended modelling mode: "Every tick based on real ticks".       |
//+------------------------------------------------------------------+
#property copyright "daxDzida research"
#property version   "1.00"
#property description "Phase 1 research EA for the 08:55-09:00 Warsaw DAX morning-zone breakout."
#property description "Strategy Tester only. Does not optimise anything."

#include <Trade/Trade.mqh>
#include <daxDzida/DzCore.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
enum EnRunMode
{
   RUN_RESEARCH       = 0,   // Research run (places orders)
   RUN_TZ_DIAGNOSTIC  = 1    // Timezone diagnostic only (no orders)
};

enum EnSlMode
{
   SLMODE_NONE          = 0, // No fixed stop loss
   SLMODE_OPPOSITE_ZONE = 1  // Stop at the opposite edge of the morning zone
};

enum EnServerTz
{
   SRVTZ_EU_DST = 0,         // Server follows the EU DST rule (e.g. EET/EEST)
   SRVTZ_FIXED  = 1          // Server clock is a constant UTC offset
};

input group "=== Run identification ==="
input EnRunMode InpRunMode                 = RUN_RESEARCH;  // Run mode
input string    InpConfigId                = "A1";          // Configuration id (A1/A2/B1/B2/C1/C2)
input string    InpRequireSymbolSubstring  = "";            // Refuse to run unless symbol contains this

input group "=== Morning zone (do NOT change in Phase 1) ==="
input int       InpZoneStartHour           = 8;             // Zone start hour (Warsaw)
input int       InpZoneStartMinute         = 55;            // Zone start minute (Warsaw)
input int       InpZoneEndHour             = 9;             // Zone freeze hour (Warsaw)
input int       InpZoneEndMinute           = 0;             // Zone freeze minute (Warsaw)

input group "=== Pre-registered variant parameters ==="
input int       InpCutoffHour              = 9;             // Hard session exit hour (Warsaw)
input int       InpCutoffMinute            = 30;            // Hard session exit minute (Warsaw)
input double    InpTpMultiplier            = 1.0;           // TP = zone edge +/- mult * range
input EnSlMode  InpSlMode                  = SLMODE_OPPOSITE_ZONE; // Stop loss mode
input int       InpMaxReversals            = 0;             // Reversals allowed on opposite breakout
input bool      InpSkipEntryOnOvershoot    = true;          // Skip entries already at/beyond TP

input group "=== Broker / server time ==="
input EnServerTz InpServerTzMode           = SRVTZ_EU_DST;  // How server timestamps map to UTC
input int        InpServerBaseUtcOffsetHrs = 2;             // Server UTC offset in WINTER (hours)

input group "=== Execution ==="
input double    InpVolume                  = 0.0;           // Fixed volume (0 = broker minimum)
input long      InpMagic                   = 8550001;       // Magic number
input ulong     InpDeviationPoints         = 100;           // Max deviation (points)

input group "=== Output ==="
input bool      InpWriteCsv                = true;          // Write the per-session research CSV
input bool      InpCsvToCommonFolder       = true;          // Write into the shared Common\Files folder
input string    InpCsvPrefix               = "daxDzida";    // CSV file name prefix
input bool      InpVerboseLog              = false;         // Log every session to the Experts journal

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade              g_trade;
DzSession           g_session;
DzCompletedSessions g_done;
DzConfig            g_cfg;
DzTzConfig          g_tz;
DzTickResult        g_res;

int    g_csv          = INVALID_HANDLE;
int    g_tzCsv        = INVALID_HANDLE;
string g_csvName      = "";
string g_tzCsvName    = "";
double g_volume       = 0.0;
long   g_lastTickMsc  = -1;
int    g_outOfOrder   = 0;

double g_balanceAtEntry   = 0.0;
double g_mtEntryPrice     = 0.0;
double g_mtExitPrice      = 0.0;
bool   g_sessionHasOrders = false;

//--- run summary counters, indexed by DzSessionState
int    g_stateCount[8];
int    g_sessionsWritten = 0;
int    g_longCount       = 0;
int    g_shortCount      = 0;
int    g_doubleBreakouts = 0;

//--- timezone diagnostic accumulator (keyed on the SERVER calendar day)
long   g_diagServerDay      = -1;
long   g_diagFirstServerMsc = -1;
long   g_diagLastServerMsc  = -1;
long   g_diagFirstWarsawMsc = -1;
long   g_diagLastWarsawMsc  = -1;
int    g_diagTicks          = 0;
int    g_diagServerOff      = 0;
int    g_diagWarsawOff      = 0;
int    g_diagFlag           = 0;

//+------------------------------------------------------------------+
//| Formatting helpers                                               |
//+------------------------------------------------------------------+
string DzFmtWallMsc(const long wallMsc)
{
   if(wallMsc < 0)
      return "";
   long day = DzFloorDiv(wallMsc, DZ_MS_PER_DAY);
   int  rem = (int)(wallMsc - day * (long)DZ_MS_PER_DAY);
   int  y, m, d;
   DzCivilFromDays(day, y, m, d);
   int hh = rem / DZ_MS_PER_HOUR; rem = rem % DZ_MS_PER_HOUR;
   int mi = rem / DZ_MS_PER_MIN;  rem = rem % DZ_MS_PER_MIN;
   int ss = rem / 1000;           rem = rem % 1000;
   return StringFormat("%04d-%02d-%02d %02d:%02d:%02d.%03d", y, m, d, hh, mi, ss, rem);
}

string DzFmtWallTimeOnly(const long wallMsc)
{
   if(wallMsc < 0)
      return "";
   long day = DzFloorDiv(wallMsc, DZ_MS_PER_DAY);
   int  rem = (int)(wallMsc - day * (long)DZ_MS_PER_DAY);
   int hh = rem / DZ_MS_PER_HOUR; rem = rem % DZ_MS_PER_HOUR;
   int mi = rem / DZ_MS_PER_MIN;  rem = rem % DZ_MS_PER_MIN;
   int ss = rem / 1000;           rem = rem % 1000;
   return StringFormat("%02d:%02d:%02d.%03d", hh, mi, ss, rem);
}

string DzFmtDate(const long epochDay)
{
   int y, m, d;
   DzCivilFromDays(epochDay, y, m, d);
   return StringFormat("%04d-%02d-%02d", y, m, d);
}

string DzDowName(const int dow)
{
   switch(dow)
   {
      case 0: return "Sun";
      case 1: return "Mon";
      case 2: return "Tue";
      case 3: return "Wed";
      case 4: return "Thu";
      case 5: return "Fri";
      case 6: return "Sat";
   }
   return "?";
}

string DzDirName(const int dir)
{
   if(dir == DZ_DIR_LONG)  return "LONG";
   if(dir == DZ_DIR_SHORT) return "SHORT";
   return "NONE";
}

string DzStateName(const int st)
{
   switch(st)
   {
      case DZ_SESS_PENDING:                   return "PENDING";
      case DZ_SESS_NO_TICKS_IN_ZONE:          return "NO_TICKS";
      case DZ_SESS_NO_TICKS_AFTER_ARM:        return "NO_TICKS_AFTER_ARM";
      case DZ_SESS_INVALID_ZONE:              return "INVALID_ZONE";
      case DZ_SESS_NO_BREAKOUT:               return "NO_BREAKOUT";
      case DZ_SESS_TRADED:                    return "TRADED";
      case DZ_SESS_ENTRY_OVERSHOOT_BEYOND_TP: return "ENTRY_OVERSHOOT_BEYOND_TP";
      case DZ_SESS_ENTRY_BEYOND_SL:           return "ENTRY_BEYOND_SL";
   }
   return "?";
}

string DzExitName(const int r)
{
   switch(r)
   {
      case DZ_EXIT_NONE:            return "";
      case DZ_EXIT_TP:              return "TP";
      case DZ_EXIT_SL:              return "SL";
      case DZ_EXIT_TIME:            return "TIME";
      case DZ_EXIT_REVERSAL:        return "REVERSAL";
      case DZ_EXIT_FORCED_NO_TICKS: return "FORCED_NO_TICKS";
   }
   return "?";
}

string DzBreakSequence(const DzSession &s)
{
   string out = "";
   int n = s.breakoutCount;
   if(n > DZ_MAX_BREAK_EVENTS)
      n = DZ_MAX_BREAK_EVENTS;
   for(int i = 0; i < n; i++)
   {
      if(i > 0)
         out += ">";
      out += (s.breakSide[i] == DZ_DIR_LONG ? "U" : "D");
   }
   if(s.breakoutCount > DZ_MAX_BREAK_EVENTS)
      out += "+";
   return out;
}

string DzSanitize(const string src)
{
   string out = "";
   int n = StringLen(src);
   for(int i = 0; i < n; i++)
   {
      ushort ch = StringGetCharacter(src, i);
      bool ok = ((ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'Z') ||
                 (ch >= 'a' && ch <= 'z') || ch == '_' || ch == '-');
      out += (ok ? ShortToString(ch) : "_");
   }
   return out;
}

//+------------------------------------------------------------------+
//| CSV                                                              |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| CSV row builder                                                  |
//|                                                                  |
//| Rows are assembled as one delimited string rather than passed as |
//| many FileWrite() arguments: FileWrite() caps the parameter count |
//| and silently truncating a research row would be worse than       |
//| useless.                                                         |
//+------------------------------------------------------------------+
string g_row  = "";
int    g_rowN = 0;   // field counter, so a legitimately EMPTY field still emits its separator

void RowReset()             { g_row = ""; g_rowN = 0; }
void RowAdd(const string v) { if(g_rowN > 0) g_row += ";"; g_row += v; g_rowN++; }
void RowAddI(const long v)  { RowAdd(IntegerToString(v)); }
void RowAddD(const double v, const int dg) { RowAdd(DoubleToString(v, dg)); }

int DzCsvFlags()
{
   int f = FILE_WRITE | FILE_TXT | FILE_ANSI;
   if(InpCsvToCommonFolder)
      f |= FILE_COMMON;
   return f;
}

bool DzOpenCsv()
{
   if(!InpWriteCsv)
      return true;

   string sym = DzSanitize(_Symbol);
   g_csvName = InpCsvPrefix + "_" + DzSanitize(InpConfigId) + "_" + sym + "_sessions.csv";
   g_csv = FileOpen(g_csvName, DzCsvFlags(), ';');
   if(g_csv == INVALID_HANDLE)
   {
      PrintFormat("ERROR: cannot open CSV '%s', error %d", g_csvName, GetLastError());
      return false;
   }

   RowReset();
   RowAdd("configurationId");
   RowAdd("symbol");
   RowAdd("date");
   RowAdd("dayOfWeek");
   RowAdd("sessionState");
   RowAdd("zoneStartWarsaw");
   RowAdd("zoneEndWarsaw");
   RowAdd("armWarsaw");
   RowAdd("zoneTicks");
   RowAdd("zoneHigh");
   RowAdd("zoneLow");
   RowAdd("zoneRange");
   RowAdd("tpLong");
   RowAdd("tpShort");
   RowAdd("slLong");
   RowAdd("slShort");
   RowAdd("slEnabled");
   RowAdd("breakoutCount");
   RowAdd("breakoutSequence");
   RowAdd("doubleBreakout");
   RowAdd("firstBreakTime");
   RowAdd("firstBreakDirection");
   RowAdd("firstBreakBid");
   RowAdd("firstBreakAsk");
   RowAdd("oppositeBreakTime");
   RowAdd("entryTime");
   RowAdd("entryDirection");
   RowAdd("entryPrice");
   RowAdd("entryBid");
   RowAdd("entryAsk");
   RowAdd("spreadAtEntry");
   RowAdd("entryOvershootBeyondTp");
   RowAdd("entryBeyondSl");
   RowAdd("reversalCount");
   RowAdd("legCount");
   RowAdd("leg1ExitTime");
   RowAdd("leg1ExitPrice");
   RowAdd("leg1ExitReason");
   RowAdd("leg2EntryTime");
   RowAdd("leg2EntryPrice");
   RowAdd("exitTime");
   RowAdd("exitPrice");
   RowAdd("exitReason");
   RowAdd("maePoints");
   RowAdd("mfePoints");
   RowAdd("holdingSeconds");
   RowAdd("grossPnLPoints");
   RowAdd("netPnLPoints");
   RowAdd("netPnLMoney");
   RowAdd("mtEntryPriceActual");
   RowAdd("mtExitPriceActual");
   RowAdd("mtEntrySlippagePoints");
   RowAdd("avgSpreadSession");
   RowAdd("sessionTicks");
   RowAdd("serverTimeArm");
   RowAdd("warsawTimeArm");
   RowAdd("utcOffsetServerSec");
   RowAdd("utcOffsetWarsawSec");
   RowAdd("tzFlag");
   FileWrite(g_csv, g_row);
   return true;
}

bool DzOpenTzCsv()
{
   string sym = DzSanitize(_Symbol);
   g_tzCsvName = InpCsvPrefix + "_TZDIAG_" + sym + "_days.csv";
   g_tzCsv = FileOpen(g_tzCsvName, DzCsvFlags(), ';');
   if(g_tzCsv == INVALID_HANDLE)
   {
      PrintFormat("ERROR: cannot open TZ diagnostic CSV '%s', error %d", g_tzCsvName, GetLastError());
      return false;
   }
   RowReset();
   RowAdd("serverDate");
   RowAdd("serverDow");
   RowAdd("tickCount");
   RowAdd("firstTickServer");
   RowAdd("lastTickServer");
   RowAdd("firstTickWarsaw");
   RowAdd("lastTickWarsaw");
   RowAdd("utcOffsetServerSec");
   RowAdd("utcOffsetWarsawSec");
   RowAdd("serverMinusWarsawSec");
   RowAdd("tzFlag");
   FileWrite(g_tzCsv, g_row);
   return true;
}

void DzWriteSessionRow(const DzSession &s, const double netMoney,
                       const double mtEntry, const double mtExit)
{
   if(s.state >= 0 && s.state < 8)
      g_stateCount[s.state]++;
   if(s.doubleBreakout)
      g_doubleBreakouts++;
   if(s.legCount > 0)
   {
      if(s.tradeDir == DZ_DIR_LONG) g_longCount++;
      else                          g_shortCount++;
   }

   if(!InpWriteCsv || g_csv == INVALID_HANDLE)
      return;

   int dow = DzDayOfWeekFromEpochDay(s.warsawDay);
   int dg  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double slip = 0.0;
   if(s.legCount > 0 && mtEntry > 0.0)
      slip = (s.tradeDir == DZ_DIR_LONG) ? (mtEntry - s.entryPrice) : (s.entryPrice - mtEntry);

   long zoneStartWall = s.warsawDay * (long)DZ_MS_PER_DAY + (long)g_cfg.zoneStartMs;
   long zoneEndWall   = s.warsawDay * (long)DZ_MS_PER_DAY + (long)g_cfg.zoneEndMs - 1;

   RowReset();
   RowAdd(InpConfigId);
   RowAdd(_Symbol);
   RowAdd(DzFmtDate(s.warsawDay));
   RowAdd(DzDowName(dow));
   RowAdd(DzStateName(s.state));
   RowAdd(DzFmtWallTimeOnly(zoneStartWall));
   RowAdd(DzFmtWallTimeOnly(zoneEndWall));
   RowAdd(DzFmtWallTimeOnly(s.armMsc));
   RowAddI(s.zoneTickCount);
   RowAddD(s.zoneHigh,  dg);
   RowAddD(s.zoneLow,   dg);
   RowAddD(s.zoneRange, dg);
   RowAddD(s.tpLong,    dg);
   RowAddD(s.tpShort,   dg);
   RowAddD(s.slEnabled ? s.slLong  : 0.0, dg);
   RowAddD(s.slEnabled ? s.slShort : 0.0, dg);
   RowAdd(s.slEnabled ? "1" : "0");
   RowAddI(s.breakoutCount);
   RowAdd(DzBreakSequence(s));
   RowAdd(s.doubleBreakout ? "DOUBLE_BREAKOUT" : "");
   RowAdd(DzFmtWallTimeOnly(s.firstBreakMsc));
   RowAdd(DzDirName(s.firstBreakDir));
   RowAddD(s.firstBreakBid, dg);
   RowAddD(s.firstBreakAsk, dg);
   RowAdd(DzFmtWallTimeOnly(s.oppositeBreakMsc));
   RowAdd(DzFmtWallTimeOnly(s.entryMsc));
   RowAdd(DzDirName(s.tradeDir));
   RowAddD(s.entryPrice,  dg);
   RowAddD(s.entryBid,    dg);
   RowAddD(s.entryAsk,    dg);
   RowAddD(s.entrySpread, dg);
   RowAdd(s.entryOvershoot ? "1" : "0");
   RowAdd(s.entryBeyondSl  ? "1" : "0");
   RowAddI(s.reversalCount);
   RowAddI(s.legCount);
   RowAdd(DzFmtWallTimeOnly(s.leg1ExitMsc));
   RowAddD(s.leg1ExitPrice, dg);
   RowAdd(DzExitName(s.leg1ExitReason));
   RowAdd(DzFmtWallTimeOnly(s.leg2EntryMsc));
   RowAddD(s.leg2EntryPrice, dg);
   RowAdd(DzFmtWallTimeOnly(s.exitMsc));
   RowAddD(s.exitPrice, dg);
   RowAdd(DzExitName(s.exitReason));
   RowAddD(s.maePoints, dg);
   RowAddD(s.mfePoints, dg);
   RowAddD(s.holdingMsc / 1000.0, 3);
   RowAddD(s.grossPnLPoints, dg);
   RowAddD(s.netPnLPoints,   dg);
   RowAddD(netMoney, 2);
   RowAddD(mtEntry, dg);
   RowAddD(mtExit,  dg);
   RowAddD(slip, dg);
   RowAddD(DzAvgSpread(s), dg);
   RowAddI(s.tickCount);
   RowAdd(DzFmtWallMsc(s.armServerMsc));
   RowAdd(DzFmtWallMsc(s.armMsc));
   RowAddI(s.armServerOffsetSec);
   RowAddI(s.armWarsawOffsetSec);
   RowAddI(s.tzFlagWorst);
   FileWrite(g_csv, g_row);

   g_sessionsWritten++;

   if(InpVerboseLog)
      PrintFormat("%s %s %s zone=[%s..%s] r=%s %s net=%s pts",
                  InpConfigId, DzFmtDate(s.warsawDay), DzStateName(s.state),
                  DoubleToString(s.zoneLow, dg), DoubleToString(s.zoneHigh, dg),
                  DoubleToString(s.zoneRange, dg), DzExitName(s.exitReason),
                  DoubleToString(s.netPnLPoints, dg));
}

//+------------------------------------------------------------------+
//| Trading                                                          |
//+------------------------------------------------------------------+
bool DzTesterOnly()
{
   return (MQLInfoInteger(MQL_TESTER) != 0);
}

bool DzHasPosition()
{
   if(!PositionSelect(_Symbol))
      return false;
   return (PositionGetInteger(POSITION_MAGIC) == InpMagic);
}

bool DzOpenPosition(const int dir)
{
   if(!DzTesterOnly())
   {
      Print("REFUSED: order requested outside the Strategy Tester.");
      return false;
   }
   bool ok = (dir == DZ_DIR_LONG)
             ? g_trade.Buy(g_volume, _Symbol, 0.0, 0.0, 0.0, "daxDzida " + InpConfigId)
             : g_trade.Sell(g_volume, _Symbol, 0.0, 0.0, 0.0, "daxDzida " + InpConfigId);
   if(!ok)
   {
      PrintFormat("ERROR: open %s failed, retcode=%d %s",
                  DzDirName(dir), g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return false;
   }
   if(g_mtEntryPrice <= 0.0)
      g_mtEntryPrice = g_trade.ResultPrice();
   return true;
}

bool DzClosePosition()
{
   if(!DzHasPosition())
      return true;
   if(!g_trade.PositionClose(_Symbol, InpDeviationPoints))
   {
      PrintFormat("ERROR: close failed, retcode=%d %s",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return false;
   }
   g_mtExitPrice = g_trade.ResultPrice();
   return true;
}

void DzExecute(const DzAction &act)
{
   if(InpRunMode != RUN_RESEARCH)
      return;

   if(act.type == DZ_ACT_OPEN)
   {
      g_balanceAtEntry   = AccountInfoDouble(ACCOUNT_BALANCE);
      g_mtEntryPrice     = 0.0;
      g_mtExitPrice      = 0.0;
      g_sessionHasOrders = true;
      DzOpenPosition(act.dir);
   }
   else if(act.type == DZ_ACT_CLOSE)
   {
      DzClosePosition();
   }
   else if(act.type == DZ_ACT_REVERSE)
   {
      DzClosePosition();
      DzOpenPosition(act.dir);
   }
}

//+------------------------------------------------------------------+
//| Timezone diagnostic                                              |
//+------------------------------------------------------------------+
void DzFlushDiagDay()
{
   if(g_diagServerDay < 0 || g_tzCsv == INVALID_HANDLE)
      return;

   long fsWall = g_diagFirstServerMsc;
   long lsWall = g_diagLastServerMsc;

   RowReset();
   RowAdd(DzFmtDate(g_diagServerDay));
   RowAdd(DzDowName(DzDayOfWeekFromEpochDay(g_diagServerDay)));
   RowAddI(g_diagTicks);
   RowAdd(DzFmtWallTimeOnly(fsWall));
   RowAdd(DzFmtWallTimeOnly(lsWall));
   RowAdd(DzFmtWallMsc(g_diagFirstWarsawMsc));
   RowAdd(DzFmtWallMsc(g_diagLastWarsawMsc));
   RowAddI(g_diagServerOff);
   RowAddI(g_diagWarsawOff);
   RowAddI(g_diagServerOff - g_diagWarsawOff);
   RowAddI(g_diagFlag);
   FileWrite(g_tzCsv, g_row);
}

void DzTrackDiag(const long serverMsc)
{
   long serverDay = DzFloorDiv(serverMsc, DZ_MS_PER_DAY);
   if(serverDay != g_diagServerDay)
   {
      DzFlushDiagDay();
      g_diagServerDay      = serverDay;
      g_diagFirstServerMsc = serverMsc;
      g_diagFirstWarsawMsc = g_res.warsawMsc;
      g_diagTicks          = 0;
      g_diagFlag           = DZ_TZFLAG_OK;
   }
   g_diagLastServerMsc = serverMsc;
   g_diagLastWarsawMsc = g_res.warsawMsc;
   g_diagServerOff     = g_res.serverOffsetSec;
   g_diagWarsawOff     = g_res.warsawOffsetSec;
   if(g_res.tzFlag > g_diagFlag)
      g_diagFlag = g_res.tzFlag;
   g_diagTicks++;
}

void DzLogEnvironment()
{
   Print("=== daxDzida Phase 1 - environment ===");
   PrintFormat("symbol=%s  digits=%d  point=%s  tickSize=%s  tickValue=%s",
               _Symbol,
               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
               DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_POINT), 8),
               DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), 8),
               DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 8));
   PrintFormat("contractSize=%s  volMin=%s  volStep=%s  volMax=%s  currency=%s",
               DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE), 2),
               DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), 2),
               DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), 2),
               DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), 2),
               SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT));
   PrintFormat("TimeCurrent=%s  TimeTradeServer=%s  TimeGMT=%s  TimeLocal=%s  TimeGMTOffset=%d",
               TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
               TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS),
               TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
               TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS),
               (int)TimeGMTOffset());
   Print("NOTE: TimeGMT()/TimeLocal() are modelled inside the Strategy Tester and are NOT a ",
         "reliable historical server->UTC mapping. The mapping actually used comes from the ",
         "InpServerTzMode / InpServerBaseUtcOffsetHrs inputs and is verified by the TZ diagnostic run.");

   for(int dow = 1; dow <= 5; dow++)
   {
      datetime from, to;
      string   line = "";
      for(int idx = 0; idx < 4; idx++)
      {
         if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dow, idx, from, to))
            break;
         line += StringFormat(" [%s-%s]",
                              TimeToString(from, TIME_MINUTES),
                              TimeToString(to,   TIME_MINUTES));
      }
      PrintFormat("server trade session dow=%d:%s", dow, (line == "" ? " (none)" : line));
   }
   Print("=== end environment ===");
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!DzTesterOnly())
   {
      Print("REFUSING TO RUN: DaxDzida_Phase1 is a RESEARCH EA and only runs in the MT5 Strategy Tester.");
      return(INIT_FAILED);
   }

   if(InpRequireSymbolSubstring != "" &&
      StringFind(_Symbol, InpRequireSymbolSubstring) < 0)
   {
      PrintFormat("REFUSING TO RUN: symbol '%s' does not contain '%s'.",
                  _Symbol, InpRequireSymbolSubstring);
      return(INIT_FAILED);
   }

   //--- configuration
   DzConfigInit(g_cfg);
   g_cfg.zoneStartMs          = InpZoneStartHour * DZ_MS_PER_HOUR + InpZoneStartMinute * DZ_MS_PER_MIN;
   g_cfg.zoneEndMs            = InpZoneEndHour   * DZ_MS_PER_HOUR + InpZoneEndMinute   * DZ_MS_PER_MIN;
   g_cfg.cutoffMs             = InpCutoffHour    * DZ_MS_PER_HOUR + InpCutoffMinute    * DZ_MS_PER_MIN;
   g_cfg.tpMult               = InpTpMultiplier;
   g_cfg.slMode               = (InpSlMode == SLMODE_OPPOSITE_ZONE ? DZ_SL_OPPOSITE_ZONE : DZ_SL_NONE);
   g_cfg.maxReversals         = InpMaxReversals;
   g_cfg.skipEntryOnOvershoot = InpSkipEntryOnOvershoot;

   if(g_cfg.zoneEndMs <= g_cfg.zoneStartMs || g_cfg.cutoffMs <= g_cfg.zoneEndMs)
   {
      Print("REFUSING TO RUN: inconsistent zone / cutoff configuration.");
      return(INIT_FAILED);
   }
   if(g_cfg.slMode == DZ_SL_OPPOSITE_ZONE && g_cfg.maxReversals > 0)
   {
      Print("REFUSING TO RUN: a stop at the opposite zone edge makes the reversal trigger ",
            "unreachable. The pre-registered C variants use InpSlMode=SLMODE_NONE.");
      return(INIT_FAILED);
   }

   DzTzConfigInit(g_tz,
                  (InpServerTzMode == SRVTZ_EU_DST ? DZ_TZ_EU_DST : DZ_TZ_FIXED),
                  InpServerBaseUtcOffsetHrs * 3600);

   DzSessionInit(g_session);
   g_done.count = 0;
   for(int i = 0; i < 8; i++)
      g_stateCount[i] = 0;

   //--- volume
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_volume = (InpVolume > 0.0 ? InpVolume : vmin);
   if(vstep > 0.0)
      g_volume = MathRound(g_volume / vstep) * vstep;
   if(g_volume < vmin)
      g_volume = vmin;

   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   DzLogEnvironment();
   PrintFormat("config=%s runMode=%s zone=%02d:%02d-%02d:%02d cutoff=%02d:%02d tpMult=%s sl=%s maxRev=%d vol=%s",
               InpConfigId,
               (InpRunMode == RUN_RESEARCH ? "RESEARCH" : "TZ_DIAGNOSTIC"),
               InpZoneStartHour, InpZoneStartMinute, InpZoneEndHour, InpZoneEndMinute,
               InpCutoffHour, InpCutoffMinute,
               DoubleToString(InpTpMultiplier, 2),
               (g_cfg.slMode == DZ_SL_OPPOSITE_ZONE ? "OPPOSITE_ZONE" : "NONE"),
               InpMaxReversals,
               DoubleToString(g_volume, 2));
   PrintFormat("server timezone model: %s, winter UTC offset = %+d h",
               (InpServerTzMode == SRVTZ_EU_DST ? "EU_DST (EET/EEST style)" : "FIXED"),
               InpServerBaseUtcOffsetHrs);

   if(InpRunMode == RUN_TZ_DIAGNOSTIC)
   {
      if(!DzOpenTzCsv())
         return(INIT_FAILED);
      Print("TZ DIAGNOSTIC RUN: no orders will be placed.");
   }
   else if(!DzOpenCsv())
      return(INIT_FAILED);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Flush completed sessions produced by the last tick               |
//+------------------------------------------------------------------+
void DzFlushCompleted()
{
   for(int i = 0; i < g_done.count; i++)
   {
      double netMoney = 0.0;
      double mtEntry  = 0.0;
      double mtExit   = 0.0;

      DzSession snap;
      if(i == 0) DzSessionCopy(snap, g_done.item0);
      else       DzSessionCopy(snap, g_done.item1);

      if(snap.legCount > 0 && g_sessionHasOrders)
      {
         netMoney = AccountInfoDouble(ACCOUNT_BALANCE) - g_balanceAtEntry;
         mtEntry  = g_mtEntryPrice;
         mtExit   = g_mtExitPrice;
      }

      DzWriteSessionRow(snap, netMoney, mtEntry, mtExit);

      g_sessionHasOrders = false;
      g_mtEntryPrice     = 0.0;
      g_mtExitPrice      = 0.0;
   }
   g_done.count = 0;
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t))
      return;
   if(t.bid <= 0.0 || t.ask <= 0.0 || t.ask < t.bid)
      return;

   long msc = (long)t.time_msc;

   //--- chronological ordering is mandatory for this study
   if(msc < g_lastTickMsc)
   {
      g_outOfOrder++;
      if(g_outOfOrder <= 5)
         PrintFormat("WARNING: out-of-order tick %s < %s - skipped.",
                     IntegerToString(msc), IntegerToString(g_lastTickMsc));
      return;
   }
   g_lastTickMsc = msc;

   DzOnTick(g_session, g_done, g_cfg, g_tz, msc, t.bid, t.ask, g_res);

   if(InpRunMode == RUN_TZ_DIAGNOSTIC)
   {
      DzTrackDiag(msc);
      g_done.count = 0;
      return;
   }

   DzExecute(g_res.act);
   DzFlushCompleted();
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(InpRunMode == RUN_TZ_DIAGNOSTIC)
   {
      DzFlushDiagDay();
      if(g_tzCsv != INVALID_HANDLE)
      {
         FileClose(g_tzCsv);
         PrintFormat("TZ diagnostic written: %s (%s)", g_tzCsvName,
                     (InpCsvToCommonFolder ? "Common\\Files" : "Tester agent MQL5\\Files"));
      }
      return;
   }

   //--- the very last day of the test never sees a rollover tick
   if(g_session.active && !g_session.flushed)
   {
      if(g_session.inTrade)
      {
         DzCloseLeg(g_session, g_session.lastMsc, g_session.lastBid,
                    g_session.lastAsk, DZ_EXIT_FORCED_NO_TICKS);
         DzClosePosition();
      }
      DzFinalise(g_session);

      double netMoney = 0.0;
      if(g_session.legCount > 0 && g_sessionHasOrders)
         netMoney = AccountInfoDouble(ACCOUNT_BALANCE) - g_balanceAtEntry;

      DzWriteSessionRow(g_session, netMoney, g_mtEntryPrice, g_mtExitPrice);
      g_session.flushed = true;
   }

   if(g_csv != INVALID_HANDLE)
   {
      FileClose(g_csv);
      PrintFormat("research CSV written: %s (%s)", g_csvName,
                  (InpCsvToCommonFolder ? "Common\\Files" : "Tester agent MQL5\\Files"));
   }

   Print("=== daxDzida Phase 1 run summary (", InpConfigId, ") ===");
   PrintFormat("sessions written        : %d", g_sessionsWritten);
   PrintFormat("  TRADED                : %d", g_stateCount[DZ_SESS_TRADED]);
   PrintFormat("  NO_BREAKOUT           : %d", g_stateCount[DZ_SESS_NO_BREAKOUT]);
   PrintFormat("  NO_TICKS              : %d", g_stateCount[DZ_SESS_NO_TICKS_IN_ZONE]);
   PrintFormat("  NO_TICKS_AFTER_ARM    : %d", g_stateCount[DZ_SESS_NO_TICKS_AFTER_ARM]);
   PrintFormat("  INVALID_ZONE          : %d", g_stateCount[DZ_SESS_INVALID_ZONE]);
   PrintFormat("  ENTRY_OVERSHOOT_TP    : %d", g_stateCount[DZ_SESS_ENTRY_OVERSHOOT_BEYOND_TP]);
   PrintFormat("  ENTRY_BEYOND_SL       : %d", g_stateCount[DZ_SESS_ENTRY_BEYOND_SL]);
   PrintFormat("LONG / SHORT            : %d / %d", g_longCount, g_shortCount);
   PrintFormat("double-breakout days    : %d", g_doubleBreakouts);
   PrintFormat("out-of-order ticks      : %d", g_outOfOrder);
   Print("=== end summary ===");
}
//+------------------------------------------------------------------+
