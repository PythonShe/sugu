#ifndef SUGU_CRIME_SHIM_H
#define SUGU_CRIME_SHIM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Pulls the statically linked plugin modules (octagram) into the binary so
/// their registration constructors run. Call once before rime setup.
void sugu_rime_link_plugins(void);

// OpenCC's C API (opencc.h), compiled into the librime archive. Sugu uses it
// to show its own Chinese candidates in the script librime's filters use.
void *opencc_open(const char *configFileName);
int opencc_close(void *opencc);
char *opencc_convert_utf8(void *opencc, const char *input, size_t length);
void opencc_convert_utf8_free(char *str);

#ifdef __cplusplus
}
#endif

#endif
