//+------------------------------------------------------------------+
//| DzTime.mqh                                                       |
//| daxDzida - Phase 1 research                                      |
//|                                                                  |
//| Deterministic calendar / timezone mathematics.                   |
//|                                                                  |
//| PORTABILITY CONTRACT                                             |
//|   This header is written in the common subset of MQL5 and C++    |
//|   so that the exact same source is compiled by MetaEditor (for   |
//|   the research EA) and by g++ (for the deterministic regression  |
//|   tests under tests/).                                           |
//|                                                                  |
//|   Rules kept in this file:                                       |
//|     - no strings, no MQL5 built-ins, no pointers, no classes     |
//|     - no dynamic arrays, no namespaces, no enum class            |
//|     - every function is defined before it is used (g++ needs it) |
//|                                                                  |
//|   When compiled by g++, tests/shim/mql5_shim.h must be included  |
//|   FIRST; it provides the `datetime` alias and nothing else.      |
//+------------------------------------------------------------------+
#ifndef DZ_TIME_MQH
#define DZ_TIME_MQH

#define DZ_SEC_PER_DAY   86400
#define DZ_MS_PER_DAY    86400000
#define DZ_MS_PER_HOUR   3600000
#define DZ_MS_PER_MIN    60000

//--- how broker/server timestamps map to UTC
enum DzServerTzMode
{
   DZ_TZ_FIXED  = 0,   // server clock is a constant UTC offset all year
   DZ_TZ_EU_DST = 1    // server clock follows the EU DST rule (e.g. EET/EEST)
};

//--- result of a server->UTC conversion
enum DzTzFlag
{
   DZ_TZFLAG_OK          = 0,
   DZ_TZFLAG_AMBIGUOUS   = 1,  // autumn overlap: this server wall-clock hour occurs twice
   DZ_TZFLAG_NONEXISTENT = 2   // spring gap: this server wall-clock hour does not exist
};

struct DzTzConfig
{
   int mode;           // DzServerTzMode
   int baseOffsetSec;  // server offset vs UTC during STANDARD (winter) time
};

void DzTzConfigInit(DzTzConfig &tz, const int mode, const int baseOffsetSec)
{
   tz.mode          = mode;
   tz.baseOffsetSec = baseOffsetSec;
}

//+------------------------------------------------------------------+
//| Floor division / modulo (C and MQL5 both truncate toward zero)   |
//+------------------------------------------------------------------+
long DzFloorDiv(const long a, const long b)
{
   long q = a / b;
   if((a % b) != 0 && ((a < 0) != (b < 0)))
      q = q - 1;
   return q;
}

//+------------------------------------------------------------------+
//| Days from 1970-01-01 for a proleptic Gregorian civil date        |
//| (Howard Hinnant's days_from_civil)                               |
//+------------------------------------------------------------------+
long DzDaysFromCivil(const int year, const int month, const int day)
{
   long y = (long)year;
   if(month <= 2)
      y = y - 1;

   long era = DzFloorDiv(y, 400);
   long yoe = y - era * 400;                                     // [0, 399]
   long mp  = (long)month + (month > 2 ? -3 : 9);                // [0, 11]
   long doy = (153 * mp + 2) / 5 + (long)day - 1;                // [0, 365]
   long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;             // [0, 146096]

   return era * 146097 + doe - 719468;
}

//+------------------------------------------------------------------+
//| Civil date from days since 1970-01-01 (civil_from_days)          |
//+------------------------------------------------------------------+
void DzCivilFromDays(const long epochDay, int &year, int &month, int &day)
{
   long z   = epochDay + 719468;
   long era = DzFloorDiv(z, 146097);
   long doe = z - era * 146097;                                  // [0, 146096]
   long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
   long y   = yoe + era * 400;
   long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);           // [0, 365]
   long mp  = (5 * doy + 2) / 153;                               // [0, 11]
   long d   = doy - (153 * mp + 2) / 5 + 1;                      // [1, 31]
   long m   = mp + (mp < 10 ? 3 : -9);                           // [1, 12]

   if(m <= 2)
      y = y + 1;

   year  = (int)y;
   month = (int)m;
   day   = (int)d;
}

//+------------------------------------------------------------------+
//| Day of week from epoch day. 0 = Sunday ... 6 = Saturday          |
//| (1970-01-01 was a Thursday)                                      |
//+------------------------------------------------------------------+
int DzDayOfWeekFromEpochDay(const long epochDay)
{
   long r = (epochDay + 4) % 7;
   if(r < 0)
      r = r + 7;
   return (int)r;
}

//+------------------------------------------------------------------+
//| Epoch day of the last Sunday of the given month.                 |
//| lastDom must be the last day-of-month number (31 for Mar/Oct).   |
//+------------------------------------------------------------------+
long DzLastSundayEpochDay(const int year, const int month, const int lastDom)
{
   long d   = DzDaysFromCivil(year, month, lastDom);
   int  dow = DzDayOfWeekFromEpochDay(d);   // 0 = Sunday
   return d - (long)dow;
}

//+------------------------------------------------------------------+
//| EU summer-time boundaries, expressed in UTC seconds.             |
//| Directive 2000/84/EC: summer time runs from 01:00 UTC on the     |
//| last Sunday of March to 01:00 UTC on the last Sunday of October. |
//+------------------------------------------------------------------+
long DzEuDstStartUtcSec(const int year)
{
   return DzLastSundayEpochDay(year, 3, 31) * DZ_SEC_PER_DAY + 3600;
}

long DzEuDstEndUtcSec(const int year)
{
   return DzLastSundayEpochDay(year, 10, 31) * DZ_SEC_PER_DAY + 3600;
}

bool DzIsEuSummerTime(const long utcSec)
{
   int y, m, d;
   DzCivilFromDays(DzFloorDiv(utcSec, DZ_SEC_PER_DAY), y, m, d);
   return (utcSec >= DzEuDstStartUtcSec(y) && utcSec < DzEuDstEndUtcSec(y));
}

//+------------------------------------------------------------------+
//| Europe/Warsaw UTC offset for a given UTC instant.                |
//| CET = UTC+1, CEST = UTC+2. Poland has followed the EU rule for   |
//| the whole period this research can possibly touch.               |
//+------------------------------------------------------------------+
int DzWarsawUtcOffsetSec(const long utcSec)
{
   return (DzIsEuSummerTime(utcSec) ? 7200 : 3600);
}

//+------------------------------------------------------------------+
//| Server wall-clock seconds -> UTC seconds.                        |
//| flag reports overlap / gap situations (see DzTzFlag).            |
//+------------------------------------------------------------------+
long DzServerToUtcSec(const DzTzConfig &tz, const long serverSec, int &flag)
{
   flag = DZ_TZFLAG_OK;

   if(tz.mode == DZ_TZ_FIXED)
      return serverSec - (long)tz.baseOffsetSec;

   // DZ_TZ_EU_DST: two candidate UTC instants, pick the self-consistent one.
   long cStd = serverSec - (long)tz.baseOffsetSec;            // assuming standard time
   long cDst = serverSec - (long)(tz.baseOffsetSec + 3600);   // assuming summer time

   bool stdOk = !DzIsEuSummerTime(cStd);
   bool dstOk =  DzIsEuSummerTime(cDst);

   if(stdOk && !dstOk)
      return cStd;
   if(dstOk && !stdOk)
      return cDst;

   if(stdOk && dstOk)
   {
      // Autumn overlap: the same server wall clock happens twice.
      // Deterministic choice: the FIRST pass (still summer time).
      flag = DZ_TZFLAG_AMBIGUOUS;
      return cDst;
   }

   // Spring gap: this server wall clock never happens.
   flag = DZ_TZFLAG_NONEXISTENT;
   return cStd;
}

//+------------------------------------------------------------------+
//| Server offset vs UTC, in seconds, at a given server instant.     |
//+------------------------------------------------------------------+
int DzServerUtcOffsetSec(const DzTzConfig &tz, const long serverSec, int &flag)
{
   long utcSec = DzServerToUtcSec(tz, serverSec, flag);
   return (int)(serverSec - utcSec);
}

//+------------------------------------------------------------------+
//| Full mapping used by the strategy: broker tick timestamp in      |
//| milliseconds -> Warsaw wall-clock milliseconds, Warsaw calendar  |
//| day and Warsaw time-of-day in milliseconds.                      |
//+------------------------------------------------------------------+
void DzServerMscToWarsaw(const DzTzConfig &tz, const long serverMsc,
                         long &utcMsc, long &warsawMsc, long &warsawDay,
                         int &todMs, int &serverOffsetSec, int &warsawOffsetSec,
                         int &flag)
{
   long serverSec = DzFloorDiv(serverMsc, 1000);
   long utcSec    = DzServerToUtcSec(tz, serverSec, flag);

   serverOffsetSec = (int)(serverSec - utcSec);
   utcMsc          = serverMsc - (long)serverOffsetSec * 1000;

   warsawOffsetSec = DzWarsawUtcOffsetSec(utcSec);
   warsawMsc       = utcMsc + (long)warsawOffsetSec * 1000;

   warsawDay = DzFloorDiv(warsawMsc, DZ_MS_PER_DAY);
   todMs     = (int)(warsawMsc - warsawDay * (long)DZ_MS_PER_DAY);
}

//+------------------------------------------------------------------+
//| Convenience: build a Warsaw wall-clock millisecond stamp.        |
//| Used mostly by the deterministic tests to author tick streams.   |
//+------------------------------------------------------------------+
long DzWarsawWallMsc(const int year, const int month, const int day,
                     const int hour, const int minute, const int second,
                     const int milli)
{
   long epochDay = DzDaysFromCivil(year, month, day);
   long tod      = (long)hour * DZ_MS_PER_HOUR
                 + (long)minute * DZ_MS_PER_MIN
                 + (long)second * 1000
                 + (long)milli;
   return epochDay * (long)DZ_MS_PER_DAY + tod;
}

//+------------------------------------------------------------------+
//| Inverse of DzServerMscToWarsaw for authoring test data:          |
//| given a Warsaw wall-clock instant, produce the matching server   |
//| tick timestamp under the supplied server timezone configuration. |
//+------------------------------------------------------------------+
long DzWarsawWallMscToServerMsc(const DzTzConfig &tz, const long warsawWallMsc)
{
   // First approximation: assume Warsaw standard time (UTC+1).
   long utcSecGuess = DzFloorDiv(warsawWallMsc, 1000) - 3600;
   int  wOff        = DzWarsawUtcOffsetSec(utcSecGuess);
   long utcMsc      = warsawWallMsc - (long)wOff * 1000;

   // Refine once (matters only inside the switch hour).
   wOff   = DzWarsawUtcOffsetSec(DzFloorDiv(utcMsc, 1000));
   utcMsc = warsawWallMsc - (long)wOff * 1000;

   long utcSec = DzFloorDiv(utcMsc, 1000);
   int  sOff;
   if(tz.mode == DZ_TZ_FIXED)
      sOff = tz.baseOffsetSec;
   else
      sOff = tz.baseOffsetSec + (DzIsEuSummerTime(utcSec) ? 3600 : 0);

   return utcMsc + (long)sOff * 1000;
}

#endif // DZ_TIME_MQH
