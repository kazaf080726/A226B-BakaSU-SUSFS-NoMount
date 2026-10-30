#include <linux/kallsyms.h>
#include <linux/types.h>
unsigned long (*kallrecon_klp)(const char *name) = kallsyms_lookup_name;
unsigned int klnum_val = 1;
