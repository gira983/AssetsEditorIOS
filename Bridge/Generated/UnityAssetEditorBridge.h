#ifndef UNITY_ASSET_EDITOR_BRIDGE_H
#define UNITY_ASSET_EDITOR_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t uae_bridge_initialize(void);
char *uae_bridge_execute(const uint8_t *request_utf8, int32_t request_length);
void uae_bridge_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
