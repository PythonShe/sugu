#ifndef SUGU_CRIME_SHIM_H
#define SUGU_CRIME_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

/// Pulls the statically linked plugin modules (octagram) into the binary so
/// their registration constructors run. Call once before rime setup.
void sugu_rime_link_plugins(void);

#ifdef __cplusplus
}
#endif

#endif
