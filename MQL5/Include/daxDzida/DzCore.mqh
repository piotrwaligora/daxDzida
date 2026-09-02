//+------------------------------------------------------------------+
//| DzCore.mqh                                                       |
//| daxDzida - Phase 1 research                                      |
//|                                                                  |
//| Deterministic, tick-driven session state machine for the         |
//| 08:55-08:59:59.999 Warsaw morning-zone breakout.                 |
//|                                                                  |
//| This file contains ALL research logic. The MQL5 Expert Advisor   |
//| is only a thin adapter: it feeds ticks in and executes the       |
//| actions this state machine emits. The same source is compiled    |
//| by g++ for the regression tests (see tests/).                    |
//|                                                                  |
//| See the PORTABILITY CONTRACT comment in DzTime.mqh.              |
//+------------------------------------------------------------------+
#ifndef DZ_CORE_MQH
#define DZ_CORE_MQH

#include "DzTime.mqh"

#define DZ_MAX_BREAK_EVENTS 8
#define DZ_NO_MSC           (-1)

//--- lifecycle of one trading day
enum DzPhase
{
   DZ_PHASE_PRE      = 0,   // before 08:55 Warsaw
   DZ_PHASE_ZONE     = 1,   // inside [08:55:00.000, 09:00:00.000)
   DZ_PHASE_ARMED    = 2,   // zone frozen, waiting for the first breakout
   DZ_PHASE_IN_TRADE = 3,
   DZ_PHASE_POST     = 4,   // trade finished, still tracking breakouts until cutoff
   DZ_PHASE_DONE     = 5
};

enum DzDir
{
   DZ_DIR_NONE  = 0,
   DZ_DIR_LONG  = 1,
   DZ_DIR_SHORT = 2
};

enum DzSlMode
{
   DZ_SL_NONE          = 0,   // no fixed stop (source-like diagnostic)
   DZ_SL_OPPOSITE_ZONE = 1    // stop at the opposite edge of the morning zone
};

enum DzExitReason
{
   DZ_EXIT_NONE            = 0,
   DZ_EXIT_TP              = 1,
   DZ_EXIT_SL              = 2,
   DZ_EXIT_TIME            = 3,   // hard session cutoff reached
   DZ_EXIT_REVERSAL        = 4,   // closed because the opposite zone edge broke
   DZ_EXIT_FORCED_NO_TICKS = 5    // no tick arrived at/after the cutoff on that day
};

enum DzSessionState
{
   DZ_SESS_PENDING                   = 0,
   DZ_SESS_NO_TICKS_IN_ZONE          = 1,  // no ticks inside 08:55-09:00 Warsaw
   DZ_SESS_NO_TICKS_AFTER_ARM        = 2,  // zone built but no tick at/after 09:00
   DZ_SESS_INVALID_ZONE              = 3,  // zone range <= 0
   DZ_SESS_NO_BREAKOUT               = 4,
   DZ_SESS_TRADED                    = 5,
   DZ_SESS_ENTRY_OVERSHOOT_BEYOND_TP = 6,  // first executable fill already at/beyond TP
   DZ_SESS_ENTRY_BEYOND_SL           = 7   // first executable fill already at/beyond SL
};

enum DzActionType
{
   DZ_ACT_NONE    = 0,
   DZ_ACT_OPEN    = 1,
   DZ_ACT_CLOSE   = 2,
   DZ_ACT_REVERSE = 3   // close the current leg and immediately open the opposite one
};

//+------------------------------------------------------------------+
//| Pre-registered configuration of one Phase 1 variant.             |
//+------------------------------------------------------------------+
struct DzConfig
{
   int    zoneStartMs;            // 08:55:00.000 inclusive
   int    zoneEndMs;              // 09:00:00.000 exclusive (== freeze/arm instant)
   int    cutoffMs;               // hard session exit, anchored to 09:00 not to entry
   double tpMult;                 // TP = zone edge +/- tpMult * range
   int    slMode;                 // DzSlMode
   int    maxReversals;           // 0 (A/B) or 1 (C)
   bool   skipEntryOnOvershoot;   // do not award a fictional win on gap-through entries
};

void DzConfigInit(DzConfig &c)
{
   c.zoneStartMs          = 8 * DZ_MS_PER_HOUR + 55 * DZ_MS_PER_MIN;  // 31 980 000
   c.zoneEndMs            = 9 * DZ_MS_PER_HOUR;                       // 32 400 000
   c.cutoffMs             = 9 * DZ_MS_PER_HOUR + 30 * DZ_MS_PER_MIN;  // 34 200 000
   c.tpMult               = 1.0;
   c.slMode               = DZ_SL_OPPOSITE_ZONE;
   c.maxReversals         = 0;
   c.skipEntryOnOvershoot = true;
}

//+------------------------------------------------------------------+
//| One trading day / one configuration. This is also the CSV row.   |
//+------------------------------------------------------------------+
struct DzSession
{
   bool   active;
   bool   flushed;
   long   warsawDay;          // epoch day of the Warsaw calendar date
   int    phase;
   int    state;
   int    tzFlagWorst;        // worst DzTzFlag seen on this day

   //--- morning zone
   int    zoneTickCount;
   double zoneHigh;
   double zoneLow;
   double zoneRange;
   bool   zoneValid;
   long   zoneFirstTickMsc;   // Warsaw wall-clock ms
   long   zoneLastTickMsc;
   long   armMsc;             // Warsaw wall-clock ms of the tick that froze the zone
   long   armServerMsc;       // broker/server ms of that same tick
   int    armServerOffsetSec; // server UTC offset in force at the freeze instant
   int    armWarsawOffsetSec; // Warsaw UTC offset in force at the freeze instant

   //--- derived levels
   double tpLong;
   double tpShort;
   double slLong;
   double slShort;
   bool   slEnabled;

   //--- breakout diagnostics (run until the cutoff regardless of trade state)
   int    breakoutCount;
   int    breakSide[DZ_MAX_BREAK_EVENTS];
   long   breakMsc [DZ_MAX_BREAK_EVENTS];
   int    lastBreakSide;
   long   firstBreakMsc;
   int    firstBreakDir;
   double firstBreakBid;
   double firstBreakAsk;
   long   oppositeBreakMsc;
   bool   doubleBreakout;

   //--- trade (session level)
   bool   inTrade;
   int    tradeDir;           // direction of the FIRST leg
   long   entryMsc;
   double entryPrice;         // ASK for long, BID for short
   double entryBid;
   double entryAsk;
   double entrySpread;
   bool   entryOvershoot;     // first executable fill was already at/beyond TP
   bool   entryBeyondSl;      // first executable fill was already at/beyond SL
   int    reversalCount;
   int    legCount;
   double maePoints;          // most adverse excursion, <= 0
   double mfePoints;          // most favourable excursion, >= 0
   long   holdingMsc;         // summed over legs

   //--- current leg
   int    legDir;
   long   legEntryMsc;
   double legEntryPrice;
   double legEntryBid;
   double legEntryAsk;

   //--- exits
   long   exitMsc;            // final exit
   double exitPrice;
   int    exitReason;
   long   leg1ExitMsc;
   double leg1ExitPrice;
   int    leg1ExitReason;
   long   leg2EntryMsc;
   double leg2EntryPrice;

   //--- P&L in index points
   double grossPnLPoints;     // BID-to-BID ("chart price") P&L
   double netPnLPoints;       // tradable-price P&L (ASK in / BID out for longs)

   //--- housekeeping
   long   lastMsc;
   double lastBid;
   double lastAsk;
   double spreadSum;
   int    spreadCount;
   int    tickCount;
};

//+------------------------------------------------------------------+
//| Emitted to the EA so it can place the corresponding MT5 order.   |
//| At most one action is produced per tick.                         |
//+------------------------------------------------------------------+
struct DzAction
{
   int    type;      // DzActionType
   int    dir;       // direction to be OPEN after this action
   double price;     // research execution price
   int    reason;    // DzExitReason for CLOSE / REVERSE
};

struct DzTickResult
{
   DzAction act;
   long     utcMsc;
   long     warsawMsc;
   long     warsawDay;
   int      todMs;
   int      serverOffsetSec;
   int      warsawOffsetSec;
   int      tzFlag;
};

//+------------------------------------------------------------------+
//| Up to two sessions can complete on a single tick: the previous   |
//| day is flushed by the day-rollover, and the incoming tick could  |
//| itself immediately terminate the new day (first tick already     |
//| past 09:00 -> NO_TICKS_IN_ZONE).                                 |
//+------------------------------------------------------------------+
struct DzCompletedSessions
{
   int       count;
   DzSession item0;
   DzSession item1;
};

//+------------------------------------------------------------------+
//| Explicit member-wise copy. Avoids relying on struct assignment   |
//| semantics being identical in MQL5 and C++.                       |
//+------------------------------------------------------------------+
void DzSessionCopy(DzSession &dst, const DzSession &src)
{
   dst.active            = src.active;
   dst.flushed           = src.flushed;
   dst.warsawDay         = src.warsawDay;
   dst.phase             = src.phase;
   dst.state             = src.state;
   dst.tzFlagWorst       = src.tzFlagWorst;

   dst.zoneTickCount     = src.zoneTickCount;
   dst.zoneHigh          = src.zoneHigh;
   dst.zoneLow           = src.zoneLow;
   dst.zoneRange         = src.zoneRange;
   dst.zoneValid         = src.zoneValid;
   dst.zoneFirstTickMsc  = src.zoneFirstTickMsc;
   dst.zoneLastTickMsc   = src.zoneLastTickMsc;
   dst.armMsc            = src.armMsc;
   dst.armServerMsc      = src.armServerMsc;
   dst.armServerOffsetSec= src.armServerOffsetSec;
   dst.armWarsawOffsetSec= src.armWarsawOffsetSec;

   dst.tpLong            = src.tpLong;
   dst.tpShort           = src.tpShort;
   dst.slLong            = src.slLong;
   dst.slShort           = src.slShort;
   dst.slEnabled         = src.slEnabled;

   dst.breakoutCount     = src.breakoutCount;
   for(int i = 0; i < DZ_MAX_BREAK_EVENTS; i++)
   {
      dst.breakSide[i] = src.breakSide[i];
      dst.breakMsc [i] = src.breakMsc [i];
   }
   dst.lastBreakSide     = src.lastBreakSide;
   dst.firstBreakMsc     = src.firstBreakMsc;
   dst.firstBreakDir     = src.firstBreakDir;
   dst.firstBreakBid     = src.firstBreakBid;
   dst.firstBreakAsk     = src.firstBreakAsk;
   dst.oppositeBreakMsc  = src.oppositeBreakMsc;
   dst.doubleBreakout    = src.doubleBreakout;

   dst.inTrade           = src.inTrade;
   dst.tradeDir          = src.tradeDir;
   dst.entryMsc          = src.entryMsc;
   dst.entryPrice        = src.entryPrice;
   dst.entryBid          = src.entryBid;
   dst.entryAsk          = src.entryAsk;
   dst.entrySpread       = src.entrySpread;
   dst.entryOvershoot    = src.entryOvershoot;
   dst.entryBeyondSl     = src.entryBeyondSl;
   dst.reversalCount     = src.reversalCount;
   dst.legCount          = src.legCount;
   dst.maePoints         = src.maePoints;
   dst.mfePoints         = src.mfePoints;
   dst.holdingMsc        = src.holdingMsc;

   dst.legDir            = src.legDir;
   dst.legEntryMsc       = src.legEntryMsc;
   dst.legEntryPrice     = src.legEntryPrice;
   dst.legEntryBid       = src.legEntryBid;
   dst.legEntryAsk       = src.legEntryAsk;

   dst.exitMsc           = src.exitMsc;
   dst.exitPrice         = src.exitPrice;
   dst.exitReason        = src.exitReason;
   dst.leg1ExitMsc       = src.leg1ExitMsc;
   dst.leg1ExitPrice     = src.leg1ExitPrice;
   dst.leg1ExitReason    = src.leg1ExitReason;
   dst.leg2EntryMsc      = src.leg2EntryMsc;
   dst.leg2EntryPrice    = src.leg2EntryPrice;

   dst.grossPnLPoints    = src.grossPnLPoints;
   dst.netPnLPoints      = src.netPnLPoints;

   dst.lastMsc           = src.lastMsc;
   dst.lastBid           = src.lastBid;
   dst.lastAsk           = src.lastAsk;
   dst.spreadSum         = src.spreadSum;
   dst.spreadCount       = src.spreadCount;
   dst.tickCount         = src.tickCount;
}

//+------------------------------------------------------------------+
//| Start a fresh trading day.                                       |
//+------------------------------------------------------------------+
void DzSessionReset(DzSession &s, const long warsawDay)
{
   s.active            = true;
   s.flushed           = false;
   s.warsawDay         = warsawDay;
   s.phase             = DZ_PHASE_PRE;
   s.state             = DZ_SESS_PENDING;
   s.tzFlagWorst       = DZ_TZFLAG_OK;

   s.zoneTickCount     = 0;
   s.zoneHigh          = 0.0;
   s.zoneLow           = 0.0;
   s.zoneRange         = 0.0;
   s.zoneValid         = false;
   s.zoneFirstTickMsc  = DZ_NO_MSC;
   s.zoneLastTickMsc   = DZ_NO_MSC;
   s.armMsc            = DZ_NO_MSC;
   s.armServerMsc      = DZ_NO_MSC;
   s.armServerOffsetSec= 0;
   s.armWarsawOffsetSec= 0;

   s.tpLong            = 0.0;
   s.tpShort           = 0.0;
   s.slLong            = 0.0;
   s.slShort           = 0.0;
   s.slEnabled         = false;

   s.breakoutCount     = 0;
   for(int i = 0; i < DZ_MAX_BREAK_EVENTS; i++)
   {
      s.breakSide[i] = DZ_DIR_NONE;
      s.breakMsc [i] = DZ_NO_MSC;
   }
   s.lastBreakSide     = DZ_DIR_NONE;
   s.firstBreakMsc     = DZ_NO_MSC;
   s.firstBreakDir     = DZ_DIR_NONE;
   s.firstBreakBid     = 0.0;
   s.firstBreakAsk     = 0.0;
   s.oppositeBreakMsc  = DZ_NO_MSC;
   s.doubleBreakout    = false;

   s.inTrade           = false;
   s.tradeDir          = DZ_DIR_NONE;
   s.entryMsc          = DZ_NO_MSC;
   s.entryPrice        = 0.0;
   s.entryBid          = 0.0;
   s.entryAsk          = 0.0;
   s.entrySpread       = 0.0;
   s.entryOvershoot    = false;
   s.entryBeyondSl     = false;
   s.reversalCount     = 0;
   s.legCount          = 0;
   s.maePoints         = 0.0;
   s.mfePoints         = 0.0;
   s.holdingMsc        = 0;

   s.legDir            = DZ_DIR_NONE;
   s.legEntryMsc       = DZ_NO_MSC;
   s.legEntryPrice     = 0.0;
   s.legEntryBid       = 0.0;
   s.legEntryAsk       = 0.0;

   s.exitMsc           = DZ_NO_MSC;
   s.exitPrice         = 0.0;
   s.exitReason        = DZ_EXIT_NONE;
   s.leg1ExitMsc       = DZ_NO_MSC;
   s.leg1ExitPrice     = 0.0;
   s.leg1ExitReason    = DZ_EXIT_NONE;
   s.leg2EntryMsc      = DZ_NO_MSC;
   s.leg2EntryPrice    = 0.0;

   s.grossPnLPoints    = 0.0;
   s.netPnLPoints      = 0.0;

   s.lastMsc           = DZ_NO_MSC;
   s.lastBid           = 0.0;
   s.lastAsk           = 0.0;
   s.spreadSum         = 0.0;
   s.spreadCount       = 0;
   s.tickCount         = 0;
}

void DzSessionInit(DzSession &s)
{
   DzSessionReset(s, 0);
   s.active = false;
}

//+------------------------------------------------------------------+
//| Freeze the morning zone at 09:00 and derive the levels.          |
//+------------------------------------------------------------------+
void DzFreezeZone(DzSession &s, const DzConfig &cfg, const long warsawMsc)
{
   s.armMsc = warsawMsc;

   if(s.zoneTickCount <= 0)
   {
      s.zoneValid = false;
      s.state     = DZ_SESS_NO_TICKS_IN_ZONE;
      return;
   }

   s.zoneRange = s.zoneHigh - s.zoneLow;
   if(s.zoneRange <= 0.0)
   {
      s.zoneValid = false;
      s.state     = DZ_SESS_INVALID_ZONE;
      return;
   }

   s.zoneValid = true;
   s.tpLong    = s.zoneHigh + s.zoneRange * cfg.tpMult;
   s.tpShort   = s.zoneLow  - s.zoneRange * cfg.tpMult;
   s.slEnabled = (cfg.slMode == DZ_SL_OPPOSITE_ZONE);
   s.slLong    = s.zoneLow;    // long is stopped at the lower zone edge
   s.slShort   = s.zoneHigh;   // short is stopped at the upper zone edge
}

//+------------------------------------------------------------------+
//| Breakout bookkeeping. Runs from 09:00 until the cutoff on every  |
//| tick, independently of whether a trade is open. A breakout is    |
//| registered when the BID leaves the zone on a side different from |
//| the previously registered side.                                  |
//+------------------------------------------------------------------+
void DzTrackBreakouts(DzSession &s, const double bid, const double ask, const long warsawMsc)
{
   int side = DZ_DIR_NONE;
   if(bid > s.zoneHigh)
      side = DZ_DIR_LONG;
   else if(bid < s.zoneLow)
      side = DZ_DIR_SHORT;

   if(side == DZ_DIR_NONE || side == s.lastBreakSide)
      return;

   s.lastBreakSide = side;

   if(s.breakoutCount < DZ_MAX_BREAK_EVENTS)
   {
      s.breakSide[s.breakoutCount] = side;
      s.breakMsc [s.breakoutCount] = warsawMsc;
   }
   s.breakoutCount++;

   if(s.breakoutCount == 1)
   {
      s.firstBreakMsc = warsawMsc;
      s.firstBreakDir = side;
      s.firstBreakBid = bid;
      s.firstBreakAsk = ask;
   }
   else if(side != s.firstBreakDir && s.oppositeBreakMsc == DZ_NO_MSC)
   {
      s.oppositeBreakMsc = warsawMsc;
      s.doubleBreakout   = true;
   }
}

//+------------------------------------------------------------------+
//| Leg open / close.                                                |
//+------------------------------------------------------------------+
void DzOpenLeg(DzSession &s, const int dir, const long warsawMsc,
               const double bid, const double ask)
{
   s.inTrade       = true;
   s.legDir        = dir;
   s.legEntryMsc   = warsawMsc;
   s.legEntryBid   = bid;
   s.legEntryAsk   = ask;
   s.legEntryPrice = (dir == DZ_DIR_LONG ? ask : bid);
   s.legCount++;

   double exc = (dir == DZ_DIR_LONG) ? (bid - s.legEntryPrice) : (s.legEntryPrice - ask);
   if(s.legCount == 1)
   {
      s.mfePoints = exc;
      s.maePoints = exc;
   }
   else
   {
      if(exc > s.mfePoints) s.mfePoints = exc;
      if(exc < s.maePoints) s.maePoints = exc;
   }
}

void DzCloseLeg(DzSession &s, const long warsawMsc, const double bid,
                const double ask, const int reason)
{
   double px    = (s.legDir == DZ_DIR_LONG) ? bid : ask;
   double net   = 0.0;
   double gross = 0.0;

   if(s.legDir == DZ_DIR_LONG)
   {
      net   = bid - s.legEntryAsk;   // paid the ask, received the bid
      gross = bid - s.legEntryBid;   // BID-to-BID "chart price" result
   }
   else
   {
      net   = s.legEntryBid - ask;   // sold the bid, bought back the ask
      gross = s.legEntryBid - bid;
   }

   s.netPnLPoints   += net;
   s.grossPnLPoints += gross;
   s.holdingMsc     += (warsawMsc - s.legEntryMsc);

   if(s.legCount == 1)
   {
      s.leg1ExitMsc    = warsawMsc;
      s.leg1ExitPrice  = px;
      s.leg1ExitReason = reason;
   }

   s.exitMsc    = warsawMsc;
   s.exitPrice  = px;
   s.exitReason = reason;
   s.inTrade    = false;
}

void DzUpdateExcursion(DzSession &s, const double bid, const double ask)
{
   double exc = (s.legDir == DZ_DIR_LONG) ? (bid - s.legEntryPrice)
                                          : (s.legEntryPrice - ask);
   if(exc > s.mfePoints) s.mfePoints = exc;
   if(exc < s.maePoints) s.maePoints = exc;
}

//+------------------------------------------------------------------+
//| Attempt the first entry.                                         |
//+------------------------------------------------------------------+
void DzTryEnter(DzSession &s, const DzConfig &cfg, const int dir, const long warsawMsc,
                const double bid, const double ask, DzAction &act)
{
   double entryPx = (dir == DZ_DIR_LONG ? ask : bid);
   double tp      = (dir == DZ_DIR_LONG ? s.tpLong : s.tpShort);

   bool overshootTp = (dir == DZ_DIR_LONG) ? (entryPx >= tp) : (entryPx <= tp);
   if(overshootTp)
   {
      s.entryOvershoot = true;
      if(cfg.skipEntryOnOvershoot)
      {
         s.state = DZ_SESS_ENTRY_OVERSHOOT_BEYOND_TP;
         s.phase = DZ_PHASE_POST;
         return;
      }
   }

   if(s.slEnabled)
   {
      bool beyondSl = (dir == DZ_DIR_LONG) ? (bid <= s.slLong) : (ask >= s.slShort);
      if(beyondSl)
      {
         s.entryBeyondSl = true;
         s.state         = DZ_SESS_ENTRY_BEYOND_SL;
         s.phase         = DZ_PHASE_POST;
         return;
      }
   }

   s.tradeDir    = dir;
   s.entryMsc    = warsawMsc;
   s.entryBid    = bid;
   s.entryAsk    = ask;
   s.entryPrice  = entryPx;
   s.entrySpread = ask - bid;

   DzOpenLeg(s, dir, warsawMsc, bid, ask);

   s.state = DZ_SESS_TRADED;
   s.phase = DZ_PHASE_IN_TRADE;

   act.type   = DZ_ACT_OPEN;
   act.dir    = dir;
   act.price  = entryPx;
   act.reason = DZ_EXIT_NONE;
}

//+------------------------------------------------------------------+
//| Finalise a session that will not receive any further ticks.      |
//+------------------------------------------------------------------+
void DzFinalise(DzSession &s)
{
   if(s.phase == DZ_PHASE_PRE)
      s.state = DZ_SESS_NO_TICKS_IN_ZONE;
   else if(s.phase == DZ_PHASE_ZONE)
      s.state = DZ_SESS_NO_TICKS_AFTER_ARM;
   else if(s.state == DZ_SESS_PENDING)
      s.state = DZ_SESS_NO_BREAKOUT;

   s.phase = DZ_PHASE_DONE;
}

void DzPushCompleted(DzCompletedSessions &done, const DzSession &s)
{
   if(done.count == 0)
      DzSessionCopy(done.item0, s);
   else if(done.count == 1)
      DzSessionCopy(done.item1, s);
   if(done.count < 2)
      done.count++;
}

//+------------------------------------------------------------------+
//| Main entry point. One call per tick, in strict chronological     |
//| order. Emits at most one action and at most two completed        |
//| session records.                                                 |
//+------------------------------------------------------------------+
void DzOnTick(DzSession &s, DzCompletedSessions &done, const DzConfig &cfg,
              const DzTzConfig &tz, const long serverMsc,
              const double bid, const double ask, DzTickResult &res)
{
   res.act.type   = DZ_ACT_NONE;
   res.act.dir    = DZ_DIR_NONE;
   res.act.price  = 0.0;
   res.act.reason = DZ_EXIT_NONE;
   done.count     = 0;

   long utcMsc, warsawMsc, warsawDay;
   int  todMs, sOff, wOff, flag;
   DzServerMscToWarsaw(tz, serverMsc, utcMsc, warsawMsc, warsawDay,
                       todMs, sOff, wOff, flag);

   res.utcMsc          = utcMsc;
   res.warsawMsc       = warsawMsc;
   res.warsawDay       = warsawDay;
   res.todMs           = todMs;
   res.serverOffsetSec = sOff;
   res.warsawOffsetSec = wOff;
   res.tzFlag          = flag;

   //--- day rollover -------------------------------------------------
   if(!s.active)
   {
      DzSessionReset(s, warsawDay);
   }
   else if(warsawDay != s.warsawDay)
   {
      if(s.inTrade)
      {
         // The day ended while a position was open, i.e. no tick arrived at or
         // after the cutoff. Close at the LAST PRICE ACTUALLY SEEN on that day -
         // using the new day's price would be a look-ahead fill.
         DzCloseLeg(s, s.lastMsc, s.lastBid, s.lastAsk, DZ_EXIT_FORCED_NO_TICKS);
         res.act.type   = DZ_ACT_CLOSE;
         res.act.dir    = s.legDir;
         res.act.price  = s.exitPrice;
         res.act.reason = DZ_EXIT_FORCED_NO_TICKS;
      }
      if(!s.flushed)
      {
         DzFinalise(s);
         DzPushCompleted(done, s);
         s.flushed = true;
      }
      DzSessionReset(s, warsawDay);
   }

   //--- housekeeping -------------------------------------------------
   s.lastMsc = warsawMsc;
   s.lastBid = bid;
   s.lastAsk = ask;
   s.spreadSum += (ask - bid);
   s.spreadCount++;
   s.tickCount++;
   if(flag > s.tzFlagWorst)
      s.tzFlagWorst = flag;

   if(s.phase == DZ_PHASE_DONE)
      return;

   //--- zone construction --------------------------------------------
   if(s.phase == DZ_PHASE_PRE)
   {
      if(todMs < cfg.zoneStartMs)
         return;                                   // before 08:55, nothing to do

      if(todMs < cfg.zoneEndMs)
      {
         s.phase = DZ_PHASE_ZONE;                  // fall through into zone build
      }
      else
      {
         // first tick of this Warsaw day is already at/after 09:00
         s.zoneValid = false;
         s.state     = DZ_SESS_NO_TICKS_IN_ZONE;
         s.phase     = DZ_PHASE_DONE;
         DzFinalise(s);
         DzPushCompleted(done, s);
         s.flushed = true;
         return;
      }
   }

   if(s.phase == DZ_PHASE_ZONE)
   {
      if(todMs < cfg.zoneEndMs)
      {
         // NO LOOK-AHEAD: ticks inside the zone window can never trade.
         if(s.zoneTickCount == 0)
         {
            s.zoneHigh         = bid;
            s.zoneLow          = bid;
            s.zoneFirstTickMsc = warsawMsc;
         }
         else
         {
            if(bid > s.zoneHigh) s.zoneHigh = bid;
            if(bid < s.zoneLow)  s.zoneLow  = bid;
         }
         s.zoneTickCount++;
         s.zoneLastTickMsc = warsawMsc;
         return;
      }

      // First tick at or after 09:00 freezes the zone AND is already eligible
      // to trigger a breakout.
      s.armServerMsc       = serverMsc;
      s.armServerOffsetSec = sOff;
      s.armWarsawOffsetSec = wOff;
      DzFreezeZone(s, cfg, warsawMsc);
      if(!s.zoneValid)
      {
         s.phase = DZ_PHASE_DONE;
         DzFinalise(s);
         DzPushCompleted(done, s);
         s.flushed = true;
         return;
      }
      s.phase = DZ_PHASE_ARMED;
   }

   //--- breakout diagnostics (independent of trade state) -------------
   if(todMs < cfg.cutoffMs)
      DzTrackBreakouts(s, bid, ask, warsawMsc);

   //--- trade management ----------------------------------------------
   if(s.phase == DZ_PHASE_IN_TRADE)
   {
      DzUpdateExcursion(s, bid, ask);

      // 1. stop loss first (pessimistic ordering)
      if(s.inTrade && s.slEnabled)
      {
         bool hitSl = (s.legDir == DZ_DIR_LONG) ? (bid <= s.slLong) : (ask >= s.slShort);
         if(hitSl)
         {
            DzCloseLeg(s, warsawMsc, bid, ask, DZ_EXIT_SL);
            res.act.type   = DZ_ACT_CLOSE;
            res.act.dir    = s.legDir;
            res.act.price  = s.exitPrice;
            res.act.reason = DZ_EXIT_SL;
         }
      }

      // 2. take profit
      if(s.inTrade)
      {
         bool hitTp = (s.legDir == DZ_DIR_LONG) ? (bid >= s.tpLong) : (ask <= s.tpShort);
         if(hitTp)
         {
            DzCloseLeg(s, warsawMsc, bid, ask, DZ_EXIT_TP);
            res.act.type   = DZ_ACT_CLOSE;
            res.act.dir    = s.legDir;
            res.act.price  = s.exitPrice;
            res.act.reason = DZ_EXIT_TP;
         }
      }

      // 3. hard session cutoff, anchored to 09:00 and not to entry time
      if(s.inTrade && todMs >= cfg.cutoffMs)
      {
         DzCloseLeg(s, warsawMsc, bid, ask, DZ_EXIT_TIME);
         res.act.type   = DZ_ACT_CLOSE;
         res.act.dir    = s.legDir;
         res.act.price  = s.exitPrice;
         res.act.reason = DZ_EXIT_TIME;
      }

      // 4. opposite-side breakout -> close and reverse once
      if(s.inTrade && todMs < cfg.cutoffMs && s.reversalCount < cfg.maxReversals)
      {
         bool opposite = (s.legDir == DZ_DIR_LONG) ? (bid < s.zoneLow) : (bid > s.zoneHigh);
         if(opposite)
         {
            int newDir = (s.legDir == DZ_DIR_LONG) ? DZ_DIR_SHORT : DZ_DIR_LONG;
            DzCloseLeg(s, warsawMsc, bid, ask, DZ_EXIT_REVERSAL);
            DzOpenLeg(s, newDir, warsawMsc, bid, ask);
            s.reversalCount++;
            s.leg2EntryMsc   = warsawMsc;
            s.leg2EntryPrice = s.legEntryPrice;

            res.act.type   = DZ_ACT_REVERSE;
            res.act.dir    = newDir;
            res.act.price  = s.legEntryPrice;
            res.act.reason = DZ_EXIT_REVERSAL;
         }
      }

      if(!s.inTrade)
         s.phase = DZ_PHASE_POST;
   }
   else if(s.phase == DZ_PHASE_ARMED)
   {
      if(todMs >= cfg.cutoffMs)
      {
         s.state = DZ_SESS_NO_BREAKOUT;
         s.phase = DZ_PHASE_DONE;
      }
      else
      {
         int dir = DZ_DIR_NONE;
         if(bid > s.zoneHigh)
            dir = DZ_DIR_LONG;
         else if(bid < s.zoneLow)
            dir = DZ_DIR_SHORT;

         if(dir != DZ_DIR_NONE)
            DzTryEnter(s, cfg, dir, warsawMsc, bid, ask, res.act);
      }
   }

   if(s.phase == DZ_PHASE_POST && todMs >= cfg.cutoffMs)
      s.phase = DZ_PHASE_DONE;

   if(s.phase == DZ_PHASE_DONE && !s.flushed)
   {
      DzFinalise(s);
      DzPushCompleted(done, s);
      s.flushed = true;
   }
}

//+------------------------------------------------------------------+
//| Derived helpers used by both the EA and the tests.               |
//+------------------------------------------------------------------+
double DzAvgSpread(const DzSession &s)
{
   if(s.spreadCount <= 0)
      return 0.0;
   return s.spreadSum / (double)s.spreadCount;
}

bool DzHasTrade(const DzSession &s)
{
   return (s.legCount > 0);
}

#endif // DZ_CORE_MQH
