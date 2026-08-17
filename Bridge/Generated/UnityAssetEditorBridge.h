#ifndef UNITY_ASSET_EDITOR_BRIDGE_H
#define UNITY_ASSET_EDITOR_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t uae_bridge_inspect(const uint8_t *path_utf8, uint8_t *output_utf8, int32_t output_capacity);

#ifdef __cplusplus
}
#endif

#endif
