#ifndef CAUDIT_TOKEN_H
#define CAUDIT_TOKEN_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

bool RoutekeeperReadAuditToken(const void *bytes, size_t length, uint32_t *uid, int32_t *pid);

#endif
