#ifndef PM_COMPAT_CORE_H
#define PM_COMPAT_CORE_H
#include <linux/types.h>
#include <linux/kallsyms.h>
#include <linux/kernel.h>
extern unsigned long (*kallrecon_klp)(const char *name);
extern unsigned int klnum_val;
static inline void find_kallsyms_base(void) { }
static inline unsigned long kallsyms_name_to_addr(const char *name)
{
	return kallsyms_lookup_name(name);
}
static inline int kallrecon_fail_reason(void) { return 0; }
static inline void kallrecon_supply(const void *hint) { (void)hint; }
#endif
