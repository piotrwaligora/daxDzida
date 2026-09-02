//+------------------------------------------------------------------+
//| tests/test_dz.cpp                                                |
//|                                                                  |
//| Deterministic regression tests for the daxDzida Phase 1 research |
//| logic. Compiles the very same DzTime.mqh / DzCore.mqh sources    |
//| that MetaEditor compiles into the EA.                            |
//|                                                                  |
//|   cd tests && ./run_tests.sh                                     |
//+------------------------------------------------------------------+
#include "shim/mql5_shim.h"
#include "../MQL5/Include/daxDzida/DzCore.mqh"

#include <cstdio>
#include <cmath>

// ------------------------------------------------------------------
//  tiny assertion harness
// ------------------------------------------------------------------
static int         g_checks = 0;
static int         g_fails  = 0;
static const char *g_case   = "(none)";

#define CASE(name) do { g_case = (name); std::printf("- %s\n", g_case); } while(0)

#define CHECK(cond)                                                            \
   do {                                                                        \
      g_checks++;                                                              \
      if(!(cond)) {                                                            \
         g_fails++;                                                            \
         std::printf("    FAIL line %d: %s\n", __LINE__, #cond);               \
      }                                                                        \
   } while(0)

#define CHECK_EQI(a, b)                                                        \
   do {                                                                        \
      g_checks++;                                                              \
      long _a = (long)(a), _b = (long)(b);                                     \
      if(_a != _b) {                                                           \
         g_fails++;                                                            \
         std::printf("    FAIL line %d: %s == %s   (%ld != %ld)\n",            \
                     __LINE__, #a, #b, _a, _b);                                \
      }                                                                        \
   } while(0)

#define CHECK_EQD(a, b, eps)                                                   \
   do {                                                                        \
      g_checks++;                                                              \
      double _a = (a), _b = (b);                                               \
      if(std::fabs(_a - _b) > (eps)) {                                         \
         g_fails++;                                                            \
         std::printf("    FAIL line %d: %s == %s   (%.6f != %.6f)\n",          \
                     __LINE__, #a, #b, _a, _b);                                \
      }                                                                        \
   } while(0)

static const double EPS = 1e-6;

// ------------------------------------------------------------------
//  test context: feeds ticks authored in Warsaw wall-clock time
// ------------------------------------------------------------------
struct Ctx
{
   DzSession           s;
   DzCompletedSessions done;
   DzConfig            cfg;
   DzTzConfig          tz;
   DzTickResult        res;
   DzSession           lastDone;
   int                 doneCount;
};

static void ctxInit(Ctx &c, int slMode, int maxRev, int cutoffMs,
                    double tpMult = 1.0, bool skipOvershoot = true,
                    int tzMode = DZ_TZ_EU_DST, int baseOff = 7200)
{
   DzConfigInit(c.cfg);
   c.cfg.slMode               = slMode;
   c.cfg.maxReversals         = maxRev;
   c.cfg.cutoffMs             = cutoffMs;
   c.cfg.tpMult               = tpMult;
   c.cfg.skipEntryOnOvershoot = skipOvershoot;

   DzTzConfigInit(c.tz, tzMode, baseOff);
   DzSessionInit(c.s);
   DzSessionInit(c.lastDone);
   c.done.count = 0;
   c.doneCount  = 0;
}

static void feed(Ctx &c, long warsawWallMsc, double bid, double ask)
{
   long serverMsc = DzWarsawWallMscToServerMsc(c.tz, warsawWallMsc);
   DzOnTick(c.s, c.done, c.cfg, c.tz, serverMsc, bid, ask, c.res);
   for(int i = 0; i < c.done.count; i++)
   {
      if(i == 0) DzSessionCopy(c.lastDone, c.done.item0);
      else       DzSessionCopy(c.lastDone, c.done.item1);
      c.doneCount++;
   }
}

#define MS0930 (9 * DZ_MS_PER_HOUR + 30 * DZ_MS_PER_MIN)
#define MS1000 (10 * DZ_MS_PER_HOUR)

// A plain CET weekday (Tuesday 2026-02-10) and a CEST weekday (2026-06-10).
static long WD(int h, int mi, int s, int ms) { return DzWarsawWallMsc(2026, 2, 10, h, mi, s, ms); }
static long WD2(int h, int mi, int s, int ms){ return DzWarsawWallMsc(2026, 2, 11, h, mi, s, ms); }

// Build a standard 90..100 zone with spread 1.0 and freeze it at 09:00.
// The 09:00 tick is inside the zone, so it cannot trigger a breakout.
static void buildStdZone(Ctx &c)
{
   feed(c, WD(8, 55,  0,   0), 95.0, 96.0);
   feed(c, WD(8, 57,  0,   0), 100.0, 101.0);
   feed(c, WD(8, 58,  0,   0), 90.0, 91.0);
   feed(c, WD(8, 59, 59, 999), 95.0, 96.0);
   feed(c, WD(9,  0,  0,   0), 95.0, 96.0);
}

// ==================================================================
//  1. calendar mathematics
// ==================================================================
static void test_calendar()
{
   CASE("calendar: days_from_civil / civil_from_days round trip");

   CHECK_EQI(DzDaysFromCivil(1970, 1, 1), 0);
   CHECK_EQI(DzDayOfWeekFromEpochDay(0), 4);           // 1970-01-01 was a Thursday
   CHECK_EQI(DzDaysFromCivil(1970, 1, 2), 1);
   CHECK_EQI(DzDaysFromCivil(2000, 3, 1) - DzDaysFromCivil(2000, 2, 28), 2); // leap year
   CHECK_EQI(DzDaysFromCivil(1900, 3, 1) - DzDaysFromCivil(1900, 2, 28), 1); // not a leap year

   int y, m, d;
   long day = DzDaysFromCivil(2026, 2, 10);
   DzCivilFromDays(day, y, m, d);
   CHECK_EQI(y, 2026); CHECK_EQI(m, 2); CHECK_EQI(d, 10);

   day = DzDaysFromCivil(2025, 12, 1);
   DzCivilFromDays(day, y, m, d);
   CHECK_EQI(y, 2025); CHECK_EQI(m, 12); CHECK_EQI(d, 1);
   CHECK_EQI(DzDayOfWeekFromEpochDay(day), 1);          // 2025-12-01 was a Monday

   // 2026-04-24 - the double-breakout reference date named in the brief.
   CHECK_EQI(DzDayOfWeekFromEpochDay(DzDaysFromCivil(2026, 4, 24)), 5); // Friday
}

// ==================================================================
//  2. Europe/Warsaw DST
// ==================================================================
static void test_warsaw_dst()
{
   CASE("timezone: EU summer-time boundary dates");

   // Last Sunday of March / October
   int y, m, d;
   DzCivilFromDays(DzLastSundayEpochDay(2025, 3, 31), y, m, d);
   CHECK_EQI(y, 2025); CHECK_EQI(m, 3); CHECK_EQI(d, 30);
   DzCivilFromDays(DzLastSundayEpochDay(2025, 10, 31), y, m, d);
   CHECK_EQI(y, 2025); CHECK_EQI(m, 10); CHECK_EQI(d, 26);
   DzCivilFromDays(DzLastSundayEpochDay(2026, 3, 31), y, m, d);
   CHECK_EQI(y, 2026); CHECK_EQI(m, 3); CHECK_EQI(d, 29);
   DzCivilFromDays(DzLastSundayEpochDay(2026, 10, 31), y, m, d);
   CHECK_EQI(y, 2026); CHECK_EQI(m, 10); CHECK_EQI(d, 25);

   CASE("timezone: Warsaw UTC offset around the switch instants");

   long springUtc = DzDaysFromCivil(2026, 3, 29) * (long)DZ_SEC_PER_DAY + 3600;
   long autumnUtc = DzDaysFromCivil(2026, 10, 25) * (long)DZ_SEC_PER_DAY + 3600;

   CHECK_EQI(DzWarsawUtcOffsetSec(springUtc - 1), 3600);   // CET
   CHECK_EQI(DzWarsawUtcOffsetSec(springUtc),     7200);   // CEST starts
   CHECK_EQI(DzWarsawUtcOffsetSec(autumnUtc - 1), 7200);   // CEST
   CHECK_EQI(DzWarsawUtcOffsetSec(autumnUtc),     3600);   // CET returns

   // Deep winter / deep summer inside the research window
   CHECK_EQI(DzWarsawUtcOffsetSec(DzDaysFromCivil(2025, 12, 15) * (long)DZ_SEC_PER_DAY), 3600);
   CHECK_EQI(DzWarsawUtcOffsetSec(DzDaysFromCivil(2026,  7, 15) * (long)DZ_SEC_PER_DAY), 7200);
}

// ==================================================================
//  3. broker/server time mapping
// ==================================================================
static void unpack(const DzTzConfig &tz, long serverMsc,
                   long &warsawDay, int &todMs, int &sOff, int &wOff, int &flag)
{
   long utcMsc, warsawMsc;
   DzServerMscToWarsaw(tz, serverMsc, utcMsc, warsawMsc, warsawDay, todMs, sOff, wOff, flag);
}

static void test_server_mapping()
{
   CASE("timezone: EET/EEST broker is always Warsaw + 1h");

   DzTzConfig eet; DzTzConfigInit(eet, DZ_TZ_EU_DST, 7200);

   long warsawDay; int todMs, sOff, wOff, flag;

   // Winter weekday: 09:55 server == 08:55 Warsaw
   long srvW = DzDaysFromCivil(2026, 2, 10) * (long)DZ_MS_PER_DAY
             + 9 * (long)DZ_MS_PER_HOUR + 55 * (long)DZ_MS_PER_MIN;
   unpack(eet, srvW, warsawDay, todMs, sOff, wOff, flag);
   CHECK_EQI(todMs, 8 * DZ_MS_PER_HOUR + 55 * DZ_MS_PER_MIN);
   CHECK_EQI(sOff, 7200); CHECK_EQI(wOff, 3600); CHECK_EQI(flag, DZ_TZFLAG_OK);
   CHECK_EQI(warsawDay, DzDaysFromCivil(2026, 2, 10));

   // Summer weekday: 09:55 server == 08:55 Warsaw as well
   long srvS = DzDaysFromCivil(2026, 6, 10) * (long)DZ_MS_PER_DAY
             + 9 * (long)DZ_MS_PER_HOUR + 55 * (long)DZ_MS_PER_MIN;
   unpack(eet, srvS, warsawDay, todMs, sOff, wOff, flag);
   CHECK_EQI(todMs, 8 * DZ_MS_PER_HOUR + 55 * DZ_MS_PER_MIN);
   CHECK_EQI(sOff, 10800); CHECK_EQI(wOff, 7200); CHECK_EQI(flag, DZ_TZFLAG_OK);

   CASE("timezone: fixed-offset broker shifts relative to Warsaw across DST");

   DzTzConfig fx; DzTzConfigInit(fx, DZ_TZ_FIXED, 7200);

   unpack(fx, srvW, warsawDay, todMs, sOff, wOff, flag);      // winter: server = Warsaw + 1h
   CHECK_EQI(todMs, 8 * DZ_MS_PER_HOUR + 55 * DZ_MS_PER_MIN);
   unpack(fx, srvS, warsawDay, todMs, sOff, wOff, flag);      // summer: server = Warsaw
   CHECK_EQI(todMs, 9 * DZ_MS_PER_HOUR + 55 * DZ_MS_PER_MIN);

   CASE("timezone: 08:55 Warsaw is never ambiguous on a DST switch day");

   long switchDays[2];
   switchDays[0] = DzDaysFromCivil(2026, 3, 29);
   switchDays[1] = DzDaysFromCivil(2026, 10, 25);
   for(int i = 0; i < 2; i++)
   {
      // walk the whole 08:00-11:00 Warsaw band in server terms
      for(int minute = 0; minute < 180; minute++)
      {
         long srv = switchDays[i] * (long)DZ_MS_PER_DAY
                  + 8 * (long)DZ_MS_PER_HOUR + (long)minute * DZ_MS_PER_MIN;
         unpack(eet, srv, warsawDay, todMs, sOff, wOff, flag);
         CHECK_EQI(flag, DZ_TZFLAG_OK);
      }
   }

   CASE("timezone: Warsaw wall-clock -> server -> Warsaw round trip");

   long probes[6];
   probes[0] = DzWarsawWallMsc(2025, 12,  1,  8, 55,  0,   0);
   probes[1] = DzWarsawWallMsc(2026,  2, 10,  8, 59, 59, 999);
   probes[2] = DzWarsawWallMsc(2026,  3, 27,  9,  0,  0,   0);   // last CET Friday
   probes[3] = DzWarsawWallMsc(2026,  3, 30,  9,  0,  0,   0);   // first CEST Monday
   probes[4] = DzWarsawWallMsc(2026,  6, 10, 10,  0,  0,   0);
   probes[5] = DzWarsawWallMsc(2026, 10, 26,  8, 55,  0,   0);   // first CET Monday again

   DzTzConfig modes[2]; DzTzConfigInit(modes[0], DZ_TZ_EU_DST, 7200);
                        DzTzConfigInit(modes[1], DZ_TZ_FIXED,  7200);
   for(int mi = 0; mi < 2; mi++)
   {
      for(int i = 0; i < 6; i++)
      {
         long srv = DzWarsawWallMscToServerMsc(modes[mi], probes[i]);
         long utcMsc, warsawMsc;
         DzServerMscToWarsaw(modes[mi], srv, utcMsc, warsawMsc, warsawDay, todMs, sOff, wOff, flag);
         CHECK_EQI(warsawMsc, probes[i]);
      }
   }
}

// ==================================================================
//  4. zone window boundaries and freeze
// ==================================================================
static void test_zone_window()
{
   CASE("zone: 08:55:00.000 is the first included tick");

   Ctx c; ctxInit(c, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   feed(c, WD(8, 54, 59, 999), 500.0, 501.0);       // must be ignored
   CHECK_EQI(c.s.zoneTickCount, 0);
   CHECK_EQI(c.s.phase, DZ_PHASE_PRE);

   feed(c, WD(8, 55, 0, 0), 95.0, 96.0);
   CHECK_EQI(c.s.zoneTickCount, 1);
   CHECK_EQI(c.s.phase, DZ_PHASE_ZONE);
   CHECK_EQD(c.s.zoneHigh, 95.0, EPS);
   CHECK_EQD(c.s.zoneLow,  95.0, EPS);

   CASE("zone: 08:59:59.999 is the last included tick, 09:00:00.000 freezes");

   feed(c, WD(8, 59, 59, 999), 100.0, 101.0);
   CHECK_EQI(c.s.zoneTickCount, 2);
   CHECK_EQD(c.s.zoneHigh, 100.0, EPS);
   CHECK_EQI(c.s.phase, DZ_PHASE_ZONE);
   CHECK(!c.s.zoneValid);

   feed(c, WD(9, 0, 0, 0), 97.0, 98.0);
   CHECK(c.s.zoneValid);
   CHECK_EQI(c.s.phase, DZ_PHASE_ARMED);
   CHECK_EQD(c.s.zoneHigh, 100.0, EPS);
   CHECK_EQD(c.s.zoneLow,   95.0, EPS);
   CHECK_EQD(c.s.zoneRange,  5.0, EPS);
   CHECK_EQI(c.s.armMsc, WD(9, 0, 0, 0));

   CASE("zone: a tick after 09:00 never widens the zone");

   feed(c, WD(9, 1, 0, 0), 99.0, 100.0);
   CHECK_EQD(c.s.zoneHigh, 100.0, EPS);
   CHECK_EQD(c.s.zoneLow,   95.0, EPS);
}

// ==================================================================
//  5. TP formula, validated against the two source examples
// ==================================================================
static void test_tp_formula()
{
   CASE("levels: TP = zone edge +/- 1.0 x range (Capital.com example)");

   Ctx c; ctxInit(c, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   feed(c, WD(8, 55, 0, 0), 26490.0, 26491.0);
   feed(c, WD(8, 56, 0, 0), 26498.9, 26499.9);
   feed(c, WD(8, 57, 0, 0), 26483.4, 26484.4);
   feed(c, WD(9,  0, 0, 0), 26490.0, 26491.0);

   CHECK_EQD(c.s.zoneHigh,  26498.9, 1e-6);
   CHECK_EQD(c.s.zoneLow,   26483.4, 1e-6);
   CHECK_EQD(c.s.zoneRange,     15.5, 1e-6);
   CHECK_EQD(c.s.tpLong,    26514.4, 1e-6);
   CHECK_EQD(c.s.tpShort,   26467.9, 1e-6);
   CHECK_EQD(c.s.slLong,    26483.4, 1e-6);
   CHECK_EQD(c.s.slShort,   26498.9, 1e-6);

   CASE("levels: TP formula (second source example)");

   Ctx c2; ctxInit(c2, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   feed(c2, WD(8, 55, 0, 0), 26495.0, 26496.0);
   feed(c2, WD(8, 56, 0, 0), 26510.3, 26511.3);
   feed(c2, WD(8, 57, 0, 0), 26481.3, 26482.3);
   feed(c2, WD(9,  0, 0, 0), 26495.0, 26496.0);

   CHECK_EQD(c2.s.zoneRange,    29.0, 1e-6);
   CHECK_EQD(c2.s.tpLong,   26539.3, 1e-6);
   CHECK_EQD(c2.s.tpShort,  26452.3, 1e-6);

   CASE("levels: the zone is built from BID only, never from ASK");

   // ASK reaches 26600 inside the window; it must not move the zone.
   Ctx c3; ctxInit(c3, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   feed(c3, WD(8, 55, 0, 0), 26490.0, 26600.0);
   feed(c3, WD(8, 56, 0, 0), 26498.9, 26499.9);
   feed(c3, WD(8, 57, 0, 0), 26483.4, 26484.4);
   feed(c3, WD(9,  0, 0, 0), 26490.0, 26491.0);
   CHECK_EQD(c3.s.zoneHigh, 26498.9, 1e-6);
}

// ==================================================================
//  6. no look-ahead
// ==================================================================
static void test_no_lookahead()
{
   CASE("no look-ahead: a tick inside the zone can never open a trade");

   Ctx c; ctxInit(c, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   feed(c, WD(8, 55, 0, 0), 95.0, 96.0);
   feed(c, WD(8, 56, 0, 0), 90.0, 91.0);
   feed(c, WD(8, 57, 0, 0), 100.0, 101.0);          // new high inside the window
   CHECK_EQI(c.res.act.type, DZ_ACT_NONE);
   feed(c, WD(8, 59, 59, 999), 130.0, 131.0);       // huge move, still inside the window
   CHECK_EQI(c.res.act.type, DZ_ACT_NONE);
   CHECK_EQI(c.s.legCount, 0);
   CHECK_EQD(c.s.zoneHigh, 130.0, EPS);             // it only widens the zone

   feed(c, WD(9, 0, 0, 0), 120.0, 121.0);           // inside the frozen zone -> no entry
   CHECK_EQI(c.res.act.type, DZ_ACT_NONE);
   CHECK_EQI(c.s.phase, DZ_PHASE_ARMED);
   CHECK_EQI(c.s.breakoutCount, 0);
}

// ==================================================================
//  7/8. entry direction and BID/ASK execution semantics
// ==================================================================
static void test_entry_semantics()
{
   CASE("entry: LONG is signalled by BID > zoneHigh and filled at ASK");

   Ctx c; ctxInit(c, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c);
   feed(c, WD(9, 1, 0, 0), 100.0, 101.0);           // BID == zoneHigh -> NOT a breakout
   CHECK_EQI(c.res.act.type, DZ_ACT_NONE);
   CHECK_EQI(c.s.breakoutCount, 0);

   feed(c, WD(9, 2, 0, 0), 100.1, 101.1);           // first BID strictly above
   CHECK_EQI(c.res.act.type, DZ_ACT_OPEN);
   CHECK_EQI(c.res.act.dir, DZ_DIR_LONG);
   CHECK_EQD(c.s.entryPrice, 101.1, EPS);           // ASK, not the zone edge
   CHECK_EQD(c.s.entryBid, 100.1, EPS);
   CHECK_EQD(c.s.entrySpread, 1.0, EPS);
   CHECK_EQI(c.s.firstBreakDir, DZ_DIR_LONG);
   CHECK_EQI(c.s.firstBreakMsc, WD(9, 2, 0, 0));
   CHECK_EQI(c.s.phase, DZ_PHASE_IN_TRADE);

   CASE("entry: SHORT is signalled by BID < zoneLow and filled at BID");

   Ctx c2; ctxInit(c2, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c2);
   feed(c2, WD(9, 1, 0, 0), 90.0, 91.0);            // BID == zoneLow -> NOT a breakout
   CHECK_EQI(c2.res.act.type, DZ_ACT_NONE);

   feed(c2, WD(9, 2, 0, 0), 89.9, 90.9);
   CHECK_EQI(c2.res.act.type, DZ_ACT_OPEN);
   CHECK_EQI(c2.res.act.dir, DZ_DIR_SHORT);
   CHECK_EQD(c2.s.entryPrice, 89.9, EPS);           // BID
   CHECK_EQI(c2.s.firstBreakDir, DZ_DIR_SHORT);
}

// ==================================================================
//  9. gap-through entry, overshoot beyond TP, entry beyond SL
// ==================================================================
static void test_gap_and_overshoot()
{
   CASE("entry: gap through the zone fills at the real ASK, not at the zone edge");

   Ctx c; ctxInit(c, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c);                                  // zone 90..100, tpLong 110
   feed(c, WD(9, 1, 0, 0), 105.0, 106.0);            // gap straight through
   CHECK_EQI(c.res.act.type, DZ_ACT_OPEN);
   CHECK_EQD(c.s.entryPrice, 106.0, EPS);
   CHECK(!c.s.entryOvershoot);

   CASE("entry: fill already at/beyond TP is logged, not awarded as a win");

   Ctx c2; ctxInit(c2, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c2);
   feed(c2, WD(9, 1, 0, 0), 112.0, 113.0);           // ASK 113 >= tpLong 110
   CHECK_EQI(c2.res.act.type, DZ_ACT_NONE);
   CHECK_EQI(c2.s.legCount, 0);
   CHECK(c2.s.entryOvershoot);
   CHECK_EQI(c2.s.state, DZ_SESS_ENTRY_OVERSHOOT_BEYOND_TP);
   CHECK_EQI(c2.s.phase, DZ_PHASE_POST);
   CHECK_EQI(c2.s.breakoutCount, 1);                 // still counted as a breakout
   feed(c2, WD(9, 30, 0, 0), 111.0, 112.0);
   CHECK_EQI(c2.doneCount, 1);
   CHECK_EQI(c2.lastDone.state, DZ_SESS_ENTRY_OVERSHOOT_BEYOND_TP);
   CHECK_EQD(c2.lastDone.netPnLPoints, 0.0, EPS);

   CASE("entry: SHORT fill already at/beyond TP is logged the same way");

   Ctx c3; ctxInit(c3, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c3);
   feed(c3, WD(9, 1, 0, 0), 79.0, 80.0);             // BID 79 <= tpShort 80
   CHECK_EQI(c3.res.act.type, DZ_ACT_NONE);
   CHECK_EQI(c3.s.state, DZ_SESS_ENTRY_OVERSHOOT_BEYOND_TP);

   CASE("entry: overshoot policy can be switched off (diagnostic only)");

   Ctx c4; ctxInit(c4, DZ_SL_OPPOSITE_ZONE, 0, MS0930, 1.0, /*skipOvershoot=*/false);
   buildStdZone(c4);
   feed(c4, WD(9, 1, 0, 0), 112.0, 113.0);
   CHECK_EQI(c4.res.act.type, DZ_ACT_OPEN);
   CHECK(c4.s.entryOvershoot);
   CHECK_EQI(c4.s.state, DZ_SESS_TRADED);

   CASE("entry: fill already beyond the stop (spread wider than the zone)");

   Ctx c5; ctxInit(c5, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c5);
   feed(c5, WD(9, 1, 0, 0), 89.0, 101.0);            // short signal, ASK already above slShort
   CHECK_EQI(c5.res.act.type, DZ_ACT_NONE);
   CHECK(c5.s.entryBeyondSl);
   CHECK_EQI(c5.s.state, DZ_SESS_ENTRY_BEYOND_SL);
   CHECK_EQI(c5.s.legCount, 0);
}

// ==================================================================
//  10. exit semantics
// ==================================================================
static void test_exits()
{
   CASE("exit: LONG TP is evaluated on BID and filled at the real BID");

   Ctx c; ctxInit(c, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c);
   feed(c, WD(9, 2, 0, 0), 100.5, 101.5);            // entry ASK 101.5
   feed(c, WD(9, 3, 0, 0), 109.9, 110.9);            // BID below tpLong -> still open
   CHECK_EQI(c.res.act.type, DZ_ACT_NONE);
   CHECK(c.s.inTrade);
   feed(c, WD(9, 4, 0, 0), 112.0, 113.0);            // BID 112 >= 110 -> TP
   CHECK_EQI(c.res.act.type, DZ_ACT_CLOSE);
   CHECK_EQI(c.res.act.reason, DZ_EXIT_TP);
   CHECK_EQD(c.s.exitPrice, 112.0, EPS);             // real BID, no fictional 110.0 fill
   CHECK_EQD(c.s.netPnLPoints,   112.0 - 101.5, EPS);
   CHECK_EQD(c.s.grossPnLPoints, 112.0 - 100.5, EPS);
   CHECK_EQI(c.s.phase, DZ_PHASE_POST);

   CASE("exit: LONG SL is evaluated on BID");

   Ctx c2; ctxInit(c2, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c2);
   feed(c2, WD(9, 2, 0, 0), 100.5, 101.5);
   feed(c2, WD(9, 3, 0, 0),  90.1,  91.1);           // above slLong -> still open
   CHECK(c2.s.inTrade);
   feed(c2, WD(9, 4, 0, 0),  89.0,  90.0);           // BID 89 <= slLong 90
   CHECK_EQI(c2.res.act.reason, DZ_EXIT_SL);
   CHECK_EQD(c2.s.exitPrice, 89.0, EPS);
   CHECK_EQD(c2.s.netPnLPoints, 89.0 - 101.5, EPS);

   CASE("exit: SHORT TP/SL are evaluated on ASK");

   Ctx c3; ctxInit(c3, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c3);
   feed(c3, WD(9, 2, 0, 0), 89.5, 90.5);             // entry BID 89.5
   CHECK_EQD(c3.s.entryPrice, 89.5, EPS);
   feed(c3, WD(9, 3, 0, 0), 79.5, 80.5);             // ASK 80.5 > tpShort 80 -> still open
   CHECK(c3.s.inTrade);
   feed(c3, WD(9, 4, 0, 0), 78.0, 79.0);             // ASK 79 <= 80 -> TP
   CHECK_EQI(c3.res.act.reason, DZ_EXIT_TP);
   CHECK_EQD(c3.s.exitPrice, 79.0, EPS);
   CHECK_EQD(c3.s.netPnLPoints,   89.5 - 79.0, EPS);
   CHECK_EQD(c3.s.grossPnLPoints, 89.5 - 78.0, EPS);

   Ctx c4; ctxInit(c4, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c4);
   feed(c4, WD(9, 2, 0, 0), 89.5, 90.5);
   feed(c4, WD(9, 3, 0, 0), 98.5, 99.5);             // ASK below slShort 100 -> still open
   CHECK(c4.s.inTrade);
   feed(c4, WD(9, 4, 0, 0), 99.5, 100.5);            // ASK 100.5 >= 100 -> SL
   CHECK_EQI(c4.res.act.reason, DZ_EXIT_SL);
   CHECK_EQD(c4.s.exitPrice, 100.5, EPS);
   CHECK_EQD(c4.s.netPnLPoints, 89.5 - 100.5, EPS);

   CASE("exit: chronological ordering - SL first means SL, later TP is irrelevant");

   Ctx c5; ctxInit(c5, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c5);
   feed(c5, WD(9, 2, 0, 0), 100.5, 101.5);
   feed(c5, WD(9, 3, 0, 0),  89.0,  90.0);           // SL
   feed(c5, WD(9, 5, 0, 0), 130.0, 131.0);           // deep past TP, must change nothing
   CHECK_EQI(c5.s.exitReason, DZ_EXIT_SL);
   CHECK_EQD(c5.s.netPnLPoints, 89.0 - 101.5, EPS);
   CHECK_EQI(c5.s.legCount, 1);

   CASE("exit: chronological ordering - TP first means TP");

   Ctx c6; ctxInit(c6, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c6);
   feed(c6, WD(9, 2, 0, 0), 100.5, 101.5);
   feed(c6, WD(9, 3, 0, 0), 110.5, 111.5);           // TP
   feed(c6, WD(9, 5, 0, 0),  50.0,  51.0);           // collapse afterwards, irrelevant
   CHECK_EQI(c6.s.exitReason, DZ_EXIT_TP);
   CHECK_EQD(c6.s.netPnLPoints, 110.5 - 101.5, EPS);
}

// ==================================================================
//  11. hard time cutoff, anchored to 09:00 and not to entry
// ==================================================================
static void test_cutoffs()
{
   CASE("cutoff: 09:30 variant exits at 09:30 even for a 09:17 entry");

   Ctx c; ctxInit(c, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c);
   feed(c, WD(9, 17, 0, 0), 100.5, 101.5);
   CHECK_EQI(c.res.act.type, DZ_ACT_OPEN);
   feed(c, WD(9, 29, 59, 999), 103.0, 104.0);
   CHECK(c.s.inTrade);
   feed(c, WD(9, 30, 0, 0), 102.0, 103.0);
   CHECK_EQI(c.res.act.reason, DZ_EXIT_TIME);
   CHECK_EQD(c.s.exitPrice, 102.0, EPS);
   CHECK_EQI(c.s.phase, DZ_PHASE_DONE);
   CHECK_EQI(c.doneCount, 1);
   CHECK_EQI(c.lastDone.state, DZ_SESS_TRADED);

   CASE("cutoff: 10:00 variant holds the same trade past 09:30");

   Ctx c2; ctxInit(c2, DZ_SL_OPPOSITE_ZONE, 0, MS1000);
   buildStdZone(c2);
   feed(c2, WD(9, 17, 0, 0), 100.5, 101.5);
   feed(c2, WD(9, 30, 0, 0), 102.0, 103.0);
   CHECK(c2.s.inTrade);
   feed(c2, WD(9, 59, 59, 999), 104.0, 105.0);
   CHECK(c2.s.inTrade);
   feed(c2, WD(10, 0, 0, 0), 106.0, 107.0);
   CHECK_EQI(c2.res.act.reason, DZ_EXIT_TIME);
   CHECK_EQD(c2.s.netPnLPoints, 106.0 - 101.5, EPS);

   CASE("cutoff: no new entry is opened at or after the cutoff");

   Ctx c3; ctxInit(c3, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c3);
   feed(c3, WD(9, 30, 0, 0), 150.0, 151.0);          // breakout, but too late
   CHECK_EQI(c3.res.act.type, DZ_ACT_NONE);
   CHECK_EQI(c3.s.legCount, 0);
   CHECK_EQI(c3.s.state, DZ_SESS_NO_BREAKOUT);
   CHECK_EQI(c3.doneCount, 1);

   CASE("cutoff: quiet session is recorded as NO_BREAKOUT");

   Ctx c4; ctxInit(c4, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c4);
   feed(c4, WD(9, 10, 0, 0), 97.0, 98.0);
   feed(c4, WD(9, 20, 0, 0), 93.0, 94.0);
   feed(c4, WD(9, 30, 0, 0), 95.0, 96.0);
   CHECK_EQI(c4.doneCount, 1);
   CHECK_EQI(c4.lastDone.state, DZ_SESS_NO_BREAKOUT);
   CHECK_EQI(c4.lastDone.breakoutCount, 0);
   CHECK_EQD(c4.lastDone.netPnLPoints, 0.0, EPS);
}

// ==================================================================
//  12. double / false breakouts
// ==================================================================
static void test_double_breakout()
{
   CASE("double breakout: A-style run records it but never re-enters");

   Ctx c; ctxInit(c, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c);
   feed(c, WD(9, 2, 0, 0), 100.5, 101.5);            // LONG
   feed(c, WD(9, 5, 0, 0),  89.5,  90.5);            // SL and opposite breakout
   CHECK_EQI(c.res.act.reason, DZ_EXIT_SL);
   feed(c, WD(9, 12, 0, 0), 101.0, 102.0);           // back through the top
   feed(c, WD(9, 20, 0, 0), 115.0, 116.0);           // eventually reaches the long TP
   CHECK_EQI(c.s.legCount, 1);                       // still one single losing trade
   CHECK_EQD(c.s.netPnLPoints, 89.5 - 101.5, EPS);
   feed(c, WD(9, 30, 0, 0), 114.0, 115.0);
   CHECK_EQI(c.lastDone.breakoutCount, 3);
   CHECK(c.lastDone.doubleBreakout);
   CHECK_EQI(c.lastDone.firstBreakDir, DZ_DIR_LONG);
   CHECK_EQI(c.lastDone.oppositeBreakMsc, WD(9, 5, 0, 0));
   CHECK_EQI(c.lastDone.breakSide[0], DZ_DIR_LONG);
   CHECK_EQI(c.lastDone.breakSide[1], DZ_DIR_SHORT);
   CHECK_EQI(c.lastDone.breakSide[2], DZ_DIR_LONG);

   CASE("reversal: C-style run reverses exactly once");

   Ctx c2; ctxInit(c2, DZ_SL_NONE, 1, MS0930);
   buildStdZone(c2);
   feed(c2, WD(9, 0, 30, 0), 100.5, 101.5);          // LONG entry at ASK 101.5
   CHECK_EQI(c2.res.act.type, DZ_ACT_OPEN);

   feed(c2, WD(9, 5, 0, 0), 89.5, 90.5);             // opposite edge -> close & reverse
   CHECK_EQI(c2.res.act.type, DZ_ACT_REVERSE);
   CHECK_EQI(c2.res.act.dir, DZ_DIR_SHORT);
   CHECK_EQI(c2.s.reversalCount, 1);
   CHECK_EQI(c2.s.legCount, 2);
   CHECK_EQI(c2.s.leg1ExitReason, DZ_EXIT_REVERSAL);
   CHECK_EQD(c2.s.leg1ExitPrice, 89.5, EPS);         // long closed at BID
   CHECK_EQD(c2.s.leg2EntryPrice, 89.5, EPS);        // short opened at BID
   CHECK_EQD(c2.s.netPnLPoints, 89.5 - 101.5, EPS);  // leg 1 only, so far

   feed(c2, WD(9, 15, 0, 0), 101.0, 102.0);          // opposite again -> must NOT reverse
   CHECK_EQI(c2.res.act.type, DZ_ACT_NONE);
   CHECK_EQI(c2.s.reversalCount, 1);
   CHECK_EQI(c2.s.legCount, 2);
   CHECK(c2.s.inTrade);

   feed(c2, WD(9, 30, 0, 0), 99.0, 100.0);           // cutoff closes the short at ASK
   CHECK_EQI(c2.res.act.reason, DZ_EXIT_TIME);
   CHECK_EQD(c2.s.netPnLPoints, (89.5 - 101.5) + (89.5 - 100.0), EPS);
   CHECK_EQI(c2.lastDone.breakoutCount, 3);
   CHECK(c2.lastDone.doubleBreakout);

   CASE("reversal: second leg can still reach the original opposite TP");

   Ctx c3; ctxInit(c3, DZ_SL_NONE, 1, MS0930);
   buildStdZone(c3);
   feed(c3, WD(9, 1, 0, 0), 100.5, 101.5);           // LONG
   feed(c3, WD(9, 5, 0, 0),  89.5,  90.5);           // reverse to SHORT at BID 89.5
   feed(c3, WD(9, 9, 0, 0),  78.0,  79.0);           // ASK 79 <= tpShort 80
   CHECK_EQI(c3.res.act.reason, DZ_EXIT_TP);
   CHECK_EQD(c3.s.netPnLPoints, (89.5 - 101.5) + (89.5 - 79.0), EPS);

   CASE("reversal: A/B configurations never reverse");

   Ctx c4; ctxInit(c4, DZ_SL_NONE, 0, MS0930);       // B-style: no SL, no reversal
   buildStdZone(c4);
   feed(c4, WD(9, 1, 0, 0), 100.5, 101.5);
   feed(c4, WD(9, 5, 0, 0),  85.0,  86.0);           // far below the zone, no SL, no reversal
   CHECK_EQI(c4.res.act.type, DZ_ACT_NONE);
   CHECK(c4.s.inTrade);
   CHECK_EQI(c4.s.legCount, 1);
   feed(c4, WD(9, 30, 0, 0), 84.0, 85.0);
   CHECK_EQI(c4.s.exitReason, DZ_EXIT_TIME);
   CHECK_EQD(c4.s.netPnLPoints, 84.0 - 101.5, EPS);
}

// ==================================================================
//  13. excursions and the gross/net decomposition
// ==================================================================
static void test_excursions()
{
   CASE("MAE/MFE are measured on the tradable exit price of the open leg");

   Ctx c; ctxInit(c, DZ_SL_NONE, 0, MS0930);
   buildStdZone(c);
   feed(c, WD(9, 2, 0, 0), 100.5, 101.5);            // entry ASK 101.5
   CHECK_EQD(c.s.mfePoints, -1.0, EPS);              // starts one spread under water
   CHECK_EQD(c.s.maePoints, -1.0, EPS);
   feed(c, WD(9, 3, 0, 0), 105.0, 106.0);
   CHECK_EQD(c.s.mfePoints, 3.5, EPS);
   feed(c, WD(9, 4, 0, 0), 95.0, 96.0);
   CHECK_EQD(c.s.maePoints, -6.5, EPS);
   feed(c, WD(9, 5, 0, 0), 112.0, 113.0);            // TP
   CHECK_EQD(c.s.mfePoints, 10.5, EPS);
   CHECK_EQD(c.s.maePoints, -6.5, EPS);

   CASE("gross (BID-to-BID) minus net equals the execution cost paid");

   // LONG: the cost is the entry spread.
   CHECK_EQD(c.s.grossPnLPoints - c.s.netPnLPoints, 1.0, EPS);

   Ctx c2; ctxInit(c2, DZ_SL_NONE, 0, MS0930);
   buildStdZone(c2);
   feed(c2, WD(9, 2, 0, 0), 89.5, 90.5);             // SHORT at BID
   feed(c2, WD(9, 5, 0, 0), 78.0, 79.5);             // exit at ASK, spread 1.5
   CHECK_EQI(c2.s.exitReason, DZ_EXIT_TP);
   CHECK_EQD(c2.s.grossPnLPoints - c2.s.netPnLPoints, 1.5, EPS);
}

// ==================================================================
//  14. session reset and multi-day behaviour
// ==================================================================
static void test_session_reset()
{
   CASE("session: a new Warsaw day starts a completely fresh session");

   Ctx c; ctxInit(c, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c);
   feed(c, WD(9, 2, 0, 0), 100.5, 101.5);
   feed(c, WD(9, 30, 0, 0), 104.0, 105.0);
   CHECK_EQI(c.doneCount, 1);
   long day1 = c.lastDone.warsawDay;

   feed(c, WD2(8, 55, 0, 0), 200.0, 201.0);          // next weekday
   CHECK_EQI(c.doneCount, 1);                        // day 1 was already flushed
   CHECK_EQI(c.s.warsawDay, day1 + 1);
   CHECK_EQI(c.s.zoneTickCount, 1);
   CHECK_EQD(c.s.zoneHigh, 200.0, EPS);
   CHECK_EQI(c.s.legCount, 0);
   CHECK_EQI(c.s.breakoutCount, 0);
   CHECK(!c.s.inTrade);

   feed(c, WD2(8, 58, 0, 0), 190.0, 191.0);
   feed(c, WD2(9,  0, 0, 0), 195.0, 196.0);
   feed(c, WD2(9,  5, 0, 0), 201.0, 202.0);          // LONG on day 2
   CHECK_EQI(c.res.act.type, DZ_ACT_OPEN);
   feed(c, WD2(9, 30, 0, 0), 205.0, 206.0);
   CHECK_EQI(c.doneCount, 2);
   CHECK_EQI(c.lastDone.warsawDay, day1 + 1);

   CASE("session: no ticks inside 08:55-09:00 is recorded, never fabricated");

   Ctx c2; ctxInit(c2, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   feed(c2, WD(9, 10, 0, 0), 100.0, 101.0);          // first tick of the day is too late
   CHECK_EQI(c2.doneCount, 1);
   CHECK_EQI(c2.lastDone.state, DZ_SESS_NO_TICKS_IN_ZONE);
   CHECK_EQI(c2.lastDone.legCount, 0);
   CHECK(!c2.lastDone.zoneValid);

   CASE("session: zone built but no tick at/after 09:00 is recorded separately");

   Ctx c3; ctxInit(c3, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   feed(c3, WD(8, 55, 0, 0), 95.0, 96.0);
   feed(c3, WD(8, 58, 0, 0), 99.0, 100.0);
   feed(c3, WD2(8, 55, 0, 0), 95.0, 96.0);           // next day arrives first
   CHECK_EQI(c3.doneCount, 1);
   CHECK_EQI(c3.lastDone.state, DZ_SESS_NO_TICKS_AFTER_ARM);

   CASE("session: a position still open at the day boundary closes on the LAST SEEN price");

   Ctx c4; ctxInit(c4, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   buildStdZone(c4);
   feed(c4, WD(9,  2, 0, 0), 100.5, 101.5);
   feed(c4, WD(9, 10, 0, 0), 103.0, 104.0);          // last tick of that day
   feed(c4, WD2(8, 55, 0, 0), 500.0, 501.0);         // next day: must NOT be used as a fill
   CHECK_EQI(c4.doneCount, 1);
   CHECK_EQI(c4.lastDone.exitReason, DZ_EXIT_FORCED_NO_TICKS);
   CHECK_EQD(c4.lastDone.exitPrice, 103.0, EPS);
   CHECK_EQD(c4.lastDone.netPnLPoints, 103.0 - 101.5, EPS);

   CASE("session: a zone with zero range is rejected, not traded");

   Ctx c5; ctxInit(c5, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   feed(c5, WD(8, 55, 0, 0), 100.0, 101.0);
   feed(c5, WD(8, 57, 0, 0), 100.0, 101.0);
   feed(c5, WD(9,  0, 0, 0), 100.0, 101.0);
   CHECK_EQI(c5.doneCount, 1);
   CHECK_EQI(c5.lastDone.state, DZ_SESS_INVALID_ZONE);
   CHECK_EQI(c5.lastDone.legCount, 0);
}

// ==================================================================
//  15. end-to-end sessions driven by raw SERVER timestamps
// ==================================================================
static void feedServer(Ctx &c, long serverMsc, double bid, double ask)
{
   DzOnTick(c.s, c.done, c.cfg, c.tz, serverMsc, bid, ask, c.res);
   for(int i = 0; i < c.done.count; i++)
   {
      if(i == 0) DzSessionCopy(c.lastDone, c.done.item0);
      else       DzSessionCopy(c.lastDone, c.done.item1);
      c.doneCount++;
   }
}

static long srvMsc(int y, int mo, int d, int h, int mi)
{
   return DzDaysFromCivil(y, mo, d) * (long)DZ_MS_PER_DAY
        + (long)h * DZ_MS_PER_HOUR + (long)mi * DZ_MS_PER_MIN;
}

static void runServerDay(Ctx &c, int y, int mo, int d, int serverHourOf0855)
{
   feedServer(c, srvMsc(y, mo, d, serverHourOf0855, 55),  95.0,  96.0);
   feedServer(c, srvMsc(y, mo, d, serverHourOf0855, 57), 100.0, 101.0);
   feedServer(c, srvMsc(y, mo, d, serverHourOf0855, 58),  90.0,  91.0);
   feedServer(c, srvMsc(y, mo, d, serverHourOf0855 + 1,  0),  95.0,  96.0);  // 09:00 Warsaw
   feedServer(c, srvMsc(y, mo, d, serverHourOf0855 + 1,  2), 100.5, 101.5);  // LONG
   feedServer(c, srvMsc(y, mo, d, serverHourOf0855 + 1, 30), 104.0, 105.0);  // 09:30 Warsaw
}

static void test_dst_sessions()
{
   CASE("DST: CET weekday on an EET/EEST broker (08:55 Warsaw == 09:55 server)");

   Ctx c; ctxInit(c, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   runServerDay(c, 2026, 3, 27, 9);                  // last CET Friday before the switch
   CHECK_EQI(c.doneCount, 1);
   CHECK_EQI(c.lastDone.warsawDay, DzDaysFromCivil(2026, 3, 27));
   CHECK_EQI(c.lastDone.state, DZ_SESS_TRADED);
   CHECK_EQD(c.lastDone.zoneHigh, 100.0, EPS);
   CHECK_EQD(c.lastDone.zoneLow,   90.0, EPS);
   CHECK_EQI(c.lastDone.exitReason, DZ_EXIT_TIME);
   CHECK_EQD(c.lastDone.netPnLPoints, 104.0 - 101.5, EPS);
   CHECK_EQI(c.lastDone.tzFlagWorst, DZ_TZFLAG_OK);
   // the offsets actually in force at the 09:00 freeze are recorded for the CSV
   CHECK_EQI(c.lastDone.armServerMsc, srvMsc(2026, 3, 27, 10, 0));
   CHECK_EQI(c.lastDone.armServerOffsetSec, 7200);   // broker on EET
   CHECK_EQI(c.lastDone.armWarsawOffsetSec, 3600);   // Warsaw on CET

   CASE("DST: CEST weekday on an EET/EEST broker (08:55 Warsaw == 09:55 server)");

   Ctx c2; ctxInit(c2, DZ_SL_OPPOSITE_ZONE, 0, MS0930);
   runServerDay(c2, 2026, 3, 30, 9);                 // first CEST Monday after the switch
   CHECK_EQI(c2.doneCount, 1);
   CHECK_EQI(c2.lastDone.warsawDay, DzDaysFromCivil(2026, 3, 30));
   CHECK_EQI(c2.lastDone.state, DZ_SESS_TRADED);
   CHECK_EQD(c2.lastDone.zoneRange, 10.0, EPS);
   CHECK_EQI(c2.lastDone.tzFlagWorst, DZ_TZFLAG_OK);
   CHECK_EQI(c2.lastDone.armServerMsc, srvMsc(2026, 3, 30, 10, 0));
   CHECK_EQI(c2.lastDone.armServerOffsetSec, 10800);  // broker on EEST
   CHECK_EQI(c2.lastDone.armWarsawOffsetSec, 7200);   // Warsaw on CEST

   CASE("DST: a fixed UTC+2 broker shifts by one hour across the switch");

   Ctx c3; ctxInit(c3, DZ_SL_OPPOSITE_ZONE, 0, MS0930, 1.0, true, DZ_TZ_FIXED, 7200);
   runServerDay(c3, 2026, 3, 27, 9);                 // winter: 09:55 server == 08:55 Warsaw
   CHECK_EQI(c3.doneCount, 1);
   CHECK_EQI(c3.lastDone.state, DZ_SESS_TRADED);

   Ctx c4; ctxInit(c4, DZ_SL_OPPOSITE_ZONE, 0, MS0930, 1.0, true, DZ_TZ_FIXED, 7200);
   runServerDay(c4, 2026, 3, 30, 9);                 // summer: 09:55 server is 09:55 Warsaw
   CHECK_EQI(c4.doneCount, 1);
   CHECK_EQI(c4.lastDone.state, DZ_SESS_NO_TICKS_IN_ZONE);   // the zone window was missed

   Ctx c5; ctxInit(c5, DZ_SL_OPPOSITE_ZONE, 0, MS0930, 1.0, true, DZ_TZ_FIXED, 7200);
   runServerDay(c5, 2026, 3, 30, 8);                 // summer: 08:55 server == 08:55 Warsaw
   CHECK_EQI(c5.doneCount, 1);
   CHECK_EQI(c5.lastDone.state, DZ_SESS_TRADED);
}

// ==================================================================
int main()
{
   std::printf("daxDzida Phase 1 - deterministic regression tests\n");
   std::printf("=================================================\n");

   test_calendar();
   test_warsaw_dst();
   test_server_mapping();
   test_zone_window();
   test_tp_formula();
   test_no_lookahead();
   test_entry_semantics();
   test_gap_and_overshoot();
   test_exits();
   test_cutoffs();
   test_double_breakout();
   test_excursions();
   test_session_reset();
   test_dst_sessions();

   std::printf("=================================================\n");
   std::printf("checks: %d   failures: %d\n", g_checks, g_fails);
   if(g_fails == 0)
      std::printf("RESULT: PASS\n");
   else
      std::printf("RESULT: FAIL\n");

   return (g_fails == 0) ? 0 : 1;
}
