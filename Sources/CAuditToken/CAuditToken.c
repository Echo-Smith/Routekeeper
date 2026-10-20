#include "CAuditToken.h"

#include <bsm/libbsm.h>
#include <mach/message.h>
#include <string.h>
#include <sys/types.h>

bool RoutekeeperReadAuditToken(const void *bytes, size_t length, uint32_t *uid, int32_t *pid)
{
    audit_token_t token;
    if (bytes == NULL || uid == NULL || pid == NULL || length != sizeof(token)) {
        return false;
    }

    memcpy(&token, bytes, sizeof(token));
    *uid = audit_token_to_ruid(token);
    *pid = audit_token_to_pid(token);
    return true;
}
