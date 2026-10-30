#ifndef PM_COMPAT_HINT_H
#define PM_COMPAT_HINT_H
#include "core.h"
enum kallrecon_fail { KALLRECON_OK = 0, KALLRECON_NO_OFFSETS = 3 };
struct kallrecon_hint { unsigned long scan_back; };
#endif
