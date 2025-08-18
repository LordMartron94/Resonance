#ifndef RESONANCE_H
#define RESONANCE_H

#ifdef __cplusplus
extern "C" {
#endif

/* Version macros (optional) */
#ifndef RESONANCE_VERSION_MAJOR
#define RESONANCE_VERSION_MAJOR 0
#endif
#ifndef RESONANCE_VERSION_MINOR
#define RESONANCE_VERSION_MINOR 0
#endif
#ifndef RESONANCE_VERSION_PATCH
#define RESONANCE_VERSION_PATCH 0
#endif

/* Public API */
const char* resonance_version_string(void);

#ifdef __cplusplus
}
#endif

#endif /* RESONANCE_H */
