//+------------------------------------------------------------------+
//| tests/shim/mt5_api_shim.h                                        |
//|                                                                  |
//| Stubs of the MetaTrader 5 API surface that DaxDzida_Phase1.mq5   |
//| actually uses, so that g++ can PARSE the real EA source.         |
//|                                                                  |
//| WHAT THIS IS FOR                                                 |
//|   MetaEditor only exists on Windows. This lets the repository    |
//|   catch the ordinary compile failures - typos, missing           |
//|   semicolons, undeclared identifiers, wrong argument counts,      |
//|   wrong return types - without a Windows round trip.             |
//|                                                                  |
//| WHAT THIS IS *NOT*                                               |
//|   It is not a substitute for MetaEditor. It cannot verify        |
//|   MQL5-only rules: `input` / `input group` syntax, `#property`   |
//|   directives, the requirement that structs be passed by          |
//|   reference, or MQL5's own conversion warnings. A green          |
//|   pre-flight means "worth compiling", never "compiles".          |
//|                                                                  |
//|   The stub bodies are meaningless on purpose. Nothing here is    |
//|   ever executed - the checker runs g++ -fsyntax-only.            |
//+------------------------------------------------------------------+
#ifndef DZ_MT5_API_SHIM_H
#define DZ_MT5_API_SHIM_H

#include <string>
#include <cstdio>
#include <cstdarg>
#include <cmath>

// ------------------------------------------------------------------ types --
typedef std::string        string;
typedef long               datetime;
typedef unsigned short     ushort;
typedef unsigned char      uchar;
typedef unsigned int       uint;
typedef unsigned long      ulong;

struct MqlTick
{
   datetime time;
   double   bid;
   double   ask;
   double   last;
   ulong    volume;
   long     time_msc;
   uint     flags;
   double   volume_real;
};

enum ENUM_DAY_OF_WEEK { SUNDAY = 0, MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY };
enum ENUM_LOG_LEVELS  { LOG_LEVEL_NO = 0, LOG_LEVEL_ERRORS = 1, LOG_LEVEL_ALL = 2 };

// -------------------------------------------------------------- constants --
enum {
   FILE_READ = 1, FILE_WRITE = 2, FILE_BIN = 4, FILE_CSV = 8, FILE_TXT = 16,
   FILE_ANSI = 32, FILE_UNICODE = 64, FILE_SHARE_READ = 128, FILE_SHARE_WRITE = 256,
   FILE_COMMON = 4096
};
enum { INVALID_HANDLE = -1 };
enum { INIT_SUCCEEDED = 0, INIT_FAILED = 1 };
enum { CP_ACP = 0 };
enum { TIME_DATE = 1, TIME_MINUTES = 2, TIME_SECONDS = 4 };
enum { MQL_TESTER = 27, MQL_OPTIMIZATION = 28, MQL_VISUAL_MODE = 29 };
enum {
   SYMBOL_DIGITS = 17, SYMBOL_POINT = 18, SYMBOL_TRADE_TICK_SIZE = 19,
   SYMBOL_TRADE_TICK_VALUE = 20, SYMBOL_TRADE_CONTRACT_SIZE = 21,
   SYMBOL_VOLUME_MIN = 22, SYMBOL_VOLUME_MAX = 23, SYMBOL_VOLUME_STEP = 24,
   SYMBOL_CURRENCY_PROFIT = 25, SYMBOL_SPREAD = 26
};
enum { ACCOUNT_BALANCE = 37, ACCOUNT_EQUITY = 38 };
enum { POSITION_MAGIC = 12, POSITION_PRICE_OPEN = 13, POSITION_VOLUME = 14 };

// --------------------------------------------------------------- globals --
static string _Symbol = "TESTSYM";
static int    _Digits = 2;
static double _Point  = 0.01;

// ------------------------------------------------------------- string API --
inline int    StringLen(const string &s)                    { return (int)s.size(); }
inline int    StringFind(const string &s, const string &f, int start = 0)
                                                            { size_t p = s.find(f, (size_t)start);
                                                              return (p == string::npos) ? -1 : (int)p; }
inline ushort StringGetCharacter(const string &s, int i)     { return (ushort)(unsigned char)s[(size_t)i]; }
inline string ShortToString(ushort c)                        { return string(1, (char)c); }
inline string IntegerToString(long v, int width = 0, ushort fill = '0')
                                                            { (void)width; (void)fill;
                                                              char b[64]; std::snprintf(b, sizeof b, "%ld", v); return b; }
inline string DoubleToString(double v, int digits = 8)       { char b[128];
                                                              std::snprintf(b, sizeof b, "%.*f", digits, v); return b; }
inline string TimeToString(datetime t, int mode = TIME_DATE | TIME_MINUTES)
                                                            { (void)t; (void)mode; return string(); }

inline string StringFormat(const char *fmt, ...)
{
   char b[1024];
   va_list ap; va_start(ap, fmt);
   std::vsnprintf(b, sizeof b, fmt, ap);
   va_end(ap);
   return b;
}
inline string StringFormat(const string &fmt, ...)           { return fmt; }

// -------------------------------------------------------------- math API --
inline double MathRound(double v) { return std::floor(v + 0.5); }
inline double MathAbs(double v)   { return std::fabs(v); }
inline double MathMax(double a, double b) { return a > b ? a : b; }
inline double MathMin(double a, double b) { return a < b ? a : b; }

// ------------------------------------------------------------- print API --
inline void PrintOne(const string &) {}
inline void PrintOne(const char *)   {}
inline void PrintOne(long)           {}
inline void PrintOne(int)            {}
inline void PrintOne(double)         {}
inline void PrintOne(bool)           {}

inline void Print() {}
template <typename T> void Print(const T &a) { (void)&a; }
template <typename A, typename B> void Print(const A &, const B &) {}
template <typename A, typename B, typename C> void Print(const A &, const B &, const C &) {}
template <typename A, typename B, typename C, typename D>
void Print(const A &, const B &, const C &, const D &) {}

inline void PrintFormat(const char *fmt, ...) { (void)fmt; }
inline void PrintFormat(const string &fmt, ...) { (void)fmt; }

// -------------------------------------------------------------- file API --
inline int  FileOpen(const string &name, int flags, short delim = '\t', uint cp = CP_ACP)
                                                    { (void)name; (void)flags; (void)delim; (void)cp; return 1; }
inline uint FileWrite(int h, const string &v)        { (void)h; (void)v; return 1; }
inline void FileClose(int h)                         { (void)h; }
inline int  GetLastError()                           { return 0; }

// ------------------------------------------------------------ market API --
inline double SymbolInfoDouble(const string &s, int prop)  { (void)s; (void)prop; return 0.0; }
inline long   SymbolInfoInteger(const string &s, int prop) { (void)s; (void)prop; return 0; }
inline string SymbolInfoString(const string &s, int prop)  { (void)s; (void)prop; return string(); }
inline bool   SymbolInfoTick(const string &s, MqlTick &t)  { (void)s; (void)t; return true; }
inline bool   SymbolInfoSessionTrade(const string &s, ENUM_DAY_OF_WEEK d, uint idx,
                                     datetime &from, datetime &to)
                                                           { (void)s; (void)d; (void)idx;
                                                             from = 0; to = 0; return true; }

inline double AccountInfoDouble(int prop)                  { (void)prop; return 0.0; }
inline long   MQLInfoInteger(int prop)                     { (void)prop; return 1; }

inline bool   PositionSelect(const string &s)              { (void)s; return false; }
inline long   PositionGetInteger(int prop)                 { (void)prop; return 0; }
inline double PositionGetDouble(int prop)                  { (void)prop; return 0.0; }

inline datetime TimeCurrent()      { return 0; }
inline datetime TimeTradeServer()  { return 0; }
inline datetime TimeGMT()          { return 0; }
inline datetime TimeLocal()        { return 0; }
inline int      TimeGMTOffset()    { return 0; }

// ------------------------------------------------------ Trade/Trade.mqh --
class CTrade
{
public:
   void   SetExpertMagicNumber(ulong m)            { (void)m; }
   void   SetDeviationInPoints(ulong d)            { (void)d; }
   bool   SetTypeFillingBySymbol(const string &s)  { (void)s; return true; }
   void   LogLevel(ENUM_LOG_LEVELS l)              { (void)l; }

   bool   Buy(double volume, const string &symbol = string(), double price = 0.0,
              double sl = 0.0, double tp = 0.0, const string &comment = string())
          { (void)volume; (void)symbol; (void)price; (void)sl; (void)tp; (void)comment; return true; }
   bool   Sell(double volume, const string &symbol = string(), double price = 0.0,
               double sl = 0.0, double tp = 0.0, const string &comment = string())
          { (void)volume; (void)symbol; (void)price; (void)sl; (void)tp; (void)comment; return true; }
   bool   PositionClose(const string &symbol, ulong deviation = 0)
          { (void)symbol; (void)deviation; return true; }

   uint   ResultRetcode()            { return 0; }
   string ResultRetcodeDescription() { return string(); }
   double ResultPrice()              { return 0.0; }
};

#endif // DZ_MT5_API_SHIM_H
