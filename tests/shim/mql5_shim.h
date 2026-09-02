//+------------------------------------------------------------------+
//| tests/shim/mql5_shim.h                                           |
//|                                                                  |
//| Minimal compatibility layer that lets g++ compile the SAME       |
//| DzTime.mqh / DzCore.mqh sources that MetaEditor compiles.        |
//|                                                                  |
//| The research headers are deliberately written in the MQL5/C++    |
//| common subset, so almost nothing is needed here. Anything that   |
//| has to be added to this file is a signal that research logic is  |
//| drifting away from the portable subset.                          |
//+------------------------------------------------------------------+
#ifndef DZ_MQL5_SHIM_H
#define DZ_MQL5_SHIM_H

#include <cstdio>
#include <cmath>

// MQL5 built-in type. Not used by the portable headers today, but the EA
// layer uses it, so the alias is kept here for completeness.
typedef long long dz_datetime_unused_check;

// MQL5 `long` is a 64-bit signed integer. Guard the assumption instead of
// hoping for it: the whole timestamp arithmetic depends on it.
typedef char dz_static_assert_long_is_64bit[(sizeof(long) == 8) ? 1 : -1];

#endif // DZ_MQL5_SHIM_H
